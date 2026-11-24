#!/usr/bin/env python3
"""BREACHPOINT character detail textures (procedural, no image sources).

Small tileable detail sets that M_Character projects triplanar in mesh space, so code-built agents
get real surface detail: fabric weave, quilting, knit ribs, leather grain, brushed/scratched metal,
skin micro-variation, hair strands and coarse canvas.

Per detail type into client/assets/agents/textures/:
  T_Char<Name>_N.png   tangent normal (OpenGL +Y)
  T_Char<Name>_V.png   R = albedo variation (0.5 neutral), G = roughness offset (0.5 neutral),
                       B = cavity (1 = open, 0 = deep crease)

Usage: python3 tools/texgen/chargen.py
"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
from PIL import Image

from texgen import blur, fbm, normal_from_height, value_noise, voronoi

ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = Path(os.environ["TEXGEN_OUT"]) if os.environ.get("TEXGEN_OUT") else ROOT
OUT = OUT_ROOT / "client" / "assets" / "agents" / "textures"
SIZE = 512

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/agents/textures/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/size_limit=0
detect_3d/compress_to=0
"""


def grid(size: int = SIZE):
    y, x = np.mgrid[0:size, 0:size] / size
    return x, y


def save(name: str, height: np.ndarray, strength: float, albedo_var: np.ndarray, rough: np.ndarray, cavity: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    n = normal_from_height(height, strength)
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / f"T_Char{name}_N.png", optimize=True)
    v = np.stack([np.clip(albedo_var, 0, 1), np.clip(rough, 0, 1), np.clip(cavity, 0, 1)], axis=-1)
    Image.fromarray((v * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / f"T_Char{name}_V.png", optimize=True)
    for suffix in ("N", "V"):
        fname = f"T_Char{name}_{suffix}.png"
        imp = OUT / (fname + ".import")
        if not imp.exists():
            imp.write_text(IMPORT.format(name=fname))
    print("wrote", name)


def norm(a: np.ndarray) -> np.ndarray:
    return (a - a.min()) / max(a.max() - a.min(), 1e-9)


def weave(rng: np.random.Generator) -> None:
    """Twill weave: diagonal over/under threads, tight (fabric, flight suit, coats)."""
    x, y = grid()
    cells = 64
    u = x * cells
    v = y * cells
    warp = 0.5 + 0.5 * np.sin((u + np.floor(v)) * np.pi)  # offset rows -> twill
    weft = 0.5 + 0.5 * np.sin((v + np.floor(u)) * np.pi)
    over = (np.floor(u) + np.floor(v)) % 2
    h = np.where(over > 0, warp * 0.8 + 0.2 * weft, weft * 0.8 + 0.2 * warp)
    h = blur(h, 1) * 0.8 + fbm(SIZE, 8, 3, rng) * 0.2
    var = 0.5 + (fbm(SIZE, 4, 4, rng) - 0.5) * 0.35 + (h - 0.5) * 0.12
    save("Weave", h, 2.2, var, 0.5 + (h - 0.5) * 0.2, 0.85 + h * 0.15)


def canvas(rng: np.random.Generator) -> None:
    """Coarse plain weave (poncho, webbing, heavy cloth)."""
    x, y = grid()
    cells = 28
    u = np.sin(x * cells * 2 * np.pi)
    v = np.sin(y * cells * 2 * np.pi)
    h = np.abs(u) * 0.5 + np.abs(v) * 0.5
    h += (fbm(SIZE, 16, 3, rng) - 0.5) * 0.4
    var = 0.5 + (fbm(SIZE, 6, 4, rng) - 0.5) * 0.5 + (h - 0.5) * 0.15
    save("Canvas", h, 3.0, var, 0.5 + (h - 0.5) * 0.25, 0.75 + norm(h) * 0.25)


def quilt(rng: np.random.Generator) -> None:
    """Diamond quilting with stitch rows and fine weave (heat-suit, puffy jackets)."""
    x, y = grid()
    cells = 4
    a = (x + y) * cells
    b = (x - y) * cells
    da = np.abs(a - np.round(a))
    db = np.abs(b - np.round(b))
    seam = np.minimum(da, db)
    puff = np.clip(seam * 2.0, 0, 1) ** 0.6
    stitch = ((np.minimum(da, db) < 0.02) & ((np.sin((x - y) * 600) > 0.2) | (np.sin((x + y) * 600) > 0.2))).astype(float)
    fine = 0.5 + 0.5 * np.sin(x * 256 * np.pi) * np.sin(y * 256 * np.pi)
    h = puff * 0.9 + fine * 0.04 - stitch * 0.05
    var = 0.5 + (puff - 0.5) * 0.25 + (fbm(SIZE, 4, 3, rng) - 0.5) * 0.2
    save("Quilt", h, 6.0, var, 0.5 + (0.5 - puff) * 0.2, 0.55 + puff * 0.45)


def knit(rng: np.random.Generator) -> None:
    """Rib knit (cuffs, collars, hoods, hems)."""
    x, y = grid()
    ribs = 24
    col = np.abs(np.sin(x * ribs * np.pi))
    loops = np.abs(np.sin((y * ribs * 2 + (np.floor(x * ribs * 2) % 2) * 0.5) * np.pi))
    h = col ** 0.6 * (0.7 + 0.3 * loops)
    var = 0.5 + (h - 0.5) * 0.25 + (fbm(SIZE, 4, 3, rng) - 0.5) * 0.2
    save("Knit", h, 3.5, var, 0.5 + (0.5 - h) * 0.2, 0.6 + h * 0.4)


def leather(rng: np.random.Generator) -> None:
    """Pebbled leather grain with soft creases (boots, belts, gloves, holsters)."""
    f1, edge, _ = voronoi(SIZE, 900, rng, 0.9)
    cell = np.clip(edge / 4.0, 0, 1)
    creases = np.abs(fbm(SIZE, 6, 4, rng) - 0.5) < 0.03
    h = cell ** 0.5 * 0.8 + fbm(SIZE, 32, 2, rng) * 0.2 - creases * 0.3
    var = 0.5 + (fbm(SIZE, 5, 4, rng) - 0.5) * 0.45 - creases * 0.1
    save("Leather", h, 2.5, var, 0.5 + (0.5 - cell) * 0.25 + creases * 0.15, 0.6 + cell * 0.4 - creases * 0.3)


def metal(rng: np.random.Generator) -> None:
    """Brushed metal with scratches and soft wear (armour, gear, mech parts)."""
    x, y = grid()
    brushed = blur(np.random.default_rng(7).random((SIZE, SIZE)), 1)
    brushed = np.repeat(brushed.mean(axis=1, keepdims=True), SIZE, axis=1) * 0.5 + brushed * 0.1
    scratches = np.zeros((SIZE, SIZE))
    for _ in range(90):
        x0, y0 = rng.random(2) * SIZE
        ang = rng.random() * np.pi
        ln = rng.random() * 80 + 20
        t = np.linspace(0, 1, int(ln))
        xs = ((x0 + np.cos(ang) * ln * t) % SIZE).astype(int)
        ys = ((y0 + np.sin(ang) * ln * t) % SIZE).astype(int)
        scratches[ys, xs] = 1.0
    scratches = blur(scratches, 1)
    wear = fbm(SIZE, 4, 5, rng)
    h = brushed * 0.4 - scratches * 0.6 + wear * 0.15
    var = 0.5 + (wear - 0.5) * 0.4 + scratches * 0.25
    save("Metal", h, 2.0, var, 0.5 - scratches * 0.3 + (wear - 0.5) * 0.3, 1.0 - scratches * 0.2)


def skin(rng: np.random.Generator) -> None:
    """Soft skin micro-variation (no pores to speak of: stylised, painterly)."""
    mott = fbm(SIZE, 6, 5, rng)
    pores = 1 - np.clip(voronoi(SIZE, 1600, rng, 1.0)[0] / 5.0, 0, 1) ** 0.5 * 0.2
    h = mott * 0.5 + pores * 0.15
    var = 0.5 + (mott - 0.5) * 0.3
    save("Skin", h, 0.8, var, 0.5 + (0.5 - mott) * 0.15, 0.95 + pores * 0.05)


def hair(rng: np.random.Generator) -> None:
    """Strand grooves running along V (hair clumps are built along their length)."""
    x, y = grid()
    lines = np.zeros(SIZE)
    for _ in range(140):
        c = rng.random() * SIZE
        w = rng.random() * 2.5 + 0.8
        d = np.abs(((np.arange(SIZE) - c + SIZE / 2) % SIZE) - SIZE / 2)
        lines += np.exp(-(d / w) ** 2) * (0.4 + rng.random() * 0.6)
    strands = np.repeat(lines[None, :], SIZE, axis=0)
    wav = value_noise(SIZE, 8, rng)
    strands = np.roll(strands, 0, axis=1) * 0.8 + wav * 0.2
    h = norm(strands)
    var = 0.5 + (h - 0.5) * 0.3 + (fbm(SIZE, 4, 3, rng) - 0.5) * 0.2
    save("Hair", h, 2.5, var, 0.5 + (0.5 - h) * 0.2, 0.7 + h * 0.3)


def main() -> None:
    rng = np.random.default_rng(4242)
    for fn in (weave, canvas, quilt, knit, leather, metal, skin, hair):
        fn(rng)


if __name__ == "__main__":
    main()
