// Auth + profile service (spec §14.1): email/password (argon2id), guest accounts for quick play in
// the browser, short-lived JWT access tokens (15 min) and rotating refresh tokens (30 days) with
// reuse detection (a replayed, already-rotated token revokes its whole family).
import { createHash, randomBytes, randomUUID } from "node:crypto";
import argon2 from "argon2";
import type { Db } from "./db.ts";
import { sign, verify, type AccessClaims } from "./jwt.ts";

export interface Tokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  account: PublicProfile;
}

export interface PublicProfile {
  id: string;
  name: string;
  tag: string;
  guest: boolean;
  level: number;
  xp: number;
  settings: Record<string, unknown>;
  loadout: Record<string, unknown>;
  ownedSkins: string[];
  rating?: { rating: number; rd: number; games: number; tier: string };
}

export class AuthError extends Error {
  constructor(
    readonly code: string,
    readonly status = 400,
  ) {
    super(code);
  }
}

const ACCESS_TTL = 15 * 60;
const REFRESH_TTL_DAYS = 30;
const NAME_RE = /^[A-Za-z0-9 _-]{3,16}$/;
const EMAIL_RE = /^[^@\s]{1,64}@[^@\s]{1,255}$/;

const sha256 = (s: string): string => createHash("sha256").update(s).digest("hex");

interface AccountRow {
  id: string;
  email: string | null;
  password_hash: string | null;
  name: string;
  tag: string;
  guest: boolean;
  level: number;
  xp: number;
  settings: Record<string, unknown>;
  loadout: Record<string, unknown>;
  owned_skins: string[];
}

export class AuthService {
  constructor(
    private readonly db: Db,
    private readonly secret: string,
  ) {}

  verifyAccess(token: string): AccessClaims | null {
    return verify<AccessClaims>(token, this.secret);
  }

  async register(email: string, password: string, name: string): Promise<Tokens> {
    if (!EMAIL_RE.test(email)) throw new AuthError("invalid_email");
    if (password.length < 8 || password.length > 128) throw new AuthError("weak_password");
    if (!NAME_RE.test(name)) throw new AuthError("invalid_name");
    const hash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    try {
      const row = await this.insertAccount(name, email.toLowerCase(), hash, false);
      return this.issue(row);
    } catch (e) {
      if ((e as { code?: string }).code === "23505") throw new AuthError("email_taken", 409);
      throw e;
    }
  }

  async login(email: string, password: string): Promise<Tokens> {
    const { rows } = await this.db.query<AccountRow>("SELECT * FROM accounts WHERE email = $1", [
      email.toLowerCase(),
    ]);
    const row = rows[0];
    // Constant-ish work whether or not the account exists.
    const ok = row?.password_hash
      ? await argon2.verify(row.password_hash, password)
      : await argon2
          .verify(
            "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0$WxQYd2Ki7cPZ8yH2xm7m2nnQ5dB0uR3YVQpBZqkQK9c",
            password,
          )
          .catch(() => false);
    if (!row || !ok) throw new AuthError("invalid_credentials", 401);
    return this.issue(row);
  }

  async guest(): Promise<Tokens> {
    const row = await this.insertAccount(
      `Guest${Math.floor(Math.random() * 9000 + 1000)}`,
      null,
      null,
      true,
    );
    return this.issue(row);
  }

  async refresh(refreshToken: string): Promise<Tokens> {
    const { rows } = await this.db.query<{
      id: string;
      account_id: string;
      family: string;
      revoked: boolean;
      expires_at: Date;
    }>(
      "SELECT id, account_id, family, revoked, expires_at FROM refresh_tokens WHERE token_hash = $1",
      [sha256(refreshToken)],
    );
    const t = rows[0];
    if (!t) throw new AuthError("invalid_refresh", 401);
    if (t.revoked) {
      // Reuse of a rotated token: assume theft, revoke the whole family.
      await this.db.query("UPDATE refresh_tokens SET revoked = TRUE WHERE family = $1", [t.family]);
      throw new AuthError("refresh_reused", 401);
    }
    if (t.expires_at.getTime() < Date.now()) throw new AuthError("refresh_expired", 401);
    await this.db.query("UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1", [t.id]);
    const acc = (
      await this.db.query<AccountRow>("SELECT * FROM accounts WHERE id = $1", [t.account_id])
    ).rows[0];
    if (!acc) throw new AuthError("invalid_refresh", 401);
    return this.issue(acc, t.family);
  }

