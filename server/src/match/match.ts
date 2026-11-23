// Authoritative match (spec §10, §13): fixed 64 Hz loop over the pure sim. Players and bots send
// input commands; the server simulates movement + weapons, resolves lag-compensated hitscan,
// runs the round state machine and economy, and sends each client a fog-of-war-culled snapshot.
// I/O-free: callers pass `send(playerId, message)`; the worker/gateway does the transport.
import { loadRawConfig } from "@breachpoint/shared/config";
import type { InputCmd, Message, PlayerState } from "@breachpoint/shared/protocol";
import type { World } from "../sim/collision.ts";
import { segmentBlocked } from "../sim/collision.ts";
import {
  traceShot,
  viewDir,
  type HitboxConfig,
  type MaterialTag,
  type TargetPose,
} from "../sim/hitscan.ts";
import {
  Buttons as B,
  newMoveState,
  playerHeight,
  speedFraction,
  stepMovement,
  type MoveState,
  type MovementConfig,
} from "../sim/movement.ts";
import { hashSeed, mulberry32 } from "../sim/rng.ts";
import { TICK_RATE } from "../sim/constants.ts";
import {
  damageAt,
  newWeaponState,
  startReload,
  tryFire,
  updateWeapon,
  type WeaponDef,
  type WeaponState,
} from "../sim/weapons.ts";
import { FixedTickLoop } from "./fixed-tick-loop.ts";
import { BotBrain, NavGraph, type BotGoal } from "./bot-brain.ts";
import { inBox, loadMeta, loadWorld, type MapMeta, type V3 } from "./world-data.ts";
import { AbilityEngine, type AbilityPlayer, type AgentDef, type Effect } from "./abilities.ts";
import { ensureReplayDir, REPLAY_EVERY, ReplayRecorder, replayPath } from "./replay.ts";
import { AntiCheat, type AntiCheatConfig } from "./anticheat.ts";

export interface MatchOptions {
  mode?: string;
  matchId: string;
  map: string;
  seed: number;
  /** Fill empty slots up to teamSize x 2 with bots. */
  fillBots?: boolean;
  /** Override round count / phases for tests and quick modes. */
  roundsToWin?: number;
  phaseScale?: number;
  /** Directory for .bpr replays (spec §14.4); omit to disable recording. */
  replayDir?: string;
}

export const Phase = { BUY: 0, COMBAT: 1, POSTPLANT: 2, END: 3, MATCH_OVER: 4 } as const;
export const ChargeStateId = {
  NONE: 0,
  CARRIED: 1,
  DROPPED: 2,
  PLANTED: 3,
  DEFUSED: 4,
  DETONATED: 5,
} as const;
const FLAG = {
  GROUNDED: 1,
  ALIVE: 2,
  RELOADING: 4,
  FIRING: 8,
  PLANTING: 16,
  DEFUSING: 32,
  HAS_CHARGE: 64,
  REVEALED: 128,
};
const ABILITY_BUTTONS: [number, "C" | "Q" | "E" | "X"][] = [
  [B.ABILITY_C, "C"],
  [B.ABILITY_Q, "Q"],
  [B.ABILITY_E, "E"],
  [B.ABILITY_X, "X"],
];
const HISTORY = 32;
const MAX_REWIND_TICKS = 16; // 250 ms (spec §13.4)

interface EconomyConfig {
  startCredits: number;
  maxCredits: number;
  killReward: number;
  roundWin: number;
  roundLossStreak: number[];
  plantTeamReward: number;
  shields: { id: string; cost: number; amount: number; absorb: number }[];
}
interface MatchConfig {
  teamSize: number;
  roundsToWin: number;
  halftimeAfterRound: number;
  overtime: { winBy: number };
  phases: { buy: number; combat: number; postPlant: number; roundEnd: number };
  breachCharge: { plantTime: number; defuseTime: number; defuseCheckpoint: number };
  antiCheat: AntiCheatConfig;
}

export interface ServerPlayer extends AbilityPlayer {
  id: number;
  name: string;
  team: number;
  agent: string;
  bot: BotBrain | null;
  move: MoveState;
  yaw: number;
  pitch: number;
  health: number;
  shield: number;
  alive: boolean;
  credits: number;
  weapons: { primary: WeaponState | null; secondary: WeaponState | null; melee: WeaponState };
  slot: 0 | 1 | 2;
  inputs: InputCmd[];
  lastCmd: InputCmd;
  lastSeq: number;
  history: { tick: number; x: number; y: number; z: number; yaw: number; crouch: number }[];
  kills: number;
  deaths: number;
  assists: number;
  score: number;
  ult: number;
  charges: number[];
  damageTaken: Map<number, number>;
  visibleTicks: Map<number, number>;
  pingMs: number;
  stepDist: number;
  plantProgress: number;
  defuseProgress: number;
  eRechargeAt: number;
  accountId: string;
}

export class Match {
  readonly loop: FixedTickLoop;
  readonly world: World;
  readonly meta: MapMeta;
  tick = 0;
  players = new Map<number, ServerPlayer>();
  phase: number = Phase.BUY;
  phaseEndsAt = 0;
  round = 0;
  score: [number, number] = [0, 0];
  lossStreak: [number, number] = [0, 0];
  charge = {
    state: ChargeStateId.NONE as number,
    carrier: -1,
    x: 0,
    y: 0,
    z: 0,
    site: 0,
    plantedTick: 0,
  };
  roundSeed = 1;
  orbsTaken: boolean[] = [];
  winner = -1;
  readonly abilities: AbilityEngine;
  private readonly mv: MovementConfig;
  private readonly weapons = new Map<string, WeaponDef>();
  private readonly econ: EconomyConfig;
  private readonly rules: MatchConfig;
  private readonly hitboxes: HitboxConfig;
  private readonly tags: MaterialTag[];
  private readonly nav: NavGraph;
  private readonly rand: () => number;
  private send: (playerId: number, msg: Message) => void = () => undefined;
  private replay: ReplayRecorder | null = null;
  /** Statistical aim checks (review flags in the match result). Reset every match cycle. */
  ac: AntiCheat;
  private replayClosed: Promise<void> = Promise.resolve();

