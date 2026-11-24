#!/usr/bin/env python3
"""BREACHPOINT procedural sound generator (spec §16). Every sound is synthesised from noise,
oscillators and envelopes — original by construction, nothing sampled, nothing to license.

Writes 16-bit mono WAVs to client/assets/sfx/<group>/SFX_<name>_<variant>.wav (music: OGG Vorbis
via ffmpeg).
Weapons get 3 layers (mech = close mechanical, body, tail) + a distant variant, 4 variations each.
Footsteps: 7 surfaces x 6 variations. Plus reloads, impacts, hit/kill feedback, UI, Breach Charge.
"""
from __future__ import annotations

import json
import sys
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/sfx"
SR = 32000


def env(n: int, attack: float, decay: float, sustain: float = 0.0, curve: float = 4.0) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) * curve / max(decay, 1e-4))
    return a * (sustain + (1 - sustain) * d)


def noise(n: int, rng) -> np.ndarray:
    return rng.uniform(-1, 1, n)


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def lowpass_fast(x: np.ndarray, cutoff: float, passes: int = 2) -> np.ndarray:
    # Moving-average approximation (vectorised) for long buffers.
    k = max(1, int(SR / (cutoff * 2.2)))
    for _ in range(passes):
        x = np.convolve(x, np.ones(k) / k, mode="same")
    return x


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass_fast(x, cutoff, 1)


def sine_sweep(n: int, f0: float, f1: float, curve: float = 3.0) -> np.ndarray:
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * curve * 10)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def reverb_tail(x: np.ndarray, length: float, damp: float, rng, wet: float = 0.4) -> np.ndarray:
    n = int(length * SR)
    ir = noise(n, rng) * env(n, 0.002, length, 0, 5.5)
    ir = lowpass_fast(ir, damp, 1)
    y = np.convolve(x, ir)[: len(x) + n] * wet
    out = np.zeros(len(y))
    out[: len(x)] += x
    out += y / (np.max(np.abs(y)) + 1e-9) * np.max(np.abs(x)) * wet
    return out


def save(group: str, name: str, x: np.ndarray, gain: float = 0.9) -> None:
    d = OUT / group
    d.mkdir(parents=True, exist_ok=True)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    wav = d / f"SFX_{name}.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if group == "music":
        # Spec 16: music ships as OGG Vorbis (streamed, ~10x smaller than PCM); SFX stay WAV.
        ogg = wav.with_suffix(".ogg")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(ogg)],
            check=True,
        )
        wav.unlink()


# ---------------------------------------------------------------- weapons

WEAPON_VOICES = {
    # id: (body_low_hz, body_len, crack_cutoff, mech_hz, tail_len, punch)
    "wasp": (140, 0.12, 5200, 2400, 0.6, 0.7),
    "pike": (90, 0.2, 4200, 1800, 0.9, 1.2),
    "hornet": (180, 0.08, 2200, 2800, 0.35, 0.45),
    "grifter": (80, 0.2, 3000, 1500, 0.8, 1.1),
    "jolt": (160, 0.09, 5000, 2600, 0.5, 0.6),
    "halcyon": (150, 0.1, 5400, 2500, 0.55, 0.65),
    "breaker": (70, 0.28, 3200, 1400, 1.1, 1.4),
    "mauler": (75, 0.25, 3400, 1500, 1.0, 1.3),
    "lancer": (120, 0.13, 6000, 2200, 0.7, 0.85),
    "kite": (95, 0.18, 6500, 1900, 1.0, 1.1),
    "saber": (100, 0.16, 6800, 2000, 0.9, 1.0),
    "specter": (130, 0.1, 2600, 2300, 0.4, 0.6),
    "shrike": (85, 0.22, 7500, 1700, 1.3, 1.3),
    "longbow": (60, 0.32, 8000, 1300, 1.8, 1.8),
    "bulwark": (85, 0.15, 5600, 1600, 0.9, 1.1),
}


