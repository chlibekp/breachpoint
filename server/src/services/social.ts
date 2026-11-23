// Parties, matchmaking and agent select (spec §14.1). State lives in Redis so several API
// processes can share it; the matcher loop runs in one process (leader by convention in dev).
import { randomUUID } from "node:crypto";
import type { Redis } from "ioredis";
import { sign, verify } from "./jwt.ts";

export const MODES = ["unrated", "competitive", "rapid", "custom"] as const;
export type Mode = (typeof MODES)[number];

export interface QueueEntry {
  key: string;
  mode: Mode;
  members: { accountId: string; name: string; mmr: number }[];
  mmr: number;
  joinedAt: number;
}

export interface Lobby {
  id: string;
  mode: Mode;
  map: string;
  players: {
    accountId: string;
    name: string;
    team: number;
    agent: string;
    locked: boolean;
    bot?: boolean;
  }[];
  deadline: number;
  state: "agent_select" | "ready";
}

export interface JoinTicket {
  matchId: string;
  accountId: string;
  name: string;
  agent: string;
  team: number;
  mode: Mode;
  exp: number;
}

export interface SocialOptions {
  ticketSecret: string;
  agents: string[];
  maps: string[];
  /** Seconds before an Unrated/Rapid/Custom queue fills the remaining slots with bots. */
  fillAfterSec: number;
  /** Minimum humans for Competitive (10 in production; lower for local testing). */
  minCompetitive: number;
  agentSelectSec: number;
  onReady: (lobby: Lobby) => void;
  now?: () => number;
}

const PARTY_MAX = 5;

export class SocialService {
  private timer: NodeJS.Timeout | null = null;
  private readonly now: () => number;

  constructor(
    private readonly redis: Redis,
    private readonly opts: SocialOptions,
  ) {
    this.now = opts.now ?? Date.now;
  }

  start(): void {
    this.timer = setInterval(() => void this.tick(), 1000);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
  }

  // ------------------------------------------------------------------ parties

  async partyOf(accountId: string): Promise<string | null> {
    return this.redis.get(`acct:party:${accountId}`);
  }

  async createParty(accountId: string, name: string): Promise<string> {
    await this.leaveParty(accountId);
    const id = randomUUID();
    await this.redis
      .multi()
      .hset(`party:${id}`, { leader: accountId })
      .hset(`party:${id}:members`, accountId, name)
      .set(`acct:party:${accountId}`, id)
      .exec();
    return id;
  }

  async invite(partyId: string, fromId: string, toAccountId: string): Promise<void> {
    if ((await this.redis.hget(`party:${partyId}`, "leader")) !== fromId)
      throw new Error("not_leader");
    await this.redis
      .multi()
      .lpush(`invites:${toAccountId}`, partyId)
      .ltrim(`invites:${toAccountId}`, 0, 9)
      .expire(`invites:${toAccountId}`, 600)
      .exec();
  }

  async invites(accountId: string): Promise<string[]> {
    return this.redis.lrange(`invites:${accountId}`, 0, -1);
  }

  async joinParty(partyId: string, accountId: string, name: string): Promise<void> {
    const invited = (await this.invites(accountId)).includes(partyId);
    if (!invited) throw new Error("not_invited");
    if ((await this.redis.hlen(`party:${partyId}:members`)) >= PARTY_MAX)
      throw new Error("party_full");
    await this.leaveParty(accountId);
    await this.redis
      .multi()
      .hset(`party:${partyId}:members`, accountId, name)
      .set(`acct:party:${accountId}`, partyId)
      .lrem(`invites:${accountId}`, 0, partyId)
      .exec();
  }

  async leaveParty(accountId: string): Promise<void> {
    const id = await this.partyOf(accountId);
    if (!id) return;
    await this.redis
      .multi()
      .hdel(`party:${id}:members`, accountId)
      .srem(`party:${id}:ready`, accountId)
      .del(`acct:party:${accountId}`)
      .exec();
    const left = await this.redis.hkeys(`party:${id}:members`);
    if (left.length === 0)
      await this.redis.del(
        `party:${id}`,
        `party:${id}:members`,
        `party:${id}:ready`,
        `party:${id}:chat`,
      );
    else if ((await this.redis.hget(`party:${id}`, "leader")) === accountId)
      await this.redis.hset(`party:${id}`, "leader", left[0]!);
  }

  async setReady(accountId: string, ready: boolean): Promise<void> {
    const id = await this.partyOf(accountId);
    if (!id) return;
    if (ready) await this.redis.sadd(`party:${id}:ready`, accountId);
    else await this.redis.srem(`party:${id}:ready`, accountId);
  }