  constructor(readonly options: MatchOptions) {
    this.loop = new FixedTickLoop(TICK_RATE, () => this.step());
    this.world = loadWorld(options.map);
    this.meta = loadMeta(options.map);
    this.mv = loadRawConfig("movement") as MovementConfig;
    for (const w of (loadRawConfig("weapons") as { weapons: WeaponDef[] }).weapons)
      this.weapons.set(w.id, w);
    this.econ = loadRawConfig("economy") as EconomyConfig;
    this.rules = { ...(loadRawConfig("match") as MatchConfig) };
    if (options.roundsToWin !== undefined) {
      this.rules.roundsToWin = options.roundsToWin;
      this.rules.halftimeAfterRound = Math.max(1, options.roundsToWin - 1);
    }
    if (options.phaseScale !== undefined) {
      const s = options.phaseScale;
      this.rules.phases = {
        buy: this.rules.phases.buy * s,
        combat: this.rules.phases.combat * s,
        postPlant: this.rules.phases.postPlant * s,
        roundEnd: this.rules.phases.roundEnd * s,
      };
    }
    this.hitboxes = loadRawConfig("hitboxes") as HitboxConfig;
    this.tags = (loadRawConfig("materials") as { tags: MaterialTag[] }).tags;
    this.nav = new NavGraph(this.meta);
    this.ac = new AntiCheat(this.rules.antiCheat);
    this.rand = mulberry32(options.seed);
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const self = this;
    this.abilities = new AbilityEngine((loadRawConfig("agents") as { agents: AgentDef[] }).agents, {
      get tick() {
        return self.tick;
      },
      world: this.world,
      players: () => this.players.values(),
      damage: (attacker, victim, amount, source) =>
        this.abilityDamage(attacker, victim, amount, source),
      emit: (effect, caster, ability, event, x, y, z, data) =>
        this.emitAbility(effect, caster, ability, event, x, y, z, data),
      toPlayer: (id, ability, event, data) =>
        this.send(id, {
          type: "AbilityEvent",
          casterId: 0,
          ability,
          event,
          pos: { x: 0, y: 0, z: 0 },
          data: new TextEncoder().encode(JSON.stringify(data)),
        }),
    });
  }

  private emitAbility(
    effect: Effect | null,
    caster: number,
    ability: string,
    event: number,
    x: number,
    y: number,
    z: number,
    data: Record<string, unknown>,
  ): void {
    const bytes = new TextEncoder().encode(JSON.stringify({ ...data, eid: effect?.id ?? 0 }));
    this.broadcast({
      type: "AbilityEvent",
      casterId: caster,
      ability,
      event,
      pos: { x, y, z },
      data: bytes,
    });
  }

  private abilityDamage(
    attackerId: number,
    victimId: number,
    amount: number,
    source: string,
  ): void {
    const a = this.players.get(attackerId);
    if (!a) return;
    const v = this.players.get(victimId);
    if (!v || !v.alive) return;
    const def = { ...this.def("knife"), id: source, tagSlow: { amount: 0.3, duration: 0.1 } };
    const vulnerable = v.status.vulnerable > this.tick ? 2 : 1;
    this.applyDamage(a, victimId, amount * vulnerable, "body", false, def);
  }

  setTransport(send: (playerId: number, msg: Message) => void): void {
    this.send = send;
  }

  start(): void {
    if (this.options.fillBots) this.fillBots();
    this.openReplay();
    this.startRound();
    this.loop.start();
  }

  stop(): void {
    this.loop.stop();
    void this.closeReplay();
  }

  /** Flushes and closes the replay file (idempotent); resolves when it is on disk. */
  closeReplay(): Promise<void> {
    if (this.replay) {
      this.replayClosed = this.replay.close();
      this.replay = null;
    }
    return this.replayClosed;
  }

  private openReplay(): void {
    const dir = this.options.replayDir;
    if (!dir || this.replay) return;
    const path = replayPath(dir, this.currentMatchId);
    if (!path) return;
    ensureReplayDir(dir);
    this.replay = new ReplayRecorder(path, {
      matchId: this.currentMatchId,
      map: this.options.map,
      mode: this.options.mode ?? "quick",
      tickRate: TICK_RATE,
      snapshotEvery: REPLAY_EVERY,
      startedAt: new Date().toISOString(),
    });
    this.replay.record(this.tick, this.matchStateMsg());
  }

  /** Starts without the real-time loop (tests, replays, load tests): call step() manually. */
  startManual(): void {
    if (this.options.fillBots) this.fillBots();
    this.openReplay();
    this.startRound();
  }

  // ------------------------------------------------------------------ players

  onResult: ((result: unknown) => void) | null = null;
  /** Fired once when a matchmade match is over and the worker can be released. */
  onFinished: (() => void) | null = null;
  finished = false;
  /** Quick servers play consecutive matches; each gets its own id (stats + replay key). */
  private cycle = 0;

  get currentMatchId(): string {
    return this.cycle === 0 ? this.options.matchId : `${this.options.matchId}-${this.cycle}`;
  }
  private roundLog: { round: number; winner: number; reason: string }[] = [];

  addPlayer(
    id: number,
    name: string,
    agent = "kestrel",
    isBot = false,
    preferTeam = -1,
    accountId = "",
  ): ServerPlayer {
    // A human joining a full match replaces a bot (on the larger team, or any team).
    if (!isBot && this.players.size >= this.rules.teamSize * 2) {
      const bots = [...this.players.values()].filter((q) => q.bot);
      const t0 = [...this.players.values()].filter((q) => q.team === 0).length;
      const t1 = this.players.size - t0;
      const pick = bots.find((b) => b.team === (t0 >= t1 ? 0 : 1)) ?? bots[0];
      if (pick) this.removePlayer(pick.id);
    }
    const counts = [0, 0];
    for (const p of this.players.values()) counts[p.team]!++;
    const team =
      preferTeam === 0 || preferTeam === 1 ? preferTeam : counts[0]! <= counts[1]! ? 0 : 1;
    const knife = newWeaponState(this.def("knife"), 0);
    const p: ServerPlayer = {
      id,
      name,
      team,
      agent,
      bot: isBot
        ? new BotBrain(
            this.nav,
            mulberry32(hashSeed(this.options.seed, id)),
            0.45 + this.rand() * 0.4,
          )
        : null,
      move: newMoveState(0, 0, 0),
      yaw: 0,
      pitch: 0,
      health: 100,
      shield: 0,
      alive: false,
      credits: this.econ.startCredits,
      weapons: { primary: null, secondary: newWeaponState(this.def("wasp")), melee: knife },
      slot: 1,
      inputs: [],
      lastCmd: { seq: 0, tick: 0, buttons: 0, yaw: 0, pitch: 0, weaponSlot: 1, interpMs: 0 },
      lastSeq: 0,
      history: [],
      kills: 0,
      deaths: 0,
      assists: 0,
      score: 0,
      ult: 0,
      charges: [0, 0, 1, 0],
      damageTaken: new Map(),
      visibleTicks: new Map(),
      pingMs: 0,
      stepDist: 0,
      plantProgress: 0,
      defuseProgress: 0,
      eRechargeAt: 0,
      accountId,
      killsSinceE: 0,
      status: {
        blind: 0,
        revealed: 0,
        detained: 0,
        speedMult: 1,
        speedUntil: 0,
        silentUntil: 0,
        redlineUntil: 0,
        nearsight: 0,
        blackout: 0,
        vulnerable: 0,
        healPerTick: 0,
        healUntil: 0,
      },
    };
    this.players.set(id, p);
    if (this.round > 0) this.spawn(p);
    this.broadcastMatchState();
    return p;
  }

  removePlayer(id: number): void {
    const p = this.players.get(id);
    if (!p) return;
    if (this.charge.carrier === id) this.dropCharge(p);
    this.players.delete(id);
    this.broadcastMatchState();
  }

  private fillBots(): void {
    const names = [
      "Halvard",
      "Ines",
      "Kofi",
      "Lumi",
      "Mateo",
      "Noor",
      "Oren",
      "Priya",
      "Rafa",
      "Sena",
    ];
    const agents = ["kestrel", "mamba", "vesper", "haldor", "orin", "sable", "imani", "tomas"];
    let id = 200;
    while (this.players.size < this.rules.teamSize * 2) {
      this.addPlayer(
        id,
        `${names[(id - 200) % names.length]!} [BOT]`,
        agents[(id - 200) % agents.length]!,
        true,
      );
      id++;
    }
  }