def weapon(wid: str, rng) -> None:
    low, body_len, crack, mech, tail_len, punch = WEAPON_VOICES[wid]
    silenced = wid in ("hornet", "specter")
    for v in range(4):
        r = np.random.default_rng(rng.integers(1 << 30))
        jitter = 1 + r.uniform(-0.06, 0.06)
        # Mechanical close layer: bolt/clack transient.
        n = int(0.09 * SR)
        m = highpass(noise(n, r), mech * jitter) * env(n, 0.0005, 0.02, 0, 6)
        m += np.sin(2 * np.pi * mech * 1.6 * jitter * np.arange(n) / SR) * env(n, 0.0003, 0.012, 0, 6) * 0.3
        save("weapons", f"{wid}_mech_{v}", m, 0.7)
        # Body: punchy low sweep + filtered noise burst + crack.
        n = int((body_len + 0.05) * SR)
        b = sine_sweep(n, low * 3.2 * jitter, low * jitter, 2.5) * env(n, 0.001, body_len, 0, 5) * punch
        nb = lowpass_fast(noise(n, r), crack * (0.4 if silenced else 1.0) * jitter) * env(n, 0.0008, body_len * 0.6, 0, 7)
        b = b * 0.8 + nb * (0.5 if silenced else 1.0)
        if not silenced:
            cr = highpass(noise(n, r), 3000) * env(n, 0.0002, 0.006, 0, 8) * 0.8
            b += cr
        b = np.tanh(b * 2.2)
        save("weapons", f"{wid}_body_{v}", b, 0.95)
        # Tails: outdoor (long, bright, slap-back) and indoor (short, boomy).
        n = int(0.05 * SR)
        exc = noise(n, r) * env(n, 0.001, 0.03, 0, 6)
        out = reverb_tail(exc, tail_len * (0.6 if silenced else 1.0), 2600, r, 0.9)
        save("weapons", f"{wid}_tail_out_{v}", out[int(0.02 * SR):], 0.5)
        ind = reverb_tail(exc, tail_len * 0.45, 900, r, 0.9)
        save("weapons", f"{wid}_tail_in_{v}", ind[int(0.01 * SR):], 0.55)
        # Distant (>30 m): low, dull thump with a long soft tail.
        n = int(0.6 * SR)
        d = lowpass_fast(noise(n, r), 600 if not silenced else 300) * env(n, 0.004, 0.25, 0, 4)
        d += sine_sweep(n, low * 1.5, low * 0.7, 1) * env(n, 0.002, 0.2, 0, 5) * 0.6
        save("weapons", f"{wid}_distant_{v}", reverb_tail(d, 0.9, 700, r, 0.6), 0.6)


def reloads(rng) -> None:
    def click(f: float, length: float, r) -> np.ndarray:
        n = int(length * SR)
        return highpass(noise(n, r), f) * env(n, 0.0003, length * 0.3, 0, 6) + np.sin(2 * np.pi * f * 0.5 * np.arange(n) / SR) * env(n, 0.0003, length * 0.2, 0, 6) * 0.4

    r = np.random.default_rng(rng.integers(1 << 30))
    save("weapons", "mag_out", np.concatenate([click(1800, 0.06, r), np.zeros(int(0.02 * SR)), lowpass_fast(noise(int(0.12 * SR), r), 1500) * env(int(0.12 * SR), 0.01, 0.08) * 0.4]))
    save("weapons", "mag_in", np.concatenate([lowpass_fast(noise(int(0.05 * SR), r), 2000) * 0.3 * env(int(0.05 * SR), 0.01, 0.04), click(1400, 0.08, r) * 1.2]))
    save("weapons", "charge", np.concatenate([click(2600, 0.05, r), np.zeros(int(0.07 * SR)), click(2000, 0.07, r) * 1.3]))
    save("weapons", "equip", np.concatenate([lowpass_fast(noise(int(0.15 * SR), r), 2500) * env(int(0.15 * SR), 0.03, 0.1) * 0.5, click(2200, 0.06, r)]))
    save("weapons", "dry_fire", click(3200, 0.04, r), 0.5)
    save("weapons", "spinup", sine_sweep(int(0.9 * SR), 60, 420, -0.2) * env(int(0.9 * SR), 0.3, 0.6, 0.8) * 0.4)
    for v in range(4):
        n = int(0.18 * SR)
        t = np.arange(n) / SR
        rr = np.random.default_rng(rng.integers(1 << 30))
        tink = sum(np.sin(2 * np.pi * f * (1 + rr.uniform(-0.03, 0.03)) * t) * np.exp(-t * d) for f, d in [(3900, 40), (5600, 55), (7300, 70)])
        save("weapons", f"shell_{v}", tink * env(n, 0.0005, 0.15, 0, 3), 0.35)


