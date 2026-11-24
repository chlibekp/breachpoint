// Public HTTP API (spec §14.1): auth, profile, party, matchmaking queue, agent select, history.
import type { AccessClaims } from "./jwt.ts";
import { AuthService } from "./auth.ts";
import { HttpError, Router, type Req } from "./http.ts";
import { MODES, SocialService, type Mode } from "./social.ts";
import type { StatsService } from "./stats.ts";
import { readFile } from "node:fs/promises";
import { replayPath } from "../match/replay.ts";
import type { OAuthService } from "./oauth.ts";

export function buildApi(
  auth: AuthService,
  social: SocialService,
  stats: StatsService,
  gatewayUrl: string,
  replayDir?: string,
  oauth?: OAuthService,
): Router {
  const r = new Router();
  const user = (req: Req): AccessClaims => {
    const h = req.headers["authorization"];
    const token = typeof h === "string" && h.startsWith("Bearer ") ? h.slice(7) : "";
    const claims = auth.verifyAccess(token);
    if (!claims) throw new HttpError(401, "unauthorized");
    return claims;
  };
  const str = (v: unknown, name: string): string => {
    if (typeof v !== "string") throw new HttpError(400, `missing_${name}`);
    return v;
  };
  r.on("GET", "/health", async () => ({ body: { ok: true } }));
  r.on("POST", "/auth/register", async (q) => ({
    status: 201,
    body: await auth.register(
      str(q.body["email"], "email"),
      str(q.body["password"], "password"),
      str(q.body["name"], "name"),
    ),
  }));
  r.on("POST", "/auth/login", async (q) => ({
    body: await auth.login(str(q.body["email"], "email"), str(q.body["password"], "password")),
  }));
  // OAuth sign-in (Google, Discord): start → browser → callback → client polls (see oauth.ts).
  r.on("GET", "/auth/oauth/providers", async () => ({
    body: { providers: oauth?.enabled ?? [] },
  }));
  r.on("POST", "/auth/oauth/start", async (q) => {
    if (!oauth) throw new HttpError(404, "oauth_disabled");
    return { body: await oauth.start(str(q.body["provider"], "provider")) };
  });
  r.on("GET", "/auth/oauth/callback", async (q) => {
    if (!oauth) throw new HttpError(404, "oauth_disabled");
    const html = await oauth.callback(q.query);
    return {
      body: null,
      raw: new TextEncoder().encode(html),
      contentType: "text/html; charset=utf-8",
    };
  });
  r.on("GET", "/auth/oauth/poll", async (q) => {
    if (!oauth) throw new HttpError(404, "oauth_disabled");
    return { body: await oauth.poll(q.query["session"] ?? "") };
  });
  r.on("POST", "/auth/guest", async () => ({ status: 201, body: await auth.guest() }));
  r.on("POST", "/auth/refresh", async (q) => ({
    body: await auth.refresh(str(q.body["refreshToken"], "refreshToken")),
  }));
  r.on("GET", "/profile", async (q) => ({ body: await auth.profile(user(q).sub) }));
  r.on("PUT", "/profile/settings", async (q) => {
    await auth.updateJson(user(q).sub, "settings", q.body);
    return { body: { ok: true } };
  });
  r.on("PUT", "/profile/loadout", async (q) => {
    await auth.updateJson(user(q).sub, "loadout", q.body);
    return { body: { ok: true } };
  });
  r.on("GET", "/matches", async (q) => ({ body: await stats.history(user(q).sub) }));
  // Party.
  r.on("POST", "/party", async (q) => {
    const u = user(q);
    return { body: { partyId: await social.createParty(u.sub, u.name) } };
  });
  r.on("GET", "/party", async (q) => {
    const u = user(q);
    const id = await social.partyOf(u.sub);
    return { body: id ? await social.party(id) : null };
  });
  r.on("POST", "/party/invite", async (q) => {
    const u = user(q);
    const target = await auth.findByNameTag(str(q.body["nameTag"], "nameTag"));
    if (!target) throw new HttpError(404, "player_not_found");
    const id = (await social.partyOf(u.sub)) ?? (await social.createParty(u.sub, u.name));
    await social.invite(id, u.sub, target.id).catch((e: Error) => {
      throw new HttpError(403, e.message);
    });
    return { body: { ok: true, partyId: id } };
  });
  r.on("GET", "/party/invites", async (q) => ({ body: await social.invites(user(q).sub) }));
  r.on("POST", "/party/join", async (q) => {
    const u = user(q);
    await social.joinParty(str(q.body["partyId"], "partyId"), u.sub, u.name).catch((e: Error) => {
      throw new HttpError(403, e.message);
    });
    return { body: { ok: true } };
  });
  r.on("POST", "/party/leave", async (q) => {
    await social.leaveParty(user(q).sub);
    return { body: { ok: true } };
  });
  r.on("POST", "/party/ready", async (q) => {
    await social.setReady(user(q).sub, q.body["ready"] !== false);
    return { body: { ok: true } };
  });
  r.on("POST", "/party/chat", async (q) => {
    const u = user(q);
    await social.chat(u.sub, u.name, str(q.body["text"], "text"));
    return { body: { ok: true } };
  });
  // Matchmaking.
  r.on("POST", "/queue", async (q) => {
    const u = user(q);
    const mode = str(q.body["mode"], "mode") as Mode;
    if (!MODES.includes(mode)) throw new HttpError(400, "bad_mode");
    if (mode === "competitive" && u.guest) throw new HttpError(403, "account_required");
    const prof = await auth.profile(u.sub);
    await social.enqueue(u.sub, u.name, prof.rating?.rating ?? 1500, mode).catch((e: Error) => {
      throw new HttpError(409, e.message);
    });
    return { body: { ok: true } };
  });
  r.on("DELETE", "/queue", async (q) => {
    await social.dequeue(user(q).sub);
    return { body: { ok: true } };
  });
  r.on("GET", "/queue/status", async (q) => ({
    body: { ...(await social.status(user(q).sub)), server: gatewayUrl },
  }));
  r.on("POST", "/select", async (q) => {
    const err = await social.select(
      user(q).sub,
      str(q.body["agent"], "agent"),
      q.body["lock"] === true,
    );
    if (err) throw new HttpError(409, err);
    return { body: { ok: true } };
  });
  r.on("POST", "/reports", async (q) => {
    const reason = str(q.body["reason"], "reason");
    const mid = q.body["matchId"];
    await stats.report(
      user(q).sub,
      str(q.body["target"], "target"),
      typeof mid === "string" ? mid : null,
      reason,
    );
    return { status: 201, body: { ok: true } };
  });
  // Replays (spec §14.4): players of the match may download its .bpr for the in-client viewer.
  r.on("GET", "/replays/:id", async (q) => {
    const claims = user(q);
    const path = replayDir ? replayPath(replayDir, q.params["id"] ?? "") : null;
    if (!path) throw new HttpError(404, "not_found");
    if (!(await stats.playedIn(claims.sub, q.params["id"]!))) throw new HttpError(403, "forbidden");
    try {
      return { body: null, raw: await readFile(path), contentType: "application/x-bp-replay" };
    } catch {
      throw new HttpError(404, "not_found");
    }
  });
  r.on("POST", "/lobby/leave", async (q) => {
    await social.leaveLobby(user(q).sub);
    return { body: { ok: true } };
  });
  return r;
}
