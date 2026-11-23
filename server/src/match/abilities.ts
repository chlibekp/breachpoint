// Ability system (spec §10.5, §11): data-driven from shared/config/agents.json. The server validates
// every cast (charges, credits/ult points, phase, alive) and owns every effect. Each ability maps to
// a small set of effect primitives the client renders: smoke/wall vision blockers, flashes, slow/
// damage/pull zones, reveals, movement boosts, buffs, destructible barriers, turrets, projectiles.
// Balance pillars (spec §11): no ability one-shots through cover; flashes are avoidable by turning
// away; traps are visible up close; every effect emits a sound cue to both teams.
import { makeBox, segmentBlocked, type World } from "../sim/collision.ts";
import { viewDir } from "../sim/hitscan.ts";

export interface AbilityDef {
  slot: "C" | "Q" | "E" | "X";
  id: string;
  name: string;
  castType: string;
  cost: number;
  ultPoints?: number;
  charges: number;
  castTime: number;
  recharge?: { type: "timer" | "kills"; amount: number };
  params: Record<string, number | boolean | string>;
}

export interface AgentDef {
  id: string;
  name: string;
  signatureColor: string;
  abilities: AbilityDef[];
}

export type EffectKind =
  | "smoke"
  | "wall"
  | "flash"
  | "slow"
  | "burn"
  | "pull"
  | "reveal_pulse"
  | "sensor"
  | "barrier"
  | "turret"
  | "tether"
  | "detain"
  | "blades"
  | "eruption"
  | "decoy"
  | "heal"
  | "hawk";

export interface Effect {
  id: number;
  kind: EffectKind;
  ability: string;
  owner: number;
  team: number;
  x: number;
  y: number;
  z: number;
  radius: number;
  /** Second point for walls/lines. */
  x2: number;
  z2: number;
  start: number;
  end: number;
  hp: number;
  boxIndex: number;
  data: Record<string, number>;
  lastPulse: number;
}

/** What the ability system needs from the match (kept narrow so it can be unit tested). */
export interface AbilityHost {
  tick: number;
  world: World;
  players(): Iterable<AbilityPlayer>;
  damage(attacker: number, victim: number, amount: number, source: string): void;
  emit(
    effect: Effect | null,
    casterId: number,
    ability: string,
    event: number,
    x: number,
    y: number,
    z: number,
    data: Record<string, unknown>,
  ): void;
  toPlayer(id: number, ability: string, event: number, data: Record<string, unknown>): void;
}

export interface AbilityPlayer {
  id: number;
  team: number;
  alive: boolean;
  agent: string;
  move: {
    x: number;
    y: number;
    z: number;
    vx: number;
    vy: number;
    vz: number;
    grounded: boolean;
    tagTimer: number;
    tagAmount: number;
    crouch: number;
  };
  yaw: number;
  pitch: number;
  health: number;
  charges: number[];
  ult: number;
  credits: number;
  /** Ability-driven status timers (ticks). */
  status: {
    blind: number;
    revealed: number;
    detained: number;
    speedMult: number;
    speedUntil: number;
    silentUntil: number;
    redlineUntil: number;
    nearsight: number;
    blackout: number;
    vulnerable: number;
    healPerTick: number;
    healUntil: number;
  };
  killsSinceE: number;
}

export const EVENT = {
  SPAWN: 1,
  END: 2,
  BLIND: 3,
  REVEAL: 4,
  HEAL: 5,
  MOVE: 6,
  PULSE: 7,
  DAMAGE: 8,
  BLACKOUT: 9,
  NEARSIGHT: 10,
  DETAIN: 11,
} as const;

const TICK = 64;

export class AbilityEngine {
  effects: Effect[] = [];
  private nextId = 1;
  private readonly agents = new Map<string, AgentDef>();
  /** Dynamic collision boxes added by barriers start after the static boxes. */
  private readonly staticBoxes: number;

  constructor(
    agents: AgentDef[],
    private readonly host: AbilityHost,
  ) {
    for (const a of agents) this.agents.set(a.id, a);
    this.staticBoxes = host.world.boxes.length;
  }

  agent(id: string): AgentDef | undefined {
    return this.agents.get(id);
  }

  slotIndex(slot: string): number {
    return ["C", "Q", "E", "X"].indexOf(slot);
  }

  /** Round start: E refreshes; C/Q persist as bought charges (spec §10.4). */
  resetRound(p: AbilityPlayer): void {
    const a = this.agents.get(p.agent);
    if (!a) return;
    const e = a.abilities.find((x) => x.slot === "E");
    if (e) p.charges[2] = Math.max(p.charges[2] ?? 0, e.recharge?.type === "timer" ? e.charges : 1);
    p.killsSinceE = 0;
  }

  clearAll(): void {
    for (const e of [...this.effects]) this.endEffect(e);
    this.effects = [];
  }