# ---------------------------------------------------------------- footsteps / impacts

SURFACES = {"stone": (1400, 0.07), "metal": (3200, 0.12), "wood": (900, 0.09), "sand": (2500, 0.11), "tile": (2000, 0.06), "water": (1600, 0.16), "carpet": (500, 0.06)}


def footsteps(rng) -> None:
    for surf, (cut, length) in SURFACES.items():
        for v in range(6):
            r = np.random.default_rng(rng.integers(1 << 30))
            n = int((length + 0.05) * SR)
            heel = lowpass_fast(noise(n, r), cut * r.uniform(0.85, 1.15)) * env(n, 0.001, length * 0.5, 0, 6)
            toe = np.roll(lowpass_fast(noise(n, r), cut * 1.4) * env(n, 0.001, length * 0.35, 0, 6) * 0.6, int(0.025 * SR))
            x = heel + toe
            if surf == "metal":
                t = np.arange(n) / SR
                x += np.sin(2 * np.pi * r.uniform(420, 560) * t) * np.exp(-t * 30) * 0.25
            if surf == "water":
                x += highpass(noise(n, r), 3000) * env(n, 0.01, 0.1, 0, 4) * 0.4
            if surf == "sand":
                x = highpass(x, 600)
            save("footsteps", f"{surf}_{v}", x, 0.6)
        n = int(0.2 * SR)
        r = np.random.default_rng(rng.integers(1 << 30))
        save("footsteps", f"{surf}_land", lowpass_fast(noise(n, r), cut * 0.8) * env(n, 0.002, 0.12, 0, 5) + np.sin(2 * np.pi * 70 * np.arange(n) / SR) * env(n, 0.001, 0.08, 0, 5), 0.75)


IMPACTS = {"concrete": (3000, 0.08), "metal": (4500, 0.18), "wood": (1200, 0.1), "glass": (6000, 0.3), "sand": (1500, 0.07), "water": (2000, 0.2), "flesh": (700, 0.06)}


def impacts(rng) -> None:
    for kind, (cut, length) in IMPACTS.items():
        for v in range(4):
            r = np.random.default_rng(rng.integers(1 << 30))
            n = int((length + 0.05) * SR)
            t = np.arange(n) / SR
            x = lowpass_fast(noise(n, r), cut) * env(n, 0.0005, length * 0.4, 0, 6)
            if kind == "metal":
                x += sum(np.sin(2 * np.pi * f * r.uniform(0.95, 1.05) * t) * np.exp(-t * 25) for f in (1800, 2700, 4100)) * 0.25
            if kind == "glass":
                x += highpass(noise(n, r), 5000) * env(n, 0.001, 0.25, 0, 3) * 0.6
            if kind == "flesh":
                x = lowpass_fast(x, 800) + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 40) * 0.5
            save("impacts", f"{kind}_{v}", x, 0.6)


# ---------------------------------------------------------------- feedback / UI / charge

