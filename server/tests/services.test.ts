// Integration tests for the backend services. Require PostgreSQL + Redis (CI provides them as
// service containers; locally: DATABASE_URL / REDIS_URL). Skipped when not configured.
import { Redis } from "ioredis";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuthService, rankTier } from "../src/services/auth.ts";
import { connect, migrate, type Db } from "../src/services/db.ts";
import { glicko2 } from "../src/services/rating.ts";
import { SocialService, type Lobby } from "../src/services/social.ts";
import { StatsService } from "../src/services/stats.ts";

const DB = process.env["TEST_DATABASE_URL"];
const REDIS = process.env["TEST_REDIS_URL"];
const run = DB && REDIS ? describe : describe.skip;

describe("glicko-2", () => {
  it("matches the worked example from Glickman's paper (±0.5)", () => {
    const r = glicko2({ rating: 1500, rd: 200, volatility: 0.06 }, [
      { rating: 1400, rd: 30, score: 1 },
      { rating: 1550, rd: 100, score: 0 },
      { rating: 1700, rd: 300, score: 0 },
    ]);
    expect(r.rating).toBeCloseTo(1464.06, 0);
    expect(r.rd).toBeCloseTo(151.52, 0);
  });
  it("names rank tiers", () => {
    expect(rankTier(1500, 2)).toBe("Unranked");
    expect(rankTier(1150, 10)).toBe("Shard 1");
    expect(rankTier(2200, 10)).toBe("Apex");
  });
});

run("auth, party, matchmaking, stats (Postgres + Redis)", () => {
  let db: Db;
  let redis: Redis;
  let auth: AuthService;
  let social: SocialService;
  const ready: Lobby[] = [];
  let clock = 1_000_000;

  beforeAll(async () => {
    db = connect(DB!);
    await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
    await migrate(db);
    redis = new Redis(REDIS!);
    await redis.flushdb();
    auth = new AuthService(db, "test-secret");
    social = new SocialService(redis, {
      ticketSecret: "t",
      agents: ["kestrel", "mamba", "vesper"],
      maps: ["solstice"],
      fillAfterSec: 5,
      minCompetitive: 2,
      agentSelectSec: 80,
      onReady: (l) => ready.push(l),
      now: () => clock,
    });
  });
  afterAll(async () => {
    await db.end();
    redis.disconnect();
  });

  it("registers, logs in, rotates refresh tokens and detects reuse", async () => {
    const reg = await auth.register("ana@example.com", "correct horse", "Ana");
    expect(reg.account.name).toBe("Ana");
    expect(auth.verifyAccess(reg.accessToken)?.name).toMatch(/^Ana#\d{4}$/);
    await expect(auth.login("ana@example.com", "wrong password")).rejects.toThrow(
      "invalid_credentials",
    );
    const r2 = await auth.refresh(reg.refreshToken);
    await expect(auth.refresh(reg.refreshToken)).rejects.toThrow("refresh_reused");
    await expect(auth.refresh(r2.refreshToken)).rejects.toThrow(); // family revoked
  });

  it("parties up, queues competitive, agent-selects without duplicates, issues tickets", async () => {
    const a = await auth.register("a@x.io", "password1", "Alpha");
    const b = await auth.register("b@x.io", "password2", "Bravo");
    const party = await social.createParty(a.account.id, "Alpha#1");
    await social.invite(party, a.account.id, b.account.id);
    await social.joinParty(party, b.account.id, "Bravo#2");
    await expect(social.enqueue(a.account.id, "Alpha#1", 1500, "competitive")).rejects.toThrow(
      "party_not_ready",
    );
    await social.setReady(b.account.id, true);
    await social.enqueue(a.account.id, "Alpha#1", 1500, "competitive");
    expect((await social.status(b.account.id))["state"]).toBe("queued");
    await social.tick();
    const st = await social.status(a.account.id);
    expect(st["state"]).toBe("agent_select");
    expect(await social.select(a.account.id, "kestrel", true)).toBe("");
    // Same team (party kept together): duplicate lock refused.
    expect(await social.select(b.account.id, "kestrel", true)).toBe("taken");
    expect(await social.select(b.account.id, "vesper", true)).toBe("");
    expect(ready).toHaveLength(1);
    const final = await social.status(b.account.id);
    expect(final["state"]).toBe("ready");
    const t = social.verifyTicket(String(final["ticket"]));
    expect(t?.agent).toBe("vesper");
    expect(t?.matchId).toBe(ready[0]!.id);
  });

  it("records a competitive result with rating changes and history", async () => {
    const x = await auth.register("x@x.io", "password3", "Xen");
    const y = await auth.register("y@x.io", "password4", "Yor");
    const stats = new StatsService(db);
    await stats.record({
      matchId: "m-test",
      mode: "competitive",
      map: "solstice",
      score: [13, 7],
      winner: 0,
      rounds: [],
      players: [
        {
          accountId: x.account.id,
          name: "Xen",
          team: 0,
          agent: "kestrel",
          kills: 20,
          deaths: 10,
          assists: 3,
          score: 5000,
        },
        {
          accountId: y.account.id,
          name: "Yor",
          team: 1,
          agent: "mamba",
          kills: 10,
          deaths: 20,
          assists: 1,
          score: 2500,
        },
      ],
    });
    const hx = (await stats.history(x.account.id)) as { rating_delta: number }[];
    expect(hx).toHaveLength(1);
    expect(hx[0]!.rating_delta).toBeGreaterThan(0);
    expect((await auth.profile(x.account.id)).rating?.games).toBe(1);
    clock += 1;
  });
});
