#!/usr/bin/env python3
"""BREACHPOINT procedural texture generator (spec §5.3/§5.4).

Every tileable material is generated from code — no photo sources, so nothing to license — and
painted in the art-bible style: low-frequency albedo variation, lighter worn edges, broad roughness
variation, detail carried by the height/normal map rather than albedo noise.

Outputs per material into client/assets/<dir>/textures/:
  T_<Name>_A.png   albedo (sRGB)
  T_<Name>_N.png   normal (OpenGL +Y)
  T_<Name>_ORM.png R=AO, G=roughness, B=metallic (linear)

Usage: python3 tools/texgen/texgen.py [material ...]   (default: all)
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024
RNG_SEED = 1337


# ---------------------------------------------------------------- noise helpers (all tileable)

def value_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Tileable smooth value noise in [0,1] with `cells` lattice cells across."""
    lattice = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = lattice[np.ix_(i0, i0)]
    b = lattice[np.ix_(i0, i1)]
    c = lattice[np.ix_(i1, i0)]
    d = lattice[np.ix_(i1, i1)]
    fy = f[:, None]
    fx = f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size: int, base_cells: int, octaves: int, rng: np.random.Generator, gain: float = 0.5) -> np.ndarray:
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    cells = base_cells
    for _ in range(octaves):
        out += value_noise(size, cells, rng) * amp
        total += amp
        amp *= gain
        cells *= 2
    return out / total


def voronoi(size: int, count: int, rng: np.random.Generator, jitter: float = 1.0):
    """Tileable Voronoi: returns (F1 distance, F2-F1 edge distance, cell id) in pixel units."""
    grid = int(np.ceil(np.sqrt(count)))
    pts = []
    for gy in range(grid):
        for gx in range(grid):
            jx, jy = rng.random(2) * jitter + (1 - jitter) * 0.5
            pts.append(((gx + jx) / grid, (gy + jy) / grid))
    pts = np.array(pts) * size
    offs = np.array([(dx, dy) for dx in (-size, 0, size) for dy in (-size, 0, size)])
    allpts = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2)
    ids = np.tile(np.arange(len(pts)), len(offs))
    ys, xs = np.mgrid[0:size, 0:size]
    f1 = np.full((size, size), 1e9)
    f2 = np.full((size, size), 1e9)
    cid = np.zeros((size, size), dtype=int)
    for (px, py), i in zip(allpts, ids):
        d = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cid = np.where(closer, i, cid)
        f1 = np.where(closer, d, f1)
    return f1, f2 - f1, cid


def blur(img: np.ndarray, radius: int) -> np.ndarray:
    """Cheap tileable box blur (repeated) via cumulative sums with wraparound."""
    out = img.astype(np.float64)
    for _ in range(2):
        for axis in (0, 1):
            pad = np.concatenate([out.take(range(-radius, 0), axis=axis), out, out.take(range(0, radius + 1), axis=axis)], axis=axis)
            cs = np.cumsum(pad, axis=axis)
            n = out.shape[axis]
            hi = cs.take(range(2 * radius + 1, 2 * radius + 1 + n), axis=axis)
            lo = cs.take(range(0, n), axis=axis)
            out = (hi - lo) / (2 * radius + 1)
    return out


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # OpenGL convention (+Y up in tangent space)
    nz = np.ones_like(h)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return (n * 0.5 + 0.5)


def curvature(h: np.ndarray, radius: int = 3) -> np.ndarray:
    """Positive on convex edges, negative in cavities."""
    return h - blur(h, radius)


def ao_from_height(h: np.ndarray, radius: int = 12, strength: float = 2.0) -> np.ndarray:
    occ = np.clip((blur(h, radius) - h) * strength, 0, 1)
    return 1 - occ


def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0


def tint(base: str, variation: np.ndarray, amount: float, hue_shift: str | None = None, hue_mask: np.ndarray | None = None) -> np.ndarray:
    col = np.ones(variation.shape + (3,)) * hex_rgb(base)
    col *= (1 + (variation[..., None] - 0.5) * amount)
    if hue_shift is not None and hue_mask is not None:
        col = col * (1 - hue_mask[..., None]) + hex_rgb(hue_shift) * hue_mask[..., None]
    return col


