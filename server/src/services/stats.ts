// Stats service (spec §14.1): writes finished matches and per-player lines to PostgreSQL, updates
// Glicko-2 ratings for Competitive, awards XP, and serves match history.
import type { Db } from "./db.ts";
import { glicko2 } from "./rating.ts";

export interface MatchResult {
  matchId: string;
  mode: string;
  map: string;
  score: [number, number];
  winner: number;
  rounds: { round: number; winner: number; reason: string }[];
  players: {
    accountId: string | null;
    name: string;
    team: number;
    agent: string;
    kills: number;
    deaths: number;
    assists: number;
    score: number;
    /** Anti-cheat review flags (server/src/match/anticheat.ts). */
    flags?: { kind: string; value: number; samples: number }[];
  }[];
}

export class StatsService {
  constructor(private readonly db: Db) {}

  async record(r: MatchResult): Promise<void> {
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "INSERT INTO matches(id, mode, map, ended_at, score_a, score_b, winner, rounds) VALUES ($1,$2,$3,now(),$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING",
        [r.matchId, r.mode, r.map, r.score[0], r.score[1], r.winner, JSON.stringify(r.rounds)],
      );
      const deltas =
        r.mode === "competitive" ? await this.rate(client, r) : new Map<string, number>();
      for (const p of r.players) {
        await client.query(
          "INSERT INTO match_players(match_id, account_id, name, team, agent, kills, deaths, assists, score, rating_delta) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT DO NOTHING",
          [
            r.matchId,
            p.accountId,
            p.name,
            p.team,
            p.agent,
            p.kills,
            p.deaths,
            p.assists,
            p.score,
            p.accountId ? (deltas.get(p.accountId) ?? null) : null,
          ],
        );
        for (const f of p.accountId ? (p.flags ?? []) : [])
          await client.query(
            "INSERT INTO anticheat_flags(account_id, match_id, kind, value, samples) VALUES ($1,$2,$3,$4,$5)",
            [p.accountId, r.matchId, f.kind, f.value, f.samples],
          );
        if (p.accountId) {
          const xp = 500 + p.score / 4 + (p.team === r.winner ? 300 : 0);
          await client.query(
            "UPDATE accounts SET xp = xp + $2, level = 1 + (xp + $2) / 5000 WHERE id = $1",
            [p.accountId, Math.round(xp)],
          );
        }
      }
      await client.query("COMMIT");
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }
  }

  private async rate(client: { query: Db["query"] }, r: MatchResult): Promise<Map<string, number>> {
    const humans = r.players.filter(
      (p): p is typeof p & { accountId: string } => p.accountId !== null,
    );
    const rows = new Map<
      string,
      { rating: number; rd: number; volatility: number; games: number }
    >();
    for (const p of humans) {
      const row = (
        await client.query<{ rating: number; rd: number; volatility: number; games: number }>(
          "SELECT rating, rd, volatility, games FROM ratings WHERE account_id = $1",
          [p.accountId],
        )
      ).rows[0];
      rows.set(p.accountId, row ?? { rating: 1500, rd: 350, volatility: 0.06, games: 0 });
    }
    const deltas = new Map<string, number>();
    for (const p of humans) {
      const me = rows.get(p.accountId)!;
      const opps = humans
        .filter((o) => o.team !== p.team)
        .map((o) => ({
          ...rows.get(o.accountId)!,
          score: r.winner < 0 ? 0.5 : p.team === r.winner ? 1 : 0,
        }));
      const next = glicko2(me, opps);
      deltas.set(p.accountId, next.rating - me.rating);
      await client.query(
        "UPDATE ratings SET rating = $2, rd = $3, volatility = $4, games = games + 1 WHERE account_id = $1",
        [p.accountId, next.rating, next.rd, next.volatility],
      );
    }
    return deltas;
  }

  /** In-game report (spec §14.3); reviewers pull the match replay by match id. */
  async report(
    reporterId: string,
    target: string,
    matchId: string | null,
    reason: string,
  ): Promise<void> {
    await this.db.query(
      "INSERT INTO reports(reporter_id, target_name, match_id, reason) VALUES ($1,$2,$3,$4)",
      [reporterId, target.slice(0, 64), matchId?.slice(0, 64) ?? null, reason.slice(0, 200)],
    );
  }

  /** True when the account played in the match (replay access check). */
  async playedIn(accountId: string, matchId: string): Promise<boolean> {
    const { rows } = await this.db.query(
      "SELECT 1 FROM match_players WHERE account_id = $1 AND match_id = $2 LIMIT 1",
      [accountId, matchId],
    );
    return rows.length > 0;
  }

  async history(accountId: string, limit = 20): Promise<unknown[]> {
    const { rows } = await this.db.query(
      `SELECT m.id, m.mode, m.map, m.ended_at, m.score_a, m.score_b, m.winner, mp.team, mp.agent, mp.kills, mp.deaths, mp.assists, mp.score, mp.rating_delta
       FROM match_players mp JOIN matches m ON m.id = mp.match_id WHERE mp.account_id = $1 ORDER BY m.ended_at DESC NULLS LAST LIMIT $2`,
      [accountId, limit],
    );
    return rows;
  }
}
