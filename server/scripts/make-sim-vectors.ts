// Generates golden parity vectors (spec §13.3): shared/tests/movement/vectors.json and
// shared/tests/weapons/vectors.json. Regenerate only when the sim changes on purpose; both the
// TypeScript tests and the GDScript tests replay them (tolerance 1 mm / 1e-6 rad).
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadRawConfig, SHARED_DIR } from "@breachpoint/shared/config";
import { makeBox, type World } from "../src/sim/collision.ts";
import {
  Buttons as B,
  newMoveState,
  stepMovement,
  type MovementConfig,
} from "../src/sim/movement.ts";
import { mulberry32, hashSeed } from "../src/sim/rng.ts";
import { newWeaponState, tryFire, updateWeapon, type WeaponDef } from "../src/sim/weapons.ts";

const cfg = loadRawConfig("movement") as MovementConfig;
const weapons = (loadRawConfig("weapons") as { weapons: WeaponDef[] }).weapons;

// Test world: floor, a rotated wall, stairs (0.3 m steps), a 1 m box, a ledge, a low ceiling beam.
const boxSpecs: [number, number, number, number, number, number, number, number][] = [
  [0, -0.5, 0, 30, 0.5, 30, 0, 0],
  [6, 1.5, -6, 3, 1.5, 0.25, 0.5236, 0],
  [-4, 0.15, -6, 1, 0.15, 0.6, 0, 0],
  [-4, 0.3, -7.2, 1, 0.3, 0.6, 0, 0],
  [-4, 0.45, -8.4, 1, 0.45, 0.6, 0, 0],
  [-4, 0.6, -9.6, 1, 0.6, 0.6, 0, 0],
  [3, 0.5, 4, 0.6, 0.5, 0.6, 0, 1],
  [-8, 1.5, 6, 2, 1.5, 2, 0, 0],
  [0, 1.65, 10, 3, 0.15, 0.5, 0, 0],
];
const world: World = { boxes: boxSpecs.map((b) => makeBox(...b)) };

interface Seg {
  ticks: number;
  buttons: number;
  yaw: number;
  runSpeed?: number;
}
interface Scenario {
  name: string;
  start: [number, number, number];
  segments: Seg[];
}

const RUN = 6.75;
const scenarios: Scenario[] = [
  {
    name: "run_then_counter_strafe",
    start: [0, 0, 0],
    segments: [
      { ticks: 40, buttons: B.RIGHT, yaw: 0 },
      { ticks: 8, buttons: B.LEFT, yaw: 0 },
      { ticks: 20, buttons: 0, yaw: 0 },
    ],
  },
  {
    name: "diagonal_into_rotated_wall",
    start: [4, 0, -2],
    segments: [{ ticks: 90, buttons: B.FORWARD | B.RIGHT, yaw: 0.3 }],
  },
  {
    name: "climb_stairs",
    start: [-4, 0, -4],
    segments: [{ ticks: 110, buttons: B.FORWARD, yaw: 0 }],
  },
  {
    name: "jump_and_land",
    start: [0, 0, 2],
    segments: [
      { ticks: 10, buttons: B.FORWARD, yaw: 1.2 },
      { ticks: 1, buttons: B.FORWARD | B.JUMP, yaw: 1.2 },
      { ticks: 60, buttons: B.FORWARD, yaw: 1.2 },
    ],
  },
  {
    name: "jump_onto_box",
    start: [3, 0, 6.5],
    segments: [
      { ticks: 4, buttons: B.FORWARD, yaw: 0 },
      { ticks: 1, buttons: B.FORWARD | B.JUMP, yaw: 0 },
      { ticks: 50, buttons: B.FORWARD, yaw: 0 },
    ],
  },
  {
    name: "crouch_walk_under_beam",
    start: [0, 0, 13],
    segments: [
      { ticks: 20, buttons: B.CROUCH, yaw: 0 },
      { ticks: 120, buttons: B.FORWARD | B.CROUCH, yaw: 0 },
      { ticks: 30, buttons: B.FORWARD, yaw: 0 },
    ],
  },
  {
    name: "walk_off_ledge",
    start: [-8, 3.0, 6],
    segments: [{ ticks: 100, buttons: B.FORWARD | B.WALK, yaw: -1.5708 }],
  },
  {
    name: "heavy_weapon_run",
    start: [0, 0, -12],
    segments: [{ ticks: 60, buttons: B.FORWARD | B.LEFT, yaw: 2.2, runSpeed: 5.4 }],
  },
];