  receiveInput(id: number, cmds: InputCmd[]): void {
    const p = this.players.get(id);
    if (!p || p.bot) return;
    for (const c of cmds) {
      if (c.seq <= p.lastSeq || p.inputs.some((q) => q.seq === c.seq)) continue;
      // Validation (spec §14.3). Angles are absolute (no turn-rate exploit), but must be finite;
      // interp is capped so a client cannot stretch lag compensation.
      if (!Number.isFinite(c.yaw) || !Number.isFinite(c.pitch) || !Number.isFinite(c.interpMs))
        continue;
      c.pitch = Math.max(-1.553, Math.min(1.553, c.pitch));
      c.interpMs = Math.max(0, Math.min(this.rules.antiCheat.maxInterpMs, c.interpMs));
      p.inputs.push(c);
    }
    p.inputs.sort((a, b) => a.seq - b.seq);
    if (p.inputs.length > 8) p.inputs.splice(0, p.inputs.length - 8);
  }

  buy(id: number, item: string): void {
    const p = this.players.get(id);
    if (!p) return;
    const reply = (ok: boolean, reason: string): void =>
      this.send(id, { type: "BuyResult", item, ok, credits: p.credits, reason });
    if (this.phase !== Phase.BUY) return reply(false, "not_buy_phase");
    const zone = this.meta.buyZones.find(
      (z) => z.team === (this.isAttacking(p.team) ? "attack" : "defense"),
    );
    if (zone && !inBox(p.move.x, p.move.y, p.move.z, zone.center, zone.size))
      return reply(false, "not_in_buy_zone");
    if (item === "ability_C" || item === "ability_Q") {
      const r = this.abilities.buyCharge(p, item === "ability_C" ? "C" : "Q");
      reply(r === "", r);
      this.sendStatus(p);
      return;
    }
    const shield = this.econ.shields.find((s) => s.id === item);
    if (shield) {
      if (p.shield >= shield.amount) return reply(false, "already_owned");
      if (p.credits < shield.cost) return reply(false, "insufficient_credits");
      p.credits -= shield.cost;
      p.shield = shield.amount;
    } else {
      const def = this.weapons.get(item);
      if (!def || def.class === "melee") return reply(false, "unknown_item");
      if (p.credits < def.cost) return reply(false, "insufficient_credits");
      p.credits -= def.cost;
      const st = newWeaponState(def, this.now());
      if (def.class === "sidearm") {
        p.weapons.secondary = st;
        p.slot = 1;
      } else {
        p.weapons.primary = st;
        p.slot = 0;
      }
    }
    reply(true, "");
    this.sendStatus(p);
  }

  // ------------------------------------------------------------------ helpers

  private def(id: string): WeaponDef {
    return this.weapons.get(id)!;
  }

  now(): number {
    return this.tick / TICK_RATE;
  }

  isAttacking(team: number): boolean {
    // Teams swap after halftime; overtime alternates every round.
    const half =
      this.round <= this.rules.halftimeAfterRound
        ? 0
        : this.round <= this.rules.halftimeAfterRound * 2
          ? 1
          : (this.round - this.rules.halftimeAfterRound * 2 + 1) % 2;
    return (team === 0) === (half === 0);
  }

  private current(p: ServerPlayer): WeaponState {
    return (
      (p.slot === 0 ? p.weapons.primary : p.slot === 1 ? p.weapons.secondary : p.weapons.melee) ??
      p.weapons.melee
    );
  }

  private eye(p: ServerPlayer): number {
    return p.move.y + (playerHeight(this.mv, p.move) - 0.18);
  }

  // ------------------------------------------------------------------ rounds (spec §10.3)

  private startRound(): void {
    this.round++;
    const halftime = this.round === this.rules.halftimeAfterRound + 1;
    const overtime = this.round > this.rules.halftimeAfterRound * 2;
    this.roundSeed = hashSeed(this.options.seed, this.round);
    for (const p of this.players.values()) {
      if (halftime || this.round === 1) {
        p.credits = this.econ.startCredits;
        p.weapons = {
          primary: null,
          secondary: newWeaponState(this.def("wasp")),
          melee: newWeaponState(this.def("knife")),
        };
        p.shield = 0;
        p.ult = halftime ? p.ult : 0;
      } else if (overtime) {
        p.credits = Math.max(p.credits, 5000);
      }
      if (!p.alive) {
        p.weapons.primary = null;
        p.weapons.secondary = newWeaponState(this.def("wasp"));
        p.shield = 0;
      }
      // Refill ammo for carried weapons; abilities persist as charges (E refreshes).
      for (const w of [p.weapons.primary, p.weapons.secondary]) {
        if (w) {
          const d = this.def(w.id);
          w.ammo = d.magazine;
          w.reserve = d.reserveAmmo;
        }
      }
      this.abilities.resetRound(p);
      p.status = {
        blind: 0,
        revealed: 0,
        detained: 0,
        speedMult: 1,
        speedUntil: 0,
        silentUntil: 0,
        redlineUntil: 0,
        nearsight: 0,
        blackout: 0,
        vulnerable: 0,
        healPerTick: 0,
        healUntil: 0,
      };
      p.damageTaken.clear();
      this.spawn(p);
    }
    if (halftime) this.lossStreak = [0, 0];
    this.orbsTaken = this.meta.riftOrbs.map(() => false);
    this.abilities.clearAll();
    // Breach Charge to a random attacker.
    const attackers = [...this.players.values()].filter((p) => this.isAttacking(p.team));
    const carrier =
      attackers.length > 0 ? attackers[Math.floor(this.rand() * attackers.length)]! : null;
    this.charge = {
      state: carrier ? ChargeStateId.CARRIED : ChargeStateId.NONE,
      carrier: carrier?.id ?? -1,
      x: 0,
      y: 0,
      z: 0,
      site: 0,
      plantedTick: 0,
    };
    this.setPhase(Phase.BUY, this.rules.phases.buy);
    this.broadcastCharge();
    this.broadcastMatchState();
    for (const p of this.players.values()) this.sendStatus(p);
  }

  private spawn(p: ServerPlayer): void {
    const list = this.isAttacking(p.team) ? this.meta.spawns.attack : this.meta.spawns.defense;
    const mates = [...this.players.values()].filter((q) => q.team === p.team);
    const idx = Math.max(0, mates.indexOf(p)) % Math.max(1, list.length);
    const s = list[idx] ?? { pos: [0, 0, 0] as V3, yaw: 0 };
    p.move = newMoveState(s.pos[0], s.pos[1], s.pos[2]);
    p.yaw = s.yaw;
    p.pitch = 0;
    p.health = 100;
    p.alive = true;
    p.plantProgress = 0;
    p.defuseProgress = 0;
    p.slot = p.weapons.primary ? 0 : 1;
    p.history = [];
    this.broadcast({
      type: "Spawn",
      playerId: p.id,
      pos: { x: s.pos[0], y: s.pos[1], z: s.pos[2] },
      yaw: s.yaw,
      team: p.team,
    });
  }