  async chat(accountId: string, name: string, text: string): Promise<void> {
    const id = await this.partyOf(accountId);
    if (!id) return;
    const line = JSON.stringify({ name, text: text.slice(0, 200), at: this.now() });
    await this.redis
      .multi()
      .rpush(`party:${id}:chat`, line)
      .ltrim(`party:${id}:chat`, -50, -1)
      .exec();
  }

  async party(id: string): Promise<{
    id: string;
    leader: string;
    members: { accountId: string; name: string; ready: boolean }[];
    chat: unknown[];
  }> {
    const leader = (await this.redis.hget(`party:${id}`, "leader")) ?? "";
    const members = await this.redis.hgetall(`party:${id}:members`);
    const ready = new Set(await this.redis.smembers(`party:${id}:ready`));
    const chat = (await this.redis.lrange(`party:${id}:chat`, -20, -1)).map(
      (l) => JSON.parse(l) as unknown,
    );
    return {
      id,
      leader,
      members: Object.entries(members).map(([accountId, name]) => ({
        accountId,
        name,
        ready: ready.has(accountId),
      })),
      chat,
    };
  }

  // ------------------------------------------------------------------ queue

  async enqueue(accountId: string, name: string, mmr: number, mode: Mode): Promise<string> {
    const partyId = await this.partyOf(accountId);
    let members = [{ accountId, name, mmr }];
    let key = `solo:${accountId}`;
    if (partyId) {
      const p = await this.party(partyId);
      if (p.leader !== accountId) throw new Error("not_leader");
      if (p.members.some((m) => !m.ready && m.accountId !== accountId))
        throw new Error("party_not_ready");
      key = `party:${partyId}`;
      members = await Promise.all(
        p.members.map(async (m) => ({
          accountId: m.accountId,
          name: m.name,
          mmr: Number((await this.redis.get(`mmr:${m.accountId}`)) ?? mmr),
        })),
      );
    }
    const avg = members.reduce((a, m) => a + m.mmr, 0) / members.length;
    const entry: QueueEntry = { key, mode, members, mmr: avg, joinedAt: this.now() };
    await this.redis
      .multi()
      .set(`mm:entry:${key}`, JSON.stringify(entry))
      .zadd(`mm:${mode}`, avg, key)
      .exec();
    for (const m of members) await this.redis.set(`acct:queue:${m.accountId}`, key);
    return key;
  }

  async dequeue(accountId: string): Promise<void> {
    const key = await this.redis.get(`acct:queue:${accountId}`);
    if (!key) return;
    const raw = await this.redis.get(`mm:entry:${key}`);
    if (raw) {
      const e = JSON.parse(raw) as QueueEntry;
      await this.redis.zrem(`mm:${e.mode}`, key);
      for (const m of e.members) await this.redis.del(`acct:queue:${m.accountId}`);
    }
    await this.redis.del(`mm:entry:${key}`);
  }

  /** What the client should show: queued (with wait time), agent select, or ready with a ticket. */
  async status(accountId: string): Promise<Record<string, unknown>> {
    const lobbyId = await this.redis.get(`acct:lobby:${accountId}`);
    if (lobbyId) {
      const lobby = await this.lobby(lobbyId);
      if (lobby) {
        const me = lobby.players.find((p) => p.accountId === accountId)!;
        const out: Record<string, unknown> = {
          state: lobby.state,
          lobbyId,
          mode: lobby.mode,
          map: lobby.map,
          team: me.team,
          deadline: lobby.deadline,
          roster: lobby.players
            .filter((p) => p.team === me.team)
            .map((p) => ({ name: p.name, agent: p.agent, locked: p.locked, bot: p.bot ?? false })),
        };
        if (lobby.state === "ready") out["ticket"] = this.ticket(lobby, me);
        return out;
      }
    }
    const key = await this.redis.get(`acct:queue:${accountId}`);
    if (key) {
      const raw = await this.redis.get(`mm:entry:${key}`);
      if (raw) {
        const e = JSON.parse(raw) as QueueEntry;
        return {
          state: "queued",
          mode: e.mode,
          waitSec: Math.round((this.now() - e.joinedAt) / 1000),
        };
      }
    }
    return { state: "idle" };
  }

  ticket(lobby: Lobby, p: Lobby["players"][number]): string {
    return sign(
      {
        matchId: lobby.id,
        accountId: p.accountId,
        name: p.name,
        agent: p.agent,
        team: p.team,
        mode: lobby.mode,
        exp: Math.floor(this.now() / 1000) + 600,
      } satisfies JoinTicket,
      this.opts.ticketSecret,
    );
  }

  verifyTicket(t: string): JoinTicket | null {
    return verify<JoinTicket>(t, this.opts.ticketSecret, this.now() / 1000);
  }

  // ------------------------------------------------------------------ agent select

  async lobby(id: string): Promise<Lobby | null> {
    const raw = await this.redis.get(`lobby:${id}`);
    return raw ? (JSON.parse(raw) as Lobby) : null;
  }

