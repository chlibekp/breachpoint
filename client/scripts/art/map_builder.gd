## MapBuilder: assembles a code-built map (spec §8.5 pipeline, adapted to the procedural workflow).
## - Geometry is merged per material (few draw calls, spec §8.5 step 7) and gets lightmap UV2.
## - Collision is hand-authored boxes (yaw-only OBBs) with a penetration material tag (spec §8.1),
##   added as StaticBody3D shapes for the client AND exported to /shared/maps for the server (§13.2).
## - Gameplay markers (spawns, sites, plant zones, orbs, callouts, camera bookmarks) go to meta JSON.
class_name MapBuilder
extends RefCounted

## Penetration tags shared with the server (shared/config/materials.json).
const TAGS: PackedStringArray = ["stone", "wood", "metal_thin", "metal_heavy", "glass", "fabric", "invisible"]

var map_id: String
var asset_dir: String  ## res://assets/maps/<id>
var root: Node3D
var kits: Dictionary = {}  ## material key -> MeshKit
var materials: Dictionary = {}  ## material key -> Material
var cast_shadows: Dictionary = {}  ## material key -> bool
## Material keys starting with "vista_" (and any added with lightmapped=false) are not baked:
## distant/background geometry uses probes + sky only (spec §8.6 "lightly lit").
var lightmapped: Dictionary = {}
var boxes: Array[Dictionary] = []  ## {center: Vector3, size: Vector3, yaw: float, tag: String}
var meta: Dictionary = {}


func _init(id: String, scene_root: Node3D) -> void:
	map_id = id
	root = scene_root
	asset_dir = "res://assets/maps/%s" % id
	meta = {
		"map": id, "version": 1, "spawns": {"attack": [], "defense": []}, "sites": [], "plantZones": [],
		"riftOrbs": [], "callouts": [], "bookmarks": [], "buyZones": [], "bounds": {},
	}


# ------------------------------------------------------------------ materials

func add_material(key: String, mat: Material, shadows: bool = true, baked: bool = true) -> void:
	materials[key] = mat
	cast_shadows[key] = shadows
	lightmapped[key] = baked and not key.begins_with("vista_")


func kit(key: String) -> MeshKit:
	if not kits.has(key):
		assert(materials.has(key), "unknown material %s" % key)
		kits[key] = MeshKit.new()
	return kits[key]


## Environment material from a texgen texture set.
static func env_material(tex_dir: String, tex_name: String, tile: float, extra: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/master/M_Env_Standard.gdshader")
	m.set_shader_parameter("albedo_tex", load("%s/T_%s_A.png" % [tex_dir, tex_name]))
	m.set_shader_parameter("normal_tex", load("%s/T_%s_N.png" % [tex_dir, tex_name]))
	m.set_shader_parameter("orm_tex", load("%s/T_%s_ORM.png" % [tex_dir, tex_name]))
	m.set_shader_parameter("tile_size", tile)
	for k: String in extra:
		m.set_shader_parameter(k, extra[k])
	return m


# ------------------------------------------------------------------ geometry + collision

## A solid chamfered block: render mesh in `mat`, collision box tagged `tag`.
func block(mat: String, size: Vector3, center: Vector3, yaw_deg: float = 0.0, tag: String = "stone", bevel: float = 0.04, collide: bool = true, tint: Color = Color.WHITE) -> void:
	var k := kit(mat)
	k.with_color(tint)
	k.set_transform(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), center))
	k.box(size, Vector3.ZERO, bevel)
	k.reset_transform().with_color(Color.WHITE)
	if collide:
		collider(size, center, yaw_deg, tag)


func collider(size: Vector3, center: Vector3, yaw_deg: float = 0.0, tag: String = "stone") -> void:
	assert(tag in TAGS, "bad tag %s" % tag)
	boxes.append({"center": center, "size": size, "yaw": deg_to_rad(yaw_deg), "tag": tag})


## Runs `fn(kit: MeshKit)` with a transform for arbitrary shapes (no collision).
func shape(mat: String, at: Transform3D, fn: Callable, tint: Color = Color.WHITE) -> void:
	var k := kit(mat)
	k.with_color(tint)
	k.set_transform(at)
	fn.call(k)
	k.reset_transform().with_color(Color.WHITE)


static func xf(pos: Vector3, yaw_deg: float = 0.0, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(scale), pos)


# ------------------------------------------------------------------ markers

func spawn(team: String, pos: Vector3, yaw_deg: float) -> void:
	(meta["spawns"][team] as Array).append({"pos": _v(pos), "yaw": deg_to_rad(yaw_deg)})


func site(letter: String, center: Vector3, size: Vector3) -> void:
	(meta["sites"] as Array).append({"name": letter, "center": _v(center), "size": _v(size)})


