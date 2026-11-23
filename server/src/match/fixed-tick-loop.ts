// Drift-corrected fixed-timestep loop (spec 13.1): schedules against an absolute
// high-resolution clock rather than setInterval, so ticks never accumulate drift.
// It sleeps with setTimeout until ~1.5 ms before the deadline, then yields with
// setImmediate for the final stretch to land within a fraction of a millisecond.

export interface TickStats {
  ticks: number;
  lateTicks: number;
  /** Duration of the tick callback, in ms. */
  lastTickMs: number;
  maxTickMs: number;
}

export class FixedTickLoop {
  readonly tickMs: number;
  readonly stats: TickStats = { ticks: 0, lateTicks: 0, lastTickMs: 0, maxTickMs: 0 };
  private running = false;
  private startNs = 0n;
  private timer: NodeJS.Timeout | NodeJS.Immediate | null = null;

  constructor(
    readonly tickRate: number,
    private readonly onTick: (tick: number) => void,
    /** Max ticks to run back-to-back after a stall before skipping ahead. */
    private readonly maxCatchUp = 8,
  ) {
    this.tickMs = 1000 / tickRate;
  }

  get isRunning(): boolean {
    return this.running;
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.startNs = process.hrtime.bigint();
    this.stats.ticks = 0;
    this.schedule();
  }

  stop(): void {
    this.running = false;
    if (this.timer !== null) {
      clearTimeout(this.timer as NodeJS.Timeout);
      clearImmediate(this.timer as NodeJS.Immediate);
      this.timer = null;
    }
  }

  private nowMs(): number {
    return Number(process.hrtime.bigint() - this.startNs) / 1e6;
  }

  private schedule(): void {
    if (!this.running) return;
    const deadline = (this.stats.ticks + 1) * this.tickMs;
    const wait = deadline - this.nowMs();
    if (wait > 1.5) {
      this.timer = setTimeout(() => this.schedule(), Math.floor(wait - 1));
    } else if (wait > 0) {
      this.timer = setImmediate(() => this.schedule());
    } else {
      this.runDue();
    }
  }

  private runDue(): void {
    let ran = 0;
    while (this.running && this.nowMs() >= (this.stats.ticks + 1) * this.tickMs) {
      if (ran >= this.maxCatchUp) {
        // Stalled too long: skip ahead instead of spiralling.
        const behind = Math.floor(this.nowMs() / this.tickMs) - this.stats.ticks;
        this.stats.lateTicks += behind;
        this.stats.ticks += behind;
        break;
      }
      if (ran > 0) this.stats.lateTicks++;
      const t0 = process.hrtime.bigint();
      this.stats.ticks++;
      this.onTick(this.stats.ticks);
      const dt = Number(process.hrtime.bigint() - t0) / 1e6;
      this.stats.lastTickMs = dt;
      if (dt > this.stats.maxTickMs) this.stats.maxTickMs = dt;
      ran++;
    }
    this.schedule();
  }
}
