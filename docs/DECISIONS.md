# Decisions

Choices the spec left open, recorded as the spec asks (§1). Newest at the bottom of each section.
Format: **decision** — why. Anything touching spec §2, §4 or §10 needs the owner's approval first.

## Engine and tooling

- **Godot 4.7-stable** (`4.7.stable.official.5b4e0cb0f`), pinned in `.godot-version`, README and CI.
  Latest stable on 2026-11-23; satisfies "4.5 or newer".
- **Jolt Physics** (built into Godot since 4.4) as the 3D physics engine — more robust character
  contacts than GodotPhysics; works on web. Gameplay movement itself will be our own deterministic
  sim (§13.3), so physics is only for props/ragdolls/raycasts.
- **3D physics interpolation on** with `physics_ticks_per_second = 64` (spec §17.2).
- **GDScript warnings → errors** for typing/unused/shadowing warnings in `project.godot` (spec §17.2).
  `return_value_discarded` stays off (too noisy for engine calls).
- **npm workspaces** (`shared`, `server`) with **tsx** to run TypeScript directly; no build step until
  match workers need bundling (milestone 4).
- **TypeScript `strict` + `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes`**, ESLint
  `strict` preset, `no-explicit-any` as error.

## Shared data

- **Configs are mirrored into `client/data/`** by `npm run sync:client` because Godot exports can only
  package files under `res://`. Copies are committed (the client opens standalone) and CI fails on drift.
- **JSON Schema subset** (documented in `shared/schemas/common.md`) so a ~120-line GDScript validator
  enforces exactly what Ajv enforces on the server. Cross-field rules (unique ids, C/Q/E/X ordering,
  burst settings) live in `shared/src/config.ts`.
- **Weapon headshot multipliers**: table rule (×4 rifles/sidearms, ×3 SMG/heavy/shotgun) except
  snipers, which the spec leaves unspecified: Shrike ×2 (75→150, one-taps heavy-shield heads per
  "one-tap head"), Longbow ×1.7 (body already kills). Knife ×1.
- **Pellet notation**: "8×11 pellets" read as 8 pellets × 11 damage (Grifter 4×20, Mauler 9×10).
- **Recoil patterns** are generated once by a deterministic formula (vertical climb for ~8 shots, then
  a sinusoidal horizontal wander) and stored as data; they will be hand-tuned in milestone 3.
- **Ability damage pillar** ("never more than a rifle body shot") applied per hit for non-ultimates:
  Proximity Charge tuned to 40. Ultimates the spec defines as lethal (Talon Barrage, Eruption) keep
  their heavier values.

## Protocol

- **Schema-first protocol** in `shared/protocol/messages.json`; `generate.ts` emits the TS codec and
  the GDScript codec. Golden vectors (`shared/tests/protocol/vectors.json`) are verified byte-for-byte
  by both Vitest and the GDScript test runner.
- Little-endian; frame = `u8 messageId` + fields. Strings/bytes: `u16` length prefix.
  Arrays: `u16` count with a schema max enforced on both encode and decode.
- **Quantisation**: positions i32 millimetres, velocities i16 at 1 mm/s (±32.767 m/s), angles u16
  turn fraction decoded to (−π, π]. Rounding is `floor(x + 0.5)` in both languages (JS `Math.round`
  and GDScript `roundi` differ on negative halves).
- **Client floats are 32-bit** (`Vector3`), the server is 64-bit. Milestone 4's TS movement port must
  use `Math.fround` at the same points the GDScript sim stores into `Vector3`, or parity vectors will
  drift; the 1 mm tolerance covers the rest.
- **Reliable vs unreliable** is a per-message `channel` flag already in the schema. Until milestone 4
  adds the in-socket sequence/ack layer, everything rides the WebSocket (which is reliable anyway).
- **Snapshot delta compression** (`baseTick` field reserved) lands in milestone 4.

## Server

- **Fixed tick loop**: absolute-deadline scheduling on `process.hrtime.bigint()`; `setTimeout` until
  ~1.5 ms before the deadline, then `setImmediate` spins. After a stall it runs at most 8 catch-up
  ticks, then skips ahead (counted in `lateTicks`). Measured: 64 ± 1 ticks/s, no cumulative drift.
- **`ws`** for the gateway now (pure JS, zero native build friction). uWebSockets.js stays an option
  if profiling at 200 matches (milestone 10) shows the gateway is the bottleneck.
- Gateway `maxPayload` 4 KiB, binary frames only, `Hello` with matching `protocolVersion` required
  before any other message; violations get `Disconnect{reason}` and a 1008 close.

## Rendering and quality

- **Fidelity tiers are data** (`shared/config/quality.json`) mirroring the §9.3 table. The
  Compatibility renderer always gets `web`; Forward+ defaults to `medium` and never gets `web`.