func plant_zone(letter: String, center: Vector3, size: Vector3) -> void:
	(meta["plantZones"] as Array).append({"site": letter, "center": _v(center), "size": _v(size)})


func buy_zone(team: String, center: Vector3, size: Vector3) -> void:
	(meta["buyZones"] as Array).append({"team": team, "center": _v(center), "size": _v(size)})


func rift_orb(pos: Vector3) -> void:
	(meta["riftOrbs"] as Array).append(_v(pos))


func callout(callout_name: String, center: Vector3, size: Vector3) -> void:
	(meta["callouts"] as Array).append({"name": callout_name, "center": _v(center), "size": _v(size)})


## Navigation rectangle for server bots (walkable lanes; touching rectangles are connected).
func nav_rect(nav_name: String, x0: float, z0: float, x1: float, z1: float) -> void:
	(meta.get_or_add("nav", []) as Array).append({"name": nav_name, "center": _v(Vector3((x0 + x1) * 0.5, 1, (z0 + z1) * 0.5)), "size": _v(Vector3(x1 - x0, 2, z1 - z0))})


func bookmark(bookmark_name: String, pos: Vector3, look_at: Vector3, fov: float = 75.0) -> void:
	(meta["bookmarks"] as Array).append({"name": bookmark_name, "pos": _v(pos), "lookAt": _v(look_at), "fov": fov})


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


# ------------------------------------------------------------------ finalize

## Commits merged meshes (saved as .res), collision, and writes collision/meta files.
## `shared_maps_dir` is an absolute path to /shared/maps (the client copy goes to res://data/maps).
func finalize(shared_maps_dir: String, texel_size: float = 0.12) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_dir + "/meshes"))
	var geo := Node3D.new()
	geo.name = "Geometry"
	_add(root, geo)
	for key: String in kits:
		var k: MeshKit = kits[key]
		var mesh := k.commit(materials[key])
		var baked: bool = lightmapped.get(key, true)
		if baked:
			MeshKit.unwrap_for_lightmap(mesh, texel_size)
		var path := "%s/meshes/SM_%s_%s.res" % [asset_dir, map_id, key]
		ResourceSaver.save(mesh, path)
		mesh.take_over_path(path)
		var mi := MeshInstance3D.new()
		mi.name = "SM_%s" % key
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if baked else GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows.get(key, true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(geo, mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	_add(root, body)
	for i: int in boxes.size():
		var b: Dictionary = boxes[i]
		var cs := CollisionShape3D.new()
		cs.name = "Box%d_%s" % [i, b["tag"]]
		var shape_res := BoxShape3D.new()
		shape_res.size = b["size"]
		cs.shape = shape_res
		cs.transform = Transform3D(Basis(Vector3.UP, b["yaw"]), b["center"])
		cs.set_meta("tag", b["tag"])
		_add(body, cs)
	_write_exports(shared_maps_dir)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


func _bounds() -> AABB:
	var aabb := AABB()
	var first := true
	for b: Dictionary in boxes:
		var c: Vector3 = b["center"]
		var s: Vector3 = b["size"]
		var r := maxf(s.x, s.z) * 0.75
		var box_aabb := AABB(c - Vector3(r, s.y * 0.5, r), Vector3(r * 2, s.y, r * 2))
		aabb = box_aabb if first else aabb.merge(box_aabb)
		first = false
	return aabb


func _write_exports(shared_maps_dir: String) -> void:
	var aabb := _bounds()
	meta["bounds"] = {"min": _v(aabb.position), "max": _v(aabb.end)}
	meta["boxCount"] = boxes.size()
	# Binary collision (spec §13.2): "BPCOL1", u32 count, then per box 7×f32 + u8 tag index.
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data("BPCOL1".to_ascii_buffer())
	buf.put_u32(boxes.size())
	for b: Dictionary in boxes:
		var c: Vector3 = b["center"]
		var s: Vector3 = b["size"]
		for f: float in [c.x, c.y, c.z, s.x * 0.5, s.y * 0.5, s.z * 0.5, float(b["yaw"])]:
			buf.put_float(f)
		buf.put_u8(TAGS.find(b["tag"]))
	var collision_bytes := buf.data_array
	var meta_text := JSON.stringify(meta, "  ", false) + "\n"
	for dir: String in [shared_maps_dir, ProjectSettings.globalize_path("res://data/maps")]:
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open("%s/%s.collision.bin" % [dir, map_id], FileAccess.WRITE)
		f.store_buffer(collision_bytes)
		f.close()
		var m := FileAccess.open("%s/%s.meta.json" % [dir, map_id], FileAccess.WRITE)
		m.store_string(meta_text)
		m.close()
	print("[map_builder] %s: %d materials, %d collision boxes" % [map_id, kits.size(), boxes.size()])
