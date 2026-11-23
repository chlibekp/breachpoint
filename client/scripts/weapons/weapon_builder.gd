## WeaponBuilder: code-built weapon models (spec §7). Parts are extruded side profiles with chamfered
## rims (1–3 mm bevels), cylinders and boxes, coloured through M_Weapon mask channels in vertex colour
## (R = base finish, G = accent, B = Rift emissive; UV2.x = machined-metal flag) so skins are pure data.
## Moving parts are separate nodes: magazine, charging_handle, trigger, bolt, ejection_cover.
## Sockets: grip (pivot), muzzle, eject, mag, sight_aim, left_hand_ik.
## Local frame: barrel along -Z, +Y up, origin at the grip.
class_name WeaponBuilder
extends RefCounted

const BASE := Color(1, 0, 0, 1)
const ACCENT := Color(0, 1, 0, 1)
const EMIT := Color(0, 0, 1, 1)
## Profile space (x forward, y up) -> weapon space (-Z forward); extrusion axis becomes +X (width).
const PROFILE_BASIS := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))


## Builds a weapon model node for `weapon_id` with the given skin (see WeaponSkins).
static func build(weapon_id: String, skin: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_%s" % weapon_id
	root.set_meta("weapon_id", weapon_id)
	var mat := material(skin, weapon_id)
	match weapon_id:
		"saber":
			_saber(root, mat)
		_:
			_generic(root, mat, weapon_id)
	return root


static func material(skin: Dictionary, weapon_id: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/master/M_Weapon.gdshader")
	var accent := Color(skin.get("accent", _class_accent(weapon_id)))
	m.set_shader_parameter("accent_color", accent)
	for key: String in ["base_color", "metal_color", "emissive_color"]:
		if skin.has(key):
			m.set_shader_parameter(key, Color(skin[key]))
	for key: String in ["base_roughness", "metal_roughness", "base_metallic", "emissive_energy", "clearcoat_amount"]:
		if skin.has(key):
			m.set_shader_parameter(key, skin[key])
	if skin.has("pattern"):
		m.set_shader_parameter("pattern_tex", load(skin["pattern"]))
		m.set_shader_parameter("use_pattern", true)
	return m


static func _class_accent(weapon_id: String) -> String:
	var data: Dictionary = SharedConfig.read_json("res://data/config/weapons.json")
	for w: Dictionary in data.get("weapons", []):
		if w["id"] == weapon_id:
			return w["accentColor"]
	return "#8A9BA8"


# ------------------------------------------------------------------ helpers

static func _kit() -> MeshKit:
	var k := MeshKit.new()
	k.with_color(BASE)
	return k


## Extrudes a side profile (x forward, y up) of width `w`, centred at `offset` (weapon space).
static func profile(k: MeshKit, pts: Array, w: float, offset: Vector3 = Vector3.ZERO, bevel: float = 0.003) -> void:
	var poly := PackedVector2Array()
	for p2: Vector2 in pts:
		poly.append(p2)
	k.set_transform(Transform3D(PROFILE_BASIS, offset))
	k.extrude(poly, w, Vector3.ZERO, bevel)
	k.reset_transform()


## Cylinder along -Z between z0 and z1 (weapon space, z negative forward).
static func tube(k: MeshKit, radius: float, z_start: float, z_end: float, y: float, x: float = 0.0, segments: int = 14, bevel: float = 0.002) -> void:
	var length := absf(z_end - z_start)
	k.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, (z_start + z_end) * 0.5)))
	k.cylinder(radius, length, Vector3.ZERO, segments, bevel)
	k.reset_transform()


