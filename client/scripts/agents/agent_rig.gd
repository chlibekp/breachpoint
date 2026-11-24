## AgentRig: the shared humanoid rig for every agent (spec §6.2: one skeleton, retargetable,
## identical hitboxes). Bones are Node3D joints so the procedural animator and the code-built
## body parts (AgentLooks) work the same on desktop and web. Model faces -Z, origin at the feet,
## 1.8 m tall (~7.5 heads).
class_name AgentRig
extends Node3D

## Render layer bit for character meshes; MapRuntime's character fill light only lights this layer.
const CHARACTER_LAYER := 4

## bone -> [parent, local rest position]
const BONES: Dictionary = {
	"hips": ["", Vector3(0, 0.96, 0)],
	"spine": ["hips", Vector3(0, 0.1, 0)],
	"chest": ["spine", Vector3(0, 0.2, 0)],
	"neck": ["chest", Vector3(0, 0.24, 0)],
	"head": ["neck", Vector3(0, 0.09, 0)],
	"shoulder_l": ["chest", Vector3(-0.19, 0.17, 0)],
	"upper_arm_l": ["shoulder_l", Vector3(-0.06, 0, 0)],
	"forearm_l": ["upper_arm_l", Vector3(0, -0.29, 0)],
	"hand_l": ["forearm_l", Vector3(0, -0.26, 0)],
	"shoulder_r": ["chest", Vector3(0.19, 0.17, 0)],
	"upper_arm_r": ["shoulder_r", Vector3(0.06, 0, 0)],
	"forearm_r": ["upper_arm_r", Vector3(0, -0.29, 0)],
	"hand_r": ["forearm_r", Vector3(0, -0.26, 0)],
	"thigh_l": ["hips", Vector3(-0.1, -0.05, 0)],
	"shin_l": ["thigh_l", Vector3(0, -0.43, 0)],
	"foot_l": ["shin_l", Vector3(0, -0.43, 0)],
	"thigh_r": ["hips", Vector3(0.1, -0.05, 0)],
	"shin_r": ["thigh_r", Vector3(0, -0.43, 0)],
	"foot_r": ["shin_r", Vector3(0, -0.43, 0)],
}

var bones: Dictionary = {}  ## name -> Node3D
var rest: Dictionary = {}  ## name -> Vector3
var materials: Dictionary = {}  ## material id -> ShaderMaterial (M_Character instances)
var weapon_socket: Node3D
var agent_id: String = ""
var _batches: Dictionary = {}  ## "bone|material id" -> [FormKit, ShaderMaterial, bone]
var mat_specs: Dictionary = {}  ## material id -> palette spec (for cached rebuilds)
var _tints: Array = []  ## [material id, rig-space centre, radius, Color]
## Stylisation scale baked into meshes per bone (bigger head, hands and feet read at range).
var bone_scale: Dictionary = {"head": 1.11, "hand_l": 1.1, "hand_r": 1.1, "foot_l": 1.1, "foot_r": 1.1}


func _init() -> void:
	name = "AgentRig"
	for bone_name: String in BONES:
		var spec: Array = BONES[bone_name]
		var n := Node3D.new()
		n.name = bone_name
		n.position = spec[1]
		rest[bone_name] = spec[1]
		var parent: Node3D = self if spec[0] == "" else bones[spec[0]]
		parent.add_child(n)
		bones[bone_name] = n
	weapon_socket = Node3D.new()
	weapon_socket.name = "weapon_socket"
	bones["hand_r"].add_child(weapon_socket)


func bone(bone_name: String) -> Node3D:
	return bones[bone_name]


## Character material by id; created lazily from a palette entry {color, roughness, metallic,
## emissive, detail (chargen set: Weave, Canvas, Quilt, Knit, Leather, Metal, Skin, Hair), ...}.
static var _outline: ShaderMaterial
static var _detail_cache: Dictionary = {}

## Triplanar detail tiling (tiles per metre) and normal strength per chargen set.
const DETAIL_SCALE: Dictionary = {"Weave": 9.0, "Canvas": 7.0, "Quilt": 4.0, "Knit": 9.0, "Leather": 7.0, "Metal": 3.0, "Skin": 5.0, "Hair": 9.0}
const DETAIL_STRENGTH: Dictionary = {"Weave": 0.55, "Canvas": 0.7, "Quilt": 0.9, "Knit": 0.8, "Leather": 0.55, "Metal": 0.6, "Skin": 0.25, "Hair": 0.7}


