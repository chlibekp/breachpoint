## Root script for every playable map scene. Applies the active quality tier to the map's
## environment/sun/particles and exposes the map's meta (spawns, sites, bookmarks).
class_name MapRuntime
extends Node3D

@export var map_id: String = ""

const SPIN_RATE := 0.08

var meta: Dictionary = {}
var _spinners: Array[Node3D] = []


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
	set_process(not _spinners.is_empty())


## Slow ambient rotation for set-dressing nodes named "Spin_*" (e.g. the NEON monolith).
func _process(delta: float) -> void:
	for n: Node3D in _spinners:
		n.rotate_y(delta * SPIN_RATE)


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
