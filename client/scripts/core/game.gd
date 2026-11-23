## Autoload: top-level game flow, build info and debug view modes (spec 9.5).
extends Node

signal view_mode_changed(mode: int)

enum ViewMode { LIT, GREYSCALE, SILHOUETTE }

const SCENES: Dictionary = {
	"boot": "res://scenes/boot/boot.tscn",
	"lightmap_test": "res://scenes/dev/lightmap_test.tscn",
}

var view_mode: ViewMode = ViewMode.LIT
var _view_layer: CanvasLayer = null
var _view_rect: ColorRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_view_mode_overlay()


func version_string() -> String:
	var engine: Dictionary = Engine.get_version_info()
	return "BREACHPOINT %s · Godot %s · %s" % [
		ProjectSettings.get_setting("application/config/version", "dev"),
		engine.get("string", "?"),
		RenderingServer.get_current_rendering_method(),
	]


func goto(scene_key: String) -> void:
	var path: String = SCENES.get(scene_key, scene_key)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Game.goto(%s) failed: %s" % [path, error_string(err)])


func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	_view_rect.visible = mode == ViewMode.GREYSCALE
	# Silhouette mode is implemented by M_Character/M_Env shaders reading a global in milestone 2.
	view_mode_changed.emit(mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_greyscale"):
		set_view_mode(ViewMode.LIT if view_mode == ViewMode.GREYSCALE else ViewMode.GREYSCALE)
	elif event.is_action_pressed("debug_silhouette"):
		set_view_mode(ViewMode.LIT if view_mode == ViewMode.SILHOUETTE else ViewMode.SILHOUETTE)


func _build_view_mode_overlay() -> void:
	_view_layer = CanvasLayer.new()
	_view_layer.layer = 128
	add_child(_view_layer)
	_view_rect = ColorRect.new()
	_view_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/debug/greyscale_view.gdshader")
	_view_rect.material = mat
	_view_rect.visible = false
	_view_layer.add_child(_view_rect)