  buyCharge(p: AbilityPlayer, slot: "C" | "Q"): string {
    const a = this.agents.get(p.agent)?.abilities.find((x) => x.slot === slot);
    if (!a) return "unknown_item";
    const i = this.slotIndex(slot);
    if ((p.charges[i] ?? 0) >= a.charges) return "already_owned";
    if (p.credits < a.cost) return "insufficient_credits";
    p.credits -= a.cost;
    p.charges[i] = (p.charges[i] ?? 0) + 1;
    return "";
  }

  /** Validates and performs a cast. Returns true on success. */
  cast(p: AbilityPlayer, slot: "C" | "Q" | "E" | "X", combat: boolean): boolean {
    const a = this.agents.get(p.agent)?.abilities.find((x) => x.slot === slot);
    if (!a || !p.alive || p.status.detained > 0) return false;
    const i = this.slotIndex(slot);
    if (slot === "X") {
      if (p.ult < (a.ultPoints ?? 7)) return false;
    } else if ((p.charges[i] ?? 0) <= 0) return false;
    // Damaging abilities only during combat; utility is allowed in the buy phase too (setup).
    const damaging = [
      "talon_barrage",
      "burnout",
      "eruption",
      "proximity_charge",
      "sentry_drill",
    ].includes(a.id);
    if (damaging && !combat) return false;
    if (slot === "X") p.ult = 0;
    else p.charges[i] = (p.charges[i] ?? 1) - 1;
    this.perform(p, a);
    return true;
  }

  private add(
    e: Omit<Effect, "id" | "start" | "lastPulse" | "boxIndex" | "hp" | "data" | "x2" | "z2"> &
      Partial<Effect>,
  ): Effect {
    const eff: Effect = {
      id: this.nextId++,
      start: this.host.tick,
      lastPulse: this.host.tick,
      boxIndex: -1,
      hp: 0,
      data: {},
      x2: e.x,
      z2: e.z,
      ...e,
    } as Effect;
    this.effects.push(eff);
    this.host.emit(eff, eff.owner, eff.ability, EVENT.SPAWN, eff.x, eff.y, eff.z, {
      kind: eff.kind,
      r: eff.radius,
      x2: eff.x2,
      z2: eff.z2,
      dur: (eff.end - eff.start) / TICK,
      team: eff.team,
      hp: eff.hp,
      ...eff.data,
    });
    return eff;
  }

  /** Point where the caster is aiming, clipped by the world (throwables land on the first surface). */
  private aimPoint(p: AbilityPlayer, maxDist: number, lob = false): [number, number, number] {
    const eyeY = p.move.y + 1.6;
    const [dx, dy, dz] = viewDir(p.yaw, p.pitch + (lob ? 0.15 : 0));
    let lo = 0;
    let hi = maxDist;
    for (let k = 0; k < 18; k++) {
      const mid = (lo + hi) / 2;
      if (segmentBlocked(this.host.world, p.move.x, eyeY, p.move.z, dx, dy, dz, mid, () => true))
        hi = mid;
      else lo = mid;
    }
    const d = Math.max(0, lo - 0.3);
    const x = p.move.x + dx * d;
    const z = p.move.z + dz * d;
    // Drop to the ground below the landing point.
    return [x, Math.max(0, p.move.y + 0.0), z];
  }