## Detail set inferred from the material id when the palette does not name one.
static func _default_detail(id: String, spec: Dictionary) -> String:
	if spec.has("emissive") or spec.get("no_outline", false):
		return ""
	if id == "skin" or id == "lip":
		return "Skin"
	if id.begins_with("hair") or id in ["beard", "brow"]:
		return "Hair"
	if id in ["leather", "boots", "gloves", "hat", "hatband"]:
		return "Leather"
	if id in ["webbing", "weave", "cable"]:
		return "Canvas"
	if id in ["cream", "trim", "hood_in"]:
		return "Knit"
	if id in ["suit"]:
		return "Quilt"
	if float(spec.get("metallic", 0.0)) >= 0.3 or id in ["armor", "metal", "basalt", "brass", "drone", "hardhat", "medwhite", "reflect"]:
		return "Metal"
	return "Weave"


static func _detail_tex(detail_set: String, kind: String) -> Texture2D:
	var path := "res://assets/agents/textures/T_Char%s_%s.png" % [detail_set, kind]
	if not _detail_cache.has(path):
		_detail_cache[path] = load(path)
	return _detail_cache[path]


## Shared silhouette outline pass (driven by per-map globals; invisible when the map disables it).
static func outline_material() -> ShaderMaterial:
	if _outline == null:
		var shader: Shader = load("res://shaders/master/M_CharacterOutline.gdshader")
		var dark := ShaderMaterial.new()
		dark.shader = shader
		_outline = ShaderMaterial.new()  # light outer line first, dark inner line drawn over it
		_outline.shader = shader
		_outline.set_shader_parameter("light_pass", true)
		_outline.next_pass = dark
	return _outline


func material(id: String, spec: Dictionary) -> ShaderMaterial:
	if materials.has(id):
		return materials[id]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/master/M_Character.gdshader")
	m.set_shader_parameter("base_color", spec.get("color", Color(0.7, 0.7, 0.7)))
	m.set_shader_parameter("roughness", spec.get("roughness", 0.6))
	m.set_shader_parameter("metallic", spec.get("metallic", 0.0))
	if spec.has("emissive"):
		m.set_shader_parameter("emissive_color", spec["emissive"])
		m.set_shader_parameter("emissive_energy", spec.get("emissive_energy", 2.0))
	if spec.has("rim"):
		m.set_shader_parameter("rim_color", spec["rim"])
	for key: String in ["sss", "sheen", "toon_mix", "edge_wear", "rim_strength", "detail_strength", "detail_albedo", "detail_cavity", "detail_rough", "terminator_color"]:
		if spec.has(key):
			m.set_shader_parameter(key, spec[key])
	var d: String = spec.get("detail", _default_detail(id, spec))
	if d != "":
		m.set_shader_parameter("use_detail", true)
		m.set_shader_parameter("detail_n", _detail_tex(d, "N"))
		m.set_shader_parameter("detail_v", _detail_tex(d, "V"))
		m.set_shader_parameter("detail_scale", spec.get("detail_scale", DETAIL_SCALE.get(d, 10.0)))
		if not spec.has("detail_strength"):
			m.set_shader_parameter("detail_strength", DETAIL_STRENGTH.get(d, 0.6))
	mat_specs[id] = spec
	# Tiny face details (eyes, lashes, lips) skip the silhouette hull: it would ring them.
	if not spec.get("no_outline", false):
		m.next_pass = outline_material()
	materials[id] = m
	return m


## Adds a mesh part (built by `fn(k: FormKit)` in bone space) to a bone with a material.
## FormKit extends MeshKit, so older `func(k: MeshKit)` builders still work. Parts sharing a bone
## and a material are batched into one mesh (fewer draw calls x3 with the outline passes);
## call finalize() once the outfit is complete.
func part(bone_name: String, mat: ShaderMaterial, fn: Callable, _part_name: String = "") -> void:
	var key := "%s|%d" % [bone_name, mat.get_instance_id()]
	if not _batches.has(key):
		_batches[key] = [FormKit.new(), mat, bone_name]
	var k: FormKit = (_batches[key] as Array)[0]
	k.reset_transform()
	k.color = Color.WHITE
	fn.call(k)
	k.reset_transform()
	k.color = Color.WHITE


