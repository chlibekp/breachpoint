# Reference study

The four reference images in `docs/` are used for **style only** (spec §1, §2). Nothing is traced,
ripped or recreated: no names, layouts, icons, fonts, characters or assets from the referenced game.
Short IDs used across the art notes:

| ID | File | What it shows |
|----|------|---------------|
| R1 | `docs/valorant1.jpg` | Courtyard firefight: warm plaster/brick, painted floral mural, cloth canopy, first-person rifle |
| R2 | `docs/valorant2.png` | Death recap HUD over a terracotta town, pistol viewmodel, minimap |
| R3 | `docs/valorant3.png` | Party / play lobby UI: tall agent cards, blurred key-art backdrop, top nav |
| R4 | `docs/valorant4.png` | Courtyard with crate, mossy flagstones, smoke dome ability, rifle viewmodel, full HUD |

## What we take from each

**R1 — environment + lighting mood**
- Warm sun / cool shadow split: lit plaster is golden cream, shade is lifted violet-grey, never black.
- Big, simple architectural masses (pillars with clean caps and bases, thick arch surrounds) — the
  60/30/10 large/medium/small detail ratio is visible here.
- Painted albedo with very low frequency: bricks read from shape + soft value shifts, not noise.
- Decorative storytelling (mural, canopy, AC unit, crates) is kept on walls and overhead, out of
  combat lines — matches spec §8.5 set-dressing rule.
- Viewmodel: matte graphite polymer + satin dark metal with one small orange accent decal — this is
  exactly the "PRISM Standard" finish (spec §7.1).

**R2 — readability + HUD hierarchy**
- Environment palette is mid-value and moderately saturated (terracotta, cream, dusty rose sky), so
  saturated UI and character accents pop. We copy the *principle*, not the HUD layout.
- HUD hierarchy: big numerals for health/ammo, thin hairline frames, icons in off-white. Our HUD
  (milestone 3+) uses its own grid and shapes.
- Distant buildings stay simple and slightly desaturated with atmospheric fog — vista ring approach.

**R3 — front-end mood**
- Dark translucent panels over a heavily blurred, desaturated key-art backdrop.
- Uppercase, widely-tracked condensed headings; small muted body text; one hot accent colour.
- Angular frames with cut corners and thin line ornaments.
  → Our boot screen uses a navy gradient backdrop with warm/cool light split, Chakra Petch wide
  headings and cut-corner buttons (see `docs/art/ui.md`).

**R4 — materials + VFX**
- Chunky bevelled crate with clear planks; stone floor with painted moss in cracks — vertex-colour
  blend target for M_Env_Blend (spec §5.3).
- Smoke dome is opaque, painterly, with crisp silhouette edges — reference for M_AbilityWall/smokes
  (spec §9.4): opaque, layered, stylised, not soft particle mush.
- Strong horizontal trims (painted red band at wall height) to structure big plaster walls.

## Global style rules derived
1. Albedo sRGB 40–220; most surfaces 70–190 (spec §4.2). Shadows tinted blue-violet.
2. Detail from shape and normals; reject any texture that reads noisy at 10 m.
3. Characters and VFX own saturation; environments stay one step calmer.