- Shader global `quality_tier` (int 0–4) declared in `project.godot`; master shaders include
  `res://shaders/include/quality.gdshaderinc`.
- **Tonemapper: AgX** for the test scene (keeps saturated terracotta/teal from clipping to yellow/cyan
  the way ACES does). Final per-map choice happens in the milestone-2 look-dev comparison.
- **LightmapGI bake automation**: Godot has no script API for baking, so the `bp_tools` editor plugin
  presses the editor's own *Bake Lightmaps* button when `BP_BAKE_SCENES` is set and answers the
  first-bake save dialog (`tools/bake-lightmaps.sh`). It runs with a display (Xvfb in CI/cloud) on a
  RenderingDevice renderer; software Vulkan (lavapipe) works, just slowly.

### Milestone-1 check: lightmaps in the Compatibility renderer (Godot 4.7)

- **Baking** requires a RenderingDevice renderer (Forward+/Mobile). Verified: the test courtyard bakes
  headlessly under Xvfb + lavapipe in 272 s (3 bounces, high quality, denoiser on, texel scale 2).
- **Rendering**: the baked `.lmbake` loads and renders in **both** Forward+ and gl_compatibility.
  See `qa/screens/2026-11-23/lightmap_test_*.png`. Shadowed (lightmap-only) areas match within
  1–3/255 sRGB between renderers, so **baked lighting is renderer-independent**. ✅
- **Two Compatibility-specific differences found** (mean sRGB over the same screen regions, 960×540,
  experiments in `qa/screens/2026-11-23/renderer-parity/`):

  | Case | Sunlit floor | Sunlit terracotta | Shaded wall |
  |------|--------------|-------------------|-------------|
  | Forward+ (medium) | 192,174,156 | 212,118,73 | 143,129,124 |
  | Compat (web tier) | 224,211,198 | 248,168,126 | 143,130,124 |
  | Compat, glow off | 208,207,197 | 217,157,108 | 143,130,125 |
  | Compat, glow off, **sun shadows off** | **192,174,155** | **212,118,72** | 143,130,125 |

  1. **Glow** is roughly twice as strong in Compatibility with identical settings.
  2. **A shadow-casting DirectionalLight3D adds a cool, desaturating lift to sunlit surfaces** in
     Compatibility (+16,+33,+41 on the floor). With sun shadows off the renderers match to 1/255.
     Not caused by fog, specular, SSAO or the lightmap (each ruled out by toggling it).
  Also: Compatibility's single 2048 cascade over 80 m shows saw-tooth shadow edges/acne on low cover.
- **Plan (milestone 2 look-dev, before art sign-off)**: (a) per-renderer environment compensation in
  `QualityManager.apply_environment()` (glow intensity/threshold for Compatibility), calibrated
  against a grey-card scene; (b) try LightmapGI **shadowmask** mode (static sun shadows baked,
  real-time shadows only for dynamic objects) and/or a shorter `directional_shadow_max_distance`
  with tuned normal bias on web; (c) check whether (2) is an engine bug and report it upstream with a
  minimal repro if so.
- Consequence: maps are baked on desktop (Forward+) and the same lightmap ships to both builds, as
  the spec's "same baked lighting" rule requires.

## Web build

- **Single-threaded web export by default** (preset `Web`), threaded preset `Web (threaded)` behind
  COOP/COEP (nginx `/threaded/` location). Pick after profiling (milestone 10).
- **Desktop VRAM formats only on web** (S3TC/BPTC). The spec's browser target is a laptop. ETC2/ASTC
  doubled the pack (217 MB) and only helps mobile browsers, which are not a target.
  *(Changed in milestone 10.)*
- **WASM SIMD**: Godot 4.7's official web templates are built by Emscripten with SIMD disabled and
  expose no export toggle. Enabling it means custom templates (`scons platform=web` with
  `-msimd128`); deferred until profiling shows the CPU is the web bottleneck.
- **Half-resolution textures on web**: Godot has no per-platform texture size import override.
  `tools/export-web.sh` exports from a staging copy whose 3D texture imports get
  `process/size_limit=512` (sources are 1024²). UI, font and VFX textures stay full size.
- **Hashed web filenames**: after export, the engine JS/WASM, pack and worklets are renamed
  `index.<sha256-12>.*` and `index.html` is rewritten. This is what lets nginx serve them `immutable`.
  Result: a 75 MB pack (26 MB gzipped) plus 10 MB gzipped WASM.
- **Branded loading shell** `client/web/shell.html` (custom HTML shell) with a real byte-progress
  bar, the logo lock-up and a readable missing-feature notice.
- Web server URL: `?server=wss://host:port` query parameter, else same host on port 7350.

## UI

- **Theme generated from code** (`addons/bp_tools/generate_theme.gd` → `breachpoint_theme.tres`)
  from `UIPalette`, so palette changes are one edit and scenes never hard-code colours.
