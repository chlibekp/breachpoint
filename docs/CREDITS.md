# Credits and third-party licences

Every third-party asset, font, sound, library and tool that ships with or builds BREACHPOINT is
listed here with source and licence (spec §2, §5.4, §16). Nothing in this repository comes from
another game. Raw CC0 material must be restyled before use and noted as such.

## Fonts (shipped)

| Asset | Files | Source | Licence |
|-------|-------|--------|---------|
| Chakra Petch (Cadson Demak) | `client/assets/fonts/ChakraPetch-{Bold,SemiBold,Medium}.ttf` | https://github.com/google/fonts/tree/main/ofl/chakrapetch | SIL Open Font License 1.1 (`OFL-ChakraPetch.txt`) |
| Inter (Rasmus Andersson) | `client/assets/fonts/Inter-Variable.ttf` | https://github.com/google/fonts/tree/main/ofl/inter | SIL Open Font License 1.1 (`OFL-Inter.txt`) |

## Engine and runtime libraries

| Component | Use | Licence |
|-----------|-----|---------|
| Godot Engine 4.7-stable | Client engine and export templates | MIT — https://godotengine.org/license |
| Jolt Physics (bundled in Godot) | Client physics | MIT |
| Node.js 22 LTS | Server runtime | MIT |
| ws | Server WebSocket transport | MIT |
| Ajv | JSON Schema validation (server/CI) | MIT |
| TypeScript, tsx, Vitest, ESLint, typescript-eslint, Prettier | Tooling | Apache-2.0 / MIT |

## Textures, models, sounds, music

None yet (milestone 1 uses only primitive BLOCKOUT_ meshes and flat colours).
When added, log: asset, file path(s), source URL, author, licence, and what restyling was done.
