# BREACHPOINT — progress tracker

**Read this first if you are picking up the work.** It records where the build is, what is
verified, what is open, and the exact next steps. Update it at the end of every work session.

- Spec: `docs/prompt.md` (authoritative). Decisions: `docs/DECISIONS.md`. Licences: `docs/CREDITS.md`.
- The owner said **"continue working on all milestones without stopping"** (overrides the
  wait-for-approval rule). Push to both `main` and `claude/confident-faraday-b81zqs`.

## Status at a glance

| # | Milestone | Status |
|---|-----------|--------|
| 1 | Foundations | ✅ Done (CI green on GitHub) |
| 2 | Look-dev vertical slice (SOLSTICE corner, KESTREL, Saber) | ✅ Done (procedural pipeline) |
| 3 | Offline game feel + the Range | ✅ Done |
| 4 | Authoritative server core | ✅ Done (prediction/reconciliation, lag comp, fog of war) |
| 5 | Round loop | ✅ Done (buy, plant/defuse, economy, halftime, bots) |
| 6 | Full SOLSTICE | ✅ Layout + lightmap baked; bookmark set in `qa/screens/2026-11-23/solstice/` |
| 7 | Agents and abilities | ✅ Done (8 agents, data-driven ability engine, bot casting) |
| 8 | Front end and backend | ✅ Done (accounts, parties, MM, agent select, menus, career) |
| 9 | NEON DISTRICT + full weapon roster | ✅ Map + lightmap, 14 weapons + knife, skins, model-rendered icons |
| 10 | Polish and launch prep | 🟡 Most done (see M10 checklist); readability pass + art polish open |

### Milestone 10 checklist

- [x] Replays: server `.bpr` recorder (gzip stream), 14-day pruning, `GET /replays/:id`, client
      viewer (free cam, POV, scrub, speeds) from Career → REPLAY. Tests both sides.
- [x] Anti-cheat: input validation (non-finite, interp cap), reaction/snap/headshot/accuracy flags →
      `anticheat_flags`; scoreboard REPORT → `reports`.
- [x] Colour-blind modes (from M8).
- [x] Voice chat: WebRTC data-channel signalling via the match server + server relay fallback,
      push-to-talk (V), per-player mute/volume; text chat (Enter team / T all).
- [x] Ping wheel (Z) with world markers; announcer + teammate ability callouts (TTS + subtitles,
      `shared/config/voicelines.json`).
- [x] End-of-match screen (timeline, MVP, stats); match loading screen (callouts, rosters, tip).
- [x] Load test: `npm run loadtest` — report `qa/perf/2026-11-23-m10-load.md` (≈85 matches/core).
- [x] Browser loading: `tools/export-web.sh` (half-res 3D textures, desktop VRAM formats only,
      hashed filenames) → 75 MB pack / 26 MB gzip + 10 MB gzip wasm; boots in Chromium in ~4 s.
- [x] Compatibility glow compensation (`glowScale`).
- [x] Readability (definition of done: character contrast ≥ 3:1). The metric is silhouette-edge
      contrast (owner decision 2026-11-24, see DECISIONS.md). Run it with
      `res://scenes/dev/readability.tscn -- --map=<id> --size=1920x1080 --out=<dir>`.
      - SOLSTICE (two-tone outline): 25 of 25 measured bookmarks pass, worst 3.35.
      - NEON (fill + lift + value floor): 13 of 13 pass, worst 6.67.
      - Reports: `qa/readability/2026-11-24-*/report.json`.
      - Skipped (no spot where an agent can stand in view): Balcony overwatch, B Link, Roofline,
        A Main push, Bay vista, Parking deck. Add dedicated player-height bookmarks for those angles
        if wanted.
- [ ] Compatibility sun-shadow lift: investigated, engine-side; options (a)/(b)/(c) in DECISIONS.md — owner call.
- [ ] Snapshot deltas against `baseTick` (halves egress; field already in the protocol).
- [x] Observability: Prometheus `/metrics` (METRICS_PORT 9464), alert rules and Grafana dashboard
      in `docker/monitoring/`, wired into docker-compose.
