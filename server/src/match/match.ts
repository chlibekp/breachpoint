// A single match's authoritative state. Milestone 1: tick bookkeeping only;
// movement/hitscan/rounds arrive in milestones 4-5 via the pure /server/src/sim package.
import { TICK_RATE } from "../sim/constants.ts";
import { FixedTickLoop } from "./fixed-tick-loop.ts";

export interface MatchOptions {
  matchId: string;
  map: string;
  seed: number;
}

export class Match {
  readonly loop: FixedTickLoop;
  tick = 0;

  constructor(readonly options: MatchOptions) {
    this.loop = new FixedTickLoop(TICK_RATE, (t) => this.step(t));
  }

  start(): void {
    this.loop.start();
  }

  stop(): void {
    this.loop.stop();
  }

  /** One simulation step. Must stay allocation-free and well under 2 ms. */
  step(tick: number): void {
    this.tick = tick;
  }
}
