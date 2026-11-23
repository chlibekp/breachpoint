// Authoritative player movement (spec §10.1, §13.3). Pure and deterministic: the GDScript port in
// client/scripts/sim/sim_movement.gd must produce the same positions to within 1 mm for the
// golden vectors in shared/tests/movement/*.json. Keep the operation order identical in both.
//
// Player = vertical cylinder (radius r, height h) standing on yaw-only boxes. Units: m, s, rad.
import type { World } from "./collision.ts";
import { toLocal, toWorldDir } from "./collision.ts";

export const Buttons = {
  FORWARD: 1,
  BACK: 2,
  LEFT: 4,
  RIGHT: 8,
  JUMP: 16,
  CROUCH: 32,
  WALK: 64,
  FIRE: 128,
  ALT_FIRE: 256,
  RELOAD: 512,
  USE: 1024,
  ABILITY_C: 2048,
  ABILITY_Q: 4096,
  ABILITY_E: 8192,
  ABILITY_X: 16384,
} as const;

export interface MovementConfig {
  tickRate: number;
  walkSpeed: number;
  crouchSpeed: number;
  crouchTransitionTime: number;
  accelerationTime: number;
  decelerationTime: number;
  airAcceleration: number;
  jumpHeight: number;
  gravity: number;
  landingSlow: { multiplier: number; duration: number };
  stepHeight: number;
  capsule: { radius: number; height: number; crouchHeight: number };
}

export interface MoveState {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  grounded: boolean;
  crouch: number;
  landingTimer: number;
  tagTimer: number;
  tagAmount: number;
  prevButtons: number;
}

export interface MoveInput {
  buttons: number;
  yaw: number;
  /** Max run speed for the equipped weapon (weapons.json runSpeed) times ability modifiers. */
  runSpeed: number;
}

export function newMoveState(x: number, y: number, z: number): MoveState {
  return {
    x,
    y,
    z,
    vx: 0,
    vy: 0,
    vz: 0,
    grounded: true,
    crouch: 0,
    landingTimer: 0,
    tagTimer: 0,
    tagAmount: 0,
    prevButtons: 0,
  };
}

export function playerHeight(cfg: MovementConfig, s: MoveState): number {
  return cfg.capsule.height + (cfg.capsule.crouchHeight - cfg.capsule.height) * s.crouch;
}

const SKIN = 0.001;