def feedback(rng) -> None:
    t = lambda d: np.arange(int(d * SR)) / SR  # noqa: E731
    tt = t(0.07)
    save("ui", "hitmarker", (np.sin(2 * np.pi * 1900 * tt) + 0.5 * np.sin(2 * np.pi * 3800 * tt)) * np.exp(-tt * 70), 0.5)
    tt = t(0.22)
    head = np.sin(2 * np.pi * 2600 * tt) * np.exp(-tt * 18) + np.sin(2 * np.pi * 3900 * tt) * np.exp(-tt * 24) * 0.6 + np.sin(2 * np.pi * 5200 * tt) * np.exp(-tt * 35) * 0.3
    save("ui", "headshot", head, 0.6)
    tt = t(0.4)
    kill = np.sin(2 * np.pi * (880 + 440 * (tt > 0.08)) * tt) * env(len(tt), 0.002, 0.3, 0, 3) + np.sin(2 * np.pi * 1760 * tt) * env(len(tt), 0.002, 0.2, 0, 4) * 0.4
    save("ui", "kill", kill, 0.55)
    tt = t(0.05)
    save("ui", "click", np.sin(2 * np.pi * 1400 * tt) * np.exp(-tt * 120), 0.35)
    tt = t(0.12)
    save("ui", "hover", np.sin(2 * np.pi * 900 * tt) * np.exp(-tt * 60) * 0.5, 0.2)
    tt = t(0.6)
    save("ui", "lockin", (np.sin(2 * np.pi * 220 * tt) + np.sin(2 * np.pi * 330 * tt) + np.sin(2 * np.pi * 440 * tt * (1 + tt))) * env(len(tt), 0.005, 0.5, 0, 3), 0.6)
    r = np.random.default_rng(rng.integers(1 << 30))
    tt = t(0.25)
    save("ui", "damage_taken", lowpass_fast(noise(len(tt), r), 500) * env(len(tt), 0.002, 0.15, 0, 5) + np.sin(2 * np.pi * 90 * tt) * np.exp(-tt * 20), 0.6)
    # Breach Charge: plant chirps, beep, defuse half-way cue, detonation.
    tt = t(0.12)
    save("charge", "beep", np.sin(2 * np.pi * 2100 * tt) * env(len(tt), 0.002, 0.08, 0, 3), 0.6)
    tt = t(4.0)
    plant = np.sin(2 * np.pi * (300 + 200 * np.floor(tt * 4) % 3) * tt) * 0.3 * (np.sin(2 * np.pi * 8 * tt) > 0)
    save("charge", "plant_loop", plant * env(len(tt), 0.02, 4, 1), 0.5)
    tt = t(7.0)
    defuse = (np.sin(2 * np.pi * 500 * tt) * 0.2 + highpass(noise(len(tt), r), 2000) * 0.08) * (np.sin(2 * np.pi * 3 * tt) > -0.2)
    save("charge", "defuse_loop", defuse, 0.45)
    tt = t(0.5)
    save("charge", "defuse_half", (np.sin(2 * np.pi * 1320 * tt) + np.sin(2 * np.pi * 1760 * tt * (tt > 0.15))) * env(len(tt), 0.002, 0.4, 0, 3), 0.6)
    tt = t(2.5)
    boom = lowpass_fast(noise(len(tt), r), 400) * env(len(tt), 0.002, 1.8, 0, 3) + sine_sweep(len(tt), 120, 30, 0.3) * env(len(tt), 0.001, 1.2, 0, 3)
    save("charge", "detonate", reverb_tail(np.tanh(boom * 3), 1.5, 600, r, 0.5), 0.95)
    # Ability generic cues (cast / travel / impact) per element, used until bespoke sounds land.
    for name, f in {"rift": 660, "smoke": 240, "flash": 1800, "scan": 1200, "trap": 520, "heal": 880, "fire": 300, "dash": 400}.items():
        tt = t(0.45)
        cast = sine_sweep(len(tt), f * 0.5, f * 1.5, -0.3) * env(len(tt), 0.01, 0.35, 0, 3) + highpass(noise(len(tt), r), 2500) * env(len(tt), 0.005, 0.2) * 0.2
        save("abilities", f"{name}_cast", cast, 0.6)
        tt = t(0.7)
        imp = sine_sweep(len(tt), f * 2, f * 0.6, 1.0) * env(len(tt), 0.002, 0.5, 0, 3) + lowpass_fast(noise(len(tt), r), f * 3) * env(len(tt), 0.002, 0.3) * 0.5
        save("abilities", f"{name}_impact", imp, 0.7)