  private setPhase(phase: number, seconds: number): void {
    this.phase = phase;
    this.phaseEndsAt = this.tick + Math.round(seconds * TICK_RATE);
    this.broadcast({
      type: "RoundPhase",
      round: this.round,
      phase,
      endsAtTick: this.phaseEndsAt,
      scoreAttack: this.score[0],
      scoreDefense: this.score[1],
    });
  }

  private endRound(winnerTeam: number, reason: string): void {
    if (this.phase === Phase.END || this.phase === Phase.MATCH_OVER) return;
    this.score[winnerTeam as 0 | 1]++;
    const loser = 1 - winnerTeam;
    this.lossStreak[winnerTeam as 0 | 1] = 0;
    this.lossStreak[loser as 0 | 1] = Math.min(
      this.lossStreak[loser as 0 | 1] + 1,
      this.econ.roundLossStreak.length,
    );
    for (const p of this.players.values()) {
      const reward =
        p.team === winnerTeam
          ? this.econ.roundWin
          : this.econ.roundLossStreak[this.lossStreak[loser as 0 | 1] - 1]!;
      p.credits = Math.min(this.econ.maxCredits, p.credits + reward);
    }
    this.broadcast({ type: "RoundEnd", round: this.round, winnerTeam, reason });
    this.roundLog.push({ round: this.round, winner: winnerTeam, reason });
    const [a, b] = this.score;
    const total = this.rules.roundsToWin;
    const over =
      (a >= total || b >= total) &&
      Math.abs(a - b) >= (a + b > (total - 1) * 2 ? this.rules.overtime.winBy : 1);
    if (over) {
      this.winner = a > b ? 0 : 1;
      this.setPhase(Phase.MATCH_OVER, 10);
      this.onResult?.({
        matchId: this.currentMatchId,
        mode: this.options.mode ?? "quick",
        map: this.options.map,
        score: [this.score[0], this.score[1]],
        winner: this.winner,
        rounds: this.roundLog,
        players: [...this.players.values()].map((p) => ({
          accountId: p.accountId || null,
          name: p.name,
          team: p.team,
          agent: p.agent,
          kills: p.kills,
          deaths: p.deaths,
          assists: p.assists,
          score: p.score,
          flags: p.bot ? [] : this.ac.flags(p.id),
        })),
      });
      this.broadcast({
        type: "RoundEnd",
        round: this.round,
        winnerTeam: this.winner,
        reason: "match",
      });
    } else {
      this.setPhase(Phase.END, this.rules.phases.roundEnd);
    }
    this.broadcastScoreboard();
    if (over) void this.closeReplay();
  }

  private checkElimination(): void {
    if (this.phase !== Phase.COMBAT && this.phase !== Phase.POSTPLANT && this.phase !== Phase.BUY)
      return;
    const aliveA = [...this.players.values()].filter(
      (p) => p.alive && this.isAttacking(p.team),
    ).length;
    const aliveD = [...this.players.values()].filter(
      (p) => p.alive && !this.isAttacking(p.team),
    ).length;
    const attTeam = this.isAttacking(0) ? 0 : 1;
    if (aliveD === 0 && [...this.players.values()].some((p) => !this.isAttacking(p.team)))
      this.endRound(attTeam, "elimination");
    else if (
      aliveA === 0 &&
      this.charge.state !== ChargeStateId.PLANTED &&
      [...this.players.values()].some((p) => this.isAttacking(p.team))
    )
      this.endRound(1 - attTeam, "elimination");
  }

  // ------------------------------------------------------------------ tick

  step(): void {
    if (this.finished) return;
    this.tick++;
    const dt = 1 / TICK_RATE;
    // Phase timers.
    if (this.tick >= this.phaseEndsAt) {
      const attTeam = this.isAttacking(0) ? 0 : 1;
      if (this.phase === Phase.BUY) this.setPhase(Phase.COMBAT, this.rules.phases.combat);
      else if (this.phase === Phase.COMBAT) this.endRound(1 - attTeam, "time");
      else if (this.phase === Phase.POSTPLANT) {
        this.charge.state = ChargeStateId.DETONATED;
        this.broadcastCharge();
        this.endRound(attTeam, "detonated");
      } else if (this.phase === Phase.END) this.startRound();
      else if (this.phase === Phase.MATCH_OVER) {
        // Matchmade games end here; quick drop-in servers roll straight into a new match.
        if (this.options.mode && this.options.mode !== "quick") {
          this.finished = true;
          this.onFinished?.();
          return;
        }
        this.cycle++;
        this.ac = new AntiCheat(this.rules.antiCheat);
        this.openReplay();
        this.score = [0, 0];
        this.round = 0;
        this.winner = -1;
        for (const p of this.players.values()) {
          p.kills = p.deaths = p.assists = p.score = 0;
        }
        this.startRound();
      }
    }
    for (const p of this.players.values()) {
      const cmd = p.bot ? this.botInput(p) : this.nextInput(p);
      this.simulate(p, cmd, dt);
    }
    this.abilities.update();
    this.reviveCheck();
    for (const p of this.players.values()) {
      p.history.push({
        tick: this.tick,
        x: p.move.x,
        y: p.move.y,
        z: p.move.z,
        yaw: p.yaw,
        crouch: p.move.crouch,
      });
      if (p.history.length > HISTORY) p.history.shift();
    }
    this.snapshots();
    if (this.tick % 64 === 0) this.broadcastScoreboard();
  }

  private nextInput(p: ServerPlayer): InputCmd {
    const cmd = p.inputs.shift();
    if (cmd) {
      p.lastCmd = cmd;
      p.lastSeq = cmd.seq;
      return cmd;
    }
    // Packet loss / late input: repeat the last command (movement continues smoothly).
    return { ...p.lastCmd, buttons: p.lastCmd.buttons & ~(B.JUMP | B.FIRE) };
  }