  private perform(p: AbilityPlayer, a: AbilityDef): void {
    const P = (k: string, d = 0): number => Number(a.params[k] ?? d);
    const t = this.host.tick;
    const base = { ability: a.id, owner: p.id, team: p.team };
    const [fx, , fz] = viewDir(p.yaw, 0);
    switch (a.id) {
      // ---------------- KESTREL
      case "updraft":
        p.move.vy = Math.sqrt(2 * 20 * P("height", 3));
        p.move.grounded = false;
        this.host.emit(null, p.id, a.id, EVENT.MOVE, p.move.x, p.move.y, p.move.z, {
          kind: "updraft",
        });
        break;
      case "slipstream": {
        const [dx, , dz] = viewDir(p.yaw, 0);
        // Dash: high velocity for a few ticks (collision still applies through the movement sim).
        p.move.vx = dx * P("distance", 5) * 4.2;
        p.move.vz = dz * P("distance", 5) * 4.2;
        this.host.emit(null, p.id, a.id, EVENT.MOVE, p.move.x, p.move.y, p.move.z, {
          kind: "dash",
        });
        break;
      }
      case "flare_round": {
        const [x, y, z] = this.aimPoint(p, 14, true);
        this.add({
          ...base,
          kind: "flash",
          x,
          y: y + 1.6,
          z,
          radius: 30,
          end: t + Math.round(P("popDelay", 0.6) * TICK) + 1,
          data: {
            pop: t + Math.round(P("popDelay", 0.6) * TICK),
            blind: P("blindDuration", 1.5),
            cone: 0,
          },
        });
        break;
      }
      case "talon_barrage":
        this.add({
          ...base,
          kind: "blades",
          x: p.move.x,
          y: p.move.y + 1.4,
          z: p.move.z,
          radius: 0,
          end: t + 8 * TICK,
          data: { left: P("blades", 5), range: P("oneShotBodyRange", 15), dmg: P("damage", 150) },
        });
        break;
      // ---------------- MAMBA
      case "burnout": {
        const [x, y, z] = this.aimPoint(p, 10);
        this.add({
          ...base,
          kind: "burn",
          x: p.move.x + fx * 1.5,
          y,
          z: p.move.z + fz * 1.5,
          x2: x,
          z2: z,
          radius: 1.2,
          end: t + P("duration", 4) * TICK,
          data: { dps: P("dps", 30) },
        });
        break;
      }
      case "afterimage":
        this.add({
          ...base,
          kind: "decoy",
          x: p.move.x + fx,
          y: p.move.y,
          z: p.move.z + fz,
          radius: 0,
          end: t + P("lifetime", 3) * TICK,
          data: {
            vx: fx * P("speed", 6.75),
            vz: fz * P("speed", 6.75),
            blind: P("blindDuration", 1.25),
            flashed: 0,
          },
        });
        break;
      case "gearshift":
        p.status.speedMult = 1.3;
        p.status.speedUntil = t + P("duration", 2) * TICK;
        p.status.silentUntil = t + P("duration", 2) * TICK;
        this.host.emit(null, p.id, a.id, EVENT.MOVE, p.move.x, p.move.y, p.move.z, {
          kind: "sprint",
        });
        break;
      case "redline":
        p.status.redlineUntil = t + P("duration", 10) * TICK;
        this.host.emit(null, p.id, a.id, EVENT.MOVE, p.move.x, p.move.y, p.move.z, {
          kind: "redline",
          dur: P("duration", 10),
        });
        break;
      // ---------------- VESPER
      case "eclipse_veil": {
        const len = P("maxLength", 18);
        const [x, , z] = this.aimPoint(p, 25);
        const [rx, rz] = [-fz, fx];
        this.add({
          ...base,
          kind: "wall",
          x: x - (rx * len) / 2,
          y: 0,
          z: z - (rz * len) / 2,
          x2: x + (rx * len) / 2,
          z2: z + (rz * len) / 2,
          radius: 0.5,
          end: t + P("duration", 12) * TICK,
          data: { h: 4.5, curve: 2.5 },
        });
        break;
      }
      case "nebula_mine": {
        const [x, y, z] = this.aimPoint(p, 12, true);
        this.add({
          ...base,
          kind: "slow",
          x,
          y,
          z,
          radius: P("radius", 3),
          end: t + 10 * TICK,
          data: { mult: P("slowMult", 0.5), armed: t + 32 },
        });
        break;
      }
      case "starfall": {
        const [x, y, z] = this.aimPoint(p, 40);
        this.add({
          ...base,
          kind: "smoke",
          x,
          y,
          z,
          radius: P("radius", 4.1),
          end: t + P("duration", 15) * TICK,
        });
        break;
      }
      case "gravity_well": {
        const [x, y, z] = this.aimPoint(p, 30);
        this.add({
          ...base,
          kind: "pull",
          x,
          y,
          z,
          radius: P("radius", 12),
          end: t + (1 + P("duration", 4)) * TICK,
          data: { strength: P("pullStrength", 4), mult: P("slowMult", 0.5), arm: t + TICK },
        });
        break;
      }
      // ---------------- HALDOR
      case "vent": {
        const [x, y, z] = this.aimPoint(p, 10, true);
        this.add({
          ...base,
          kind: "smoke",
          x,
          y,
          z,
          radius: P("radius", 3),
          end: t + P("duration", 8) * TICK,
          data: { muffle: 1, column: 1 },
        });
        break;
      }
      case "basalt_pillar": {
        const [x, , z] = this.aimPoint(p, 6);
        this.barrier(base, x, z, 1.6, P("height", 2), 1.6, p.yaw, P("health", 800), 60 * TICK);
        break;
      }
      case "geyser_smoke": {
        const [x, y, z] = this.aimPoint(p, 22, true);
        this.add({
          ...base,
          kind: "smoke",
          x,
          y,
          z,
          radius: P("radius", 4.1),
          end: t + P("duration", 14) * TICK,
        });
        break;
      }
      case "eruption": {
        const [dx, , dz] = viewDir(p.yaw, 0);
        this.add({
          ...base,
          kind: "eruption",
          x: p.move.x + dx * 4,
          y: p.move.y,
          z: p.move.z + dz * 4,
          x2: dx,
          z2: dz,
          radius: P("radius", 4),
          end: t + Math.round((P("blasts", 3) * P("delay", 0.8) + 0.5) * TICK),
          data: {
            blasts: P("blasts", 3),
            delay: P("delay", 0.8),
            dmg: P("damage", 120),
            done: 0,
            smoke: P("smokeDuration", 6),
          },
        });
        break;
      }
      // ---------------- ORIN
      case "hawk":
        this.add({
          ...base,
          kind: "hawk",
          x: p.move.x,
          y: p.move.y + 2,
          z: p.move.z,
          radius: 0,
          end: t + P("duration", 7) * TICK,
          data: {
            vx: fx * P("speed", 7),
            vz: fz * P("speed", 7),
            tagged: 0,
            reveal: P("dartRevealDuration", 3),
          },
        });
        break;
      case "dust_burst": {
        const [x, y, z] = this.aimPoint(p, 12, true);
        this.add({
          ...base,
          kind: "flash",
          x,
          y: y + 1.2,
          z,
          radius: P("range", 15),
          end: t + 20,
          data: {
            pop: t + 19,
            blind: P("blindDuration", 1.75),
            cone: P("coneDegrees", 70),
            dx: fx,
            dz: fz,
          },
        });
        break;
      }
      case "echo_arrow": {
        const [x, y, z] = this.aimPoint(p, 45, true);
        this.add({
          ...base,
          kind: "reveal_pulse",
          x,
          y: y + 1,
          z,
          radius: P("radius", 30),
          end: t + Math.round(P("pulses", 2) * 1.1 * TICK) + 10,
          data: { pulses: P("pulses", 2), interval: 1.1, done: 0, los: 1, dur: 2 },
        });
        break;
      }
      case "apex_hunt":
        this.add({
          ...base,
          kind: "reveal_pulse",
          x: p.move.x,
          y: p.move.y,
          z: p.move.z,
          radius: 9999,
          end: t + P("duration", 6) * TICK,
          data: {
            pulses: P("pulses", 3),
            interval: P("duration", 6) / P("pulses", 3),
            done: 0,
            los: 0,
            dur: 1.5,
          },
        });
        break;
      // ---------------- SABLE
      case "tripwire_trace": {
        const [x, , z] = this.aimPoint(p, 6);
        const [rx, rz] = [-fz, fx];
        const half = P("maxLength", 8) / 2;
        this.add({
          ...base,
          kind: "slow",
          x: x - rx * half,
          y: 0.5,
          z: z - rz * half,
          x2: x + rx * half,
          z2: z + rz * half,
          radius: 0.4,
          end: t + 90 * TICK,
          data: {
            mult: P("slowMult", 0.5),
            reveal: P("revealDuration", 3),
            line: 1,
            armed: t + 64,
            once: 1,
          },
        });
        break;
      }
      case "static": {
        const [x, y, z] = this.aimPoint(p, 30);
        // Goes through walls: everyone in the radius is near-sighted (spec: through walls).
        for (const q of this.host.players()) {
          if (
            q.team !== p.team &&
            q.alive &&
            Math.hypot(q.move.x - x, q.move.z - z) < P("radius", 6)
          ) {
            q.status.nearsight = t + P("nearsightDuration", 2.5) * TICK;
            this.host.toPlayer(q.id, a.id, EVENT.NEARSIGHT, { dur: P("nearsightDuration", 2.5) });
          }
        }
        this.host.emit(null, p.id, a.id, EVENT.PULSE, x, y + 1, z, {
          kind: "static",
          r: P("radius", 6),
        });
        break;
      }
      case "ping": {
        const [x, y, z] = this.aimPoint(p, 8);
        this.add({
          ...base,
          kind: "sensor",
          x,
          y,
          z,
          radius: P("radius", 10),
          end: t + 60 * TICK,
          hp: 60,
          data: { interval: P("interval", 3), los: 0, dur: 1.2 },
        });
        break;
      }
      case "blackout":
        for (const q of this.host.players()) {
          if (q.team !== p.team) {
            q.status.blackout = t + P("duration", 8) * TICK;
            this.host.toPlayer(q.id, a.id, EVENT.BLACKOUT, { dur: P("duration", 8) });
          }
        }
        this.host.emit(null, p.id, a.id, EVENT.PULSE, p.move.x, p.move.y, p.move.z, {
          kind: "blackout",
        });
        break;
      // ---------------- IMANI
      case "barricade": {
        const [x, , z] = this.aimPoint(p, 5);
        this.barrier(
          base,
          x,
          z,
          P("width", 8),
          2.6,
          0.5,
          p.yaw,
          P("health", 1000),
          40 * TICK,
          P("deployTime", 3.6),
        );
        break;
      }
      case "mend": {
        // Heals the targeted ally (or self at half rate).
        let target: AbilityPlayer = p;
        let best = 10;
        for (const q of this.host.players()) {
          if (q.id === p.id || q.team !== p.team || !q.alive) continue;
          const d = Math.hypot(q.move.x - p.move.x, q.move.z - p.move.z);
          const [dx, , dz] = viewDir(p.yaw, 0);
          const facing =
            ((q.move.x - p.move.x) * dx + (q.move.z - p.move.z) * dz) / Math.max(0.01, d);
          if (d < best && facing > 0.8) {
            best = d;
            target = q;
          }
        }
        const rate = target === p ? P("selfRateMult", 0.5) : 1;
        target.status.healPerTick = (P("heal", 60) / (P("duration", 3) * TICK)) * rate;
        target.status.healUntil = t + Math.round((P("duration", 3) * TICK) / rate);
        this.host.emit(null, p.id, a.id, EVENT.HEAL, target.move.x, target.move.y, target.move.z, {
          target: target.id,
        });
        break;
      }
      case "lattice": {
        const [x, y, z] = this.aimPoint(p, 18, true);
        this.add({
          ...base,
          kind: "slow",
          x,
          y,
          z,
          radius: P("radius", 6),
          end: t + P("duration", 4) * TICK,
          data: { mult: P("slowMult", 0.5), armed: t },
        });
        break;
      }
      case "second_wind": {
        this.add({
          ...base,
          kind: "heal",
          x: p.move.x,
          y: p.move.y,
          z: p.move.z,
          radius: 4,
          end: t + Math.round(P("castTime", 1.4) * TICK),
          data: { revive: 1, hp: P("reviveHealth", 100) },
        });
        break;
      }
      // ---------------- TOMAS
      case "proximity_charge": {
        const [x, y, z] = this.aimPoint(p, 6);
        this.add({
          ...base,
          kind: "tether",
          x,
          y,
          z,
          radius: 2.5,
          end: t + 90 * TICK,
          data: {
            triggered: 0,
            explodeAt: 0,
            dmg: P("damage", 40),
            mult: P("slowMult", 0.6),
            tether: P("tetherDuration", 1.5),
            armed: t + 64,
          },
        });
        break;
      }
      case "sentry_drill": {
        const [x, y, z] = this.aimPoint(p, 5);
        this.add({
          ...base,
          kind: "turret",
          x,
          y,
          z,
          radius: P("range", 20),
          end: t + 45 * TICK,
          hp: P("health", 125),
          data: { dps: P("dps", 15), mult: P("slowMult", 0.8), yaw: p.yaw },
        });
        break;
      }
      case "alarm_spike": {
        const [x, y, z] = this.aimPoint(p, 6);
        this.add({
          ...base,
          kind: "sensor",
          x,
          y,
          z,
          radius: P("triggerRadius", 5),
          end: t + 90 * TICK,
          hp: 40,
          data: {
            interval: 0.5,
            los: 1,
            dur: P("revealDuration", 4),
            vulnerable: 1,
            once: 1,
            armed: t + 64,
          },
        });
        break;
      }
      case "lockdown":
        this.add({
          ...base,
          kind: "detain",
          x: p.move.x,
          y: p.move.y,
          z: p.move.z,
          radius: P("radius", 32),
          end: t + (P("warmup", 13) + P("detainDuration", 8)) * TICK,
          hp: 150,
          data: { fireAt: t + P("warmup", 13) * TICK, detain: P("detainDuration", 8), fired: 0 },
        });
        break;
    }
  }