## Soft colour tint baked into vertices of material `mat_id` near a rig-space point (blush, warm
## ears and nose, cooler jaw).
func tint(mat_id: String, centre: Vector3, radius: float, color: Color) -> void:
	_tints.append([mat_id, centre, radius, color])


## Rest-pose origin of a bone in rig space (bones carry no rest rotation).
func rest_origin(bone_name: String) -> Vector3:
	var p := Vector3.ZERO
	var b := bone_name
	while b != "":
		p += BONES[b][1]
		b = BONES[b][0]
	return p


## Commits batched parts into one MeshInstance3D per bone and material, baking per-vertex painted
## lighting first: stylisation scale, head-to-toe value gradient, ambient occlusion from a voxel
## occupancy grid of the whole outfit (armpits, under collars, between layers darken), and tints.
## Returns cache entries [bone, ArrayMesh, material id] for AgentLooks.
func finalize() -> Array:
	var surfaces: Array = []  # [bone, mat id, arrays, origin]
	var mat_ids: Dictionary = {}
	for mid: String in materials:
		mat_ids[(materials[mid] as ShaderMaterial).get_instance_id()] = mid
	for key: String in _batches:
		var b: Array = _batches[key]
		var k: FormKit = b[0]
		var mat: ShaderMaterial = b[1]
		var bone_name: String = b[2]
		k.st.index()
		var arr := k.st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var sc: float = bone_scale.get(bone_name, 1.0)
		if sc != 1.0:
			var pivot := Vector3(0, 0.02, 0) if bone_name == "head" else Vector3.ZERO
			# The head also sits a little lower on the neck (stylised, shorter neck).
			var shift := Vector3(0, -0.012, 0) if bone_name == "head" else Vector3.ZERO
			for i: int in verts.size():
				verts[i] = pivot + (verts[i] - pivot) * sc + shift
			arr[Mesh.ARRAY_VERTEX] = verts
		surfaces.append([bone_name, mat_ids.get(mat.get_instance_id(), ""), arr, rest_origin(bone_name)])
	_bake_vertex_light(surfaces)
	var entries: Array = []
	for srf: Array in surfaces:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, srf[2])
		entries.append([srf[0], mesh, srf[1]])
	_batches.clear()
	instance_entries(entries)
	return entries


## Adds MeshInstances for baked entries (also used for cached rebuilds of the same agent).
func instance_entries(entries: Array) -> void:
	for e: Array in entries:
		var bone_name: String = e[0]
		var mi := MeshInstance3D.new()
		mi.name = "mesh_%d" % bones[bone_name].get_child_count()
		mi.mesh = e[1]
		mi.material_override = materials.get(e[2], null)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mi.layers = 1 | CHARACTER_LAYER  # world + character-only fill light (MapRuntime)
		bones[bone_name].add_child(mi)


const _VOX := 0.022
const _VOX_MIN := Vector3(-0.75, -0.05, -0.6)
const _VOX_DIM := Vector3i(68, 100, 55)
const _AO_DIRS: Array[Vector3] = [
	Vector3(0, 1, 0), Vector3(0.7, 0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0, 0.7, 0.7), Vector3(0, 0.7, -0.7),
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0.6, -0.5, 0.6),
	Vector3(-0.6, -0.5, 0.6), Vector3(0.6, -0.5, -0.6), Vector3(-0.6, -0.5, -0.6), Vector3(0, -1, 0),
]
const _AO_STEPS: Array[float] = [0.03, 0.06, 0.1, 0.15]


static func _vox_index(p: Vector3) -> int:
	var c := ((p - _VOX_MIN) / _VOX).floor()
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= _VOX_DIM.x or c.y >= _VOX_DIM.y or c.z >= _VOX_DIM.z:
		return -1
	return int(c.x) + int(c.y) * _VOX_DIM.x + int(c.z) * _VOX_DIM.x * _VOX_DIM.y