const movement = scenarios.map((sc) => {
  const s = newMoveState(...sc.start);
  const inputs: [number, number, number][] = [];
  const checkpoints: {
    tick: number;
    x: number;
    y: number;
    z: number;
    vx: number;
    vy: number;
    vz: number;
    grounded: boolean;
    crouch: number;
  }[] = [];
  let tick = 0;
  for (const seg of sc.segments) {
    for (let i = 0; i < seg.ticks; i++) {
      const rs = seg.runSpeed ?? RUN;
      inputs.push([seg.buttons, seg.yaw, rs]);
      stepMovement(cfg, world, s, { buttons: seg.buttons, yaw: seg.yaw, runSpeed: rs });
      tick++;
      if (tick % 8 === 0)
        checkpoints.push({
          tick,
          x: s.x,
          y: s.y,
          z: s.z,
          vx: s.vx,
          vy: s.vy,
          vz: s.vz,
          grounded: s.grounded,
          crouch: s.crouch,
        });
    }
  }
  checkpoints.push({
    tick,
    x: s.x,
    y: s.y,
    z: s.z,
    vx: s.vx,
    vy: s.vy,
    vz: s.vz,
    grounded: s.grounded,
    crouch: s.crouch,
  });
  return { name: sc.name, start: sc.start, inputs, checkpoints };
});

const dir = join(SHARED_DIR, "tests");
mkdirSync(join(dir, "movement"), { recursive: true });
writeFileSync(
  join(dir, "movement", "vectors.json"),
  JSON.stringify({
    comment: "Golden movement vectors. Regenerate: npm run sim:vectors",
    boxes: boxSpecs,
    scenarios: movement,
  }) + "\n",
);

// Weapons: RNG stream, then a Saber spray + Wasp taps + Breaker pellets with fixed seeds.
const rng = mulberry32(hashSeed(12345, 7));
const rngSeq = Array.from({ length: 8 }, () => rng());
function spray(id: string, shots: number, held: boolean, speedFrac: number): { shots: unknown[] } {
  const def = weapons.find((w) => w.id === id)!;
  const st = newWeaponState(def, 0);
  const out: unknown[] = [];
  let now = def.equipTime;
  for (let t = 0; t < shots * 20 && out.length < shots; t++) {
    const pressed = held ? t === 0 : t % 16 === 0;
    const hold = held || pressed;
    updateWeapon(def, st, now, 1 / 64, hold);
    const shot = tryFire(
      def,
      st,
      {
        now,
        speedFrac,
        standingThreshold: 0.2,
        crouched: false,
        airborne: false,
        ads: false,
        seed: 777,
        playerId: 3,
      },
      pressed,
      hold,
    );
    if (shot) out.push({ t: now, ...shot, ammo: st.ammo });
    now += 1 / 64;
  }
  return { shots: out };
}
mkdirSync(join(dir, "weapons"), { recursive: true });
writeFileSync(
  join(dir, "weapons", "vectors.json"),
  JSON.stringify({
    comment: "Golden weapon vectors. Regenerate: npm run sim:vectors",
    rng: { seedA: 12345, seedB: 7, hash: hashSeed(12345, 7), sequence: rngSeq },
    cases: {
      saber_spray: spray("saber", 12, true, 0),
      wasp_taps: spray("wasp", 5, false, 0.6),
      breaker: spray("breaker", 2, false, 0),
      lancer_burst: spray("lancer", 6, true, 0),
    },
  }) + "\n",
);
console.log(`✓ ${movement.length} movement scenarios, weapon vectors written`);
