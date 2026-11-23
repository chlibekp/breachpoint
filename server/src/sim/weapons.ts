// Weapon state machine + shot direction (spec §10.2, §12). Deterministic and shared with
// client/scripts/sim/sim_weapons.gd: fire rate, burst/auto/semi, ammo, reload, equip, the
// data-defined spray pattern (learnable), and seeded random spread that grows with sustained fire.
import { hashSeed, mulberry32 } from "./rng.ts";

export interface WeaponDef {
  id: string;
  class: string;
  cost: number;
  runSpeed: number;
  fireRate: number;
  fireMode: "semi" | "auto" | "burst";
  magazine: number;
  reserveAmmo: number;
  reloadTime: number;
  equipTime: number;
  movementSpreadMult: number;
  damage: {
    body: number;
    headMult: number;
    legMult: number;
    pellets: number;
    falloff: { range: number; multiplier: number }[];
  };
  spread: {
    base: number;
    perShot: number;
    max: number;
    recoveryDelay: number;
    recoveryRate: number;
  };
  recoil: { pattern: [number, number][] };
  burst: { count: number; interval: number } | null;
  ads: {
    zoom: number;
    accuracyBonus: number;
    fireRateMult: number;
    scoped?: boolean;
    unscopedSpread?: number;
  } | null;
  spinUp: { startRate: number; endRate: number; time: number } | null;
  penetration: "low" | "medium" | "high";
  tagSlow: { amount: number; duration: number };
  meleeRange?: number;
}

export interface WeaponState {
  id: string;
  ammo: number;
  reserve: number;
  /** Sim time (s) when the next shot may fire. */
  nextFire: number;
  /** >0 while reloading: sim time when the reload completes. */
  reloadEnd: number;
  equipEnd: number;
  /** Recoil pattern index (fractional while recovering). */
  recoilIndex: number;
  lastShot: number;
  burstLeft: number;
  shotCounter: number;
  spinTime: number;
  triggerHeld: boolean;
}

export interface ShotContext {
  now: number;
  /** Horizontal speed fraction of run speed (0..1+). */
  speedFrac: number;
  standingThreshold: number;
  crouched: boolean;
  airborne: boolean;
  ads: boolean;
  seed: number;
  playerId: number;
}

export interface Shot {
  /** Angle offsets (radians) added to the view: + yaw = right, + pitch = up. */
  yawOffset: number;
  pitchOffset: number;
  pellets: { yaw: number; pitch: number }[];
  shotNumber: number;
}

export function newWeaponState(def: WeaponDef, now = 0): WeaponState {
  return {
    id: def.id,
    ammo: def.magazine,
    reserve: def.reserveAmmo,
    nextFire: now,
    reloadEnd: 0,
    equipEnd: now + def.equipTime,
    recoilIndex: 0,
    lastShot: -1e9,
    burstLeft: 0,
    shotCounter: 0,
    spinTime: 0,
    triggerHeld: false,
  };
}

const DEG = Math.PI / 180;

/** Current spread cone half-angle in degrees. */
export function currentSpread(def: WeaponDef, st: WeaponState, ctx: ShotContext): number {
  let s = def.spread.base + Math.min(def.spread.max, st.recoilIndex * def.spread.perShot);
  const over = Math.max(0, ctx.speedFrac - ctx.standingThreshold) / (1 - ctx.standingThreshold);
  s += over * def.movementSpreadMult;
  if (ctx.airborne) s += def.movementSpreadMult * 1.5 + 2;
  if (ctx.crouched) s *= 0.85;
  if (def.ads) {
    if (ctx.ads) s *= 1 - def.ads.accuracyBonus;
    else if (def.ads.scoped && def.ads.unscopedSpread !== undefined) s += def.ads.unscopedSpread;
  }
  return s;
}

function fireInterval(def: WeaponDef, st: WeaponState, ads: boolean): number {
  let rate = def.fireRate;
  if (def.spinUp)
    rate =
      def.spinUp.startRate +
      (def.spinUp.endRate - def.spinUp.startRate) * Math.min(1, st.spinTime / def.spinUp.time);
  if (ads && def.ads) rate *= def.ads.fireRateMult;
  return 1 / rate;
}