func _bake_vertex_light(surfaces: Array) -> void:
	var occ := PackedByteArray()
	occ.resize(_VOX_DIM.x * _VOX_DIM.y * _VOX_DIM.z)
	for srf: Array in surfaces:
		var arr: Array = srf[2]
		var o: Vector3 = srf[3]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for v: Vector3 in verts:
			var i := _vox_index(o + v)
			if i >= 0:
				occ[i] = 1
		for t: int in range(0, idx.size(), 3):
			var c := o + (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var i := _vox_index(c)
			if i >= 0:
				occ[i] = 1
	for srf: Array in surfaces:
		var arr: Array = srf[2]
		var o: Vector3 = srf[3]
		var mid: String = srf[1]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var tints: Array = []
		for t: Array in _tints:
			if t[0] == mid:
				tints.append(t)
		var emissive: bool = (mat_specs.get(mid, {}) as Dictionary).has("emissive")
		for i: int in verts.size():
			var p := o + verts[i]
			var n := norms[i]
			var hits := 0.0
			var total := 0.0
			for d: Vector3 in _AO_DIRS:
				var dn := d.normalized()
				var c := dn.dot(n)
				if c < 0.15:
					continue
				total += c
				for s: int in _AO_STEPS.size():
					var vi := _vox_index(p + n * 0.012 + dn * _AO_STEPS[s])
					if vi >= 0 and occ[vi] == 1:
						hits += c * (1.0 - s * 0.18)
						break
			var ao := 1.0 - clampf(hits / maxf(total, 0.001), 0.0, 1.0) * 0.55
			var grad := lerpf(0.8, 1.0, smoothstep(0.05, 1.45, p.y))
			var shade := 1.0 if emissive else ao * grad
			var col := cols[i]
			var tc := Color(1, 1, 1)
			for t: Array in tints:
				var w := 1.0 - smoothstep(0.0, float(t[2]), p.distance_to(t[1]))
				tc = tc.lerp(t[3], w)
			cols[i] = Color(col.r * shade * tc.r, col.g * shade * tc.g, col.b * shade * tc.b, col.a)
		arr[Mesh.ARRAY_COLOR] = cols


## Enemy-spotted reveal outline (spec §4.4): drives M_Character `reveal` on every material.
func set_reveal(amount: float) -> void:
	for m: ShaderMaterial in materials.values():
		m.set_shader_parameter("reveal", amount)


func set_rim(color: Color, strength: float) -> void:
	for m: ShaderMaterial in materials.values():
		m.set_shader_parameter("rim_color", color)
		m.set_shader_parameter("rim_strength", strength)


func reset_pose() -> void:
	for bone_name: String in bones:
		var n: Node3D = bones[bone_name]
		n.position = rest[bone_name]
		n.basis = Basis.IDENTITY


## Two-bone IK in the rig's space: rotates `upper` and `lower` so `end` reaches `target_world`,
## bending toward `pole_world`. Bones point down their local -Y.
func solve_two_bone(upper_name: String, lower_name: String, end_name: String, target_world: Vector3, pole_world: Vector3) -> void:
	var upper: Node3D = bones[upper_name]
	var lower: Node3D = bones[lower_name]
	var a := upper.global_position
	var l1 := (rest[lower_name] as Vector3).length()
	var l2 := (rest[end_name] as Vector3).length()
	var to_t := target_world - a
	var d := clampf(to_t.length(), 0.05, (l1 + l2) * 0.999)
	var dir := to_t.normalized()
	# Angle at the upper joint from the law of cosines.
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang_a := acos(cos_a)
	var pole_dir := (pole_world - a)
	pole_dir = (pole_dir - dir * pole_dir.dot(dir)).normalized()
	if pole_dir.length() < 0.01:
		pole_dir = Vector3.FORWARD
	var elbow := a + (dir * cos(ang_a) + pole_dir * sin(ang_a)) * l1
	_aim_bone(upper, elbow)
	_aim_bone(lower, a + dir * d)


## Rotates `n` (global) so its local -Y axis points at `target`.
func _aim_bone(n: Node3D, target: Vector3) -> void:
	var down := (target - n.global_position).normalized()
	if down.length() < 0.001:
		return
	var parent_basis := (n.get_parent() as Node3D).global_basis.orthonormalized()
	var y := -down
	var ref := parent_basis.z if absf(y.dot(parent_basis.z)) < 0.95 else parent_basis.x
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	n.global_basis = Basis(x, y, z)
