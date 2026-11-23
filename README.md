# BREACHPOINT

A 5v5 round-based tactical hero shooter: Godot 4 client (desktop Forward+ and browser WebGL2),
authoritative Node.js/TypeScript game server, and shared data/protocol definitions.

- Spec: [`docs/prompt.md`](docs/prompt.md) — the complete design document.
- **Progress / where to pick up: [`docs/PROGRESS.md`](docs/PROGRESS.md)**
- Decisions the spec left open: [`docs/DECISIONS.md`](docs/DECISIONS.md)
- Licences: [`docs/CREDITS.md`](docs/CREDITS.md)

## Pinned versions

| Tool    | Version                                                                                       |
| ------- | --------------------------------------------------------------------------------------------- |
| Godot   | **4.7-stable** (`4.7.stable.official.5b4e0cb0f`) — also in [`.godot-version`](.godot-version) |
| Node.js | 22 LTS                                                                                        |

## Layout

```
client/   Godot project (scenes, scripts, shaders, assets, addons/bp_tools pipeline tools)
server/   TypeScript: gateway/, match/ (64 Hz worker loop), sim/ (pure deterministic sim), services/
shared/   config/*.json + schemas/ (data), protocol/ (schema + generator), tests/ (golden vectors)
docs/     spec, decisions, credits, art notes, map docs
qa/       screenshot captures and perf reports
docker/   Dockerfiles and web server config
tools/    repo scripts (Godot wrapper, client data sync, lightmap baking, web export)
```

## Quick start

```bash
npm ci
```

```bash
npm run ci
```

```bash
npm run server:dev
```

Godot (set `GODOT_BIN` to your 4.7 binary, or put `godot` on PATH):

```bash
GODOT_BIN=/path/to/godot bash tools/godot.sh --path client
```

```bash
GODOT_BIN=/path/to/godot npm run godot:test
```

Exports (export templates for 4.7 must be installed):

```bash
GODOT_BIN=/path/to/godot bash tools/export.sh
```

Then serve the web build locally (single-threaded, no special headers needed):

```bash
npx serve client/build/web -l 8080
```

## Data flow

- Edit balance/data only in `shared/config/*.json`; schemas in `shared/schemas/`.
  `npm run sync:client` mirrors them into `client/data/` (Godot can only package `res://`).
- Edit the wire protocol only in `shared/protocol/messages.json`; `npm run protocol:gen`
  regenerates `shared/protocol/generated/protocol.ts` and `client/scripts/net/generated/protocol.gd`.
- CI fails if generated or mirrored files drift (`npm run check:generated`).
