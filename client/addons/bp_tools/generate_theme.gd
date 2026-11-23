## Generates res://assets/ui/theme/breachpoint_theme.tres from UIPalette.
## Run: godot --headless --path client -s res://addons/bp_tools/generate_theme.gd
extends SceneTree

const OUT := "res://assets/ui/theme/breachpoint_theme.tres"


func _init() -> void:
	var theme := Theme.new()
	var body: FontFile = load(UIPalette.FONT_BODY)
	var heading: FontFile = load(UIPalette.FONT_HEADING)
	var heading_semi: FontFile = load(UIPalette.FONT_HEADING_SEMI)

	var body_var := FontVariation.new()
	body_var.base_font = body
	body_var.variation_opentype = {"wght": 450}
	var body_bold := FontVariation.new()
	body_bold.base_font = body
	body_bold.variation_opentype = {"wght": 650}
	var head_wide := FontVariation.new()
	head_wide.base_font = heading
	head_wide.spacing_glyph = 3
	var head_semi_wide := FontVariation.new()
	head_semi_wide.base_font = heading_semi
	head_semi_wide.spacing_glyph = 2

	theme.default_font = body_var
	theme.default_font_size = UIPalette.SIZE_BODY

	# Label
	theme.set_color("font_color", "Label", UIPalette.TEXT)
	# Heading variations
	_variation(theme, "TitleLabel", "Label", head_wide, UIPalette.SIZE_TITLE, UIPalette.TEXT)
	_variation(theme, "HeaderLarge", "Label", head_wide, UIPalette.SIZE_H2, UIPalette.TEXT)
	_variation(theme, "HeaderSmall", "Label", head_semi_wide, UIPalette.SIZE_H3, UIPalette.TEXT)
	_variation(theme, "MutedLabel", "Label", body_var, UIPalette.SIZE_SMALL, UIPalette.TEXT_MUTED)
	_variation(theme, "ValueLabel", "Label", body_bold, UIPalette.SIZE_BODY, UIPalette.TEXT)
	_variation(theme, "OkLabel", "Label", head_semi_wide, UIPalette.SIZE_SMALL, UIPalette.OK)
	_variation(theme, "WarnLabel", "Label", head_semi_wide, UIPalette.SIZE_SMALL, UIPalette.WARN)
	_variation(theme, "FailLabel", "Label", head_semi_wide, UIPalette.SIZE_SMALL, UIPalette.FAIL)
	_variation(theme, "AccentLabel", "Label", head_semi_wide, UIPalette.SIZE_SMALL, UIPalette.ACCENT)

	# Panels: near-black blue at 85%, hairline border, cut corner via corner_detail=1 bevel.
	var panel := _box(Color(UIPalette.PANEL, UIPalette.PANEL_ALPHA), UIPalette.LINE, 1)
	panel.set_content_margin_all(24)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	var row := _box(Color(UIPalette.PANEL_RAISED, 0.6), Color(0, 0, 0, 0), 0)
	row.set_content_margin_all(10)
	row.content_margin_left = 14
	theme.set_type_variation("RowPanel", "PanelContainer")
	theme.set_stylebox("panel", "RowPanel", row)
	var accent_bar := StyleBoxFlat.new()
	accent_bar.bg_color = UIPalette.ACCENT
	theme.set_type_variation("AccentBar", "Panel")
	theme.set_stylebox("panel", "AccentBar", accent_bar)

	# Buttons: outline style; primary variation filled with accent.
	theme.set_font("font", "Button", head_semi_wide)
	theme.set_font_size("font_size", "Button", UIPalette.SIZE_H3)
	for state: String in ["font_color", "font_focus_color"]:
		theme.set_color(state, "Button", UIPalette.TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", UIPalette.TEXT_MUTED)
	theme.set_stylebox("normal", "Button", _button(Color(UIPalette.PANEL, 0.55), Color(UIPalette.TEXT, 0.35)))
	theme.set_stylebox("hover", "Button", _button(Color(UIPalette.PANEL_RAISED, 0.9), UIPalette.TEXT))
	theme.set_stylebox("pressed", "Button", _button(Color(UIPalette.ACCENT, 0.25), UIPalette.ACCENT))
	theme.set_stylebox("disabled", "Button", _button(Color(UIPalette.PANEL, 0.3), Color(UIPalette.TEXT, 0.12)))
	theme.set_stylebox("focus", "Button", _button(Color(0, 0, 0, 0), UIPalette.ALLY))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _button(UIPalette.ACCENT, UIPalette.ACCENT))
	theme.set_stylebox("hover", "PrimaryButton", _button(UIPalette.ACCENT_HOVER, UIPalette.ACCENT_HOVER))
	theme.set_stylebox("pressed", "PrimaryButton", _button(UIPalette.ACCENT.darkened(0.15), UIPalette.ACCENT))

	# Tooltip / line edit basics.
	theme.set_stylebox("panel", "TooltipPanel", panel)
	theme.set_stylebox("normal", "LineEdit", _box(Color(UIPalette.PANEL, 0.9), Color(UIPalette.TEXT, 0.25), 1))

	var err := ResourceSaver.save(theme, OUT)
	print("theme saved: %s (%s)" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _variation(theme: Theme, type_name: String, base: String, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(type_name, base)
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)


func _box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.anti_aliasing = true
	return sb


func _button(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := _box(bg, border, 1)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	# Angular cut on the top-left and bottom-right corners (spec 15.1: sharp cut corners).
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_detail = 1
	return sb
