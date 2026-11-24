// OAuth 2.0 sign-in with Google and Discord (spec §14.1), authorization-code flow with PKCE.
// Works the same for the desktop client and the browser build:
//   1. client POST /auth/oauth/start {provider}  → {url, session}; it opens `url` in a browser
//   2. browser → provider → GET /auth/oauth/callback?code&state → account linked/created, tokens
//      parked in Redis under the session for 2 minutes, a "return to the game" page is shown
//   3. client polls GET /auth/oauth/poll?session=… until it receives the tokens (one-shot)
// Providers are enabled by OAUTH_<GOOGLE|DISCORD>_CLIENT_ID / _CLIENT_SECRET; OAUTH_REDIRECT_BASE is
// the public base URL of this API (the callback is <base>/auth/oauth/callback). Endpoint URLs can be
// overridden (OAUTH_<P>_AUTH_URL / _TOKEN_URL / _USERINFO_URL) for tests and self-hosted proxies.
import { createHash, randomBytes } from "node:crypto";
import type { Redis } from "ioredis";
import type { AuthService, Tokens } from "./auth.ts";
import { HttpError } from "./http.ts";

export interface ProviderConfig {
  id: "google" | "discord";
  clientId: string;
  clientSecret: string;
  authUrl: string;
  tokenUrl: string;
  userInfoUrl: string;
  scope: string;
}

interface Profile {
  subject: string;
  email: string | null;
  emailVerified: boolean;
  name: string;
}

const DEFAULTS = {
  google: {
    authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    userInfoUrl: "https://openidconnect.googleapis.com/v1/userinfo",
    scope: "openid email profile",
  },
  discord: {
    authUrl: "https://discord.com/oauth2/authorize",
    tokenUrl: "https://discord.com/api/oauth2/token",
    userInfoUrl: "https://discord.com/api/users/@me",
    scope: "identify email",
  },
} as const;

/** Reads enabled providers from the environment. */
export function providersFromEnv(env: NodeJS.ProcessEnv): ProviderConfig[] {
  const out: ProviderConfig[] = [];
  for (const id of ["google", "discord"] as const) {
    const p = id.toUpperCase();
    const clientId = env[`OAUTH_${p}_CLIENT_ID`];
    const clientSecret = env[`OAUTH_${p}_CLIENT_SECRET`];
    if (!clientId || !clientSecret) continue;
    out.push({
      id,
      clientId,
      clientSecret,
      authUrl: env[`OAUTH_${p}_AUTH_URL`] ?? DEFAULTS[id].authUrl,
      tokenUrl: env[`OAUTH_${p}_TOKEN_URL`] ?? DEFAULTS[id].tokenUrl,
      userInfoUrl: env[`OAUTH_${p}_USERINFO_URL`] ?? DEFAULTS[id].userInfoUrl,
      scope: DEFAULTS[id].scope,
    });
  }
  return out;
}

const b64url = (b: Buffer): string => b.toString("base64url");
const STATE_TTL = 600;
const RESULT_TTL = 120;

export class OAuthService {
  private readonly providers = new Map<string, ProviderConfig>();

  constructor(
    private readonly redis: Redis,
    private readonly auth: AuthService,
    providers: ProviderConfig[],
    private readonly redirectBase: string,
  ) {
    for (const p of providers) this.providers.set(p.id, p);
  }

  get enabled(): string[] {
    return [...this.providers.keys()];
  }

  private get callbackUrl(): string {
    return `${this.redirectBase.replace(/\/$/, "")}/auth/oauth/callback`;
  }

  async start(providerId: string): Promise<{ url: string; session: string }> {
    const p = this.providers.get(providerId);
    if (!p) throw new HttpError(404, "provider_not_enabled");
    const state = b64url(randomBytes(24));
    const session = b64url(randomBytes(24));
    const verifier = b64url(randomBytes(32));
    const challenge = b64url(createHash("sha256").update(verifier).digest());
    await this.redis.set(
      `oauth:state:${state}`,
      JSON.stringify({ provider: p.id, verifier, session }),
      "EX",
      STATE_TTL,
    );
    await this.redis.set(
      `oauth:session:${session}`,
      JSON.stringify({ status: "pending" }),
      "EX",
      STATE_TTL,
    );
    const q = new URLSearchParams({
      client_id: p.clientId,
      redirect_uri: this.callbackUrl,
      response_type: "code",
      scope: p.scope,
      state,
      code_challenge: challenge,
      code_challenge_method: "S256",
    });
    if (p.id === "google") q.set("prompt", "select_account");
    return { url: `${p.authUrl}?${q.toString()}`, session };
  }