  private barrier(
    base: { ability: string; owner: number; team: number },
    x: number,
    z: number,
    w: number,
    h: number,
    d: number,
    yaw: number,
    hp: number,
    life: number,
    deploy = 0.5,
  ): void {
    const e = this.add({
      ...base,
      kind: "barrier",
      x,
      y: 0,
      z,
      radius: Math.hypot(w, d) / 2,
      end: this.host.tick + life,
      hp,
      data: { w, h, d, yaw, deploy },
    });
    // Dynamic collision (bullet-blocking, movement-blocking) once deployed.
    this.host.world.boxes.push(makeBox(x, h / 2, z, w / 2, h / 2, d / 2, yaw, 0));
    e.boxIndex = this.host.world.boxes.length - 1;
    delete this.host.world.grid; // rebuild broad phase
  }

  private endEffect(e: Effect): void {
    if (e.boxIndex >= this.staticBoxes) {
      // Remove the barrier box: keep indices stable by collapsing it to nothing.
      const b = this.host.world.boxes[e.boxIndex];
      if (b) {
        b.hx = b.hy = b.hz = 0;
        b.cy = -1000;
      }
      delete this.host.world.grid;
    }
    this.host.emit(e, e.owner, e.ability, EVENT.END, e.x, e.y, e.z, { id: e.id });
  }