def save(name: str, out_dir: Path, albedo: np.ndarray, normal: np.ndarray, ao: np.ndarray, rough: np.ndarray, metal: np.ndarray) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    # Art bible §4.2: albedo stays within sRGB 40–220.
    a = np.clip(albedo, 40 / 255, 220 / 255)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGB").save(out_dir / f"T_{name}_A.png", optimize=True)
    Image.fromarray((np.clip(normal, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(out_dir / f"T_{name}_N.png", optimize=True)
    orm = np.stack([ao, rough, metal], axis=-1)
    Image.fromarray((np.clip(orm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(out_dir / f"T_{name}_ORM.png", optimize=True)
    print(f"  T_{name}_[A|N|ORM] -> {out_dir.relative_to(ROOT)}")


# ---------------------------------------------------------------- materials

def mat_plaster(rng, base="#E9DCC0", name="Plaster_Cream", out="maps/solstice"):
    """Lime-wash plaster: big soft patches, faint trowel strokes, chipped spots showing stone."""
    s = SIZE
    big = fbm(s, 3, 3, rng)
    mid = fbm(s, 12, 3, rng)
    trowel = blur(value_noise(s, 48, rng), 6)
    chips = (fbm(s, 5, 4, rng) > 0.76).astype(float)
    chips = blur(chips, 3)
    height = big * 0.3 + mid * 0.25 + trowel * 0.15 - chips * 0.25
    albedo = tint(base, big * 0.7 + mid * 0.3, 0.12)
    stone = tint("#B9A88C", mid, 0.2)
    albedo = albedo * (1 - chips[..., None] * 0.45) + stone * chips[..., None] * 0.45
    cur = curvature(height, 4)
    albedo *= (1 + np.clip(cur, -0.05, 0.05)[..., None] * 2.0)
    rough = np.clip(0.88 - mid * 0.08 + chips * 0.05, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 3.0), ao_from_height(height, 10, 2.5), rough, np.zeros_like(rough))


def mat_flagstone(rng, name="Flagstone", out="maps/solstice"):
    """Irregular flagstones with mortar, painted moss in the joints (R4)."""
    s = SIZE
    f1, edge, cid = voronoi(s, 36, rng, jitter=0.8)
    joint = np.clip(1 - edge / 7.0, 0, 1)
    cell_val = rng.random(cid.max() + 1)[cid]
    dome = np.clip(edge / 30.0, 0, 1) ** 0.5
    detail = fbm(s, 16, 4, rng)
    height = dome * 0.6 + detail * 0.15 - joint * 0.6
    albedo = tint("#BDB29E", cell_val * 0.6 + detail * 0.4, 0.22)
    albedo *= (0.92 + 0.08 * hex_rgb("#E8D9C0") / hex_rgb("#E8D9C0").max())
    moss_mask = np.clip(joint * 1.4 * (fbm(s, 6, 3, rng) > 0.45), 0, 1)
    albedo = albedo * (1 - moss_mask[..., None]) + tint("#6E7F45", detail, 0.25) * moss_mask[..., None]
    grout = np.clip(joint - moss_mask, 0, 1)
    albedo = albedo * (1 - grout[..., None] * 0.5) + hex_rgb("#8E8676") * grout[..., None] * 0.5
    edge_hi = np.clip(curvature(height, 3) * 6, 0, 0.12)
    albedo += edge_hi[..., None]
    rough = np.clip(0.78 - dome * 0.12 + joint * 0.15 + (cell_val - 0.5) * 0.1, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 5.0), ao_from_height(height, 8, 3.0), rough, np.zeros_like(rough))


def mat_cobble(rng, name="Cobble", out="maps/solstice"):
    s = SIZE
    f1, edge, cid = voronoi(s, 144, rng, jitter=0.6)
    joint = np.clip(1 - edge / 5.0, 0, 1)
    dome = np.clip(edge / 18.0, 0, 1) ** 0.6
    cell_val = rng.random(cid.max() + 1)[cid]
    detail = fbm(s, 24, 3, rng)
    height = dome * 0.7 + detail * 0.1 - joint * 0.4
    albedo = tint("#A79C8A", cell_val * 0.7 + detail * 0.3, 0.3)
    moss = np.clip(joint * (fbm(s, 5, 3, rng) > 0.5) * 1.3, 0, 1)
    albedo = albedo * (1 - moss[..., None]) + tint("#66763F", detail, 0.3) * moss[..., None]
    albedo += np.clip(curvature(height, 3) * 6, 0, 0.1)[..., None]
    rough = np.clip(0.7 - dome * 0.15 + joint * 0.2, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 5.0), ao_from_height(height, 6, 3.0), rough, np.zeros_like(rough))


def mat_brick(rng, name="Brick_Warm", out="maps/solstice"):
    """Warm brick (R1): chunky rounded bricks, soft colour variation per brick, recessed mortar."""
    s = SIZE
    rows, cols = 16, 8  # 4 m tile -> 25 cm x 50 cm courses (stylised, chunky)
    ys, xs = np.mgrid[0:s, 0:s] / s
    r = np.floor(ys * rows).astype(int)
    xo = xs * cols + (r % 2) * 0.5
    c = np.floor(xo).astype(int) % cols
    fx = xo - np.floor(xo)
    fy = ys * rows - r
    ex = np.minimum(fx, 1 - fx) * (s / cols)
    ey = np.minimum(fy, 1 - fy) * (s / rows)
    e = np.minimum(ex, ey)
    mortar = np.clip(1 - e / 4.0, 0, 1)
    bevel = np.clip(e / 10.0, 0, 1) ** 0.5
    brick_id = r * cols + c
    bv = rng.random(rows * cols + cols)[brick_id]
    detail = fbm(s, 20, 3, rng)
    height = bevel * 0.6 + detail * 0.12 - mortar * 0.5
    albedo = tint("#B8744E", bv * 0.7 + detail * 0.3, 0.28)
    albedo = albedo * (1 - mortar[..., None]) + tint("#CDBFA6", detail, 0.1) * mortar[..., None]
    # plaster remnants over some bricks (lime-wash town)
    wash = blur((fbm(s, 4, 4, rng) > 0.6).astype(float), 3)
    albedo = albedo * (1 - wash[..., None] * 0.8) + tint("#E6D7BA", detail, 0.1) * wash[..., None] * 0.8
    albedo += np.clip(curvature(height, 3) * 5, 0, 0.1)[..., None]
    rough = np.clip(0.85 - bevel * 0.05 + mortar * 0.08, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 4.0), ao_from_height(height, 6, 3.0), rough, np.zeros_like(rough))


def mat_roof(rng, name="RoofTile", out="maps/solstice"):
    """Terracotta barrel roof tiles in rows."""
    s = SIZE
    rows, cols = 8, 10
    ys, xs = np.mgrid[0:s, 0:s] / s
    r = np.floor(ys * rows).astype(int)
    fx = (xs * cols + (r % 2) * 0.5) % 1.0
    fy = ys * rows - r
    barrel = np.sin(fx * np.pi) ** 0.7
    overlap = np.clip((fy - 0.82) / 0.18, 0, 1)
    tile_id = r * cols + np.floor(xs * cols + (r % 2) * 0.5).astype(int) % cols
    tv = rng.random(rows * cols + cols)[tile_id]
    detail = fbm(s, 16, 3, rng)
    height = barrel * 0.6 * (1 - overlap * 0.6) + fy * 0.15 + detail * 0.08
    albedo = tint("#C0623A", tv * 0.6 + detail * 0.4, 0.3)
    albedo *= (0.85 + 0.15 * (1 - overlap))[..., None]
    lichen = np.clip((fbm(s, 8, 4, rng) > 0.66) * 1.0, 0, 1) * 0.6
    albedo = albedo * (1 - lichen[..., None]) + tint("#C9BC8C", detail, 0.2) * lichen[..., None]
    rough = np.clip(0.8 - barrel * 0.08, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 4.0), ao_from_height(height, 8, 3.0), rough, np.zeros_like(rough))


def mat_wood(rng, base="#8A5A3A", name="WoodPlank", out="maps/solstice", planks=6, painted: str | None = None):
    """Weathered planks; optional painted finish with worn edges (shutters/doors)."""
    s = SIZE
    ys, xs = np.mgrid[0:s, 0:s] / s
    p = np.floor(xs * planks).astype(int)
    fx = xs * planks - p
    seam = np.clip(1 - np.minimum(fx, 1 - fx) * (s / planks) / 3.0, 0, 1)
    pv = rng.random(planks + 1)[p]
    grain_n = value_noise(s, 64, rng)
    grain = np.sin((ys * 6 + pv * 10 + fbm(s, 3, 3, rng) * 2.5) * np.pi * 2 + grain_n * 0.8) * 0.5 + 0.5
    grain = blur(grain, 1)
    knots = np.clip((fbm(s, 10, 3, rng) > 0.75) * 1.0, 0, 1)
    height = grain * 0.12 - seam * 0.5 - knots * 0.1 + (1 - seam) * 0.2
    albedo = tint(base, pv * 0.7 + grain * 0.3, 0.22)
    rough = np.clip(0.78 + grain * 0.06, 0, 1)
    if painted:
        wear = np.clip((fbm(s, 14, 4, rng) + seam * 0.6) > 0.78, 0, 1).astype(float)
        wear = blur(wear, 1)
        paint = tint(painted, fbm(s, 4, 3, rng), 0.12)
        albedo = paint * (1 - wear[..., None]) + albedo * wear[..., None]
        height = height + (1 - wear) * 0.05
        rough = np.clip(rough * wear + 0.6 * (1 - wear), 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 3.5), ao_from_height(height, 6, 2.0), rough, np.zeros_like(rough))


