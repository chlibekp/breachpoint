// Server bots (spec milestone 4: "10 bots + real players in one match"). Bots produce the same
// input commands as players, so they run through the identical authoritative pipeline.
// Navigation: a graph over the map's callout rectangles (walkable lanes); combat: reaction delay,
// limited turn rate, counter-strafe before firing, short bursts, aim error that tightens over time.
import { Buttons as B } from "../sim/movement.ts";
import type { MapMeta, V3 } from "./world-data.ts";

export interface BotView {
  x: number;
  y: number;
  z: number;
  yaw: number;
  pitch: number;
  team: number;
  attacking: boolean;
  hasCharge: boolean;
  speed: number;
}

export interface BotTarget {
  id: number;
  x: number;
  y: number;
  z: number;
  visible: boolean;
}

export interface BotGoal {
  kind: "plant" | "defuse" | "hold" | "hunt";
  x: number;
  z: number;
}

export interface BotOutput {
  buttons: number;
  yaw: number;
  pitch: number;
}

interface NavNode {
  name: string;
  cx: number;
  cz: number;
  hx: number;
  hz: number;
  edges: number[];
}

export class NavGraph {
  nodes: NavNode[] = [];

  constructor(meta: MapMeta) {
    for (const c of meta.nav ?? meta.callouts) {
      this.nodes.push({
        name: c.name,
        cx: c.center[0],
        cz: c.center[2],
        hx: c.size[0] / 2,
        hz: c.size[2] / 2,
        edges: [],
      });
    }
    for (let i = 0; i < this.nodes.length; i++) {
      for (let j = i + 1; j < this.nodes.length; j++) {
        const a = this.nodes[i]!;
        const b = this.nodes[j]!;
        const ox = Math.min(a.cx + a.hx, b.cx + b.hx) - Math.max(a.cx - a.hx, b.cx - b.hx);
        const oz = Math.min(a.cz + a.hz, b.cz + b.hz) - Math.max(a.cz - a.hz, b.cz - b.hz);
        // Touching/overlapping rectangles with at least ~1.5 m of shared edge are connected.
        if (ox >= -0.5 && oz >= -0.5 && Math.max(ox, oz) >= 1.5) {
          a.edges.push(j);
          b.edges.push(i);
        }
      }
    }
  }

