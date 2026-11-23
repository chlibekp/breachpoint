# UI style note (milestone 1)

References: **R3** (front-end mood), **R2** (HUD hierarchy). See `references.md`.

- Panels: `#0F1923` at 85% opacity, 1 px hairline border in off-white at 14% (spec §15.1).
- Text: off-white `#ECE8E1`; muted text same colour at 60%.
- Accent: `#FF4655`-family for primary actions; ally cyan `#3FE0D0` for OK states and focus rings.
- Type: Chakra Petch Bold/SemiBold for headings, uppercase with wide glyph spacing (from R3's
  tracked caps); Inter (variable) for body and numbers.
- Shapes: buttons have two cut corners (top-left, bottom-right) — `corner_detail = 1` gives a
  chamfer rather than a round — which echoes the bevelled-forms rule of spec §4.1.
- Backdrop: shader-driven navy gradient with a warm key glow upper-right and a slow violet Rift glow
  lower-left — a nod to the warm-sun / cool-shadow split (R1) without needing key art yet.
- All values live in `client/scripts/ui/ui_palette.gd` and are baked into
  `client/assets/ui/theme/breachpoint_theme.tres` by `addons/bp_tools/generate_theme.gd`. Scenes use
  theme type variations (`TitleLabel`, `HeaderLarge`, `HeaderSmall`, `MutedLabel`, `ValueLabel`,
  `OkLabel`/`WarnLabel`/`FailLabel`, `PrimaryButton`, `RowPanel`, `AccentBar`) — never raw colours.
