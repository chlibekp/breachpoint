#!/usr/bin/env python3
"""Stylised VFX textures (spec §9.4): crisp shapes, stepped alpha, bright cores — no soft mush.
Outputs to client/assets/vfx/: muzzle flash flipbook (3 frames), bullet-hole decals per surface,
smoke puff, spark streak, generic soft dot, crosshair-safe hitmarker glyph."""
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "client/assets/vfx"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)


def save(name, rgba):
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"T_{name}.png", optimize=True)


def grid(s):
    y, x = np.mgrid[0:s, 0:s] / (s - 1) * 2 - 1
    return x, y, np.sqrt(x * x + y * y), np.arctan2(y, x)


# Muzzle flash: 3 frames side by side (256 each), star with 5-7 petals, hot white core -> orange edge.
s = 256
frames = []
for f in range(3):
    x, y, r, a = grid(s)
    petals = 5 + f
    rot = rng.uniform(0, np.pi)
    lobes = 0.35 + 0.65 * np.abs(np.cos((a + rot) * petals / 2)) ** (3 + f)
    shape = r < lobes * (0.95 - f * 0.12)
    core = np.clip(1 - r / (0.35 - f * 0.05), 0, 1)
    alpha = np.where(shape, 1.0, 0.0)
    alpha = np.floor(alpha * (1 - np.clip((r - 0.6) * 2, 0, 1)) * 4) / 4  # stepped alpha
    col = np.stack([np.ones_like(r), 0.55 + 0.45 * core, 0.18 + 0.82 * core ** 2], -1)
    frames.append(np.concatenate([col, alpha[..., None]], -1))
save("MuzzleFlash_Flipbook", np.concatenate(frames, 1))

# Bullet hole decals per surface: dark centre, chipped ring, painted lighter rim (readable, not noisy).
for name, base, rim in [("Concrete", (0.25, 0.22, 0.2), (0.85, 0.8, 0.72)), ("Metal", (0.12, 0.12, 0.13), (0.75, 0.75, 0.78)),
                        ("Wood", (0.22, 0.14, 0.08), (0.72, 0.55, 0.38)), ("Glass", (0.6, 0.75, 0.8), (0.95, 0.98, 1.0))]:
    s = 128
    x, y, r, a = grid(s)
    jag = 1 + 0.18 * np.sin(a * 7 + rng.uniform(0, 6)) + 0.1 * np.sin(a * 13)
    hole = r < 0.22 * jag
    ring = (r < 0.55 * jag) & ~hole
    if name == "Glass":
        cracks = (np.abs(np.sin(a * 6 + rng.uniform(0, 6))) < 0.06) & (r < 0.95)
        ring = ring | cracks
    alpha = np.where(hole, 1.0, np.where(ring, 0.75 * (1 - r / 0.6), 0.0))
    col = np.where(hole[..., None], np.array(base), np.array(rim))
    save(f"BulletHole_{name}", np.concatenate([col, np.clip(alpha, 0, 1)[..., None]], -1))

# Smoke puff: chunky cloud with 3 stepped value bands.
s = 128
x, y, r, a = grid(s)
n = 0.75 + 0.25 * np.sin(a * 5 + 1) * np.sin(a * 3)
inside = r < n * 0.9
shade = np.floor((0.6 + 0.4 * (-y * 0.5 + 0.5)) * 3) / 3
alpha = inside * np.clip((n * 0.9 - r) * 6, 0, 1)
save("SmokePuff", np.concatenate([np.stack([shade, shade, shade * 0.97], -1), (np.floor(alpha * 4) / 4)[..., None]], -1))

# Spark streak (stretched along X).
s = 64
x, y, r, a = grid(s)
core = np.clip(1 - np.abs(y) * 5, 0, 1) * np.clip(1 - np.abs(x), 0, 1)
save("Spark", np.concatenate([np.stack([np.ones_like(x), 0.8 + 0.2 * core, 0.4 + 0.6 * core], -1), core[..., None]], -1))

# Soft dot (generic particles, tracer heads).
x, y, r, a = grid(64)
d = np.clip(1 - r, 0, 1) ** 1.5
save("Dot", np.concatenate([np.ones((64, 64, 3)), d[..., None]], -1))
print("vfx textures written:", sorted(p.name for p in OUT.glob("*.png")))