static func _mesh_node(parent: Node3D, part_name: String, k: MeshKit, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = k.commit(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _socket(parent: Node3D, socket_name: String, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = socket_name
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


# ------------------------------------------------------------------ Saber (hard-hitting rifle)

static func _saber(root: Node3D, mat: ShaderMaterial) -> void:
	var body := _kit()
	# Upper receiver: machined, angular front, slight step at the rear.
	body.uv2_flag = Vector2(1, 0)
	profile(body, [Vector2(-0.13, 0.0), Vector2(0.2, 0.0), Vector2(0.235, 0.035), Vector2(0.235, 0.085), Vector2(-0.06, 0.092), Vector2(-0.13, 0.075)], 0.048, Vector3(0, 0.03, 0), 0.004)
	# Top rail with teeth.
	profile(body, [Vector2(-0.07, 0.0), Vector2(0.43, 0.0), Vector2(0.43, 0.012), Vector2(-0.07, 0.012)], 0.026, Vector3(0, 0.122, 0), 0.002)
	for i: int in 17:
		body.box(Vector3(0.03, 0.006, 0.012), Vector3(0, 0.137, 0.06 - i * 0.03), 0.001)
	# Barrel + muzzle brake.
	tube(body, 0.012, -0.5, -0.69, 0.07, 0.0, 14)
	tube(body, 0.021, -0.69, -0.77, 0.07, 0.0, 12, 0.004)
	body.uv2_flag = Vector2.ZERO
	# Lower receiver + mag well (polymer).
	profile(body, [Vector2(-0.08, 0.0), Vector2(0.16, 0.0), Vector2(0.17, 0.03), Vector2(-0.08, 0.03)], 0.042, Vector3(0, 0.0, 0), 0.004)
	profile(body, [Vector2(0.02, -0.045), Vector2(0.12, -0.045), Vector2(0.13, 0.0), Vector2(0.01, 0.0)], 0.04, Vector3(0, 0.0, 0), 0.004)
	# Handguard: long, flat-sided with vent windows.
	profile(body, [Vector2(0.235, 0.0), Vector2(0.52, 0.004), Vector2(0.53, 0.025), Vector2(0.52, 0.098), Vector2(0.235, 0.098)], 0.054, Vector3(0, 0.022, 0), 0.006)
	# Pistol grip, angled back.
	profile(body, [Vector2(-0.025, 0.005), Vector2(0.035, 0.005), Vector2(0.005, -0.12), Vector2(-0.055, -0.125), Vector2(-0.06, -0.11)], 0.034, Vector3(0, 0.0, 0), 0.006)
	# Trigger guard.
	profile(body, [Vector2(0.035, -0.0), Vector2(0.1, -0.0), Vector2(0.1, -0.05), Vector2(0.03, -0.05), Vector2(0.03, -0.042), Vector2(0.09, -0.042), Vector2(0.09, -0.008), Vector2(0.035, -0.008)], 0.01, Vector3.ZERO, 0.002)
	# Stock: skeletal polymer stock with cheek riser and butt pad.
	profile(body, [Vector2(-0.43, -0.075), Vector2(-0.38, -0.08), Vector2(-0.2, -0.02), Vector2(-0.13, 0.0), Vector2(-0.13, 0.08), Vector2(-0.3, 0.095), Vector2(-0.43, 0.1)], 0.04, Vector3(0, 0.02, 0), 0.006)
	profile(body, [Vector2(-0.45, -0.085), Vector2(-0.43, -0.085), Vector2(-0.43, 0.105), Vector2(-0.45, 0.105)], 0.046, Vector3(0, 0.02, 0), 0.004)
	# Compact holographic sight.
	profile(body, [Vector2(0.0, 0.0), Vector2(0.11, 0.0), Vector2(0.11, 0.012), Vector2(0.0, 0.012)], 0.036, Vector3(0, 0.143, 0), 0.002)
	profile(body, [Vector2(0.02, 0.0), Vector2(0.05, 0.0), Vector2(0.045, 0.055), Vector2(0.025, 0.055)], 0.05, Vector3(0, 0.15, 0), 0.003)
	profile(body, [Vector2(0.075, 0.0), Vector2(0.105, 0.0), Vector2(0.1, 0.06), Vector2(0.08, 0.06)], 0.05, Vector3(0, 0.15, 0), 0.003)
	body.box(Vector3(0.05, 0.01, 0.1), Vector3(0, 0.21, -0.063), 0.003)
	# Front flip sight post.
	profile(body, [Vector2(0.4, 0.0), Vector2(0.43, 0.0), Vector2(0.425, 0.045), Vector2(0.405, 0.045)], 0.012, Vector3(0, 0.134, 0), 0.002)
	# Accent: receiver side panels in the class accent colour (PRISM Standard, one muted accent).
	body.with_color(ACCENT)
	for sx: float in [-1.0, 1.0]:
		profile(body, [Vector2(-0.05, 0.0), Vector2(0.12, 0.0), Vector2(0.14, 0.04), Vector2(-0.05, 0.04)], 0.004, Vector3(sx * 0.0255, 0.055, 0), 0.0015)
	# Accent stripe on the stock.
	profile(body, [Vector2(-0.34, 0.0), Vector2(-0.2, 0.0), Vector2(-0.2, 0.012), Vector2(-0.34, 0.012)], 0.042, Vector3(0, 0.088, 0), 0.001)
	# Rift emissive strip in the handguard vents + sight reticle.
	body.with_color(EMIT)
	for sx: float in [-1.0, 1.0]:
		for i: int in 3:
			body.box(Vector3(0.003, 0.012, 0.055), Vector3(sx * 0.0275, 0.065, -0.29 - i * 0.075), 0.001)
	body.box(Vector3(0.004, 0.004, 0.002), Vector3(0, 0.185, -0.04), 0.0005)
	body.with_color(BASE)
	# Handguard vent windows (dark recesses): metal flag gives them a different finish.
	body.uv2_flag = Vector2(1, 0)
	for sx: float in [-1.0, 1.0]:
		for i: int in 3:
			body.box(Vector3(0.003, 0.03, 0.06), Vector3(sx * 0.0265, 0.065, -0.29 - i * 0.075), 0.001)
	body.uv2_flag = Vector2.ZERO
	_mesh_node(root, "body", body, mat)

	# Moving parts.
	var mag := _kit()
	profile(mag, [Vector2(0.025, 0.0), Vector2(0.115, 0.0), Vector2(0.135, -0.19), Vector2(0.05, -0.2)], 0.034, Vector3.ZERO, 0.004)
	mag.with_color(ACCENT)
	profile(mag, [Vector2(0.045, -0.2), Vector2(0.14, -0.19), Vector2(0.142, -0.205), Vector2(0.045, -0.215)], 0.038, Vector3.ZERO, 0.003)
	var mag_node := Node3D.new()
	mag_node.name = "magazine"
	mag_node.position = Vector3(0, -0.04, 0)
	root.add_child(mag_node)
	_mesh_node(mag_node, "mesh", mag, mat)

	var ch := _kit()
	ch.uv2_flag = Vector2(1, 0)
	ch.box(Vector3(0.07, 0.014, 0.025), Vector3(0, 0, 0), 0.003)
	var ch_node := Node3D.new()
	ch_node.name = "charging_handle"
	ch_node.position = Vector3(0, 0.11, 0.115)
	root.add_child(ch_node)
	_mesh_node(ch_node, "mesh", ch, mat)

	var trig := _kit()
	trig.uv2_flag = Vector2(1, 0)
	profile(trig, [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.006, -0.03), Vector2(-0.004, -0.028)], 0.006, Vector3.ZERO, 0.001)
	var trig_node := Node3D.new()
	trig_node.name = "trigger"
	trig_node.position = Vector3(0, -0.006, -0.055)
	root.add_child(trig_node)
	_mesh_node(trig_node, "mesh", trig, mat)

	var bolt := _kit()
	bolt.uv2_flag = Vector2(1, 0)
	bolt.box(Vector3(0.004, 0.022, 0.06), Vector3.ZERO, 0.001)
	var bolt_node := Node3D.new()
	bolt_node.name = "bolt"
	bolt_node.position = Vector3(0.0255, 0.085, -0.04)
	root.add_child(bolt_node)
	_mesh_node(bolt_node, "mesh", bolt, mat)

	_socket(root, "grip", Vector3(0, -0.055, 0.02), Vector3(deg_to_rad(15), 0, 0))
	_socket(root, "muzzle", Vector3(0, 0.07, -0.78))
	_socket(root, "eject", Vector3(0.03, 0.085, -0.04))
	_socket(root, "mag", Vector3(0, -0.04, -0.07))
	_socket(root, "sight_aim", Vector3(0, 0.185, -0.04))
	_socket(root, "left_hand_ik", Vector3(-0.01, 0.0, -0.4), Vector3(deg_to_rad(-10), 0, deg_to_rad(-80)))


## Placeholder silhouette for weapons not yet built (milestone 9 fills these in).
static func _generic(root: Node3D, mat: ShaderMaterial, weapon_id: String) -> void:
	var body := _kit()
	var length := 0.5 if weapon_id in ["wasp", "pike", "hornet", "grifter"] else 0.85
	profile(body, [Vector2(-length * 0.3, 0.0), Vector2(length * 0.7, 0.0), Vector2(length * 0.7, 0.08), Vector2(-length * 0.3, 0.08)], 0.045, Vector3(0, 0.0, 0), 0.004)
	profile(body, [Vector2(-0.025, 0.0), Vector2(0.035, 0.0), Vector2(0.005, -0.12), Vector2(-0.055, -0.12)], 0.034, Vector3.ZERO, 0.006)
	_mesh_node(root, "body", body, mat)
	_socket(root, "grip", Vector3(0, -0.055, 0.02), Vector3(deg_to_rad(15), 0, 0))
	_socket(root, "muzzle", Vector3(0, 0.05, -length * 0.7))
	_socket(root, "eject", Vector3(0.03, 0.06, 0))
	_socket(root, "sight_aim", Vector3(0, 0.12, 0))
	_socket(root, "left_hand_ik", Vector3(-0.01, 0.0, -length * 0.4), Vector3(deg_to_rad(-10), 0, deg_to_rad(-80)))