/** One fixed tick. Mutates and returns `s`. */
export function stepMovement(
  cfg: MovementConfig,
  w: World,
  s: MoveState,
  inp: MoveInput,
): MoveState {
  const dt = 1 / cfg.tickRate;
  const b = inp.buttons;
  // --- crouch (blocked from standing up under a ceiling)
  const wantCrouch = (b & Buttons.CROUCH) !== 0;
  const crouchRate = dt / cfg.crouchTransitionTime;
  if (wantCrouch) s.crouch = Math.min(1, s.crouch + crouchRate);
  else {
    const next = Math.max(0, s.crouch - crouchRate);
    const h = cfg.capsule.height + (cfg.capsule.crouchHeight - cfg.capsule.height) * next;
    if (!ceilingBlocked(w, s.x, s.y, s.z, cfg.capsule.radius, h)) s.crouch = next;
  }
  // --- wish direction (yaw 0 faces -Z, Godot convention)
  let fx = 0;
  let fz = 0;
  if (b & Buttons.FORWARD) fz -= 1;
  if (b & Buttons.BACK) fz += 1;
  if (b & Buttons.LEFT) fx -= 1;
  if (b & Buttons.RIGHT) fx += 1;
  const c = Math.cos(inp.yaw);
  const sn = Math.sin(inp.yaw);
  let wx = fx * c + fz * sn;
  let wz = -fx * sn + fz * c;
  const wl = Math.sqrt(wx * wx + wz * wz);
  if (wl > 0) {
    wx /= wl;
    wz /= wl;
  }
  // --- target speed
  let maxSpeed = inp.runSpeed;
  if (b & Buttons.WALK) maxSpeed = Math.min(maxSpeed, cfg.walkSpeed);
  if (s.crouch > 0.5) maxSpeed = Math.min(maxSpeed, cfg.crouchSpeed);
  if (s.landingTimer > 0) maxSpeed *= cfg.landingSlow.multiplier;
  if (s.tagTimer > 0) maxSpeed *= 1 - s.tagAmount;
  const tx = wx * maxSpeed;
  const tz = wz * maxSpeed;
  // --- horizontal acceleration
  let dvx = tx - s.vx;
  let dvz = tz - s.vz;
  const dl = Math.sqrt(dvx * dvx + dvz * dvz);
  let rate: number;
  if (s.grounded) {
    const opposing = tx * s.vx + tz * s.vz < 0;
    rate =
      wl === 0 || opposing
        ? inp.runSpeed / cfg.decelerationTime
        : inp.runSpeed / cfg.accelerationTime;
  } else {
    rate = cfg.airAcceleration;
  }
  const maxDv = rate * dt;
  if (dl > maxDv) {
    dvx = (dvx / dl) * maxDv;
    dvz = (dvz / dl) * maxDv;
  }
  if (s.grounded || wl > 0) {
    s.vx += dvx;
    s.vz += dvz;
  }
  // --- jump (edge-triggered; no bunny-hop gain because air accel never exceeds target speed)
  const jumpPressed = (b & Buttons.JUMP) !== 0 && (s.prevButtons & Buttons.JUMP) === 0;
  if (s.grounded && jumpPressed && s.crouch < 0.5) {
    s.vy = Math.sqrt(2 * cfg.gravity * cfg.jumpHeight);
    s.grounded = false;
  }
  if (!s.grounded) s.vy -= cfg.gravity * dt;
  // --- horizontal move + collision (push-out in XZ against boxes spanning the body)
  const h = playerHeight(cfg, s);
  const r = cfg.capsule.radius;
  s.x += s.vx * dt;
  s.z += s.vz * dt;
  for (let pass = 0; pass < 3; pass++) {
    let moved = false;
    for (let i = 0; i < w.boxes.length; i++) {
      const bx = w.boxes[i]!;
      const top = bx.cy + bx.hy;
      const bottom = bx.cy - bx.hy;
      if (top <= s.y + cfg.stepHeight || bottom >= s.y + h) continue;
      const ddx = s.x - bx.cx;
      const ddz = s.z - bx.cz;
      const reach = bx.rxz + r;
      if (ddx * ddx + ddz * ddz > reach * reach) continue;
      const [lx, lz] = toLocal(bx, s.x, s.z);
      const cx = Math.max(-bx.hx, Math.min(bx.hx, lx));
      const cz = Math.max(-bx.hz, Math.min(bx.hz, lz));
      let nx = lx - cx;
      let nz = lz - cz;
      let d2 = nx * nx + nz * nz;
      if (d2 >= r * r) continue;
      let push: number;
      if (d2 < 1e-12) {
        // Centre inside the box: push out along the shallowest local axis.
        const px = bx.hx - Math.abs(lx);
        const pz = bx.hz - Math.abs(lz);
        if (px < pz) {
          nx = lx >= 0 ? 1 : -1;
          nz = 0;
          push = px + r;
        } else {
          nx = 0;
          nz = lz >= 0 ? 1 : -1;
          push = pz + r;
        }
        d2 = 1;
      } else {
        const d = Math.sqrt(d2);
        nx /= d;
        nz /= d;
        push = r - d;
      }
      const [wnx, wnz] = toWorldDir(bx, nx, nz);
      s.x += wnx * (push + SKIN);
      s.z += wnz * (push + SKIN);
      const vn = s.vx * wnx + s.vz * wnz;
      if (vn < 0) {
        s.vx -= wnx * vn;
        s.vz -= wnz * vn;
      }
      moved = true;
    }
    if (!moved) break;
  }
  // --- vertical move: ground snap / step up / landing / ceiling
  const wasGrounded = s.grounded;
  const fallSpeed = -s.vy;
  s.y += s.vy * dt;
  const ground = groundHeight(w, s.x, s.y + cfg.stepHeight, s.z, r);
  if (s.vy <= 0 && ground > -1e8 && s.y <= ground + (wasGrounded ? cfg.stepHeight : 0) + SKIN) {
    s.y = ground;
    s.vy = 0;
    s.grounded = true;
    if (!wasGrounded && fallSpeed > 2) s.landingTimer = cfg.landingSlow.duration;
  } else {
    s.grounded = false;
    if (s.vy > 0 && ceilingBlocked(w, s.x, s.y, s.z, r, h)) s.vy = 0;
  }
  // --- timers
  if (s.landingTimer > 0) s.landingTimer = Math.max(0, s.landingTimer - dt);
  if (s.tagTimer > 0) s.tagTimer = Math.max(0, s.tagTimer - dt);
  s.prevButtons = b;
  return s;
}

/** Highest box top at or below `maxY` under the cylinder footprint, or -1e9. */
export function groundHeight(w: World, x: number, maxY: number, z: number, r: number): number {
  let best = -1e9;
  for (let i = 0; i < w.boxes.length; i++) {
    const bx = w.boxes[i]!;
    const top = bx.cy + bx.hy;
    if (top > maxY || top <= best) continue;
    if (!circleOverlapsBox(bx, x, z, r * 0.7)) continue;
    best = top;
  }
  return best;
}

function circleOverlapsBox(bx: World["boxes"][number], x: number, z: number, r: number): boolean {
  const ddx = x - bx.cx;
  const ddz = z - bx.cz;
  const reach = bx.rxz + r;
  if (ddx * ddx + ddz * ddz > reach * reach) return false;
  const [lx, lz] = toLocal(bx, x, z);
  const cx = Math.max(-bx.hx, Math.min(bx.hx, lx));
  const cz = Math.max(-bx.hz, Math.min(bx.hz, lz));
  const nx = lx - cx;
  const nz = lz - cz;
  return nx * nx + nz * nz < r * r;
}

export function ceilingBlocked(
  w: World,
  x: number,
  y: number,
  z: number,
  r: number,
  h: number,
): boolean {
  for (let i = 0; i < w.boxes.length; i++) {
    const bx = w.boxes[i]!;
    const bottom = bx.cy - bx.hy;
    const top = bx.cy + bx.hy;
    if (bottom < y + 0.5 || bottom >= y + h || top <= y) continue;
    if (circleOverlapsBox(bx, x, z, r * 0.9)) return true;
  }
  return false;
}

/** Horizontal speed as a fraction of the weapon's run speed (drives movement inaccuracy). */
export function speedFraction(s: MoveState, runSpeed: number): number {
  return Math.sqrt(s.vx * s.vx + s.vz * s.vz) / runSpeed;
}