  /** Damage to destructible utility (barriers, sensors, turrets) from bullets near their position. */
  damageUtility(x: number, y: number, z: number, amount: number, attackerTeam: number): void {
    for (const e of this.effects) {
      if (e.hp <= 0 || e.team === attackerTeam) continue;
      const r = e.kind === "barrier" ? Math.max(e.data["w"] ?? 1, e.data["d"] ?? 1) / 2 + 0.3 : 0.6;
      if (Math.hypot(x - e.x, z - e.z) < r && Math.abs(y - (e.y + 1)) < 2) {
        e.hp -= amount;
        if (e.hp <= 0) e.end = this.host.tick;
      }
    }
  }

  /** Is the segment's sight blocked by smokes/walls? (fog of war + bots, spec §9.4) */
  sightBlocked(ax: number, ay: number, az: number, bx: number, by: number, bz: number): boolean {
    for (const e of this.effects) {
      if (e.kind === "smoke") {
        if (segmentSphere(ax, ay, az, bx, by, bz, e.x, e.y + 1, e.z, e.radius * 0.95)) return true;
      } else if (e.kind === "wall") {
        if (
          segmentsIntersect2D(ax, az, bx, bz, e.x, e.z, e.x2, e.z2) &&
          Math.min(ay, by) < (e.data["h"] ?? 4)
        )
          return true;
      }
    }
    return false;
  }

