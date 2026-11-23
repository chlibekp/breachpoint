// Statistical anti-cheat (spec §14.3). Authority + fog of war remove most cheat value; this layer
// watches what is left (aim assistance) and produces *review flags* stored with the match result.
// Nothing here kicks or bans: a human reviews the flagged match replay.
//   • reaction: time from an enemy becoming visible (after being unseen for reacquireGapMs) to the
//     first damaging hit on them. Median below reactionMedianFlagMs over enough samples is inhuman.
//   • snap: a large view rotation within snapWindowTicks immediately before a headshot.
//   • headshot ratio and raw accuracy over the whole match.
import { TICK_RATE } from "../sim/constants.ts";

export interface AntiCheatConfig {
  reactionMinSamples: number;
  reactionMedianFlagMs: number;
  reacquireGapMs: number;
  snapDegrees: number;
  snapWindowTicks: number;
  snapMinCount: number;
  snapShareOfHeadshots: number;
  headshotMinHits: number;
  headshotRatioFlag: number;
  accuracyMinShots: number;
  accuracyFlag: number;
  maxInterpMs: number;
}

export interface CheatFlag {
  kind: "reaction" | "snap" | "headshot_ratio" | "accuracy";
  value: number;
  samples: number;
}

class AimStats {
  shots = 0;
  hitShots = 0;
  hits = 0;
  headHits = 0;
  snapHeads = 0;
  reactionsMs: number[] = [];
  /** Recent view angles, newest last: [yaw, pitch]. */
  view: [number, number][] = [];
  /** enemy id -> tick they (re)appeared and have not been hit since. */
  spotted = new Map<number, number>();
  lastVisible = new Map<number, number>();
}

export class AntiCheat {
  private readonly players = new Map<number, AimStats>();

  constructor(readonly cfg: AntiCheatConfig) {}

  private s(id: number): AimStats {
    let st = this.players.get(id);
    if (!st) {
      st = new AimStats();
      this.players.set(id, st);
    }
    return st;
  }

  /** Called once per tick per human with the view the input produced. */
  view(id: number, yaw: number, pitch: number): void {
    const st = this.s(id);
    st.view.push([yaw, pitch]);
    if (st.view.length > this.cfg.snapWindowTicks + 1) st.view.shift();
  }

  /** Viewer can see target this tick (from the fog-of-war pass). */
  visible(viewer: number, target: number, tick: number): void {
    const st = this.s(viewer);
    const last = st.lastVisible.get(target) ?? -1e9;
    const gapTicks = (this.cfg.reacquireGapMs / 1000) * TICK_RATE;
    if (tick - last > gapTicks) st.spotted.set(target, tick);
    st.lastVisible.set(target, tick);
  }

  /** One trigger pull resolved: whether any pellet hit, and whether it hit a head. */
  shot(id: number, hitAny: boolean, headAny: boolean): void {
    const st = this.s(id);
    st.shots++;
    if (hitAny) st.hitShots++;
    if (!headAny) return;
    // Rotation across the snap window right before this headshot.
    const v = st.view;
    if (v.length >= 2) {
      const [y0, p0] = v[0]!;
      const [y1, p1] = v[v.length - 1]!;
      const dy = Math.atan2(Math.sin(y1 - y0), Math.cos(y1 - y0));
      const deg = (Math.hypot(dy, p1 - p0) * 180) / Math.PI;
      if (deg >= this.cfg.snapDegrees) st.snapHeads++;
    }
  }

  /** A damaging hit landed (per victim per shot). */
  hit(attacker: number, victim: number, head: boolean, tick: number): void {
    const st = this.s(attacker);
    st.hits++;
    if (head) st.headHits++;
    const seen = st.spotted.get(victim);
    if (seen !== undefined) {
      st.reactionsMs.push(((tick - seen) * 1000) / TICK_RATE);
      st.spotted.delete(victim);
    }
  }

  flags(id: number): CheatFlag[] {
    const st = this.players.get(id);
    if (!st) return [];
    const c = this.cfg;
    const out: CheatFlag[] = [];
    if (st.reactionsMs.length >= c.reactionMinSamples) {
      const sorted = [...st.reactionsMs].sort((a, b) => a - b);
      const median = sorted[Math.floor(sorted.length / 2)]!;
      if (median < c.reactionMedianFlagMs)
        out.push({ kind: "reaction", value: median, samples: sorted.length });
    }
    if (
      st.snapHeads >= c.snapMinCount &&
      st.snapHeads / Math.max(1, st.headHits) >= c.snapShareOfHeadshots
    )
      out.push({
        kind: "snap",
        value: st.snapHeads / Math.max(1, st.headHits),
        samples: st.snapHeads,
      });
    if (st.hits >= c.headshotMinHits && st.headHits / st.hits >= c.headshotRatioFlag)
      out.push({ kind: "headshot_ratio", value: st.headHits / st.hits, samples: st.hits });
    if (st.shots >= c.accuracyMinShots && st.hitShots / st.shots >= c.accuracyFlag)
      out.push({ kind: "accuracy", value: st.hitShots / st.shots, samples: st.shots });
    return out;
  }

  summary(id: number): { shots: number; hits: number; headHits: number; reactions: number } {
    const st = this.s(id);
    return {
      shots: st.shots,
      hits: st.hits,
      headHits: st.headHits,
      reactions: st.reactionsMs.length,
    };
  }
}