/** Advances timers (reload completion, recoil recovery, spin). Call every tick before tryFire. */
export function updateWeapon(
  def: WeaponDef,
  st: WeaponState,
  now: number,
  dt: number,
  triggerHeld: boolean,
): void {
  if (st.reloadEnd > 0 && now >= st.reloadEnd) {
    const need = def.magazine - st.ammo;
    const take = Math.min(need, st.reserve);
    st.ammo += take;
    st.reserve -= take;
    st.reloadEnd = 0;
  }
  if (now - st.lastShot > def.spread.recoveryDelay) {
    st.recoilIndex = Math.max(0, st.recoilIndex - def.spread.recoveryRate * dt);
  }
  if (def.spinUp) st.spinTime = triggerHeld ? st.spinTime + dt : Math.max(0, st.spinTime - dt * 2);
  if (!triggerHeld) st.burstLeft = 0;
}

export function startReload(def: WeaponDef, st: WeaponState, now: number): boolean {
  if (st.reloadEnd > 0 || st.ammo >= def.magazine || st.reserve <= 0 || def.magazine === 0)
    return false;
  st.reloadEnd = now + def.reloadTime;
  st.burstLeft = 0;
  return true;
}

/**
 * Tries to fire. `pressed` = trigger went down this tick, `held` = trigger is down.
 * Returns a Shot (direction offsets relative to the view) or null.
 */
export function tryFire(
  def: WeaponDef,
  st: WeaponState,
  ctx: ShotContext,
  pressed: boolean,
  held: boolean,
): Shot | null {
  const now = ctx.now;
  if (now < st.equipEnd || st.reloadEnd > 0 || now < st.nextFire) {
    st.triggerHeld = held;
    return null;
  }
  if (def.magazine > 0 && st.ammo <= 0) {
    st.triggerHeld = held;
    return null;
  }
  const mode = def.ads && ctx.ads && def.id === "lancer" ? "semi" : def.fireMode;
  let fire = false;
  if (st.burstLeft > 0) fire = true;
  else if (mode === "auto") fire = held;
  else fire = pressed;
  st.triggerHeld = held;
  if (!fire) return null;

  const spreadDeg = currentSpread(def, st, ctx);
  const idx = Math.min(Math.floor(st.recoilIndex), def.recoil.pattern.length - 1);
  const pat = def.recoil.pattern[idx] ?? [0, 0];
  // Pattern: [x, y] degrees; recovery blends between pattern steps.
  const frac = st.recoilIndex - Math.floor(st.recoilIndex);
  const next = def.recoil.pattern[Math.min(idx + 1, def.recoil.pattern.length - 1)] ?? pat;
  const px = pat[0] + (next[0] - pat[0]) * frac;
  const py = pat[1] + (next[1] - pat[1]) * frac;
  const rng = mulberry32(hashSeed(ctx.seed, ctx.playerId * 65536 + st.shotCounter));
  const pellets: { yaw: number; pitch: number }[] = [];
  for (let i = 0; i < def.damage.pellets; i++) {
    const a = rng() * Math.PI * 2;
    // sqrt for uniform disc distribution; first standing rifle/sidearm shot has base 0 -> pinpoint.
    const r = Math.sqrt(rng()) * spreadDeg;
    pellets.push({ yaw: (px + Math.cos(a) * r) * DEG, pitch: (py + Math.sin(a) * r) * DEG });
  }
  const shot: Shot = {
    yawOffset: px * DEG,
    pitchOffset: py * DEG,
    pellets,
    shotNumber: st.shotCounter,
  };
  st.shotCounter++;
  if (def.magazine > 0) st.ammo--;
  st.recoilIndex = Math.min(st.recoilIndex + 1, def.recoil.pattern.length - 1 + 0.999);
  st.lastShot = now;
  if (mode === "burst" && def.burst) {
    if (st.burstLeft === 0) st.burstLeft = def.burst.count - 1;
    else st.burstLeft--;
    st.nextFire = now + (st.burstLeft > 0 ? def.burst.interval : fireInterval(def, st, ctx.ads));
  } else {
    st.nextFire = now + fireInterval(def, st, ctx.ads);
  }
  return shot;
}

/** Damage for a hit at `distance` metres in `zone`, before shields/penetration. */
export function damageAt(def: WeaponDef, distance: number, zone: "head" | "body" | "leg"): number {
  let mult = 1;
  for (const step of def.damage.falloff) if (distance >= step.range) mult = step.multiplier;
  const zoneMult = zone === "head" ? def.damage.headMult : zone === "leg" ? def.damage.legMult : 1;
  return def.damage.body * mult * zoneMult;
}
