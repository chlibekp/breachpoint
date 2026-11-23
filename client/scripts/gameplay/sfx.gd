## Sound playback (spec §16): random variants, pooled 3D players with distance attenuation and
## occlusion (sounds behind walls are low-passed and quieter), layered weapon shots
## (mech + body + indoor/outdoor tail, distant variant beyond 30 m), and 2D UI sounds.
class_name Sfx
extends RefCounted

const POOL_3D := 40
const POOL_2D := 12
const DISTANT_RANGE := 30.0

static var _manifest: Dictionary = {}
static var _streams: Dictionary = {}
static var _pool3d: Array[AudioStreamPlayer3D] = []
static var _pool2d: Array[AudioStreamPlayer] = []
static var _i3 := 0
static var _i2 := 0
static var world: SimWorld = null  ## for occlusion + indoor/outdoor checks
static var listener: Node3D = null


static func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


static func _ensure() -> void:
	if not _pool3d.is_empty():
		return
	_manifest = SharedConfig.read_json("res://assets/sfx/manifest.json")
	var holder := Node.new()
	holder.name = "SfxPool"
	_root().add_child.call_deferred(holder)
	for i: int in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.panning_strength = 1.2
		holder.add_child(p)
		_pool3d.append(p)
	for i: int in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		holder.add_child(p2)
		_pool2d.append(p2)


## Picks a stream: exact `name`, or a random `name_<n>` variant.
static func stream(group: String, sfx_name: String) -> AudioStream:
	_ensure()
	var names: Array = _manifest.get(group, [])
	var exact := "SFX_%s" % sfx_name
	var chosen := ""
	if exact in names:
		chosen = exact
	else:
		var variants: Array = names.filter(func(n: String) -> bool: return n.begins_with(exact + "_") and n.substr(exact.length() + 1).is_valid_int())
		if variants.is_empty():
			return null
		chosen = variants[randi() % variants.size()]
	var path := "res://assets/sfx/%s/%s.wav" % [group, chosen]
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]


static func play_2d(group: String, sfx_name: String, volume_db: float = 0.0, bus: String = "UI") -> void:
	var s := stream(group, sfx_name)
	if s == null:
		return
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	if not p.is_inside_tree():
		return
	p.stream = s
	p.volume_db = volume_db
	p.bus = bus
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()


static func play_3d(group: String, sfx_name: String, pos: Vector3, volume_db: float = 0.0, bus: String = "SFX", max_distance: float = 90.0) -> void:
	var s := stream(group, sfx_name)
	if s == null:
		return
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	if not p.is_inside_tree():
		return
	p.stream = s
	p.global_position = pos
	p.max_distance = max_distance
	p.bus = bus
	p.pitch_scale = randf_range(0.96, 1.04)
	var occluded := _occluded(pos)
	p.volume_db = volume_db - (5.0 if occluded else 0.0)
	p.attenuation_filter_cutoff_hz = 1400.0 if occluded else 20500.0
	p.play()


static func _occluded(pos: Vector3) -> bool:
	if world == null or listener == null or not is_instance_valid(listener):
		return false
	var from := listener.global_position
	var to := pos + Vector3(0, 0.3, 0)
	var dir := to - from
	var dist := dir.length()
	if dist < 1.0:
		return false
	return not world.raycast(from.x, from.y, from.z, dir.x / dist, dir.y / dist, dir.z / dist, dist - 0.5).is_empty()


static func is_indoor(pos: Vector3) -> bool:
	if world == null:
		return false
	return not world.raycast(pos.x, pos.y + 1.0, pos.z, 0, 1, 0, 8.0).is_empty()


## Layered gunshot. `local` = fired by the listener (adds the close mechanical layer, 2D-ish).
static func gunshot(weapon_id: String, pos: Vector3, local: bool) -> void:
	var dist := 0.0 if listener == null or not is_instance_valid(listener) else listener.global_position.distance_to(pos)
	var tail := "tail_in" if is_indoor(pos) else "tail_out"
	if local:
		play_2d("weapons", "%s_mech" % weapon_id, -6.0, "Weapons")
		play_2d("weapons", "%s_body" % weapon_id, -1.0, "Weapons")
		play_2d("weapons", "%s_%s" % [weapon_id, tail], -7.0, "Weapons")
		return
	if dist > DISTANT_RANGE:
		play_3d("weapons", "%s_distant" % weapon_id, pos, 2.0, "Weapons", 250.0)
	else:
		play_3d("weapons", "%s_body" % weapon_id, pos, 2.0, "Weapons", 120.0)
	play_3d("weapons", "%s_%s" % [weapon_id, tail], pos, -2.0, "Weapons", 200.0)