  private botInput(p: ServerPlayer): InputCmd {
    if (!p.alive || !p.bot) return { ...p.lastCmd, buttons: 0 };
    const attacking = this.isAttacking(p.team);
    const targets = [...this.players.values()]
      .filter((q) => q.team !== p.team && q.alive)
      .map((q) => ({
        id: q.id,
        x: q.move.x,
        y: q.move.y,
        z: q.move.z,
        visible: this.canSee(p, q),
      }));
    let goal: BotGoal;
    const siteFor = (i: number): { center: V3 } =>
      this.meta.plantZones[i % Math.max(1, this.meta.plantZones.length)] ?? { center: [0, 0, 0] };
    const mySite = siteFor(p.id % 2);
    if (this.phase === Phase.BUY) goal = { kind: "hold", x: p.move.x, z: p.move.z };
    else if (this.charge.state === ChargeStateId.PLANTED)
      goal = { kind: attacking ? "hold" : "defuse", x: this.charge.x, z: this.charge.z };
    else if (attacking && this.charge.carrier === p.id)
      goal = {
        kind: "plant",
        x: siteFor(this.round % 2).center[0],
        z: siteFor(this.round % 2).center[2],
      };
    else if (attacking && this.charge.state === ChargeStateId.DROPPED)
      goal = { kind: "hunt", x: this.charge.x, z: this.charge.z };
    else if (attacking)
      goal = {
        kind: "hunt",
        x: siteFor(this.round % 2).center[0] + (p.id % 3) * 2,
        z: siteFor(this.round % 2).center[2],
      };
    else
      goal = {
        kind: "hold",
        x: mySite.center[0] + ((p.id % 3) - 1) * 3,
        z: mySite.center[2] + ((p.id % 2) * 2 - 1) * 3,
      };
    const cls = this.def(this.current(p).id).class;
    const engage =
      cls === "sniper"
        ? 120
        : cls === "rifle" || cls === "heavy"
          ? 70
          : cls === "smg"
            ? 40
            : cls === "shotgun"
              ? 15
              : 30;
    const out = p.bot.think(
      {
        x: p.move.x,
        y: p.move.y,
        z: p.move.z,
        yaw: p.yaw,
        pitch: p.pitch,
        team: p.team,
        attacking,
        hasCharge: this.charge.carrier === p.id,
        speed: Math.hypot(p.move.vx, p.move.vz),
      },
      targets,
      goal,
      1.62,
      engage,
    );
    // Bots buy a rifle when they can afford it.
    if (this.phase === Phase.BUY && !p.weapons.primary && p.credits >= 2900)
      this.buy(p.id, this.rand() < 0.5 ? "saber" : "specter");
    else if (this.phase === Phase.BUY && !p.weapons.primary && p.credits >= 1600)
      this.buy(p.id, "halcyon");
    if (this.phase === Phase.BUY && p.shield === 0 && p.credits >= 1000)
      this.buy(p.id, "heavy_shield");
    // Bots use utility: occasionally on contact, the ultimate as soon as it is ready.
    let botButtons = out.buttons;
    const engaged = targets.some((t) => t.visible);
    if (this.phase === Phase.COMBAT || this.phase === Phase.POSTPLANT) {
      const r = this.rand();
      if (engaged && r < 0.004 && (p.charges[1] ?? 0) > 0) botButtons |= B.ABILITY_Q;
      else if (engaged && r < 0.008 && (p.charges[0] ?? 0) > 0) botButtons |= B.ABILITY_C;
      else if (r < 0.002 && (p.charges[2] ?? 0) > 0) botButtons |= B.ABILITY_E;
      const ult = this.abilities.agent(p.agent)?.abilities.find((a) => a.slot === "X");
      if (engaged && ult && p.ult >= (ult.ultPoints ?? 7) && r > 0.99) botButtons |= B.ABILITY_X;
    }
    if (this.phase === Phase.BUY && p.credits >= 600 && (p.charges[0] ?? 0) === 0)
      this.buy(p.id, "ability_C");
    const cmd: InputCmd = {
      seq: p.lastSeq + 1,
      tick: this.tick,
      buttons: botButtons,
      yaw: out.yaw,
      pitch: out.pitch,
      weaponSlot: p.weapons.primary ? 0 : 1,
      interpMs: 0,
    };
    p.lastSeq = cmd.seq;
    p.lastCmd = cmd;
    return cmd;
  }

  private simulate(p: ServerPlayer, cmd: InputCmd, dt: number): void {
    if (!p.alive) return;
    p.yaw = cmd.yaw;
    p.pitch = cmd.pitch;
    if (!p.bot) this.ac.view(p.id, p.yaw, p.pitch);
    let buttons = cmd.buttons;
    // Spawn barriers during the buy phase are enforced after movement (enforceBarriers).
    if (this.phase === Phase.MATCH_OVER) buttons = 0;
    const prevButtons = p.move.prevButtons;
    if (cmd.weaponSlot !== p.slot && cmd.weaponSlot <= 2) {
      const target =
        cmd.weaponSlot === 0
          ? p.weapons.primary
          : cmd.weaponSlot === 1
            ? p.weapons.secondary
            : p.weapons.melee;
      if (target) {
        p.slot = cmd.weaponSlot as 0 | 1 | 2;
        target.equipEnd = this.now() + this.def(target.id).equipTime;
        target.reloadEnd = 0;
      }
    }
    const w = this.current(p);
    const def = this.def(w.id);
    const prevX = p.move.x;
    const prevZ = p.move.z;
    const planting = (p.plantProgress > 0 || p.defuseProgress > 0) && (buttons & B.USE) !== 0;
    // Abilities (edge-triggered casts; the server validates everything).
    const combat = this.phase === Phase.COMBAT || this.phase === Phase.POSTPLANT;
    for (const [bit, slot] of ABILITY_BUTTONS) {
      if (
        (buttons & bit) !== 0 &&
        (prevButtons & bit) === 0 &&
        this.abilities.cast(p, slot, combat)
      ) {
        if (slot === "E") p.eRechargeAt = 0;
        this.sendStatus(p);
      }
    }
    this.eRecharge(p);
    const speedMult = p.status.speedUntil > this.tick ? p.status.speedMult : 1;
    stepMovement(this.mv, this.world, p.move, {
      buttons: planting ? buttons & ~(B.FORWARD | B.BACK | B.LEFT | B.RIGHT | B.JUMP) : buttons,
      yaw: p.yaw,
      runSpeed: def.runSpeed * speedMult,
    });
    if (this.phase === Phase.BUY) this.enforceBarriers(p, prevX, prevZ);
    // Footstep sound events (audible within 40 m when running, never when walking/crouching).
    const sp = Math.hypot(p.move.vx, p.move.vz);
    if (
      p.move.grounded &&
      sp > 3.5 &&
      !(buttons & B.WALK) &&
      p.move.crouch < 0.5 &&
      p.status.silentUntil <= this.tick
    ) {
      p.stepDist += sp * dt;
      if (p.stepDist > 2.1) {
        p.stepDist = 0;
        this.soundEvent(p, 1, "stone", 40);
      }
    }
    // Weapons.
    const held =
      (buttons & B.FIRE) !== 0 && this.phase !== Phase.BUY && p.status.detained <= this.tick;
    const pressed = held && (prevButtons & B.FIRE) === 0;
    const blades = this.abilities.bladeReady(p.id);
    if (blades && pressed) {
      this.throwBlade(p, blades);
      this.objective(p, buttons, dt);
      return;
    }
    updateWeapon(def, w, this.now(), dt, held);
    if (buttons & B.RELOAD && startReload(def, w, this.now()) && p.status.redlineUntil > this.tick)
      w.reloadEnd = this.now() + def.reloadTime * 0.6;
    if (held) {
      const shot = tryFire(
        def,
        w,
        {
          now: this.now(),
          speedFrac: speedFraction(p.move, def.runSpeed),
          standingThreshold: 0.2,
          crouched: p.move.crouch > 0.5,
          airborne: !p.move.grounded,
          ads: (buttons & B.ALT_FIRE) !== 0 && def.ads !== null,
          seed: this.roundSeed,
          playerId: p.id,
        },
        pressed,
        held,
      );
      if (shot) this.resolveShot(p, def, shot.pellets, cmd);
      else if (w.ammo === 0 && def.magazine > 0) startReload(def, w, this.now());
    }
    this.objective(p, buttons, dt);
  }

