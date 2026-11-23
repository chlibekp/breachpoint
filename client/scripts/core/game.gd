## Autoload: top-level game flow, build info and debug view modes (spec 9.5).
extends Node

signal view_mode_changed(mode: int)

enum ViewMode { LIT, GREYSCALE, SILHOUETTE }

const SCENES: Dictionary = {
	"boot": "res://scenes/boot/boot.tscn",
	"lightmap_test": "res://scenes/dev/lightmap_test.tscn",
	"range": "res://scenes/game/range.tscn",
	"online": "res://scenes/game/online.tscn",
	"lookdev": "res://scenes/dev/lookdev.tscn",
}

var view_mode: ViewMode = ViewMode.LIT
var _view_layer: CanvasLayer = null
var _view_rect: ColorRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_view_mode_overlay()
	var args := parse_user_args(OS.get_cmdline_user_args())
	if args.has("capture"):
		_run_capture.call_deferred(args)


## Parses `-- --key=value --flag` user arguments into a Dictionary.
static func parse_user_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in argv:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


## QA capture (spec 9.5): `godot --path client -- --capture=<scene key or path> --out=<png>
## [--frames=N] [--tier=<id>] [--size=WxH]`. Loads the scene, waits N frames, saves a PNG and quits.
## Also writes average frame time over the wait into <png>.json for quick perf notes.
func _run_capture(args: Dictionary) -> void:
	if args.has("tier"):
		Settings.set_value("video", "tier", str(args["tier"]), false)
	if args.has("size"):
		var wh := str(args["size"]).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	if str(args["capture"]) != "current":
		goto(str(args["capture"]))
	var frames := int(args.get("frames", "90"))
	var t0 := Time.get_ticks_usec()
	for _i: int in frames:
		await get_tree().process_frame
	var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	await RenderingServer.frame_post_draw
	var out := str(args.get("out", "user://capture.png"))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	var meta := {
		"scene": args["capture"], "renderer": RenderingServer.get_current_rendering_method(),
		"tier": QualityManager.tier_id(), "adapter": RenderingServer.get_video_adapter_name(),
		"size": [img.get_width(), img.get_height()], "frames": frames, "avg_frame_ms": avg_ms,
		"engine": Engine.get_version_info()["string"],
	}
	var f := FileAccess.open(out + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
	print("[capture] %s -> %s (%s)" % [args["capture"], out, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


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