  async profile(accountId: string): Promise<PublicProfile> {
    const row = (
      await this.db.query<AccountRow>("SELECT * FROM accounts WHERE id = $1", [accountId])
    ).rows[0];
    if (!row) throw new AuthError("not_found", 404);
    const r = (
      await this.db.query<{ rating: number; rd: number; games: number }>(
        "SELECT rating, rd, games FROM ratings WHERE account_id = $1",
        [accountId],
      )
    ).rows[0];
    const p = this.toPublic(row);
    if (r) p.rating = { ...r, tier: rankTier(r.rating, r.games) };
    return p;
  }

  async updateJson(
    accountId: string,
    field: "settings" | "loadout",
    value: Record<string, unknown>,
  ): Promise<void> {
    if (JSON.stringify(value).length > 16384) throw new AuthError("too_large", 413);
    await this.db.query(`UPDATE accounts SET ${field} = $2 WHERE id = $1`, [
      accountId,
      JSON.stringify(value),
    ]);
  }

  async findByNameTag(nameTag: string): Promise<{ id: string; name: string; tag: string } | null> {
    const [name, tag] = nameTag.split("#");
    if (!name || !tag) return null;
    const r = (
      await this.db.query<{ id: string; name: string; tag: string }>(
        "SELECT id, name, tag FROM accounts WHERE name = $1 AND tag = $2",
        [name, tag],
      )
    ).rows[0];
    return r ?? null;
  }

  private async insertAccount(
    name: string,
    email: string | null,
    hash: string | null,
    guest: boolean,
  ): Promise<AccountRow> {
    for (let attempt = 0; attempt < 8; attempt++) {
      const tag = String(Math.floor(Math.random() * 9000 + 1000));
      try {
        const { rows } = await this.db.query<AccountRow>(
          "INSERT INTO accounts(email, password_hash, name, tag, guest) VALUES ($1, $2, $3, $4, $5) RETURNING *",
          [email, hash, name, tag, guest],
        );
        await this.db.query("INSERT INTO ratings(account_id) VALUES ($1)", [rows[0]!.id]);
        return rows[0]!;
      } catch (e) {
        // Retry only on a (name, tag) collision; email collisions bubble up.
        if (
          (e as { code?: string; constraint?: string }).code === "23505" &&
          (e as { constraint?: string }).constraint === "accounts_name_tag_key"
        )
          continue;
        throw e;
      }
    }
    throw new AuthError("name_unavailable", 409);
  }

  private async issue(row: AccountRow, family: string = randomUUID()): Promise<Tokens> {
    const now = Math.floor(Date.now() / 1000);
    const accessToken = sign(
      {
        sub: String(row.id),
        name: `${row.name}#${row.tag}`,
        guest: row.guest,
        exp: now + ACCESS_TTL,
      } satisfies AccessClaims,
      this.secret,
    );
    const refreshToken = randomBytes(32).toString("base64url");
    await this.db.query(
      "INSERT INTO refresh_tokens(account_id, token_hash, family, expires_at) VALUES ($1, $2, $3, now() + ($4 || ' days')::interval)",
      [row.id, sha256(refreshToken), family, String(REFRESH_TTL_DAYS)],
    );
    return { accessToken, refreshToken, expiresIn: ACCESS_TTL, account: this.toPublic(row) };
  }

  private toPublic(row: AccountRow): PublicProfile {
    return {
      id: String(row.id),
      name: row.name,
      tag: row.tag,
      guest: row.guest,
      level: row.level,
      xp: row.xp,
      settings: row.settings,
      loadout: row.loadout,
      ownedSkins: row.owned_skins,
    };
  }
}

/** Visible rank tiers with original names (spec §14.1): Shard, Prism, Lumen, Nova, Zenith, Apex. */
export function rankTier(rating: number, games: number): string {
  if (games < 5) return "Unranked";
  const tiers = ["Shard", "Prism", "Lumen", "Nova", "Zenith"];
  if (rating >= 2100) return "Apex";
  const idx = Math.max(0, Math.min(tiers.length - 1, Math.floor((rating - 1100) / 200)));
  const div = Math.max(1, Math.min(3, Math.floor(((rating - 1100) % 200) / 66.7) + 1));
  return `${tiers[idx]} ${div}`;
}