- [x] Web FXAA pass; music as OGG Vorbis.
- [x] OAuth (Google, Discord): PKCE code flow, browser + polling for desktop and web, account
      linking by verified e-mail, Career tab sign-in UI (also e-mail login/registration, which
      had no UI before). Enable with `OAUTH_<GOOGLE|DISCORD>_CLIENT_ID/_SECRET` and
      `OAUTH_REDIRECT_BASE`. Tested against a fake provider; not tried against the real ones.
- [ ] Final art polish pass on every bookmark camera; perf capture on real hardware.

## What exists (map of the code)

- **Shared** `shared/config/*.json` (+ `shared/schemas`): weapons, agents, economy, movement, match,
  quality, hitboxes, materials, skins. `shared/protocol/messages.json` (28 msgs) → generated TS + GDScript
  codecs, golden vectors. `shared/maps/<id>.collision.bin|meta.json` exported by the map builders.
- **Server** `server/src/`
  - `sim/` deterministic movement, weapons, hitscan, mulberry32 RNG, collision grid + DDA LOS
    (bit-exact with the GDScript port: `client/scripts/sim/`).
  - `match/` Match (64 Hz worker), AbilityEngine, bot brain (nav rects + Dijkstra), MatchManager.
  - `gateway/` WebSocket gateway, rate limits, JWT/ticket auth.
  - `services/` Postgres (`migrations/`), Redis, auth (argon2id, rotating refresh), Glicko-2,
    social (parties, matchmaking, agent select, HMAC join tickets), stats, HTTP API on `API_PORT`.
  - `main.ts` env: `PORT, API_PORT, DATABASE_URL, REDIS_URL, JWT_SECRET, MAP` (comma list rotation,
    default `solstice,neon`), `FILL_BOTS, PHASE_SCALE, MM_FILL_AFTER, AGENT_SELECT_SEC,
    MM_MIN_COMPETITIVE, PUBLIC_GATEWAY_URL, ALLOW_ANON`.
- **Client** `client/`
  - Autoloads: Data, Settings, QualityManager, Audio, Net, Api, Game.
  - Art pipeline (no Blender): `tools/texgen` (numpy PBR sets), `tools/sfxgen` (synth WAVs),
    `scripts/art/` MeshKit, MapBuilder, SolsticeKit, LayoutFill, SceneIO.
  - Map builders (editor scripts): `addons/bp_tools/build_solstice.gd` (+ `solstice_full.gd`),
    `build_neon.gd`, `build_range.gd`, `build_lightmap_test.gd`.
  - Gameplay: `scripts/gameplay/`, `scripts/game/` (offline `game_session`, online `net_session`),
    agents (`scripts/agents/`), weapons (`scripts/weapons/`, 14 parametric recipes + knife), UI.
  - Scenes: `scenes/menu/main_menu.tscn` (main), `scenes/game/{range,online}.tscn`,
    `scenes/maps/{solstice,neon,range}.tscn`, dev scenes in `scenes/dev/`.

## Verification commands (all passing at the end of the last session)

```bash
npm ci && TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/breachpoint_test \
  TEST_REDIS_URL=redis://127.0.0.1:6379/1 npm run ci     # 80 Vitest tests incl. e2e matchmaking
GODOT_BIN=… bash tools/gdcheck.sh                        # compiles all scripts in the runtime
GODOT_BIN=… npm run godot:test                           # 21 GDScript tests incl. sim parity
GODOT_BIN=… bash tools/bake-lightmaps.sh [res://scene]   # needs Xvfb + lavapipe, 10–25 min/map
GODOT_BIN=… bash tools/export-web.sh                     # half-res, hashed web build
GODOT_BIN=… bash tools/capture-bookmarks.sh <map>        # qa/screens/<date>/<map>/
npm run loadtest -- --matches 200                        # load test report to stdout
```

Bot-match perf (Vitest `server/tests/match.test.ts`, 10 bots): SOLSTICE avg 0.27 ms / p99 0.88 ms
per tick; NEON avg 0.16 ms / p99 0.52 ms (budget 15.6 ms).

## Rebuilding maps / baking (read before touching assets)

