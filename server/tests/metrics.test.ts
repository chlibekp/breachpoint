import { describe, expect, it } from "vitest";
import { Registry, TickSampler } from "../src/services/metrics.ts";

describe("prometheus metrics", () => {
  it("renders counters, labelled gauges and cumulative histograms in text format", () => {
    const r = new Registry();
    r.bytesOut.inc(100);
    r.bytesOut.inc(50);
    r.players.set(4, { kind: "human" });
    const s = new TickSampler();
    for (const ms of [0.3, 0.7, 3, 11, 40]) s.observe(ms / 1000);
    const d = s.take();
    r.tickSeconds.merge(d.counts, d.sum, d.count);
    const text = r.render();
    expect(text).toContain("# TYPE bp_tick_duration_seconds histogram");
    expect(text).toContain("bp_bytes_sent_total 150");
    expect(text).toContain('bp_players{kind="human"} 4');
    expect(text).toContain('bp_tick_duration_seconds_bucket{le="0.001"} 2');
    expect(text).toContain('bp_tick_duration_seconds_bucket{le="0.01"} 3');
    expect(text).toContain('bp_tick_duration_seconds_bucket{le="+Inf"} 5');
    expect(text).toContain("bp_tick_duration_seconds_count 5");
    // The sampler resets after take().
    expect(s.take().count).toBe(0);
  });
});