  private enforceBarriers(p: ServerPlayer, px: number, pz: number): void {
    const team = this.isAttacking(p.team) ? "attack" : "defense";
    const zone = this.meta.buyZones.find((z) => z.team === team);
    if (zone && !inBox(p.move.x, p.move.y, p.move.z, zone.center, zone.size)) {
      p.move.x = px;
      p.move.z = pz;
      p.move.vx = 0;
      p.move.vz = 0;
    }
  }

  // ------------------------------------------------------------------ shooting (spec §13.4)

  private posesAt(viewTick: number): TargetPose[] {
    const out: TargetPose[] = [];
    for (const q of this.players.values()) {
      if (!q.alive) continue;
      let h = q.history[q.history.length - 1];
      for (let i = q.history.length - 1; i >= 0; i--) {
        const e = q.history[i]!;
        h = e;
        if (e.tick <= viewTick) break;
      }
      out.push(
        h
          ? { playerId: q.id, x: h.x, y: h.y, z: h.z, yaw: h.yaw, crouch: h.crouch }
          : {
              playerId: q.id,
              x: q.move.x,
              y: q.move.y,
              z: q.move.z,
              yaw: q.yaw,
              crouch: q.move.crouch,
            },
      );
    }
    return out;
  }

  private resolveShot(
    p: ServerPlayer,
    def: WeaponDef,
    pellets: { yaw: number; pitch: number }[],
    cmd: InputCmd,
  ): void {
    // Rewind other players to where this client saw them, capped at 250 ms.
    const rewind = Math.min(
      MAX_REWIND_TICKS,
      Math.round(cmd.interpMs / (1000 / TICK_RATE)) + Math.max(0, this.tick - cmd.tick),
    );
    const poses = this.posesAt(this.tick - rewind).filter((t) => {
      const q = this.players.get(t.playerId);
      return q !== undefined && q.team !== p.team;
    });
    const ox = p.move.x;
    const oy = this.eye(p);
    const oz = p.move.z;
    const range = def.class === "melee" ? (def.meleeRange ?? 2) : 400;
    const dmgBy = new Map<
      number,
      { dmg: number; zone: "head" | "body" | "leg"; wallbang: boolean }
    >();
    let firstHit: { x: number; y: number; z: number; tag: number } | null = null;
    for (const pel of pellets) {
      const [dx, dy, dz] = viewDir(p.yaw - pel.yaw, p.pitch + pel.pitch);
      const hit = traceShot(
        this.world,
        this.tags,
        this.hitboxes,
        poses,
        p.id,
        def.penetration,
        ox,
        oy,
        oz,
        dx,
        dy,
        dz,
        range,
      );
      if (!firstHit)
        firstHit = { x: hit.x, y: hit.y, z: hit.z, tag: hit.kind === "player" ? 99 : hit.tag };
      if (hit.kind === "world")
        this.abilities.damageUtility(hit.x, hit.y, hit.z, damageAt(def, hit.t, "body"), p.team);
      if (hit.kind !== "player") continue;
      const dmg = damageAt(def, hit.t, hit.zone) * hit.damageScale;
      const prev = dmgBy.get(hit.playerId);
      dmgBy.set(hit.playerId, {
        dmg: (prev?.dmg ?? 0) + dmg,
        zone: prev?.zone === "head" ? "head" : hit.zone,
        wallbang: hit.wallbang || (prev?.wallbang ?? false),
      });
    }
    if (firstHit && def.class !== "melee") {
      const ev: Message = {
        type: "ShotEvent",
        playerId: p.id,
        weapon: def.id,
        origin: { x: ox, y: oy, z: oz },
        hit: { x: firstHit.x, y: firstHit.y, z: firstHit.z },
        impact: firstHit.tag,
      };
      for (const q of this.players.values()) {
        if (q.id !== p.id && Math.hypot(q.move.x - ox, q.move.z - oz) < 120) this.send(q.id, ev);
      }
    }
    if (!p.bot) {
      let head = false;
      for (const [vid, d] of dmgBy) {
        head ||= d.zone === "head";
        if (this.players.get(vid)?.alive) this.ac.hit(p.id, vid, d.zone === "head", this.tick);
      }
      if (def.class !== "melee") this.ac.shot(p.id, dmgBy.size > 0, head);
    }
    for (const [vid, d] of dmgBy) this.applyDamage(p, vid, d.dmg, d.zone, d.wallbang, def);
  }

  private applyDamage(
    attacker: ServerPlayer,
    victimId: number,
    raw: number,
    zone: "head" | "body" | "leg",
    wallbang: boolean,
    def: WeaponDef,
  ): void {
    const v = this.players.get(victimId);
    if (!v || !v.alive) return;
    let dmg = raw;
    const absorbed = Math.min(v.shield, dmg * 0.66);
    v.shield -= absorbed;
    dmg -= absorbed;
    v.health -= dmg;
    v.move.tagTimer = def.tagSlow.duration;
    v.move.tagAmount = def.tagSlow.amount;
    v.damageTaken.set(attacker.id, (v.damageTaken.get(attacker.id) ?? 0) + raw);
    const amount = Math.min(255, Math.round(raw));
    const hitZone = zone === "head" ? 0 : zone === "leg" ? 2 : 1;
    this.send(attacker.id, {
      type: "HitConfirm",
      shotSeq: attacker.lastSeq,
      victimId,
      hitZone,
      damage: amount,
    });
    this.send(v.id, {
      type: "Damage",
      attackerId: attacker.id,
      victimId,
      amount,
      hitZone,
      fromPos: { x: attacker.move.x, y: attacker.move.y, z: attacker.move.z },
    });
    if (v.health <= 0) this.kill(attacker, v, def.id, zone === "head", wallbang);
  }

  private kill(
    killer: ServerPlayer,
    v: ServerPlayer,
    weapon: string,
    headshot: boolean,
    wallbang: boolean,
  ): void {
    v.alive = false;
    v.health = 0;
    v.deaths++;
    v.ult = Math.min(8, v.ult + 1);
    if (killer.team !== v.team) {
      killer.kills++;
      killer.score += 200 + (headshot ? 50 : 0);
      killer.credits = Math.min(this.econ.maxCredits, killer.credits + this.econ.killReward);
      killer.ult = Math.min(8, killer.ult + 1);
      killer.killsSinceE++;
      if (killer.status.redlineUntil > this.tick) killer.health = Math.min(100, killer.health + 50);
    }
    const assisters = [...v.damageTaken.keys()].filter((id) => id !== killer.id).slice(0, 4);
    for (const a of assisters) {
      const ap = this.players.get(a);
      if (ap) ap.assists++;
    }
    if (this.charge.carrier === v.id) this.dropCharge(v);
    this.broadcast({
      type: "Kill",
      killerId: killer.id,
      victimId: v.id,
      assisterIds: assisters,
      weapon,
      headshot,
      wallbang,
    });
    this.sendStatus(killer);
    this.checkElimination();
  }

  // ------------------------------------------------------------------ Breach Charge (spec §10.3)

