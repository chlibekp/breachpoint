## First-person viewmodel (spec §6.2/§7.2): the agent's own first-person arms (sleeves + gloves per
## agent) holding the weapon, drawn with the fixed 68° viewmodel projection. The third-person body
## is never visible in first person. Procedural layers (sway, inertia, bob, landing dip, strafe tilt,
## recoil spring) and the animation clips are driven by ViewmodelAnimator.
class_name Viewmodel
extends Node3D

const HIP_POSITION := Vector3(0.17, -0.2, -0.42)
const ADS_POSITION := Vector3(0.0, -0.163, -0.3)

var weapon: Node3D
var weapon_id: String = ""
var arms: Dictionary = {}  ## "l"/"r" -> {upper: MeshInstance3D, fore: ..., hand: ...}
var arm_materials: Array[ShaderMaterial] = []
var pivot: Node3D  ## animated by ViewmodelAnimator; weapon is its child


func _init() -> void:
	name = "Viewmodel"
	pivot = Node3D.new()
	pivot.name = "pivot"
	pivot.position = HIP_POSITION
	add_child(pivot)


## Builds arms for `agent_id` and equips `weapon_id` with `skin`.
func setup(agent_id: String, new_weapon_id: String, skin: Dictionary = {}) -> void:
	_build_arms(agent_id)
	equip(new_weapon_id, skin)


func equip(new_weapon_id: String, skin: Dictionary = {}) -> void:
	if weapon != null:
		weapon.queue_free()
	weapon_id = new_weapon_id
	weapon = WeaponBuilder.build(weapon_id, skin)
	pivot.add_child(weapon)
	_mark_viewmodel(weapon)


func _mark_viewmodel(n: Node) -> void:
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = 2  ## viewmodel layer (excluded from reflection probes and world cameras)
		var mat := m.mesh.surface_get_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("viewmodel", true)


func _build_arms(agent_id: String) -> void:
	for side: String in arms:
		for n: Node3D in (arms[side] as Dictionary).values():
			n.queue_free()
	arms.clear()
	arm_materials.clear()
	var look := _arm_look(agent_id)
	var sleeve := _mat(look["sleeve"], 0.75)
	var cuff := _mat(look["cuff"], 0.7)
	var glove := _mat(look["glove"], 0.5)
	var skin := _mat(look["skin"], 0.55)
	for side: String in ["l", "r"]:
		var parts: Dictionary = {}
		var fore := _part(sleeve, func(k: MeshKit) -> void:
			k.capsule(0.043, 0.05, 0.36, Vector3(0, -0.17, 0), 14, 3)
			k.with_color(Color.WHITE)
		)
		var cuff_mi := _part(cuff, func(k: MeshKit) -> void: k.cylinder(0.052, 0.07, Vector3(0, -0.32, 0), 14, 0.015))
		var wrist := _part(skin, func(k: MeshKit) -> void: k.cylinder(0.036, 0.03, Vector3(0, -0.36, 0), 12, 0.008))
		var hand := _part(glove, func(k: MeshKit) -> void:
			k.box(Vector3(0.08, 0.1, 0.038), Vector3(0, -0.05, 0), 0.016)
			# Curled fingers wrapping the grip, chunky knuckle pads (premium glove read).
			k.box(Vector3(0.082, 0.04, 0.06), Vector3(0, -0.105, -0.02), 0.015)
			k.box(Vector3(0.028, 0.06, 0.028), Vector3(0.045, -0.04, -0.025), 0.009)
			k.box(Vector3(0.07, 0.02, 0.012), Vector3(0, -0.07, 0.022), 0.005))
		fore.add_child(cuff_mi)
		fore.add_child(wrist)
		var hand_pivot := Node3D.new()
		hand_pivot.name = "hand_%s" % side
		hand_pivot.position = Vector3(0, -0.37, 0)
		hand_pivot.add_child(hand)
		fore.add_child(hand_pivot)
		add_child(fore)
		parts["fore"] = fore
		parts["hand"] = hand_pivot
		arms[side] = parts


static func _arm_look(agent_id: String) -> Dictionary:
	# Matches AgentLooks (sleeve, cuff/wrist band, glove, skin).
	match agent_id:
		"kestrel":
			return {"sleeve": Color("#F2701A"), "cuff": Color("#D8CBB2"), "glove": Color("#2A2D31"), "skin": Color("#EDC6AA")}
		"mamba":
			return {"sleeve": Color("#22262B"), "cuff": Color("#9BE22B"), "glove": Color("#16181B"), "skin": Color("#5C3826")}
		"vesper":
			return {"sleeve": Color("#43308A"), "cuff": Color("#9A7CF0"), "glove": Color("#241D38"), "skin": Color("#DDAA86")}
		"haldor":
			return {"sleeve": Color("#DDD7CB"), "cuff": Color("#26272B"), "glove": Color("#26272B"), "skin": Color("#EDC6AA")}
		"orin":
			return {"sleeve": Color("#BA845E"), "cuff": Color("#7D6B4E"), "glove": Color("#4A3828"), "skin": Color("#BA845E")}
		"sable":
			return {"sleeve": Color("#2F8CFF"), "cuff": Color("#F4F6FA"), "glove": Color("#DDAA86"), "skin": Color("#DDAA86")}
		"imani":
			return {"sleeve": Color("#33413A"), "cuff": Color("#E8AE2E"), "glove": Color("#262B28"), "skin": Color("#5C3826")}
		"tomas":
			return {"sleeve": Color("#C8743A"), "cuff": Color("#454D55"), "glove": Color("#3A2E28"), "skin": Color("#BA845E")}
	return {"sleeve": Color("#2B3440"), "cuff": Color("#5B6673"), "glove": Color("#30343A"), "skin": Color("#DDAA86")}


func _mat(color: Color, roughness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/master/M_Character.gdshader")
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("viewmodel", true)
	m.set_shader_parameter("rim_strength", 0.15)
	arm_materials.append(m)
	return m


func _part(mat: ShaderMaterial, fn: Callable) -> MeshInstance3D:
	var k := MeshKit.new()
	fn.call(k)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	return mi


## Points each forearm from an off-screen elbow to the weapon's grip / support socket.
func _process(_delta: float) -> void:
	if weapon == null or arms.is_empty():
		return
	var targets := {"r": weapon.get_node_or_null("grip"), "l": weapon.get_node_or_null("left_hand_ik")}
	var elbows := {"r": Vector3(0.33, -0.44, -0.14), "l": Vector3(-0.2, -0.46, -0.36)}
	for side: String in ["l", "r"]:
		var target := targets[side] as Node3D
		if target == null:
			continue
		var fore: Node3D = (arms[side] as Dictionary)["fore"]
		var hand: Node3D = (arms[side] as Dictionary)["hand"]
		var elbow_local: Vector3 = elbows[side] + Vector3(0, 0, pivot.position.z - HIP_POSITION.z) + (pivot.position - HIP_POSITION) * 0.6
		var target_local := to_local(target.global_position)
		var dir := (target_local - elbow_local)
		var length := dir.length()
		var y := -dir.normalized()
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
		var x := y.cross(ref).normalized()
		var z := x.cross(y).normalized()
		fore.transform = Transform3D(Basis(x, y, z), elbow_local)
		fore.scale = Vector3(1, length / 0.37, 1)
		hand.global_basis = target.global_basis.orthonormalized()
		hand.scale = Vector3(1, 0.37 / maxf(length, 0.01), 1)
