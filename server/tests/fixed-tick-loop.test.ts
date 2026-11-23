import { describe, expect, it } from "vitest";
import { FixedTickLoop } from "../src/match/fixed-tick-loop.ts";

describe("FixedTickLoop", () => {
  it("runs at 64 Hz without drift over one second", async () => {
    const stamps: number[] = [];
    const t0 = performance.now();
    const loop = new FixedTickLoop(64, () => stamps.push(performance.now() - t0));
    loop.start();
    await new Promise((r) => setTimeout(r, 1000));
    loop.stop();
    // 64 ticks expected in 1 s; allow ±2 for timer granularity on CI runners.
    expect(stamps.length).toBeGreaterThanOrEqual(62);
    expect(stamps.length).toBeLessThanOrEqual(65);
    // No cumulative drift: tick n lands near n * 15.625 ms.
    const last = stamps[stamps.length - 1]!;
    expect(Math.abs(last - stamps.length * (1000 / 64))).toBeLessThan(6);
  });

  it("skips ahead after a long stall instead of spiralling", async () => {
    let calls = 0;
    const loop = new FixedTickLoop(
      64,
      () => {
        calls++;
        if (calls === 1) {
          const until = performance.now() + 400; // simulate a 400 ms stall (~25 ticks)
          while (performance.now() < until) {
            /* busy */
          }
        }
      },
      4,
    );
    loop.start();
    await new Promise((r) => setTimeout(r, 500));
    loop.stop();
    expect(loop.stats.lateTicks).toBeGreaterThan(10);
    expect(calls).toBeLessThan(loop.stats.ticks);
  });
});
