import { describe, expect, it } from "vitest";
import { Match, Phase } from "../src/match/match.ts";
import { newMoveState } from "../src/sim/movement.ts";

function setup(
  agentA: string,
  agentD: string,
): {
  m: Match;
  a: ReturnType<Match["addPlayer"]>;
  d: ReturnType<Match["addPlayer"]>;
  events: string[];
} {
  const m = new Match({ matchId: "t", map: "range", seed: 3 });
  const events: string[] = [];
  m.setTransport((_id, msg) => {
    if (msg.type === "AbilityEvent") events.push(`${msg.ability}:${msg.event}`);
  });
  const a = m.addPlayer(1, "a", agentA);
  const d = m.addPlayer(2, "d", agentD);
  m.startManual();
  m.phase = Phase.COMBAT;
  // Facing each other down the open lane, 12 m apart.
  a.move = newMoveState(0, 0, -10);
  a.yaw = 0;
  d.move = newMoveState(0, 0, -22);
  d.yaw = Math.PI;
  // The server takes view angles from each player's latest input command.
  d.lastCmd = { ...d.lastCmd, yaw: Math.PI, pitch: 0 };
  return { m, a, d, events };
}

describe("abilities (spec §10.5, §11)", () => {
  it("smoke blocks line of sight for fog of war", () => {
    const { m, a, d } = setup("vesper", "kestrel");
    m.step();
    expect(m.canSee(a, d)).toBe(true);
    a.pitch = -0.25; // aim at the ground between them (~6 m ahead)
    a.charges[2] = 1;
    expect(m.abilities.cast(a, "E", true)).toBe(true);
    m.step();
    expect(m.abilities.effects.some((e) => e.kind === "smoke")).toBe(true);
    expect(m.canSee(a, d)).toBe(false);
  });

  it("flash blinds only players facing it", () => {
    const { m, a, d } = setup("kestrel", "kestrel");
    a.charges[1] = 1;
    a.pitch = 0;
    expect(m.abilities.cast(a, "Q", true)).toBe(true);
    const f0 = m.abilities.effects.find((e) => e.kind === "flash")!;
    for (let i = 0; i < 64; i++) {
      // Facing the pop point (yaw 0 = -Z): direction toward the flash.
      d.lastCmd = {
        ...d.lastCmd,
        yaw: Math.atan2(-(f0.x - d.move.x), -(f0.z - d.move.z)),
        pitch: 0,
      };
      m.step();
    }
    expect(d.status.blind).toBeGreaterThan(m.tick - 64);
    // Turned away: no blind.
    const r = setup("kestrel", "kestrel");
    r.a.charges[1] = 1;
    r.m.abilities.cast(r.a, "Q", true);
    const fl = r.m.abilities.effects.find((e) => e.kind === "flash")!;
    // Look directly away from where the flash will pop (yaw 0 faces -Z).
    for (let i = 0; i < 64; i++) {
      r.d.lastCmd = {
        ...r.d.lastCmd,
        yaw: Math.atan2(fl.x - r.d.move.x, fl.z - r.d.move.z),
        pitch: 0 /* looking away */,
      };
      r.m.step();
    }
    expect(r.d.status.blind).toBe(0);
  });

  it("barricade adds bullet- and movement-blocking collision", () => {
    const { m, a } = setup("imani", "kestrel");
    const before = m.world.boxes.length;
    a.charges[0] = 1;
    expect(m.abilities.cast(a, "C", true)).toBe(true);
    expect(m.world.boxes.length).toBe(before + 1);
  });

  it("C/Q charges are bought with credits, ultimate needs points", () => {
    const { m, a } = setup("sable", "kestrel");
    m.phase = Phase.BUY;
    a.credits = 1000;
    a.charges[0] = 0;
    m.buy(a.id, "ability_C");
    expect(a.charges[0]).toBe(1);
    expect(a.credits).toBe(800);
    a.ult = 0;
    expect(m.abilities.cast(a, "X", true)).toBe(false);
    a.ult = 7;
    expect(m.abilities.cast(a, "X", true)).toBe(true);
    expect(a.ult).toBe(0);
  });
});
