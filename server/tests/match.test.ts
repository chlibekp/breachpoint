import { describe, expect, it } from "vitest";
import { Match, Phase } from "../src/match/match.ts";

describe.each(["solstice", "neon"])("authoritative match with 10 bots on %s", (map) => {
  it("plays rounds to completion within the tick budget", () => {
    const m = new Match({
      matchId: "t",
      map,
      seed: 42,
      fillBots: true,
      roundsToWin: 3,
      phaseScale: 0.5,
    });
    const kills: number[] = [];
    const ends: string[] = [];
    m.setTransport(() => undefined);
    // Count events by wrapping the internal broadcast via a fake human observer.
    m.addPlayer(1, "observer");
    m.setTransport((id, msg) => {
      if (id !== 1) return;
      if (msg.type === "Kill") kills.push(msg.victimId);
      if (msg.type === "RoundEnd") ends.push(msg.reason);
    });
    m.startManual();
    expect(m.players.size).toBe(10);
    const times: number[] = [];
    let ticks = 0;
    while (m.phase !== Phase.MATCH_OVER && ticks < 64 * 60 * 15) {
      const t0 = performance.now();
      m.step();
      times.push(performance.now() - t0);
      ticks++;
    }
    times.sort((a, b) => a - b);
    const avg = times.reduce((a, b) => a + b, 0) / times.length;
    const p99 = times[Math.floor(times.length * 0.99)]!;
    console.log(
      `${map} ticks=${ticks} rounds=${m.round} score=${m.score.join(":")} kills=${kills.length} ends=${ends.join(",")} avg=${avg.toFixed(3)}ms p99=${p99.toFixed(3)}ms`,
    );
    expect(m.phase).toBe(Phase.MATCH_OVER);
    expect(kills.length).toBeGreaterThan(3);
    expect(avg).toBeLessThan(2);
    expect(p99).toBeLessThan(10);
    for (const p of m.players.values()) {
      expect(p.credits).toBeLessThanOrEqual(9000);
      expect(Number.isFinite(p.move.x) && Number.isFinite(p.move.z)).toBe(true);
    }
  }, 120000);
});