  nodeAt(x: number, z: number): number {
    let best = -1;
    let bestD = Infinity;
    for (let i = 0; i < this.nodes.length; i++) {
      const n = this.nodes[i]!;
      const inside = Math.abs(x - n.cx) <= n.hx && Math.abs(z - n.cz) <= n.hz;
      const d = inside ? 0 : Math.hypot(x - n.cx, z - n.cz);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /** BFS path of node indices from a to b. */
  path(a: number, b: number): number[] {
    if (a < 0 || b < 0) return [];
    const prev = new Map<number, number>([[a, -1]]);
    const q = [a];
    while (q.length > 0) {
      const n = q.shift()!;
      if (n === b) break;
      for (const e of this.nodes[n]!.edges) {
        if (!prev.has(e)) {
          prev.set(e, n);
          q.push(e);
        }
      }
    }
    if (!prev.has(b)) return [];
    const out: number[] = [];
    for (let n = b; n !== -1; n = prev.get(n)!) out.unshift(n);
    return out;
  }

  /** A waypoint inside the shared edge between two nodes, so bots pass through doorways. */
  portal(a: number, b: number): [number, number] {
    const na = this.nodes[a]!;
    const nb = this.nodes[b]!;
    const x0 = Math.max(na.cx - na.hx, nb.cx - nb.hx);
    const x1 = Math.min(na.cx + na.hx, nb.cx + nb.hx);
    const z0 = Math.max(na.cz - na.hz, nb.cz - nb.hz);
    const z1 = Math.min(na.cz + na.hz, nb.cz + nb.hz);
    return [(x0 + x1) / 2, (z0 + z1) / 2];
  }
}

export class BotBrain {
  private path: number[] = [];
  private goalKey = "";
  private reaction = 0;
  private currentTarget = -1;
  private aimErr = 0;
  private burst = 0;
  private stuckTicks = 0;
  private lastPos: [number, number] = [0, 0];
  private strafeDir = 1;
  private repathTicks = 0;
  private trigger = false;

  constructor(
    private readonly nav: NavGraph,
    private readonly rand: () => number,
    readonly skill = 0.6,
  ) {}

  think(
    me: BotView,
    targets: BotTarget[],
    goal: BotGoal,
    eyeH: number,
    engageRange = 45,
  ): BotOutput {
    let buttons = 0;
    let yaw = me.yaw;
    let pitch = me.pitch;
    // --- combat: pick the closest visible enemy.
    let best: BotTarget | null = null;
    let bestD = Infinity;
    for (const t of targets) {
      if (!t.visible) continue;
      const d = Math.hypot(t.x - me.x, t.z - me.z);
      if (d > engageRange) continue; // out of effective range: keep playing the objective
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    if (best) {
      if (best.id !== this.currentTarget) {
        this.currentTarget = best.id;
        this.reaction = Math.round((0.18 + (1 - this.skill) * 0.25 + this.rand() * 0.12) * 64);
        this.aimErr = (1.5 - this.skill) * 0.12;
      }
      const dx = best.x - me.x;
      const dz = best.z - me.z;
      const dy = best.y + 1.35 - (me.y + eyeH);
      const wantYaw = Math.atan2(-dx, -dz);
      const wantPitch = Math.atan2(dy, Math.hypot(dx, dz));
      const turn = (0.09 + this.skill * 0.08) * (this.reaction > 0 ? 0.4 : 1);
      yaw = approachAngle(me.yaw, wantYaw + (this.rand() - 0.5) * this.aimErr, turn);
      pitch =
        me.pitch +
        clamp(wantPitch + (this.rand() - 0.5) * this.aimErr * 0.6 - me.pitch, -turn, turn);
      this.aimErr = Math.max(0.004, this.aimErr * 0.96);
      if (this.reaction > 0) {
        this.reaction--;
        // Strafe while reacting (peek feel), then stop to shoot accurately.
        buttons |= this.strafeDir > 0 ? B.RIGHT : B.LEFT;
      } else {
        const aligned = Math.abs(angleDiff(me.yaw, wantYaw)) < 0.06 + bestD * 0.0005;
        if (me.speed > 1.4) buttons |= this.strafeDir > 0 ? B.LEFT : B.RIGHT; // counter-strafe
        if (aligned && me.speed < 1.4) {
          if (this.burst <= 0) this.burst = 3 + Math.floor(this.rand() * 4);
          // Tap the trigger (release every other tick) so semi-automatic weapons keep firing.
          this.trigger = !this.trigger;
          if (this.trigger) {
            buttons |= B.FIRE;
            this.burst--;
          }
        }
        if (this.burst <= 0 && this.rand() < 0.08) this.strafeDir = -this.strafeDir;
      }
      return { buttons, yaw, pitch };
    }
    this.currentTarget = -1;
    // --- objective actions.
    const toGoal = Math.hypot(goal.x - me.x, goal.z - me.z);
    if (
      (goal.kind === "plant" && me.hasCharge && toGoal < 2.5) ||
      (goal.kind === "defuse" && toGoal < 1.0)
    ) {
      return { buttons: B.USE | B.CROUCH, yaw: me.yaw, pitch: -0.3 };
    }
    if (goal.kind === "hold" && toGoal < 2.0) {
      // Hold an angle: slowly sweep.
      return {
        buttons: 0,
        yaw: me.yaw + Math.sin(Date.now() / 900 + this.skill * 10) * 0.004,
        pitch: 0,
      };
    }
    // --- navigation.
    const key = `${goal.kind}:${Math.round(goal.x)}:${Math.round(goal.z)}`;
    if (key !== this.goalKey || this.path.length === 0 || --this.repathTicks <= 0) {
      this.goalKey = key;
      this.path = this.nav.path(this.nav.nodeAt(me.x, me.z), this.nav.nodeAt(goal.x, goal.z));
      this.repathTicks = 64 * 3;
    }
    let tx = goal.x;
    let tz = goal.z;
    // Inside overlapping lane rectangles, take the one furthest along the path (no oscillation).
    let idx = -1;
    for (let k = this.path.length - 1; k >= 0; k--) {
      const n = this.nav.nodes[this.path[k]!]!;
      if (Math.abs(me.x - n.cx) <= n.hx && Math.abs(me.z - n.cz) <= n.hz) {
        idx = k;
        break;
      }
    }
    if (idx < 0) idx = this.path.indexOf(this.nav.nodeAt(me.x, me.z));
    if (idx >= 0 && idx < this.path.length - 1) {
      [tx, tz] = this.nav.portal(this.path[idx]!, this.path[idx + 1]!);
      const n = this.nav.nodes[this.path[idx + 1]!]!;
      // Already inside the next rectangle's overlap (or at the portal): head for its centre.
      if (
        Math.hypot(tx - me.x, tz - me.z) < 1.5 ||
        (Math.abs(me.x - n.cx) <= n.hx && Math.abs(me.z - n.cz) <= n.hz)
      )
        [tx, tz] = [n.cx, n.cz];
    }
    yaw = approachAngle(me.yaw, Math.atan2(-(tx - me.x), -(tz - me.z)), 0.12);
    pitch = me.pitch * 0.9;
    buttons |= B.FORWARD;
    // Stuck detection: jump / sidestep.
    if (Math.hypot(me.x - this.lastPos[0], me.z - this.lastPos[1]) < 0.02) this.stuckTicks++;
    else this.stuckTicks = 0;
    this.lastPos = [me.x, me.z];
    if (this.stuckTicks > 20) {
      buttons |= this.rand() < 0.5 ? B.JUMP : this.strafeDir > 0 ? B.RIGHT : B.LEFT;
      if (this.stuckTicks > 60) {
        this.strafeDir = -this.strafeDir;
        this.stuckTicks = 0;
        this.path = [];
      }
    }
    return { buttons, yaw, pitch };
  }
}

function angleDiff(a: number, b: number): number {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

function approachAngle(cur: number, want: number, maxStep: number): number {
  return cur + clamp(angleDiff(cur, want), -maxStep, maxStep);
}

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

export function centerOf(c: { center: V3 }): [number, number] {
  return [c.center[0], c.center[2]];
}
