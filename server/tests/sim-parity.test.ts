import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { loadRawConfig, SHARED_DIR } from "@breachpoint/shared/config";
import { makeBox, type World } from "../src/sim/collision.ts";
import { newMoveState, stepMovement, type MovementConfig } from "../src/sim/movement.ts";
import { hashSeed, mulberry32 } from "../src/sim/rng.ts";
import { newWeaponState, tryFire, updateWeapon, type WeaponDef } from "../src/sim/weapons.ts";

const mv = JSON.parse(readFileSync(join(SHARED_DIR, "tests/movement/vectors.json"), "utf8")) as {
  boxes: [number, number, number, number, number, number, number, number][];
  scenarios: {
    name: string;
    start: [number, number, number];
    inputs: [number, number, number][];
    checkpoints: Record<string, number | boolean>[];
  }[];
};
const wv = JSON.parse(readFileSync(join(SHARED_DIR, "tests/weapons/vectors.json"), "utf8")) as {
  rng: { seedA: number; seedB: number; hash: number; sequence: number[] };
  cases: Record<
    string,
    {
      shots: {
        t: number;
        yawOffset: number;
        pitchOffset: number;
        pellets: { yaw: number; pitch: number }[];
        ammo: number;
      }[];
    }
  >;
};
const cfg = loadRawConfig("movement") as MovementConfig;
const weapons = (loadRawConfig("weapons") as { weapons: WeaponDef[] }).weapons;

describe("movement golden vectors (server side)", () => {
  const world: World = { boxes: mv.boxes.map((b) => makeBox(...b)) };
  for (const sc of mv.scenarios) {
    it(sc.name, () => {
      const s = newMoveState(...sc.start);
      let cp = 0;
      sc.inputs.forEach(([buttons, yaw, runSpeed], i) => {
        stepMovement(cfg, world, s, { buttons, yaw, runSpeed });
        const want = sc.checkpoints[cp];
        if (want && want["tick"] === i + 1) {
          for (const k of ["x", "y", "z"] as const)
            expect(Math.abs(s[k] - (want[k] as number))).toBeLessThan(0.001);
          expect(s.grounded).toBe(want["grounded"]);
          cp++;
        }
      });
    });
  }
});

describe("movement feel targets (spec §10.1)", () => {
  const world: World = { boxes: [makeBox(0, -0.5, 0, 50, 0.5, 50, 0, 0)] };
  it("reaches full run speed in ~0.15 s and stops in ~0.1 s", () => {
    const s = newMoveState(0, 0, 0);
    let ticks = 0;
    while (Math.hypot(s.vx, s.vz) < 6.75 - 1e-6 && ticks < 64) {
      stepMovement(cfg, world, s, { buttons: 1, yaw: 0, runSpeed: 6.75 });
      ticks++;
    }
    expect(ticks / 64).toBeLessThanOrEqual(0.16);
    let stop = 0;
    while (Math.hypot(s.vx, s.vz) > 1e-6 && stop < 64) {
      stepMovement(cfg, world, s, { buttons: 0, yaw: 0, runSpeed: 6.75 });
      stop++;
    }
    expect(stop / 64).toBeLessThanOrEqual(0.11);
  });
  it("jumps 1 m high", () => {
    const s = newMoveState(0, 0, 0);
    stepMovement(cfg, world, s, { buttons: 16, yaw: 0, runSpeed: 6.75 });
    let peak = 0;
    for (let i = 0; i < 64; i++) {
      stepMovement(cfg, world, s, { buttons: 0, yaw: 0, runSpeed: 6.75 });
      peak = Math.max(peak, s.y);
    }
    expect(peak).toBeGreaterThan(0.95);
    expect(peak).toBeLessThan(1.05);
  });
});

describe("weapon golden vectors (server side)", () => {
  it("rng stream", () => {
    expect(hashSeed(wv.rng.seedA, wv.rng.seedB)).toBe(wv.rng.hash);
    const r = mulberry32(wv.rng.hash);
    for (const v of wv.rng.sequence) expect(r()).toBe(v);
  });
  it("first standing Saber shot is pinpoint", () => {
    const shot = wv.cases["saber_spray"]!.shots[0]!;
    expect(shot.pellets[0]!.yaw).toBe(0);
    expect(shot.pellets[0]!.pitch).toBe(0);
  });
  it("spray climbs (learnable pattern)", () => {
    const shots = wv.cases["saber_spray"]!.shots;
    expect(shots[7]!.pitchOffset).toBeGreaterThan(shots[1]!.pitchOffset);
  });
  it("regenerates identically", () => {
    const def = weapons.find((w) => w.id === "saber")!;
    const st = newWeaponState(def, 0);
    let now = def.equipTime;
    let n = 0;
    for (let t = 0; t < 240 && n < 12; t++) {
      updateWeapon(def, st, now, 1 / 64, true);
      const shot = tryFire(
        def,
        st,
        {
          now,
          speedFrac: 0,
          standingThreshold: 0.2,
          crouched: false,
          airborne: false,
          ads: false,
          seed: 777,
          playerId: 3,
        },
        t === 0,
        true,
      );
      if (shot) {
        const want = wv.cases["saber_spray"]!.shots[n]!;
        expect(shot.pellets[0]!.yaw).toBeCloseTo(want.pellets[0]!.yaw, 12);
        n++;
      }
      now += 1 / 64;
    }
    expect(n).toBe(12);
  });
});