  /** Handles the provider redirect. Returns HTML for the browser tab. */
  async callback(query: Record<string, string>): Promise<string> {
    const state = query["state"] ?? "";
    const raw = await this.redis.getdel(`oauth:state:${state}`);
    if (!raw) return page("Sign-in expired", "Start the sign-in again from the game.");
    const st = JSON.parse(raw) as { provider: string; verifier: string; session: string };
    const p = this.providers.get(st.provider)!;
    if (query["error"] || !query["code"]) {
      await this.park(st.session, { status: "error", error: query["error"] ?? "denied" });
      return page("Sign-in cancelled", "You can close this tab and return to the game.");
    }
    try {
      const profile = await this.fetchProfile(p, query["code"], st.verifier);
      const tokens = await this.auth.oauthLogin({ provider: p.id, ...profile });
      await this.park(st.session, { status: "ok", tokens });
      return page("Signed in", "You can close this tab and return to BREACHPOINT.");
    } catch (e) {
      console.error(
        JSON.stringify({ level: "error", msg: "oauth callback failed", error: String(e) }),
      );
      await this.park(st.session, { status: "error", error: "provider_error" });
      return page("Sign-in failed", "Something went wrong talking to the provider. Try again.");
    }
  }

  /** One-shot result for the polling client. */
  async poll(session: string): Promise<{ status: string; tokens?: Tokens; error?: string }> {
    const key = `oauth:session:${session}`;
    const raw = await this.redis.get(key);
    if (!raw) throw new HttpError(404, "unknown_session");
    const v = JSON.parse(raw) as { status: string; tokens?: Tokens; error?: string };
    if (v.status !== "pending") await this.redis.del(key);
    return v;
  }

  private async park(session: string, value: object): Promise<void> {
    await this.redis.set(`oauth:session:${session}`, JSON.stringify(value), "EX", RESULT_TTL);
  }

  private async fetchProfile(p: ProviderConfig, code: string, verifier: string): Promise<Profile> {
    const res = await fetch(p.tokenUrl, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: this.callbackUrl,
        client_id: p.clientId,
        client_secret: p.clientSecret,
        code_verifier: verifier,
      }),
    });
    if (!res.ok) throw new Error(`token endpoint ${res.status}`);
    const token = (await res.json()) as { access_token?: string };
    if (!token.access_token) throw new Error("no access_token");
    const ui = await fetch(p.userInfoUrl, {
      headers: { authorization: `Bearer ${token.access_token}`, accept: "application/json" },
    });
    if (!ui.ok) throw new Error(`userinfo ${ui.status}`);
    const u = (await ui.json()) as Record<string, unknown>;
    if (p.id === "google")
      return {
        subject: String(u["sub"]),
        email: typeof u["email"] === "string" ? u["email"] : null,
        emailVerified: u["email_verified"] === true,
        name: String(u["given_name"] ?? u["name"] ?? ""),
      };
    return {
      subject: String(u["id"]),
      email: typeof u["email"] === "string" ? u["email"] : null,
      emailVerified: u["verified"] === true,
      name: String(u["global_name"] ?? u["username"] ?? ""),
    };
  }
}

function page(title: string, text: string): string {
  const esc = (s: string): string =>
    s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)} · BREACHPOINT</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0e14;color:#eceff4;font:16px system-ui,sans-serif}main{text-align:center;padding:24px}h1{font-size:28px;letter-spacing:.08em;margin:0 0 8px}p{color:#9aa3b2}</style></head><body><main><h1>${esc(title.toUpperCase())}</h1><p>${esc(text)}</p></main></body></html>`;
}