- Build a map: `godot --headless --path client -s res://addons/bp_tools/build_<map>.gd`, then
  `npm run sync:client`. **Rebuilding wipes the scene's baked lightmap — re-bake after.**
- Bake: `bash tools/bake-lightmaps.sh res://scenes/maps/<map>.tscn` (runs the editor; the plugin
  presses the bake button, timeout 3 h; `BP_BAKE_QUALITY=high` for final quality).
- **Never add PNG/WAV files to `client/` while a bake runs** — the editor reimports and the bake
  breaks. Generate into a staging root instead (`TEXGEN_OUT=<dir> python3 tools/texgen/texgen.py …`)
  or work in a copy of `client/` (that is how NEON was built during the SOLSTICE bake).
- SOLSTICE lightmap is 4096² (16 MB VRAM-compressed) — candidate for a smaller web variant.

## Open problems

1. **Compatibility look parity** — glow ≈ 2× stronger and a shadowed sun adds a cool lift on web
   (measured; DECISIONS.md). Needs per-renderer env compensation in `QualityManager.apply_environment`.
2. ~~No FXAA on Compatibility~~: own FXAA pass (`shaders/post/fxaa_web.gdshader`) under the HUD.
3. ~~Half-res web textures / OGG~~: `tools/export-web.sh`; music is OGG Vorbis, SFX WAV (spec 16).
4. NEON street lights are dynamic (unshadowed) so the map reads at night without a bake; the
   bake adds moon bounce only. Check web perf with ~25 omni lights (Compatibility limit 8/object).
5. Perf numbers are from software rendering; real-hardware capture still needed.
6. Captures on lavapipe are slow (minutes per lightmapped frame); run them in the background.

## Next steps (in order)

2. Snapshot delta compression (protocol: encode players relative to `baseTick`, acked by the client).
3. Compatibility shadow-lift investigation; real-hardware perf captures (144 fps Medium / 60 fps web).
4. Art polish pass using the bookmark sets in `qa/screens/2026-11-23/`.

## Environment notes for agents (cloud container)

- Godot is **not** preinstalled. Download `Godot_v4.7-stable_linux.x86_64.zip` into your scratchpad
  and set `GODOT_BIN`; export templates go in `~/.local/share/godot/export_templates/4.7.stable/`.
- Rendering without a GPU: `export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json`, run under
  `xvfb-run -a -s "-screen 0 1920x1080x24"`. Forward+ uses lavapipe, Compatibility llvmpipe.
- After adding a `class_name`, run `godot --headless --path client --import` once. `-s` scripts
  cannot reference autoloads (keep pure logic in classes; `tools/gdcheck.sh` checks in-runtime).
- Postgres 16 + Redis: `apt` packages. Postgres data dir lives at `/var/lib/postgresql/bp-data`
  (not the scratchpad — its permissions get reset):
  `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/bp-data -o '-p 5432 -k /tmp' -l /var/lib/postgresql/bp.log start"`;
  `redis-server --daemonize yes`. DBs: `breachpoint`, `breachpoint_test` (password `postgres`).
- If e2e fails with 500 on register, check for a stale `server/src/main.ts` process on port 17351.
- Chromium + Playwright are preinstalled (`NODE_PATH=$(npm root -g)`) for testing the web build.

## Session log

- **2026-11-23 (1)** — M1 built and verified; CI green on GitHub.
- **2026-11-23 (2)** — M2–M8: procedural art pipeline, SOLSTICE, KESTREL + 7 agents, shared sim,
  authoritative server + netcode, round loop, bots, abilities, backend + menus.
- **2026-11-23 (3)** — M9: full weapon roster with skins; NEON DISTRICT (metro A / market B /
  arcade Mid, Rift monolith); both lightmaps baked; map rotation; weapon icons.
- **2026-11-23 (4)** — M10: replays, anti-cheat, reports, voice + text chat, ping wheel, announcer,
  end/loading screens, load test (+LOS optimisation), web build 217→75 MB with hashed files.
  Fixed: matchmade matches ignored lobby map/mode (ratings never moved), workers never released,
  e2e test leaked its server, replaced bots left a frozen body on the joining player's spawn.
