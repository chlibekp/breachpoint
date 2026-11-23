## Root script for every playable map scene. Applies the active quality tier to the map's
## environment/sun/particles and exposes the map's meta (spawns, sites, bookmarks).
class_name MapRuntime
extends Node3D

@export var map_id: String = ""
## Readability fill (spec 4.4, definition of done: character contrast >= 3:1). A shadowless directional
## light that only reaches character meshes (AgentRig.CHARACTER_LAYER), aimed from just behind and
## above the active camera, so agents stand out on dark maps. 0 = off (daylight maps).
@export var character_fill: float = 0.0
@export var character_fill_color: Color = Color(1.0, 0.96, 0.9)
## Self-illumination for characters as a fraction of albedo (global `character_lift`), lifting the
## dark parts of outfits that a fill light barely moves.
@export var character_lift: float = 0.0
## Raises dark character albedo toward mid-tones on dark maps (global `character_value_floor`).
@export var character_value_floor: float = 0.0

const SPIN_RATE := 0.08

var meta: Dictionary = {}
var _spinners: Array[Node3D] = []
var _fill: DirectionalLight3D
const FILL_TILT := 0.35  ## radians: the fill comes from slightly above the eye line


func _ready() -> void:
	meta = load_meta(map_id)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		QualityManager.apply_environment(we.environment)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		QualityManager.apply_sun(sun)
	QualityManager.convert_particles(self)
	for c: Node in get_children():
		if c.name.begins_with("Spin_") and c is Node3D:
			_spinners.append(c)
	RenderingServer.global_shader_parameter_set("character_lift", character_lift)
	RenderingServer.global_shader_parameter_set("character_value_floor", character_value_floor)
	if character_fill > 0.0:
		_fill = DirectionalLight3D.new()
		_fill.name = "CharacterFill"
		_fill.light_energy = character_fill
		_fill.light_color = character_fill_color
		_fill.light_cull_mask = AgentRig.CHARACTER_LAYER
		_fill.shadow_enabled = false
		_fill.light_bake_mode = Light3D.BAKE_DISABLED
		_fill.light_specular = 0.3
		add_child(_fill)
	set_process(not _spinners.is_empty() or _fill != null)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("character_lift", 0.0)
	RenderingServer.global_shader_parameter_set("character_value_floor", 0.0)


## Stops ambient animation (QA captures that diff frames).
func freeze_ambient() -> void:
	_spinners.clear()


## Slow ambient rotation for set-dressing nodes named "Spin_*" (e.g. the NEON monolith).
func _process(delta: float) -> void:
	for n: Node3D in _spinners:
		n.rotate_y(delta * SPIN_RATE)
	if _fill != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var r := cam.global_rotation
			_fill.global_rotation = Vector3(r.x - FILL_TILT, r.y, 0.0)


static func load_meta(id: String) -> Dictionary:
	var path := "res://data/maps/%s.meta.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func bookmarks() -> Array:
	return meta.get("bookmarks", [])