  /** Per-tick update. Returns nothing; applies statuses and damage through the host. */
  update(): void {
    const t = this.host.tick;
    const players = [...this.host.players()];
    for (const p of players) {
      if (p.status.healUntil > t && p.alive)
        p.health = Math.min(100, p.health + p.status.healPerTick);
    }
    for (const e of [...this.effects]) {
      switch (e.kind) {
        case "flash":
          if (t >= (e.data["pop"] ?? t)) {
            this.flash(e, players);
            e.end = t;
          }
          break;
        case "slow":
        case "pull":
          if (t < (e.data["armed"] ?? e.data["arm"] ?? 0)) break;
          for (const q of players) {
            if (!q.alive || q.team === e.team) continue;
            const inside = e.data["line"]
              ? distToSegment(q.move.x, q.move.z, e.x, e.z, e.x2, e.z2) < e.radius
              : Math.hypot(q.move.x - e.x, q.move.z - e.z) < e.radius;
            if (!inside) continue;
            q.move.tagTimer = Math.max(q.move.tagTimer, 0.25);
            q.move.tagAmount = Math.max(q.move.tagAmount, 1 - (e.data["mult"] ?? 0.5));
            if (e.kind === "pull") {
              const dx = e.x - q.move.x;
              const dz = e.z - q.move.z;
              const d = Math.max(0.5, Math.hypot(dx, dz));
              q.move.vx += (((dx / d) * (e.data["strength"] ?? 4)) / TICK) * 8;
              q.move.vz += (((dz / d) * (e.data["strength"] ?? 4)) / TICK) * 8;
            }
            if (e.data["reveal"]) this.reveal(q, e.data["reveal"], e);
            if (e.data["once"]) e.end = t + (e.data["reveal"] ?? 1) * TICK;
          }
          break;
        case "burn":
          for (const q of players) {
            if (
              q.alive &&
              distToSegment(q.move.x, q.move.z, e.x, e.z, e.x2, e.z2) < e.radius &&
              q.move.y < e.y + 1
            ) {
              // Area denial: damage over time (per tick ≤ a rifle body shot per second, spec pillar 1).
              this.host.damage(e.owner, q.id, (e.data["dps"] ?? 30) / TICK, e.ability);
            }
          }
          break;
        case "decoy": {
          e.x += (e.data["vx"] ?? 0) / TICK;
          e.z += (e.data["vz"] ?? 0) / TICK;
          if (!e.data["flashed"]) {
            for (const q of players) {
              if (!q.alive || q.team === e.team) continue;
              if (
                this.facing(q, e.x, e.y + 1.4, e.z) > 0.9 &&
                Math.hypot(q.move.x - e.x, q.move.z - e.z) < 20
              ) {
                e.data["flashed"] = 1;
                this.flash({ ...e, data: { ...e.data, cone: 0 }, radius: 20 }, players);
                e.end = t;
                break;
              }
            }
          }
          break;
        }
        case "reveal_pulse":
        case "sensor": {
          if (t < (e.data["armed"] ?? 0)) break;
          const interval = Math.round((e.data["interval"] ?? 1) * TICK);
          if (e.kind === "reveal_pulse" && (e.data["done"] ?? 0) >= (e.data["pulses"] ?? 1)) break;
          if (
            t - e.lastPulse >= interval ||
            (e.kind === "reveal_pulse" && e.data["done"] === 0 && t - e.start > 20)
          ) {
            e.lastPulse = t;
            if (e.kind === "reveal_pulse") e.data["done"] = (e.data["done"] ?? 0) + 1;
            this.host.emit(e, e.owner, e.ability, EVENT.PULSE, e.x, e.y, e.z, { r: e.radius });
            for (const q of players) {
              if (!q.alive || q.team === e.team) continue;
              if (Math.hypot(q.move.x - e.x, q.move.z - e.z) > e.radius) continue;
              if (
                e.data["los"] &&
                segmentBlocked(
                  this.host.world,
                  e.x,
                  e.y + 0.5,
                  e.z,
                  ...norm(q.move.x - e.x, q.move.y + 1.2 - e.y - 0.5, q.move.z - e.z),
                  Math.hypot(q.move.x - e.x, q.move.y + 1.2 - e.y - 0.5, q.move.z - e.z),
                  () => true,
                )
              )
                continue;
              this.reveal(q, e.data["dur"] ?? 1.5, e);
              if (e.data["vulnerable"]) q.status.vulnerable = t + (e.data["dur"] ?? 4) * TICK;
              if (e.data["once"]) e.end = t + 2;
            }
          }
          break;
        }
        case "hawk": {
          e.x += (e.data["vx"] ?? 0) / TICK;
          e.z += (e.data["vz"] ?? 0) / TICK;
          if (!e.data["tagged"]) {
            for (const q of players) {
              if (q.alive && q.team !== e.team && Math.hypot(q.move.x - e.x, q.move.z - e.z) < 6) {
                e.data["tagged"] = 1;
                this.reveal(q, e.data["reveal"] ?? 3, e);
              }
            }
          }
          if (t % 8 === 0)
            this.host.emit(e, e.owner, e.ability, EVENT.MOVE, e.x, e.y, e.z, { id: e.id });
          break;
        }
        case "blades": {
          // Each FIRE press while active throws one blade (handled by the match via throwBlade).
          if ((e.data["left"] ?? 0) <= 0) e.end = t;
          break;
        }
        case "eruption": {
          const done = e.data["done"] ?? 0;
          const next = e.start + Math.round((done + 1) * (e.data["delay"] ?? 0.8) * TICK);
          if (done < (e.data["blasts"] ?? 3) && t >= next) {
            e.data["done"] = done + 1;
            const bx = e.x + e.x2 * done * 4;
            const bz = e.z + e.z2 * done * 4;
            this.host.emit(e, e.owner, e.ability, EVENT.PULSE, bx, e.y, bz, {
              r: e.radius,
              kind: "eruption",
            });
            for (const q of players) {
              if (!q.alive || q.team === e.team) continue;
              const d = Math.hypot(q.move.x - bx, q.move.z - bz);
              if (d < e.radius)
                this.host.damage(
                  e.owner,
                  q.id,
                  (e.data["dmg"] ?? 120) * (1 - (d / e.radius) * 0.5),
                  e.ability,
                );
            }
            this.add({
              ability: e.ability,
              owner: e.owner,
              team: e.team,
              kind: "smoke",
              x: bx,
              y: e.y,
              z: bz,
              radius: 2.6,
              end: t + (e.data["smoke"] ?? 6) * TICK,
            });
          }
          break;
        }
        case "tether": {
          if (t < (e.data["armed"] ?? 0)) break;
          if (!e.data["triggered"]) {
            for (const q of players) {
              if (
                q.alive &&
                q.team !== e.team &&
                Math.hypot(q.move.x - e.x, q.move.z - e.z) < e.radius
              ) {
                e.data["triggered"] = q.id;
                e.data["explodeAt"] = t + Math.round((e.data["tether"] ?? 1.5) * TICK);
                this.host.emit(e, e.owner, e.ability, EVENT.PULSE, e.x, e.y, e.z, {
                  kind: "tether",
                  target: q.id,
                });
              }
            }
          } else {
            const q = players.find((x) => x.id === e.data["triggered"]);
            if (q && q.alive) {
              q.move.tagTimer = 0.2;
              q.move.tagAmount = 1 - (e.data["mult"] ?? 0.6);
            }
            if (t >= (e.data["explodeAt"] ?? 0)) {
              for (const v of players) {
                if (
                  v.alive &&
                  v.team !== e.team &&
                  Math.hypot(v.move.x - e.x, v.move.z - e.z) < e.radius + 0.5
                )
                  this.host.damage(e.owner, v.id, e.data["dmg"] ?? 40, e.ability);
              }
              this.host.emit(e, e.owner, e.ability, EVENT.PULSE, e.x, e.y, e.z, {
                kind: "explode",
                r: e.radius,
              });
              e.end = t;
            }
          }
          break;
        }
        case "turret": {
          if (t % 8 !== 0) break;
          let best: AbilityPlayer | null = null;
          let bestD = e.radius;
          for (const q of players) {
            if (!q.alive || q.team === e.team) continue;
            const d = Math.hypot(q.move.x - e.x, q.move.z - e.z);
            if (
              d < bestD &&
              !segmentBlocked(
                this.host.world,
                e.x,
                e.y + 0.6,
                e.z,
                ...norm(q.move.x - e.x, q.move.y + 1.1 - e.y - 0.6, q.move.z - e.z),
                d,
                (tag) => tag !== 6,
              )
            ) {
              bestD = d;
              best = q;
            }
          }
          if (best) {
            this.host.damage(e.owner, best.id, (e.data["dps"] ?? 15) / 8, e.ability);
            best.move.tagTimer = 0.3;
            best.move.tagAmount = 1 - (e.data["mult"] ?? 0.8);
            this.host.emit(
              e,
              e.owner,
              e.ability,
              EVENT.DAMAGE,
              best.move.x,
              best.move.y + 1.1,
              best.move.z,
              { from: e.id },
            );
          }
          break;
        }
        case "detain": {
          if (!e.data["fired"] && t >= (e.data["fireAt"] ?? 0)) {
            e.data["fired"] = 1;
            for (const q of players) {
              if (
                q.alive &&
                q.team !== e.team &&
                Math.hypot(q.move.x - e.x, q.move.z - e.z) < e.radius
              ) {
                q.status.detained = t + (e.data["detain"] ?? 8) * TICK;
                this.host.toPlayer(q.id, e.ability, EVENT.DETAIN, { dur: e.data["detain"] ?? 8 });
              }
            }
            this.host.emit(e, e.owner, e.ability, EVENT.PULSE, e.x, e.y, e.z, {
              kind: "detain",
              r: e.radius,
            });
          }
          break;
        }
        case "heal": {
          if (t >= e.end - 1 && e.data["revive"]) {
            // Second Wind: revive the closest fallen ally (handled by the match through `revive`).
            e.data["reviveNow"] = 1;
          }
          break;
        }
        default:
          break;
      }
      if (t >= e.end) {
        this.effects.splice(this.effects.indexOf(e), 1);
        this.endEffect(e);
      }
    }
    for (const p of players) {
      if (p.status.detained > t) {
        p.move.tagTimer = 0.2;
        p.move.tagAmount = Math.max(p.move.tagAmount, 0.6);
      }
    }
  }

