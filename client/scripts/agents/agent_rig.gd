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


## Character material by id; created lazily from a palette entry {color, roughness, metallic, emissive}.
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
	materials[id] = m
	return m


## Adds a mesh part (built by `fn(k: MeshKit)` in bone space) to a bone with a material.
func part(bone_name: String, mat: ShaderMaterial, fn: Callable, part_name: String = "") -> MeshInstance3D:
	var k := MeshKit.new()
	fn.call(k)
	var mi := MeshInstance3D.new()
	mi.name = part_name if part_name != "" else "part_%d" % bones[bone_name].get_child_count()
	mi.mesh = k.commit(mat)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	mi.layers = 1 | CHARACTER_LAYER  # world + character-only fill light (MapRuntime)
	bones[bone_name].add_child(mi)
	return mi


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