  private async saveLobby(l: Lobby): Promise<void> {
    await this.redis.set(`lobby:${l.id}`, JSON.stringify(l), "EX", 7200);
  }

  /** Hover or lock an agent; duplicates are prevented per team (spec §14.1). */
  async select(accountId: string, agent: string, lock: boolean): Promise<string> {
    const lobbyId = await this.redis.get(`acct:lobby:${accountId}`);
    const lobby = lobbyId ? await this.lobby(lobbyId) : null;
    if (!lobby || lobby.state !== "agent_select") return "no_lobby";
    if (!this.opts.agents.includes(agent)) return "unknown_agent";
    const me = lobby.players.find((p) => p.accountId === accountId)!;
    if (me.locked) return "already_locked";
    if (lobby.players.some((p) => p.team === me.team && p.locked && p.agent === agent))
      return "taken";
    me.agent = agent;
    me.locked = lock;
    await this.saveLobby(lobby);
    if (lobby.players.every((p) => p.locked)) await this.finishSelect(lobby);
    return "";
  }

  private async finishSelect(lobby: Lobby): Promise<void> {
    for (const team of [0, 1]) {
      const taken = new Set(
        lobby.players.filter((p) => p.team === team && p.locked).map((p) => p.agent),
      );
      for (const p of lobby.players.filter((q) => q.team === team && !q.locked)) {
        const free = this.opts.agents.find((a) => !taken.has(a)) ?? this.opts.agents[0]!;
        p.agent = free;
        p.locked = true;
        taken.add(free);
      }
    }
    lobby.state = "ready";
    await this.saveLobby(lobby);
    this.opts.onReady(lobby);
  }

  // ------------------------------------------------------------------ matcher

  async tick(): Promise<void> {
    for (const mode of MODES) {
      const keys = await this.redis.zrange(`mm:${mode}`, 0, -1);
      const entries = (await Promise.all(keys.map(async (k) => this.redis.get(`mm:entry:${k}`))))
        .filter((r): r is string => r !== null)
        .map((r) => JSON.parse(r) as QueueEntry);
      const used = new Set<string>();
      for (const seed of entries) {
        if (used.has(seed.key)) continue;
        const wait = (this.now() - seed.joinedAt) / 1000;
        // Widen the MMR window over time (spec §14.1).
        const window = 100 + wait * 25;
        const group: QueueEntry[] = [seed];
        let count = seed.members.length;
        for (const other of entries) {
          if (other === seed || used.has(other.key) || count + other.members.length > 10) continue;
          if (Math.abs(other.mmr - seed.mmr) <= window) {
            group.push(other);
            count += other.members.length;
          }
        }
        const need = mode === "competitive" ? this.opts.minCompetitive : 10;
        const fill = mode !== "competitive" && wait >= this.opts.fillAfterSec;
        if (count >= need || fill) {
          for (const g of group) used.add(g.key);
          await this.formLobby(mode, group, mode !== "competitive");
        }
      }
    }
    // Agent-select deadlines.
    for (const key of await this.redis.keys("lobby:*")) {
      const l = await this.lobby(key.slice(6));
      if (l && l.state === "agent_select" && this.now() >= l.deadline) await this.finishSelect(l);
    }
  }

  private async formLobby(mode: Mode, group: QueueEntry[], fillBots: boolean): Promise<void> {
    const id = `mm-${randomUUID().slice(0, 8)}`;
    const players: Lobby["players"] = [];
    // Keep parties together: alternate whole entries between teams by size.
    const sizes = [0, 0];
    for (const g of [...group].sort((a, b) => b.members.length - a.members.length)) {
      const team = sizes[0]! <= sizes[1]! ? 0 : 1;
      for (const m of g.members)
        players.push({ accountId: m.accountId, name: m.name, team, agent: "", locked: false });
      sizes[team] = sizes[team]! + g.members.length;
    }
    const lobby: Lobby = {
      id,
      mode,
      map: this.opts.maps[Math.floor(Math.random() * this.opts.maps.length)]!,
      players,
      deadline: this.now() + this.opts.agentSelectSec * 1000,
      state: "agent_select",
    };
    void fillBots; // bots are added by the match itself (fillBots) once humans join
    const m = this.redis.multi();
    for (const g of group) {
      m.zrem(`mm:${mode}`, g.key).del(`mm:entry:${g.key}`);
      for (const mem of g.members)
        m.del(`acct:queue:${mem.accountId}`).set(`acct:lobby:${mem.accountId}`, id, "EX", 7200);
    }
    await m.exec();
    await this.saveLobby(lobby);
  }

  async leaveLobby(accountId: string): Promise<void> {
    await this.redis.del(`acct:lobby:${accountId}`);
  }
}
