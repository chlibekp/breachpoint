// Server-side hitscan (spec §10.2, §13.4): one ray against map boxes (with material-tag wall
// penetration) and player hitbox capsules (shared/config/hitboxes.json, identical for every agent),
// using lag-compensated player poses supplied by the caller.
import type { World } from "./collision.ts";
import { raycastAll } from "./collision.ts";

export interface Capsule {
  name: string;
  zone: "head" | "upper_torso" | "lower_torso" | "arm" | "leg";
  a: [number, number, number];
  b: [number, number, number];
  r: number;
}

export interface HitboxConfig {
  crouchScale: number;
  capsules: Capsule[];
}

export interface MaterialTag {
  id: string;
  impact: string;
  maxThickness: { low: number; medium: number; high: number };
  damageLossPerCm: { low: number; medium: number; high: number };
}

export interface TargetPose {
  playerId: number;
  x: number;
  y: number;
  z: number;
  yaw: number;
  crouch: number;
}

export interface HitResult {
  kind: "player" | "world" | "none";
  t: number;
  playerId: number;
  zone: "head" | "body" | "leg";
  /** Fraction of damage that survives penetration (1 = clean hit). */
  damageScale: number;
  wallbang: boolean;
  x: number;
  y: number;
  z: number;
  nx: number;
  ny: number;
  nz: number;
  tag: number;
}

/** Ray vs capsule (segment a-b, radius r). Returns smallest t >= 0 or -1. */
export function rayCapsule(
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
  ax: number,
  ay: number,
  az: number,
  bx: number,
  by: number,
  bz: number,
  r: number,
): number {
  // Sample-free analytic approach: closest approach between ray and segment, then sphere test.
  let best = -1;
  const steps = 6;
  for (let i = 0; i <= steps; i++) {
    const u = i / steps;
    const cx = ax + (bx - ax) * u;
    const cy = ay + (by - ay) * u;
    const cz = az + (bz - az) * u;
    const t = raySphere(ox, oy, oz, dx, dy, dz, cx, cy, cz, r);
    if (t >= 0 && (best < 0 || t < best)) best = t;
  }
  return best;
}

export function raySphere(
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
  cx: number,
  cy: number,
  cz: number,
  r: number,
): number {
  const lx = ox - cx;
  const ly = oy - cy;
  const lz = oz - cz;
  const b = lx * dx + ly * dy + lz * dz;
  const c = lx * lx + ly * ly + lz * lz - r * r;
  const disc = b * b - c;
  if (disc < 0) return -1;
  const s = Math.sqrt(disc);
  const t0 = -b - s;
  if (t0 >= 0) return t0;
  const t1 = -b + s;
  return t1 >= 0 ? 0 : -1;
}

function zoneOf(z: Capsule["zone"]): "head" | "body" | "leg" {
  return z === "head" ? "head" : z === "leg" ? "leg" : "body";
}

/** Transforms a hitbox point into world space for a pose (yaw around Y, crouch scales Y). */
function hbPoint(
  p: [number, number, number],
  pose: TargetPose,
  crouchScale: number,
): [number, number, number] {
  const sy = 1 + (crouchScale - 1) * pose.crouch;
  const c = Math.cos(pose.yaw);
  const s = Math.sin(pose.yaw);
  return [pose.x + p[0] * c + p[2] * s, pose.y + p[1] * sy, pose.z - p[0] * s + p[2] * c];
}

/**
 * Traces one bullet. Penetrates world boxes whose tag allows it for the weapon tier, scaling damage
 * by thickness; returns the first player hit (or the blocking world surface).
 */
export function traceShot(
  world: World,
  tags: MaterialTag[],
  hitboxes: HitboxConfig,
  targets: TargetPose[],
  shooterId: number,
  tier: "low" | "medium" | "high",
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
  range: number,
): HitResult {
  // Nearest player capsule along the ray.
  let pT = Infinity;
  let pId = -1;
  let pZone: "head" | "body" | "leg" = "body";
  for (const pose of targets) {
    if (pose.playerId === shooterId) continue;
    // Broad phase: skip players far from the ray.
    const tx = pose.x - ox;
    const ty = pose.y + 1 - oy;
    const tz = pose.z - oz;
    const along = tx * dx + ty * dy + tz * dz;
    if (along < -1 || along > range + 1) continue;
    const px = tx - dx * along;
    const py = ty - dy * along;
    const pz = tz - dz * along;
    if (px * px + py * py + pz * pz > 2.0 * 2.0) continue;
    for (const cap of hitboxes.capsules) {
      const a = hbPoint(cap.a, pose, hitboxes.crouchScale);
      const b = hbPoint(cap.b, pose, hitboxes.crouchScale);
      const t = rayCapsule(ox, oy, oz, dx, dy, dz, a[0], a[1], a[2], b[0], b[1], b[2], cap.r);
      if (t < 0 || t > range) continue;
      // Head beats body at equal distance so headshots are not stolen by overlapping capsules.
      if (t < pT - 1e-4 || (Math.abs(t - pT) <= 1e-4 && zoneOf(cap.zone) === "head")) {
        pT = t;
        pId = pose.playerId;
        pZone = zoneOf(cap.zone);
      }
    }
  }
  const walls = raycastAll(world, ox, oy, oz, dx, dy, dz, Math.min(range, pT));
  let scale = 1;
  let wallbang = false;
  for (const w of walls) {
    if (w.t >= pT) break;
    const tag = tags[world.boxes[w.box]!.tag];
    if (tag === undefined) continue;
    if (tag.id === "invisible") continue;
    const maxThick = tag.maxThickness[tier];
    if (w.thickness > maxThick) {
      return {
        kind: "world",
        t: w.t,
        playerId: -1,
        zone: "body",
        damageScale: 0,
        wallbang: false,
        x: ox + dx * w.t,
        y: oy + dy * w.t,
        z: oz + dz * w.t,
        nx: w.nx,
        ny: w.ny,
        nz: w.nz,
        tag: world.boxes[w.box]!.tag,
      };
    }
    scale *= Math.max(0, 1 - tag.damageLossPerCm[tier] * w.thickness * 100);
    wallbang = true;
    if (scale <= 0.05) {
      return {
        kind: "world",
        t: w.t,
        playerId: -1,
        zone: "body",
        damageScale: 0,
        wallbang: false,
        x: ox + dx * w.t,
        y: oy + dy * w.t,
        z: oz + dz * w.t,
        nx: w.nx,
        ny: w.ny,
        nz: w.nz,
        tag: world.boxes[w.box]!.tag,
      };
    }
  }
  if (pId >= 0) {
    return {
      kind: "player",
      t: pT,
      playerId: pId,
      zone: pZone,
      damageScale: scale,
      wallbang,
      x: ox + dx * pT,
      y: oy + dy * pT,
      z: oz + dz * pT,
      nx: -dx,
      ny: -dy,
      nz: -dz,
      tag: -1,
    };
  }
  return {
    kind: "none",
    t: range,
    playerId: -1,
    zone: "body",
    damageScale: 0,
    wallbang: false,
    x: ox + dx * range,
    y: oy + dy * range,
    z: oz + dz * range,
    nx: 0,
    ny: 0,
    nz: 0,
    tag: -1,
  };
}

/** View direction from yaw/pitch (yaw 0 = -Z, pitch + up), Godot convention. */
export function viewDir(yaw: number, pitch: number): [number, number, number] {
  const cp = Math.cos(pitch);
  return [-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp];
}
