## UI palette and type scale (spec 15.1). The Theme generator reads these; scenes must use the
## Theme (and its type variations) rather than hard-coded colours or fonts.
class_name UIPalette
extends RefCounted

const PANEL := Color("#0F1923")
const PANEL_ALPHA := 0.85
const PANEL_RAISED := Color("#18252F")
const LINE := Color("#ECE8E1", 0.14)
const TEXT := Color("#ECE8E1")
const TEXT_MUTED := Color("#ECE8E1", 0.6)
const ACCENT := Color("#FF4655")
const ACCENT_HOVER := Color("#FF5E6B")
const ALLY := Color("#3FE0D0")
const OK := Color("#3FE0D0")
const WARN := Color("#F2B632")
const FAIL := Color("#FF4655")

const FONT_HEADING := "res://assets/fonts/ChakraPetch-Bold.ttf"
const FONT_HEADING_SEMI := "res://assets/fonts/ChakraPetch-SemiBold.ttf"
const FONT_BODY := "res://assets/fonts/Inter-Variable.ttf"

const SIZE_BODY := 18
const SIZE_SMALL := 14
const SIZE_H3 := 20
const SIZE_H2 := 28
const SIZE_TITLE := 96
