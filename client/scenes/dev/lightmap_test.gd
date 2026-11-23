## Lightmap verification scene (milestone 1). Applies the active quality tier, shows a status
## overlay, and returns to the boot screen on Escape.
extends Node3D

var _label: Label


func _ready() -> void:
	var env: WorldEnvironment = $WorldEnvironment
	QualityManager.apply_environment(env.environment)
	QualityManager.apply_sun($Sun)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.theme_type_variation = &"HeaderSmall"
	_label.position = Vector2(32, 24)
	layer.add_child(_label)
	var lm: LightmapGI = $LightmapGI
	_label.text = "LIGHTMAP TEST  ·  %s  ·  tier %s  ·  lightmap %s  ·  ESC to return" % [
		RenderingServer.get_current_rendering_method(),
		QualityManager.tier_id().to_upper(),
		"BAKED" if lm.light_data != null else "NOT BAKED",
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		Game.goto("boot")
