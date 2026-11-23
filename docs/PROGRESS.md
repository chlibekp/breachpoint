# BREACHPOINT — progress tracker

**Read this first if you are picking up the work.** It records where the build is, what is
verified, what is open, and the exact next steps. Update it at the end of every work session.

- Spec: `docs/prompt.md` (authoritative). Decisions: `docs/DECISIONS.md`. Licences: `docs/CREDITS.md`.
- Working rule from the spec: finish one milestone, report (summary, screenshots, perf, open problems),
  then **wait for the owner's approval** before starting the next.
- Owner asked for pushes to both `main` and the session branch while working.

## Status at a glance

| # | Milestone | Status |
|---|-----------|--------|
| 1 | Foundations | ✅ **Built and verified — awaiting owner approval** |
| 2 | Look-dev vertical slice (SOLSTICE corner, KESTREL, Saber) | ⏳ Not started (blocked on M1 approval) |
| 3 | Offline game feel + the Range | — |
| 4 | Authoritative server core | — |
| 5 | Round loop | — |
| 6 | Full SOLSTICE | — |
| 7 | Agents and abilities | — |
| 8 | Front end and backend | — |
| 9 | NEON DISTRICT + full weapon roster | — |
| 10 | Polish and launch prep | — |

## Milestone 1 — Foundations

Spec §18.1: "Monorepo, CI, Godot project with both export presets, QualityManager, the shared JSON
configs and protocol generator. Confirm the Compatibility renderer's lightmap support on the pinned
Godot version."

### Checklist

- [x] Monorepo layout per spec §17.1 (`client/ server/ shared/ docs/ qa/ docker/ .github/`)
- [x] Godot 4.7-stable pinned (`.godot-version`, README, CI)
- [x] Godot project: Forward+ desktop, `rendering_method.web = gl_compatibility`, 64 Hz physics +
      interpolation, Jolt, warnings-as-errors, shader globals (`quality_tier`, team colours)
- [x] Export presets: Linux, Windows, Web (single-threaded), Web (threaded, COOP/COEP)
- [x] Autoloads: `Data`, `Settings`, `QualityManager`, `Audio`, `Net`, `Game`
- [x] QualityManager: tier from `shared/config/quality.json`, renderer-aware, applies AA/shadows/
      SSAO/SSIL/SSR/volumetrics, GPU→CPU particle conversion, global `quality_tier`
- [x] Shared configs: weapons (15 + knife), agents (8 × 4 abilities), economy, movement, match,
      quality — JSON Schemas, Ajv (server/CI) + GDScript validator (client), cross-field checks
- [x] Protocol: `shared/protocol/messages.json` (21 messages) → generated TS + GDScript codecs;
      golden vectors byte-checked by both test suites
- [x] Server: drift-corrected 64 Hz loop, match worker entry, WebSocket gateway (guest auth, ping)
- [x] Client ↔ server verified end-to-end, from desktop and from the **web build in Chromium**
- [x] CI workflow: lint, typecheck, tests, generated-code drift, Godot import + tests, exports, Docker
- [x] Docker: server image, docker-compose (gateway, web/nginx, Postgres, Redis)
- [x] Branded web loading shell with byte progress bar
- [x] **Lightmap check in Compatibility (Godot 4.7)**: bakes headlessly, renders in both renderers;
      two Compatibility differences found and measured (see DECISIONS.md → "Milestone-1 check")
- [x] QA: capture hook (`-- --capture=<scene> --out=<png>`), screenshots in `qa/screens/2026-11-23/`
- [x] Perf report `qa/perf/2026-11-23-m1.md`
- [x] Art notes: `docs/art/references.md`, `docs/art/ui.md`, `docs/art/maps/solstice.md`

### Verification commands (all passing at the end of the session)

```bash
npm ci && npm run ci                      # 34 Vitest tests, lint, types, schema, drift check
GODOT_BIN=… npm run godot:test            # 12 GDScript tests incl. protocol parity
GODOT_BIN=… bash tools/export.sh Linux Web
GODOT_BIN=… bash tools/bake-lightmaps.sh  # needs a display (Xvfb ok) + Vulkan (lavapipe ok)
```

### Open problems carried into milestone 2

1. **Compatibility look parity** — glow ≈ 2× stronger, and a shadow-casting sun adds a cool lift to
   sunlit surfaces (measured; DECISIONS.md). Fix in look-dev: per-renderer env compensation,
   try LightmapGI shadowmask, tune web shadow distance/bias (saw-tooth shadow acne at 1×2048).
2. **No FXAA on Compatibility** in 4.7: web AA is MSAA 2x only (spec asked MSAA 2x + FXAA).
   Option: a cheap FXAA post shader for the web tier if edges look rough on real art.
3. **Half-res web textures**: no per-platform import size in Godot; needs a pre-export re-import step.
4. **WASM SIMD**: needs custom web templates; deferred until profiling.
5. Perf numbers so far are from software rendering only; real-hardware capture needed.
6. Reliable channel (seq/ack inside the socket), snapshot deltas, JWT auth — scheduled for M4/M8.
7. ~~CI first run~~ — passed on GitHub (run #1: node, godot tests + exports, docker all green).

## Milestone 2 — next steps (once M1 is approved)

1. Write `docs/art/agents/kestrel.md` (concept sheet: front/side/back silhouettes + colour callouts)
   and `docs/art/weapons/saber.md` style notes citing `docs/art/references.md`.
2. Master shaders in `client/shaders/` (`M_Env_Standard`, `M_Env_Blend`, `M_Character`, `M_Weapon`,
   `M_Glass`, `M_Foliage`, `M_RiftEnergy`, `M_AbilityWall`), all including `include/quality.gdshaderinc`.
3. Texture pipeline: import presets (Albedo/Normal/ORM/UI) applied by script; texture tooling
   (Blender is **not** installed in the cloud container — check what is available before planning
   the modelling path).
4. SOLSTICE 40×40 m corner: modular kit, trims, 8–12 tiling materials, 20 props, bake, LUT, sky.
5. Resolve open problem 1 before judging the art on web.
6. Screenshot bookmarks (20+) + `qa/screens/<date>/` capture on both renderers.

## Environment notes for agents (cloud container)

- Godot is **not** preinstalled. Download `Godot_v4.7-stable_linux.x86_64.zip` from the GitHub
  release into your scratchpad and set `GODOT_BIN`; export templates go in
  `~/.local/share/godot/export_templates/4.7.stable/` (only linux/web/windows files are needed).
- Rendering without a GPU: `export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json` and run under
  `xvfb-run -a -s "-screen 0 1920x1080x24"`. Forward+ uses lavapipe, Compatibility uses llvmpipe.
- After adding a new `class_name`, run `godot --headless --path client --import` once so `-s`
  scripts can see it. Scripts run with `-s` cannot reference autoloads (keep pure logic in classes).
- Chromium + Playwright are preinstalled (`NODE_PATH=$(npm root -g)`), good for testing the web build.

## Session log

- **2026-11-23** — Milestone 1 built and verified (this document). Pushed to `main` and
  `claude/confident-faraday-b81zqs`. Awaiting approval to start milestone 2.

### TODO on next SOLSTICE rebuild (do not rebuild while a bake is running)
- Mid has a straight ~130 m spawn-to-spawn sightline (x -10..0). Add a solid "Mid Kiosk" cover
  block and a dog-leg near z 8–14 in `solstice_full.gd` so neither spawn can see the other.
