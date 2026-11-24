import { createServer, type Server } from "node:http";
import { Redis } from "ioredis";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuthService } from "../src/services/auth.ts";
import { connect, migrate, type Db } from "../src/services/db.ts";
import { OAuthService, providersFromEnv } from "../src/services/oauth.ts";

const DB = process.env["TEST_DATABASE_URL"];
const REDIS = process.env["TEST_REDIS_URL"];
const run = DB && REDIS ? describe : describe.skip;

describe("oauth provider config", () => {
  it("enables only providers with both client id and secret", () => {
    const p = providersFromEnv({
      OAUTH_GOOGLE_CLIENT_ID: "g",
      OAUTH_GOOGLE_CLIENT_SECRET: "gs",
      OAUTH_DISCORD_CLIENT_ID: "d",
    });
    expect(p.map((x) => x.id)).toEqual(["google"]);
    expect(p[0]!.tokenUrl).toBe("https://oauth2.googleapis.com/token");
  });
});

run("oauth sign-in against a fake provider (Postgres + Redis)", () => {
  let db: Db;
  let redis: Redis;
  let fake: Server;
  let oauth: OAuthService;
  let auth: AuthService;
  // What the fake provider will report for the next login.
  let user: Record<string, unknown> = {};
  let lastTokenBody = "";

  beforeAll(async () => {
    db = connect(DB!);
    await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
    await migrate(db);
    redis = new Redis(REDIS!);
    fake = createServer((req, res) => {
      let body = "";
      req.on("data", (c: Buffer) => (body += c.toString()));
      req.on("end", () => {
        res.setHeader("content-type", "application/json");
        if (req.url === "/token") {
          lastTokenBody = body;
          res.end(JSON.stringify({ access_token: "at-123", token_type: "Bearer" }));
        } else if (req.url === "/me" && req.headers.authorization === "Bearer at-123") {
          res.end(JSON.stringify(user));
        } else res.writeHead(401).end("{}");
      });
    });
    await new Promise<void>((r) => fake.listen(18081, "127.0.0.1", () => r()));
    auth = new AuthService(db, "test-secret");
    const providers = providersFromEnv({
      OAUTH_DISCORD_CLIENT_ID: "cid",
      OAUTH_DISCORD_CLIENT_SECRET: "csecret",
      OAUTH_DISCORD_TOKEN_URL: "http://127.0.0.1:18081/token",
      OAUTH_DISCORD_USERINFO_URL: "http://127.0.0.1:18081/me",
    });
    oauth = new OAuthService(redis, auth, providers, "http://api.test");
  });
  afterAll(async () => {
    fake.close();
    await db.end();
    redis.disconnect();
  });

  async function signIn(): Promise<{ id: string; name: string }> {
    const { url, session } = await oauth.start("discord");
    const u = new URL(url);
    expect(u.searchParams.get("code_challenge_method")).toBe("S256");
    expect(u.searchParams.get("redirect_uri")).toBe("http://api.test/auth/oauth/callback");
    expect((await oauth.poll(session)).status).toBe("pending");
    const html = await oauth.callback({ code: "the-code", state: u.searchParams.get("state")! });
    expect(html).toContain("SIGNED IN");
    expect(lastTokenBody).toContain("code_verifier=");
    const r = await oauth.poll(session);
    expect(r.status).toBe("ok");
    await expect(oauth.poll(session)).rejects.toThrow(); // one-shot
    return { id: r.tokens!.account.id, name: r.tokens!.account.name };
  }

  it("creates an account on first sign-in and reuses it after", async () => {
    user = { id: "d-1", username: "Night Owl!", email: "owl@example.com", verified: true };
    const a = await signIn();
    expect(a.name).toBe("NightOwl");
    const b = await signIn();
    expect(b.id).toBe(a.id);
  });

  it("links to an existing account only through a verified e-mail", async () => {
    const reg = await auth.register("mira@example.com", "hunter2hunter2", "Mira");
    user = { id: "d-2", username: "mira", email: "MIRA@example.com", verified: false };
    expect((await signIn()).id).not.toBe(reg.account.id);
    user = { id: "d-3", username: "mira", email: "mira@example.com", verified: true };
    expect((await signIn()).id).toBe(reg.account.id);
  });

  it("rejects a replayed or unknown state", async () => {
    const html = await oauth.callback({ code: "x", state: "nope" });
    expect(html).toContain("EXPIRED");
    await expect(oauth.start("google")).rejects.toThrow();
  });
});