  private objective(p: ServerPlayer, buttons: number, dt: number): void {
    const use = (buttons & B.USE) !== 0;
    const cfg = this.rules.breachCharge;
    // Pick up a dropped charge (attackers only).
    if (
      this.charge.state === ChargeStateId.DROPPED &&
      this.isAttacking(p.team) &&
      Math.hypot(p.move.x - this.charge.x, p.move.z - this.charge.z) < 1.2
    ) {
      this.charge.state = ChargeStateId.CARRIED;
      this.charge.carrier = p.id;
      this.broadcastCharge();
    }
    // Rift orbs: +1 ult point once per orb per round.
    this.meta.riftOrbs.forEach((o, i) => {
      if (!this.orbsTaken[i] && use && Math.hypot(p.move.x - o[0], p.move.z - o[2]) < 1.5) {
        this.orbsTaken[i] = true;
        p.ult = Math.min(8, p.ult + 1);
        this.sendStatus(p);
      }
    });
    if (this.phase === Phase.COMBAT && this.charge.carrier === p.id && use && p.move.grounded) {
      const zone = this.meta.plantZones.find((z) =>
        inBox(p.move.x, p.move.y, p.move.z, z.center, z.size),
      );
      if (zone) {
        if (p.plantProgress === 0)
          this.broadcast({
            type: "PlantStart",
            playerId: p.id,
            site: zone.site === "A" ? 0 : 1,
            pos: { x: p.move.x, y: p.move.y, z: p.move.z },
          });
        p.plantProgress += dt;
        if (p.plantProgress >= cfg.plantTime) {
          this.charge = {
            state: ChargeStateId.PLANTED,
            carrier: -1,
            x: p.move.x,
            y: p.move.y,
            z: p.move.z,
            site: zone.site === "A" ? 0 : 1,
            plantedTick: this.tick,
          };
          p.plantProgress = 0;
          p.ult = Math.min(8, p.ult + 1);
          for (const q of this.players.values())
            if (q.team === p.team)
              q.credits = Math.min(this.econ.maxCredits, q.credits + this.econ.plantTeamReward);
          this.setPhase(Phase.POSTPLANT, this.rules.phases.postPlant);
          this.broadcastCharge();
        }
        return;
      }
    }
    p.plantProgress = 0;
    if (
      this.phase === Phase.POSTPLANT &&
      !this.isAttacking(p.team) &&
      use &&
      Math.hypot(p.move.x - this.charge.x, p.move.z - this.charge.z) < 1.4
    ) {
      if (p.defuseProgress === 0 || p.defuseProgress === cfg.defuseCheckpoint)
        this.broadcast({
          type: "DefuseStart",
          playerId: p.id,
          resumeFromCheckpoint: p.defuseProgress >= cfg.defuseCheckpoint,
        });
      p.defuseProgress += dt;
      if (p.defuseProgress >= cfg.defuseTime) {
        this.charge.state = ChargeStateId.DEFUSED;
        p.ult = Math.min(8, p.ult + 1);
        this.broadcastCharge();
        this.endRound(p.team, "defused");
        p.defuseProgress = 0;
      }
    } else if (p.defuseProgress > 0) {
      // Interrupted: progress falls back to the half-way checkpoint if it was reached.
      p.defuseProgress = p.defuseProgress >= cfg.defuseCheckpoint ? cfg.defuseCheckpoint : 0;
    }
  }

  private dropCharge(p: ServerPlayer): void {
    this.charge = {
      ...this.charge,
      state: ChargeStateId.DROPPED,
      carrier: -1,
      x: p.move.x,
      y: p.move.y,
      z: p.move.z,
    };
    this.broadcastCharge();
  }

  // ------------------------------------------------------------------ visibility + snapshots (spec §13.5)

  private visCache = new Map<number, number>();
  private blocksSight = (tag: number): boolean => {
    const id = this.tags[tag]?.id;
    return id !== "invisible" && id !== "glass" && id !== "fabric";
  };

  /** Line of sight with a lead margin (spec §13.5); cached per (viewer, target, tick). */
  canSee(viewer: ServerPlayer, target: ServerPlayer): boolean {
    const key = viewer.id * 4096 + target.id;
    const cached = this.visCache.get(key);
    if (cached !== undefined && cached >> 1 === this.tick) return (cached & 1) === 1;
    const vis = this.computeSight(viewer, target);
    this.visCache.set(key, (this.tick << 1) | (vis ? 1 : 0));
    return vis;
  }

  private computeSight(viewer: ServerPlayer, target: ServerPlayer): boolean {
    if (viewer.status.blind > this.tick && viewer.bot) return false;
    const ex = viewer.move.x;
    const ey = this.eye(viewer);
    const ez = viewer.move.z;
    const dx0 = target.move.x - ex;
    const dz0 = target.move.z - ez;
    if (dx0 * dx0 + dz0 * dz0 < 9) return true; // always aware within 3 m
    // Lead margin: also test where the target will be in ~2 ticks + latency, so enemies are sent
    // slightly before they become visible (no pop-in).
    const lead = (2 + (viewer.pingMs / 1000) * TICK_RATE) / TICK_RATE;
    const pts: [number, number, number][] = [];
    const crouchK = 1 - target.move.crouch * 0.33;
    for (const hy of [1.15, 1.6, 0.35])
      pts.push([target.move.x, target.move.y + hy * crouchK, target.move.z]);
    pts.push([
      target.move.x + target.move.vx * lead,
      target.move.y + 1.15 * crouchK,
      target.move.z + target.move.vz * lead,
    ]);
    for (const [px, py, pz] of pts) {
      const dx = px - ex;
      const dy = py - ey;
      const dz = pz - ez;
      const dist = Math.hypot(dx, dy, dz);
      if (
        !segmentBlocked(
          this.world,
          ex,
          ey,
          ez,
          dx / dist,
          dy / dist,
          dz / dist,
          dist,
          this.blocksSight,
        ) &&
        !this.abilities.sightBlocked(ex, ey, ez, px, py, pz)
      )
        return true;
    }
    return false;
  }

  private snapshots(): void {
    const states = new Map<number, PlayerState>();
    for (const q of this.players.values()) {
      const w = this.current(q);
      let flags = 0;
      if (q.move.grounded) flags |= FLAG.GROUNDED;
      if (q.alive) flags |= FLAG.ALIVE;
      if (w.reloadEnd > 0) flags |= FLAG.RELOADING;
      if (this.tick / TICK_RATE - w.lastShot < 0.1) flags |= FLAG.FIRING;
      if (q.plantProgress > 0) flags |= FLAG.PLANTING;
      if (q.defuseProgress > 0) flags |= FLAG.DEFUSING;
      if (this.charge.carrier === q.id) flags |= FLAG.HAS_CHARGE;
      if (q.status.revealed > this.tick) flags |= FLAG.REVEALED;
      flags |= Math.round(q.move.crouch * 255) << 8;
      states.set(q.id, {
        playerId: q.id,
        pos: { x: q.move.x, y: q.move.y, z: q.move.z },
        vel: { x: q.move.vx, y: q.move.vy, z: q.move.vz },
        yaw: q.yaw,
        pitch: q.pitch,
        flags,
        health: Math.max(0, Math.round(q.health)),
        shield: Math.round(q.shield),
        weapon: [...this.weapons.keys()].indexOf(w.id),
      });
    }
    if (this.replay && this.tick % REPLAY_EVERY === 0)
      this.replay.record(this.tick, {
        type: "Snapshot",
        tick: this.tick,
        baseTick: 0,
        lastProcessedSeq: 0,
        players: [...states.values()],
      });
    for (const viewer of this.players.values()) {
      if (viewer.bot) continue;
      const players: PlayerState[] = [];
      for (const q of this.players.values()) {
        let send = q.team === viewer.team || !viewer.alive || !q.alive;
        if (!send) {
          const vis = this.canSee(viewer, q);
          if (vis) {
            viewer.visibleTicks.set(q.id, this.tick);
            this.ac.visible(viewer.id, q.id, this.tick);
          }
          // Short grace window avoids pop-out flicker at corners.
          send =
            vis ||
            this.tick - (viewer.visibleTicks.get(q.id) ?? -999) < 6 ||
            q.status.revealed > this.tick;
        }
        if (send) players.push(states.get(q.id)!);
      }
      this.send(viewer.id, {
        type: "Snapshot",
        tick: this.tick,
        baseTick: 0,
        lastProcessedSeq: viewer.lastSeq,
        players,
      });
    }
  }

