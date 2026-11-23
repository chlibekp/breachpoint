// Map collision for the authoritative sim (spec §13.2): yaw-only oriented boxes exported by the
// Godot MapBuilder (shared/maps/<map>.collision.bin). Pure data + queries, no I/O here.

export interface Box {
  cx: number;
  cy: number;
  cz: number;
  hx: number;
  hy: number;
  hz: number;
  yaw: number;
  cos: number;
  sin: number;
  tag: number;
  /** Conservative XZ bounding radius for broad-phase rejection. */
  rxz: number;
}

export interface World {
  boxes: Box[];
}

export function makeBox(
  cx: number,
  cy: number,
  cz: number,
  hx: number,
  hy: number,
  hz: number,
  yaw: number,
  tag: number,
): Box {
  return {
    cx,
    cy,
    cz,
    hx,
    hy,
    hz,
    yaw,
    cos: Math.cos(yaw),
    sin: Math.sin(yaw),
    tag,
    rxz: Math.sqrt(hx * hx + hz * hz),
  };
}

/** Parses "BPCOL1" binary: u32 count, then per box 7×f32 (center, half extents, yaw) + u8 tag. */
export function parseCollision(bytes: Uint8Array): World {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = String.fromCharCode(...bytes.subarray(0, 6));
  if (magic !== "BPCOL1") throw new Error("bad collision magic");
  const count = view.getUint32(6, true);
  const boxes: Box[] = [];
  let off = 10;
  for (let i = 0; i < count; i++) {
    const f = (k: number): number => view.getFloat32(off + k * 4, true);
    boxes.push(makeBox(f(0), f(1), f(2), f(3), f(4), f(5), f(6), view.getUint8(off + 28)));
    off += 29;
  }
  return { boxes };
}

/** Box-local XZ coordinates of a world point (rotation by -yaw around Y). */
export function toLocal(b: Box, x: number, z: number): [number, number] {
  const dx = x - b.cx;
  const dz = z - b.cz;
  // Godot's Basis(UP, yaw) maps local (lx, lz) -> world (lx*cos + lz*sin, -lx*sin + lz*cos).
  return [dx * b.cos - dz * b.sin, dx * b.sin + dz * b.cos];
}

export function toWorldDir(b: Box, lx: number, lz: number): [number, number] {
  return [lx * b.cos + lz * b.sin, -lx * b.sin + lz * b.cos];
}

export interface RayHit {
  t: number;
  /** Distance travelled inside the box (for wall penetration). */
  thickness: number;
  box: number;
  nx: number;
  ny: number;
  nz: number;
}

/** Ray vs one box (slab test in box space). Returns entry t/exit t or null. */
export function rayBox(
  b: Box,
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
): [number, number, number] | null {
  const [lox, loz] = toLocal(b, ox, oz);
  const loy = oy - b.cy;
  const ldx = dx * b.cos - dz * b.sin;
  const ldz = dx * b.sin + dz * b.cos;
  let tmin = -Infinity;
  let tmax = Infinity;
  let axis = -1;
  const o = [lox, loy, loz];
  const d = [ldx, dy, ldz];
  const h = [b.hx, b.hy, b.hz];
  for (let i = 0; i < 3; i++) {
    const oi = o[i]!;
    const di = d[i]!;
    const hi = h[i]!;
    if (Math.abs(di) < 1e-12) {
      if (oi < -hi || oi > hi) return null;
      continue;
    }
    let t1 = (-hi - oi) / di;
    let t2 = (hi - oi) / di;
    if (t1 > t2) [t1, t2] = [t2, t1];
    if (t1 > tmin) {
      tmin = t1;
      axis = i;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  return [tmin, tmax, axis];
}

/** All box intersections along a ray up to maxT, sorted by entry distance. */
export function raycastAll(
  w: World,
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
  maxT: number,
): RayHit[] {
  const hits: RayHit[] = [];
  for (let i = 0; i < w.boxes.length; i++) {
    const b = w.boxes[i]!;
    const r = rayBox(b, ox, oy, oz, dx, dy, dz);
    if (r === null) continue;
    const [t0, t1, axis] = r;
    if (t1 < 0 || t0 > maxT) continue;
    const entry = Math.max(t0, 0);
    let lnx = 0;
    let lny = 0;
    let lnz = 0;
    const ld = [dx * b.cos - dz * b.sin, dy, dx * b.sin + dz * b.cos];
    if (axis === 0) lnx = -Math.sign(ld[0]!);
    else if (axis === 1) lny = -Math.sign(ld[1]!);
    else if (axis === 2) lnz = -Math.sign(ld[2]!);
    const [wx, wz] = toWorldDir(b, lnx, lnz);
    hits.push({ t: entry, thickness: Math.min(t1, maxT) - entry, box: i, nx: wx, ny: lny, nz: wz });
  }
  hits.sort((a, b) => a.t - b.t || a.box - b.box);
  return hits;
}
