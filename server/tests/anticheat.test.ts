import { describe, expect, it } from "vitest";
import { loadRawConfig } from "@breachpoint/shared/config";
import { AntiCheat, type AntiCheatConfig } from "../src/match/anticheat.ts";
import { Match } from "../src/match/match.ts";

const cfg = (loadRawConfig("match") as { antiCheat: AntiCheatConfig }).antiCheat;

/** Plays `n` engagements: enemy appears, the player turns `turnDeg` over 3 ticks and fires. */
function engage(
  ac: AntiCheat,
  n: number,
  reactTicks: number,
  turnDeg: number,
  hitEvery: number,
  headEvery = 1,
): void {
  let tick = 1000;
  for (let i = 0; i < n; i++) {
    const enemy = 100 + (i % 5);
    tick += 200; // well past the reacquire gap
    ac.visible(1, enemy, tick);
    let yaw = 0;
    for (let t = 0; t < reactTicks; t++) ac.view(1, yaw, 0);
    for (let t = 1; t <= 3; t++) {
      yaw = ((turnDeg * Math.PI) / 180) * (t / 3);
      ac.view(1, yaw, 0);
    }
    const hit = i % hitEvery === 0;
    const head = hit && (i / hitEvery) % headEvery === 0;
    ac.shot(1, hit, head);
    if (hit) ac.hit(1, enemy, head, tick + reactTicks + 3);
  }
}

describe("statistical anti-cheat", () => {
  it("flags inhuman reaction, snap-to-head, headshot ratio and accuracy", () => {
    const ac = new AntiCheat(cfg);
    engage(ac, 150, 2, 40, 1); // ~78 ms reactions, 40° snaps, every shot a headshot
    const kinds = ac.flags(1).map((f) => f.kind);
    expect(kinds).toEqual(
      expect.arrayContaining(["reaction", "snap", "headshot_ratio", "accuracy"]),
    );
  });

  it("does not flag a strong but human player", () => {
    const ac = new AntiCheat(cfg);
    engage(ac, 150, 16, 6, 3, 3); // ~300 ms reactions, small corrections, 1/3 hit, 1/3 of hits head
    expect(ac.flags(1)).toEqual([]);
  });

  it("bots never collect flags and results carry a flags field", () => {
    const m = new Match({
      matchId: "ac",
      map: "solstice",
      seed: 5,
      fillBots: true,
      roundsToWin: 1,
    });
    m.startManual();
    for (let i = 0; i < 64 * 30; i++) m.step();
    for (const p of m.players.values()) expect(m.ac.flags(p.id)).toEqual([]);
  });

  it("drops non-finite inputs and caps interpolation", () => {
    const m = new Match({ matchId: "ac2", map: "solstice", seed: 5 });
    m.addPlayer(1, "human");
    m.startManual();
    const base = { tick: 1, buttons: 0, weaponSlot: 1, pitch: 0 };
    m.receiveInput(1, [
      { ...base, seq: 1, yaw: Number.NaN, interpMs: 100 },
      { ...base, seq: 2, yaw: 0.5, interpMs: 5000 },
    ]);
    const p = m.players.get(1)!;
    expect(p.inputs.map((c) => c.seq)).toEqual([2]);
    expect(p.inputs[0]!.interpMs).toBe(cfg.maxInterpMs);
  });
});
