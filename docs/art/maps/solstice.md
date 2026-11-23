# SOLSTICE — palette and lighting (written before modelling, spec §4.2)

References: R1 (warm plaster courtyard, light split), R2 (terracotta town, vista), R4 (mossy flagstones).

| Role | Hex | Share | Use |
|------|-----|-------|-----|
| Base | `#EFE3C8` warm cream | ~60% | Lime-washed walls, cornices, stone trims |
| Secondary | `#C8643B` terracotta | ~30% | Roofs, accent walls, awnings, pots |
| Accent | `#2BA6A4` sea teal | ~10% | Shutters, doors, harbour paint, signage |
| Supporting | `#B9AE9A` flagstone, `#8A5A3A` wood, `#D9C9A8` shaded cream | — | Floors, crates, shaded plaster |

Light: golden late-morning sun `#FFE2B8` (~5200 K) at ~38° elevation; sky fill `#5C86C9` → horizon
`#C9D6E3`; turquoise bounce from the bay. Shadows lifted and blue-violet. Rift crystal wave casts faint
violet caustics on the cliffs (milestone 6).

Milestone-1 use: these colours drive the BLOCKOUT_ lightmap test courtyard
(`client/scenes/dev/lightmap_test.tscn`) to check that terracotta bounce reads in the bake.