def mat_metal_painted(rng, base="#2BA6A4", name="MetalPainted_Teal", out="maps/solstice"):
    """Painted steel: satin paint, chipped to bare metal on edges/scratches, faint panel seams."""
    s = SIZE
    ys, xs = np.mgrid[0:s, 0:s] / s
    seam = np.clip(1 - np.minimum(np.abs((xs * 2) % 1 - 0.5) * s / 2, 99) / 2.0, 0, 1) * 0
    big = fbm(s, 4, 3, rng)
    chips = blur(((fbm(s, 18, 4, rng) > 0.74)).astype(float), 1)
    scratches = blur((value_noise(s, 200, rng) > 0.985).astype(float), 1)
    bare = np.clip(chips + scratches, 0, 1)
    height = (1 - bare) * 0.08 + big * 0.05 - seam
    albedo = tint(base, big, 0.12)
    albedo = albedo * (1 - bare[..., None]) + tint("#8C9196", big, 0.1) * bare[..., None]
    rough = np.clip(0.45 + big * 0.1 + bare * 0.15, 0, 1)
    metal = np.clip(bare, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 4.0), ao_from_height(height, 4, 2.0), rough, metal)


def mat_concrete(rng, base="#B5AFA4", name="Concrete", out="shared"):
    s = SIZE
    big = fbm(s, 3, 4, rng)
    pores = (value_noise(s, 160, rng) > 0.93).astype(float)
    height = big * 0.2 - blur(pores, 1) * 0.3
    albedo = tint(base, big, 0.14)
    rough = np.clip(0.82 + (big - 0.5) * 0.15, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 2.5), ao_from_height(height, 6, 2.0), rough, np.zeros_like(rough))