  /** Talon Barrage: throws one blade straight down the view. Returns true if a blade was thrown. */
  bladeReady(ownerId: number): Effect | undefined {
    return this.effects.find(
      (e) => e.kind === "blades" && e.owner === ownerId && (e.data["left"] ?? 0) > 0,
    );
  }

  private reveal(q: AbilityPlayer, seconds: number, e: Effect): void {
    q.status.revealed = Math.max(q.status.revealed, this.host.tick + Math.round(seconds * TICK));
    this.host.emit(e, e.owner, e.ability, EVENT.REVEAL, q.move.x, q.move.y, q.move.z, {
      target: q.id,
      dur: seconds,
    });
  }

  private facing(q: AbilityPlayer, x: number, y: number, z: number): number {
    const [dx, dy, dz] = viewDir(q.yaw, q.pitch);
    const ex = x - q.move.x;
    const ey = y - (q.move.y + 1.6);
    const ez = z - q.move.z;
    const d = Math.hypot(ex, ey, ez);
    return (dx * ex + dy * ey + dz * ez) / Math.max(0.001, d);
  }

  /** Flash: blinds players who can see the pop and are looking toward it (turning away avoids it). */
  private flash(e: Effect, players: AbilityPlayer[]): void {
    this.host.emit(e, e.owner, e.ability, EVENT.PULSE, e.x, e.y, e.z, { kind: "flash" });
    for (const q of players) {
      if (!q.alive || q.team === e.team) continue;
      const ex = e.x - q.move.x;
      const ey = e.y - (q.move.y + 1.6);
      const ez = e.z - q.move.z;
      const d = Math.hypot(ex, ey, ez);
      if (d > e.radius) continue;
      if (e.data["cone"]) {
        // Cone flash (Dust Burst): only players in front of the burst direction.
        const dot =
          (-ex * (e.data["dx"] ?? 0) + -ez * (e.data["dz"] ?? 0)) /
          Math.max(0.01, Math.hypot(ex, ez));
        if (dot < Math.cos(((e.data["cone"] ?? 70) * Math.PI) / 360)) continue;
      }
      if (
        segmentBlocked(
          this.host.world,
          q.move.x,
          q.move.y + 1.6,
          q.move.z,
          ex / d,
          ey / d,
          ez / d,
          d,
          (tag) => tag !== 6 && tag !== 4,
        )
      )
        continue;
      const f = this.facing(q, e.x, e.y, e.z);
      if (f < 0.1) continue;
      const dur = (e.data["blind"] ?? 1.5) * Math.min(1, (f - 0.1) / 0.6);
      q.status.blind = Math.max(q.status.blind, this.host.tick + Math.round(dur * TICK));
      this.host.toPlayer(q.id, e.ability, EVENT.BLIND, { dur });
    }
  }
}

