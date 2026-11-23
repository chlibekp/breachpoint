## Match loading screen (spec §15): map name over its key art backdrop, the map's callouts (from the
## exported meta), both team rosters with agents, and a gameplay tip. Shown while the map scene loads
## and held for a moment after so players can read their roster.
class_name LoadingScreen
extends CanvasLayer

const TIPS: PackedStringArray = [
	"Utility wins rounds: smoke a sightline before you cross it.",
	"Moving ruins your accuracy. Stop, then shoot.",
	"Footsteps carry. Hold walk to move quietly.",
	"Economy matters: saving one round can buy the next three.",
	"The Breach Charge defuse keeps its half-way checkpoint.",
	"Ping what you see. Your team can't read your mind.",
	"Headshots end fights. Keep your crosshair at head height.",
	"Rift orbs charge your ultimate. Grab them when it's safe.",
]

var _root: Control
var _progress: ProgressBar


func show_match(map_id: String, roster: Dictionary, my_team: int) -> void:
	layer = 40
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ui/menu_backdrop.gdshader")
	bg.material = mat
	_root.add_child(bg)
	var v := VBoxContainer.new()
	v.position = Vector2(80, 70)
	v.add_theme_constant_override("separation", 10)
	_root.add_child(v)
	var tag := Label.new()
	tag.text = "NOW LOADING"
	tag.theme_type_variation = &"AccentLabel"
	v.add_child(tag)
	var title := Label.new()
	title.text = {"neon": "NEON DISTRICT"}.get(map_id, map_id.to_upper())
	title.theme_type_variation = &"HeaderLarge"
	title.add_theme_font_size_override("font_size", 96)
	v.add_child(title)
	var meta := MapRuntime.load_meta(map_id)
	var callouts: Array = []
	for c: Dictionary in meta.get("callouts", []):
		callouts.append(str(c["name"]).to_upper())
	var cl := Label.new()
	cl.text = "  ·  ".join(PackedStringArray(callouts))
	cl.theme_type_variation = &"MutedLabel"
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD
	cl.custom_minimum_size = Vector2(1100, 0)
	v.add_child(cl)
	var teams := HBoxContainer.new()
	teams.position = Vector2(80, 420)
	teams.add_theme_constant_override("separation", 120)
	_root.add_child(teams)
	for team: int in [my_team, 1 - my_team]:
		var col := VBoxContainer.new()
		var h := Label.new()
		h.text = "YOUR TEAM" if team == my_team else "OPPONENTS"
		h.theme_type_variation = &"AccentLabel"
		h.add_theme_color_override("font_color", Color("#3FE0D0") if team == my_team else Color("#FF4655"))
		col.add_child(h)
		for id: int in roster:
			var e: Dictionary = roster[id]
			if int(e["team"]) != team:
				continue
			var l := Label.new()
			l.text = "%s   %s" % [str(e["name"]), str(e["agent"]).to_upper()]
			l.theme_type_variation = &"ValueLabel"
			col.add_child(l)
		teams.add_child(col)
	var tip := Label.new()
	tip.text = "TIP  ·  " + TIPS[randi() % TIPS.size()]
	tip.theme_type_variation = &"ValueLabel"
	tip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip.position = Vector2(80, -110)
	_root.add_child(tip)
	_progress = ProgressBar.new()
	_progress.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_progress.offset_left = 80
	_progress.offset_right = -80
	_progress.offset_top = -60
	_progress.offset_bottom = -52
	_progress.show_percentage = false
	_progress.value = 10
	_root.add_child(_progress)


func set_progress(p: float) -> void:
	if _progress != null:
		_progress.value = clampf(p * 100.0, 0.0, 100.0)


func finish(hold_seconds: float = 2.0) -> void:
	set_progress(1.0)
	var tw := create_tween()
	tw.tween_interval(hold_seconds)
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)