def mat_sand(rng, name="Sand", out="maps/solstice"):
    s = SIZE
    ys, xs = np.mgrid[0:s, 0:s] / s
    ripples = np.sin((xs * 14 + fbm(s, 4, 3, rng) * 3) * np.pi * 2) * 0.5 + 0.5
    detail = fbm(s, 32, 3, rng)
    height = ripples * 0.15 + detail * 0.1
    albedo = tint("#D9C49A", fbm(s, 3, 3, rng) * 0.7 + detail * 0.3, 0.12)
    rough = np.full((s, s), 0.92)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 2.0), ao_from_height(height, 6, 1.5), rough, np.zeros_like(rough))


def mat_facility_panel(rng, name="FacilityPanel", out="shared", base="#C9CDD1"):
    """Clean PRISM facility wall panels for the Range: large panels, recessed seams, satin finish."""
    s = SIZE
    ys, xs = np.mgrid[0:s, 0:s] / s
    gx = np.minimum((xs * 2) % 1, 1 - (xs * 2) % 1) * s / 2
    gy = np.minimum((ys * 1) % 1, 1 - (ys * 1) % 1) * s
    e = np.minimum(gx, gy)
    seam = np.clip(1 - e / 4.0, 0, 1)
    bevel = np.clip(e / 12.0, 0, 1) ** 0.5
    big = fbm(s, 3, 3, rng)
    height = bevel * 0.4 - seam * 0.4 + big * 0.03
    albedo = tint(base, big, 0.06)
    albedo *= (1 - seam * 0.35)[..., None]
    albedo += np.clip(curvature(height, 3) * 4, 0, 0.08)[..., None]
    rough = np.clip(0.5 + big * 0.1 + seam * 0.2, 0, 1)
    save(name, ROOT / "client/assets" / out / "textures", albedo, normal_from_height(height, 3.0), ao_from_height(height, 6, 2.5), rough, np.zeros_like(rough))


MATERIALS = {
    "plaster_cream": lambda r: mat_plaster(r),
    "plaster_terracotta": lambda r: mat_plaster(r, base="#C8693F", name="Plaster_Terracotta"),
    "plaster_shade": lambda r: mat_plaster(r, base="#D8C7A6", name="Plaster_Sand"),
    "flagstone": mat_flagstone,
    "cobble": mat_cobble,
    "brick": mat_brick,
    "roof": mat_roof,
    "wood": lambda r: mat_wood(r),
    "wood_shutter": lambda r: mat_wood(r, base="#7A5638", name="WoodShutter_Teal", planks=8, painted="#2E9C9A"),
    "metal_teal": mat_metal_painted,
    "metal_rust": lambda r: mat_metal_painted(r, base="#B5552F", name="MetalPainted_Rust"),
    "sand": mat_sand,
    "concrete": mat_concrete,
    "facility": mat_facility_panel,
    "facility_dark": lambda r: mat_facility_panel(r, name="FacilityPanel_Dark", base="#4A5560"),
}


def main(argv: list[str]) -> None:
    names = argv or list(MATERIALS)
    for i, key in enumerate(names):
        print(f"[texgen] {key}")
        MATERIALS[key](np.random.default_rng(RNG_SEED + i * 101 + sum(map(ord, key))))


if __name__ == "__main__":
    main(sys.argv[1:])