def music(rng) -> None:
    """Short original cues (spec §16): menu theme loop, agent-select loop, buy sting, win/loss."""
    def chord_loop(seconds: float, bpm: float, roots: list[float], bright: float) -> np.ndarray:
        n = int(seconds * SR)
        t = np.arange(n) / SR
        beat = 60 / bpm
        out = np.zeros(n)
        bar = beat * 4
        for i, root in enumerate(roots * int(np.ceil(seconds / (bar * len(roots))))):
            s = int(i * bar * SR)
            e = min(n, int((i + 1) * bar * SR))
            if s >= n:
                break
            tt = t[: e - s]
            pad = sum(np.sin(2 * np.pi * root * m * tt + np.sin(2 * np.pi * 0.3 * tt) * 0.5) / (k + 1) for k, m in enumerate([1, 1.5, 2, 2.52, 3]))
            out[s:e] += pad * 0.12 * env(e - s, 0.4, bar, 0.6, 1.5)
        pulse = (np.sin(2 * np.pi * t / beat * 2) > 0.7).astype(float)
        out += lowpass_fast(noise(n, rng), 3000) * pulse * env(n, 0.01, seconds, 1) * 0.04 * bright
        kick = np.zeros(n)
        for b in np.arange(0, seconds, beat):
            s = int(b * SR)
            k = min(n - s, int(0.25 * SR))
            kick[s:s + k] += sine_sweep(k, 160, 45, 1.5) * env(k, 0.001, 0.2, 0, 4)
        out += kick * 0.35
        return out

    save("music", "menu_theme", chord_loop(32, 96, [110, 87.3, 130.8, 98], 1.0), 0.7)
    save("music", "agent_select", chord_loop(16, 120, [146.8, 130.8], 1.4), 0.7)
    n = int(2.2 * SR)
    tt = np.arange(n) / SR
    save("music", "buy_sting", sum(np.sin(2 * np.pi * f * tt) * env(n, 0.01 + i * 0.12, 1.5, 0, 2.5) for i, f in enumerate([220, 277.2, 329.6, 440])), 0.6)
    save("music", "win", sum(np.sin(2 * np.pi * f * tt) * env(n, 0.01 + i * 0.15, 2.0, 0, 2) for i, f in enumerate([261.6, 329.6, 392, 523.3])), 0.6)
    save("music", "loss", sum(np.sin(2 * np.pi * f * tt) * env(n, 0.01 + i * 0.2, 2.0, 0, 2) for i, f in enumerate([220, 207.7, 174.6, 146.8])), 0.6)


def main(argv: list[str]) -> None:
    rng = np.random.default_rng(2040)
    groups = argv or ["weapons", "reloads", "footsteps", "impacts", "feedback", "music"]
    if "weapons" in groups:
        for wid in WEAPON_VOICES:
            weapon(wid, rng)
            print(f"[sfxgen] weapon {wid}")
    if "reloads" in groups:
        reloads(rng)
    if "footsteps" in groups:
        footsteps(rng)
    if "impacts" in groups:
        impacts(rng)
    if "feedback" in groups:
        feedback(rng)
    if "music" in groups:
        music(rng)
    manifest = {g.name: sorted(p.stem for p in [*g.glob("*.wav"), *g.glob("*.ogg")]) for g in OUT.iterdir() if g.is_dir()}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print("[sfxgen] done")


if __name__ == "__main__":
    main(sys.argv[1:])
