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
  /** Lazily built uniform grid over box XZ bounds (broad phase). */
  grid?: Grid;
}

export interface Grid {
  cell: number;
  minX: number;
  minZ: number;
  nx: number;
  nz: number;
  cells: number[][];
  stamp: Uint32Array;
  stampId: number;
}

const GRID_CELL = 4;

export function grid(w: World): Grid {
  if (w.grid) return w.grid;
  let minX = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxZ = -Infinity;
  for (const b of w.boxes) {
    minX = Math.min(minX, b.cx - b.rxz);
    minZ = Math.min(minZ, b.cz - b.rxz);
    maxX = Math.max(maxX, b.cx + b.rxz);
    maxZ = Math.max(maxZ, b.cz + b.rxz);
  }
  if (!Number.isFinite(minX)) {
    minX = minZ = 0;
    maxX = maxZ = 1;
  }
  const nx = Math.max(1, Math.ceil((maxX - minX) / GRID_CELL));
  const nz = Math.max(1, Math.ceil((maxZ - minZ) / GRID_CELL));
  const cells: number[][] = Array.from({ length: nx * nz }, () => []);
  w.boxes.forEach((b, i) => {
    const x0 = Math.max(0, Math.floor((b.cx - b.rxz - minX) / GRID_CELL));
    const x1 = Math.min(nx - 1, Math.floor((b.cx + b.rxz - minX) / GRID_CELL));
    const z0 = Math.max(0, Math.floor((b.cz - b.rxz - minZ) / GRID_CELL));
    const z1 = Math.min(nz - 1, Math.floor((b.cz + b.rxz - minZ) / GRID_CELL));
    for (let z = z0; z <= z1; z++) for (let x = x0; x <= x1; x++) cells[z * nx + x]!.push(i);
  });
  w.grid = {
    cell: GRID_CELL,
    minX,
    minZ,
    nx,
    nz,
    cells,
    stamp: new Uint32Array(w.boxes.length),
    stampId: 0,
  };
  return w.grid;
}

/**
 * Box indices whose XZ bounds may touch the rectangle, in ascending index order — iterating these
 * gives exactly the same results as a full scan for any query confined to the rectangle.
 */
export function candidates(
  w: World,
  x0: number,
  z0: number,
  x1: number,
  z1: number,
  out: number[] = [],
): number[] {
  const g = grid(w);
  out.length = 0;
  g.stampId = (g.stampId + 1) >>> 0;
  if (g.stampId === 0) {
    g.stamp.fill(0);
    g.stampId = 1;
  }
  const cx0 = Math.max(0, Math.floor((x0 - g.minX) / g.cell));
  const cx1 = Math.min(g.nx - 1, Math.floor((x1 - g.minX) / g.cell));
  const cz0 = Math.max(0, Math.floor((z0 - g.minZ) / g.cell));
  const cz1 = Math.min(g.nz - 1, Math.floor((z1 - g.minZ) / g.cell));
  for (let z = cz0; z <= cz1; z++) {
    for (let x = cx0; x <= cx1; x++) {
      for (const i of g.cells[z * g.nx + x]!) {
        if (g.stamp[i] !== g.stampId) {
          g.stamp[i] = g.stampId;
          out.push(i);
        }
      }
    }
  }
  out.sort((a, b) => a - b);
  return out;
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

const _rayScratch: number[] = [];

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

/**
 * True if the segment (o + d*t, 0 < t < dist) hits any box for which `blocks(tag)` is true.
 * Walks the broad-phase grid cells along the ray (2D DDA in XZ) and exits on the first hit —
 * the fast path for line-of-sight checks (fog of war, bots).
 */
export function segmentBlocked(
  w: World,
  ox: number,
  oy: number,
  oz: number,
  dx: number,
  dy: number,
  dz: number,
  dist: number,
  blocks: (tag: number) => boolean,
): boolean {
  const g = grid(w);
  g.stampId = (g.stampId + 1) >>> 0;
  if (g.stampId === 0) {
    g.stamp.fill(0);
    g.stampId = 1;
  }
  let cx = Math.floor((ox - g.minX) / g.cell);
  let cz = Math.floor((oz - g.minZ) / g.cell);
  const stepX = dx > 0 ? 1 : -1;
  const stepZ = dz > 0 ? 1 : -1;
  const tDeltaX = Math.abs(dx) > 1e-12 ? g.cell / Math.abs(dx) : Infinity;
  const tDeltaZ = Math.abs(dz) > 1e-12 ? g.cell / Math.abs(dz) : Infinity;
  const nextX = g.minX + (cx + (stepX > 0 ? 1 : 0)) * g.cell;
  const nextZ = g.minZ + (cz + (stepZ > 0 ? 1 : 0)) * g.cell;
  let tMaxX = Math.abs(dx) > 1e-12 ? (nextX - ox) / dx : Infinity;
  let tMaxZ = Math.abs(dz) > 1e-12 ? (nextZ - oz) / dz : Infinity;
  let t = 0;
  while (t <= dist) {
    if (cx >= 0 && cz >= 0 && cx < g.nx && cz < g.nz) {
      for (const i of g.cells[cz * g.nx + cx]!) {
        if (g.stamp[i] === g.stampId) continue;
        g.stamp[i] = g.stampId;
        const b = w.boxes[i]!;
        if (!blocks(b.tag)) continue;
        const r = rayBox(b, ox, oy, oz, dx, dy, dz);
        if (r !== null && r[1] > 0 && r[0] < dist) return true;
      }
    } else if (
      (cx < 0 && stepX < 0) ||
      (cz < 0 && stepZ < 0) ||
      (cx >= g.nx && stepX > 0) ||
      (cz >= g.nz && stepZ > 0)
    ) {
      return false;
    }
    if (tMaxX < tMaxZ) {
      t = tMaxX;
      tMaxX += tDeltaX;
      cx += stepX;
    } else {
      t = tMaxZ;
      tMaxZ += tDeltaZ;
      cz += stepZ;
    }
  }
  return false;
}