- **Input actions are registered at runtime** by `Settings.apply_bindings()` from a defaults table,
  with user overrides in `user://settings.cfg` — keeps rebinding data-driven.
- Audio bus layout built at runtime by the `Audio` autoload (Master limiter, Music side-chained to
  Voice) instead of a hand-edited `.tres`.

## Art pipeline (milestones 2–9)

- **No Blender in the build container.** All art is generated from code so it stays reproducible and
  original:
  - `tools/texgen` makes numpy PBR sets (albedo, normal, ORM).
  - `tools/sfxgen` synthesises the WAVs.
  - `MeshKit` builds chamfered meshes. Vertex alpha 0 marks bevel edges for edge wear.
  - `MapBuilder` merges geometry per material, unwraps UV2, and exports yaw-only OBB collision for the
    server.
  - Agents and weapons are parametric (`AgentLooks`, `WeaponBuilder.RECIPES`).
- **Map layouts are walk-rect lists.** `LayoutFill` turns everything else into building mass with
  facades facing the walkable space. Nav rects for bots come from the same rects.
- **NEON DISTRICT street lights are dynamic and unshadowed.** At night, static lights would leave the
  map black until a bake exists. The LightmapGI pass adds moon bounce only. Compatibility's per-object
  light limit (8) is respected by spacing.

## Replays, anti-cheat, comms (milestone 10)

- **Replays record snapshots plus broadcast events, not inputs.**
  - The server stream is the protocol itself: an unculled snapshot every 3rd tick plus every broadcast
    message, gzip-streamed to `.bpr`. The viewer reuses the client codec and `RemotePlayer`.
  - Re-simulating inputs would tie old replays to the sim version.
  - Size: about 2.5 MB per full match. Kept 14 days. Players of a match may download it.
- **Anti-cheat produces review flags, never bans.**
  - Detectors: reaction time from re-acquisition to first hit, snap-to-head, headshot ratio and
    accuracy. Thresholds are in `match.json → antiCheat`.
  - Flags go to `anticheat_flags` next to player `reports`. A reviewer watches the replay.
- **Voice runs over WebRTC data channels, not media tracks.**
  - Godot's WebRTC API has no audio tracks. Push-to-talk audio is 16 kHz G.711 µ-law in 20 ms
    frames, sent unordered with no retransmits.
  - Desktop needs the webrtc-native GDExtension (probed at runtime). Without it, or until a channel
    opens, the match server relays `VoiceData` to teammates only.
  - No STUN server by default. Configure one in Settings → `comms.stun_server`.
- **Fog-of-war line of sight is reused over time.**
  - Visible results hold for 3 ticks; hidden ones are rechecked every 2nd tick. The cache is cleared
    when smokes or walls change.
  - This halved per-match tick cost (`qa/perf/2026-11-23-m10-load.md`).
- **Matchmade matches end; quick servers cycle.** Each cycle gets its own match id (`<id>-<n>`) for
  stats and replays.
- **Snapshot delta compression is deferred.** The spec's bandwidth target is under 25 KB/s down per
  player in a full 10-player fight. The load test measures about 8 KB/s (64 kbit/s) per client with
  full snapshots, fog-of-war culling and quantised fields. Deltas against `baseTick` stay as an
  optimisation: the field is reserved and currently always 0.
- **Readability metric: silhouette-edge contrast (owner decision 2026-11-24).**
  - `scenes/dev/readability.tscn` stands an enemy agent about 10 m into every bookmark view (chest
    and knees visible) and renders at 1080p with TAA off (MSAA 4×).
  - It takes the agent mask from a with/without diff, keeping the largest region only, and excludes
    glow, SSR and the agent's shadow.
  - At every outline pixel it compares the 2 px boundary band with the background 2 px outside, as a
    WCAG ratio. Pass = median ≥ 3:1. The report also gives p25, the share of the outline ≥ 3:1, and
    the old mean-luminance "fill" ratio.
  - Superseded the mean-luminance metric, which daylight maps could only pass with near-black or
    near-white characters.
- **Character readability levers (all per map, `MapRuntime` exports → shader globals):**
  - `character_fill`: a shadowless, camera-aligned fill light that only reaches the character layer.
  - `character_lift`: albedo self-illumination.
  - `character_value_floor`: raises dark albedo.
  - `character_outline` / `character_outline_light` / `character_outline_px`: a two-tone screen-space
    hull outline (`M_CharacterOutline`). A dark inner line separates from bright walls; a light outer
    line at twice the width separates from dark ones.
  - NEON (night) uses fill 7, lift 3 and floor 0.3, with no outline. SOLSTICE (day) uses only the
    2 px two-tone outline.
  - Outlines are neutral for every character. The red enemy outline from spec §4.4 still appears only
    when revealed.
