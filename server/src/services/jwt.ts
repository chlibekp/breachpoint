// Minimal HS256 JWT (no dependency) for short-lived access tokens, plus HMAC-signed join tickets
// (spec §14.1, §14.3: sign join tickets, never expose internal addresses).
import { createHmac, timingSafeEqual } from "node:crypto";

const b64url = (b: Buffer | string): string => Buffer.from(b).toString("base64url");

export interface AccessClaims {
  sub: string;
  name: string;
  guest: boolean;
  exp: number;
}

export function sign(payload: object, secret: string): string {
  const head = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(payload));
  const sig = b64url(createHmac("sha256", secret).update(`${head}.${body}`).digest());
  return `${head}.${body}.${sig}`;
}

export function verify<T extends { exp?: number }>(
  token: string,
  secret: string,
  nowSec = Date.now() / 1000,
): T | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts as [string, string, string];
  const expect = createHmac("sha256", secret).update(`${head}.${body}`).digest();
  const got = Buffer.from(sig, "base64url");
  if (got.length !== expect.length || !timingSafeEqual(got, expect)) return null;
  try {
    const claims = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as T;
    if (claims.exp !== undefined && claims.exp < nowSec) return null;
    return claims;
  } catch {
    return null;
  }
}