function norm(x: number, y: number, z: number): [number, number, number] {
  const l = Math.hypot(x, y, z) || 1;
  return [x / l, y / l, z / l];
}

export function distToSegment(
  px: number,
  pz: number,
  ax: number,
  az: number,
  bx: number,
  bz: number,
): number {
  const vx = bx - ax;
  const vz = bz - az;
  const l2 = vx * vx + vz * vz;
  const t = l2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * vx + (pz - az) * vz) / l2)) : 0;
  return Math.hypot(px - (ax + vx * t), pz - (az + vz * t));
}

function segmentSphere(
  ax: number,
  ay: number,
  az: number,
  bx: number,
  by: number,
  bz: number,
  cx: number,
  cy: number,
  cz: number,
  r: number,
): boolean {
  const dx = bx - ax;
  const dy = by - ay;
  const dz = bz - az;
  const l2 = dx * dx + dy * dy + dz * dz;
  const t =
    l2 > 0 ? Math.max(0, Math.min(1, ((cx - ax) * dx + (cy - ay) * dy + (cz - az) * dz) / l2)) : 0;
  const px = ax + dx * t - cx;
  const py = ay + dy * t - cy;
  const pz = az + dz * t - cz;
  return px * px + py * py + pz * pz < r * r;
}

function segmentsIntersect2D(
  ax: number,
  az: number,
  bx: number,
  bz: number,
  cx: number,
  cz: number,
  dx: number,
  dz: number,
): boolean {
  const o = (px: number, pz: number, qx: number, qz: number, rx: number, rz: number): number =>
    Math.sign((qx - px) * (rz - pz) - (qz - pz) * (rx - px));
  return (
    o(ax, az, bx, bz, cx, cz) !== o(ax, az, bx, bz, dx, dz) &&
    o(cx, cz, dx, dz, ax, az) !== o(cx, cz, dx, dz, bx, bz)
  );
}