  private soundEvent(p: ServerPlayer, kind: number, param: string, range: number): void {
    for (const q of this.players.values()) {
      if (q.id === p.id || q.bot) continue;
      if (Math.hypot(q.move.x - p.move.x, q.move.z - p.move.z) <= range) {
        this.send(q.id, {
          type: "SoundEvent",
          kind,
          pos: { x: p.move.x, y: p.move.y, z: p.move.z },
          playerId: p.id,
          param,
        });
      }
    }
  }

  // ------------------------------------------------------------------ ability helpers

  /** E recharge: timer-based or kill-based (KESTREL Slipstream: 2 kills). */
  private eRecharge(p: ServerPlayer): void {
    const e = this.abilities.agent(p.agent)?.abilities.find((a) => a.slot === "E");
    if (!e || !e.recharge || (p.charges[2] ?? 0) >= e.charges) return;
    if (e.recharge.type === "kills") {
      if (p.killsSinceE >= e.recharge.amount) {
        p.charges[2] = (p.charges[2] ?? 0) + 1;
        p.killsSinceE = 0;
        this.sendStatus(p);
      }
    } else if (e.recharge.amount > 0) {
      if (p.eRechargeAt === 0)
        p.eRechargeAt = this.tick + Math.round(e.recharge.amount * TICK_RATE);
      else if (this.tick >= p.eRechargeAt) {
        p.charges[2] = (p.charges[2] ?? 0) + 1;
        p.eRechargeAt = 0;
        this.sendStatus(p);
      }
    }
  }

  /** KESTREL Talon Barrage blade: one-shot to body under 15 m; refunds the blade on a kill. */
  private throwBlade(p: ServerPlayer, e: Effect): void {
    e.data["left"] = (e.data["left"] ?? 1) - 1;
    const [dx, dy, dz] = viewDir(p.yaw, p.pitch);
    const poses = this.posesAt(this.tick).filter(
      (t) => this.players.get(t.playerId)?.team !== p.team,
    );
    const hit = traceShot(
      this.world,
      this.tags,
      this.hitboxes,
      poses,
      p.id,
      "low",
      p.move.x,
      this.eye(p),
      p.move.z,
      dx,
      dy,
      dz,
      60,
    );
    this.broadcast({
      type: "ShotEvent",
      playerId: p.id,
      weapon: "talon_barrage",
      origin: { x: p.move.x, y: this.eye(p), z: p.move.z },
      hit: { x: hit.x, y: hit.y, z: hit.z },
      impact: hit.kind === "player" ? 99 : Math.max(0, hit.tag),
    });
    if (hit.kind === "player") {
      const victim = this.players.get(hit.playerId);
      const range = e.data["range"] ?? 15;
      const dmg = hit.t < range ? (e.data["dmg"] ?? 150) : (e.data["dmg"] ?? 150) * 0.5;
      const wasAlive = victim?.alive ?? false;
      this.applyDamage(p, hit.playerId, dmg * hit.damageScale, hit.zone, hit.wallbang, {
        ...this.def("knife"),
        id: "talon_barrage",
      });
      if (wasAlive && victim && !victim.alive) e.data["left"] = (e.data["left"] ?? 0) + 1;
    }
  }

  /** IMANI Second Wind: revive the nearest fallen ally where they fell, with full health. */
  private reviveCheck(): void {
    for (const e of this.abilities.effects) {
      if (e.kind !== "heal" || !e.data["reviveNow"]) continue;
      e.data["reviveNow"] = 0;
      e.data["revive"] = 0;
      let best: ServerPlayer | null = null;
      let bestD = 6;
      for (const q of this.players.values()) {
        if (q.team !== e.team || q.alive) continue;
        const d = Math.hypot(q.move.x - e.x, q.move.z - e.z);
        if (d < bestD) {
          bestD = d;
          best = q;
        }
      }
      if (best) {
        best.alive = true;
        best.health = e.data["hp"] ?? 100;
        this.broadcast({
          type: "Spawn",
          playerId: best.id,
          pos: { x: best.move.x, y: best.move.y, z: best.move.z },
          yaw: best.yaw,
          team: best.team,
        });
      }
    }
  }

  // ------------------------------------------------------------------ broadcasts

  private broadcast(msg: Message): void {
    for (const p of this.players.values()) if (!p.bot) this.send(p.id, msg);
    this.replay?.record(this.tick, msg);
  }

  broadcastMatchState(): void {
    this.broadcast(this.matchStateMsg());
  }

  private matchStateMsg(): Message {
    return {
      type: "MatchState",
      matchId: this.currentMatchId,
      map: this.options.map,
      seed: this.roundSeed,
      roster: [...this.players.values()].map((p) => ({
        playerId: p.id,
        name: p.name,
        team: p.team,
        agent: p.agent,
      })),
    };
  }

  private broadcastCharge(): void {
    for (const p of this.players.values()) {
      if (p.bot) continue;
      // A dropped charge is only shown to attackers (spec §10.3).
      if (this.charge.state === ChargeStateId.DROPPED && !this.isAttacking(p.team)) continue;
      this.send(p.id, {
        type: "ChargeState",
        state: this.charge.state,
        carrierId: Math.max(0, this.charge.carrier),
        pos: { x: this.charge.x, y: this.charge.y, z: this.charge.z },
        site: this.charge.site,
        plantedTick: this.charge.plantedTick,
        progress: 0,
      });
    }
  }

  sendStatus(p: ServerPlayer): void {
    if (p.bot) return;
    const w = this.current(p);
    this.send(p.id, {
      type: "PlayerStatus",
      playerId: p.id,
      credits: p.credits,
      primary: p.weapons.primary?.id ?? "",
      secondary: p.weapons.secondary?.id ?? "",
      slot: p.slot,
      ammo: w.ammo,
      reserve: w.reserve,
      shield: Math.round(p.shield),
      ultPoints: p.ult,
      charges: p.charges,
      agent: p.agent,
    });
  }

  broadcastScoreboard(): void {
    this.broadcast({
      type: "Scoreboard",
      entries: [...this.players.values()].slice(0, 10).map((p) => ({
        playerId: p.id,
        kills: p.kills,
        deaths: p.deaths,
        assists: p.assists,
        score: p.score,
        credits: p.credits,
        ult: p.ult,
        pingMs: p.pingMs,
      })),
    });
  }
}
