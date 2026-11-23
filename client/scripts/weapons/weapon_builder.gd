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
		"knife":
			_knife(root, mat)
		_:
			if RECIPES.has(weapon_id):
				_parametric(root, mat, RECIPES[weapon_id])
			else:
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
	if skin.has("pattern") and ResourceLoader.exists(str(skin["pattern"])):
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


## Silhouette recipes (spec §7.1: each weapon recognisable from its first-person silhouette).
## len = receiver length, h = receiver height, barrel = barrel length past the handguard,
## stock: none/fixed/skeleton/folding, mag: pistol/straight/curved/drum/cylinder/tube/top/box,
## sight: iron/holo/scope2/scope_long, extras: suppressor, pump, spin, slide, brake.
const RECIPES: Dictionary = {
	"wasp": {"len": 0.19, "h": 0.042, "barrel": 0.0, "stock": "none", "mag": "pistol", "sight": "iron", "extras": ["slide"], "width": 0.032},
	"pike": {"len": 0.24, "h": 0.05, "barrel": 0.07, "stock": "none", "mag": "cylinder", "sight": "iron", "extras": ["brake"], "width": 0.04},
	"hornet": {"len": 0.2, "h": 0.045, "barrel": 0.0, "stock": "none", "mag": "pistol_long", "sight": "iron", "extras": ["suppressor", "slide"], "width": 0.034},
	"grifter": {"len": 0.2, "h": 0.05, "barrel": 0.02, "stock": "none", "mag": "pistol", "sight": "iron", "extras": ["double_barrel"], "width": 0.045},
	"jolt": {"len": 0.3, "h": 0.07, "barrel": 0.05, "stock": "folding", "mag": "straight", "sight": "iron", "extras": [], "width": 0.042},
	"halcyon": {"len": 0.36, "h": 0.075, "barrel": 0.08, "stock": "skeleton", "mag": "curved_short", "sight": "holo", "extras": [], "width": 0.046},
	"breaker": {"len": 0.42, "h": 0.07, "barrel": 0.26, "stock": "fixed", "mag": "tube", "sight": "iron", "extras": ["pump"], "width": 0.05},
	"mauler": {"len": 0.4, "h": 0.085, "barrel": 0.18, "stock": "fixed", "mag": "drum", "sight": "holo", "extras": ["brake"], "width": 0.056},
	"lancer": {"len": 0.44, "h": 0.07, "barrel": 0.14, "stock": "fixed", "mag": "straight", "sight": "iron", "extras": ["brake"], "width": 0.046},
	"kite": {"len": 0.48, "h": 0.075, "barrel": 0.24, "stock": "fixed", "mag": "box", "sight": "scope2", "extras": [], "width": 0.046},
	"specter": {"len": 0.46, "h": 0.078, "barrel": 0.02, "stock": "skeleton", "mag": "curved", "sight": "holo", "extras": ["suppressor"], "width": 0.05},
	"shrike": {"len": 0.5, "h": 0.07, "barrel": 0.32, "stock": "skeleton", "mag": "box", "sight": "scope_long", "extras": ["bolt"], "width": 0.044},
	"longbow": {"len": 0.62, "h": 0.095, "barrel": 0.48, "stock": "fixed", "mag": "box", "sight": "scope_long", "extras": ["brake", "bipod", "bolt"], "width": 0.058},
	"bulwark": {"len": 0.56, "h": 0.11, "barrel": 0.3, "stock": "fixed", "mag": "drum_side", "sight": "holo", "extras": ["spin", "carry_handle"], "width": 0.07},
}


## Builds any weapon from a recipe. Same part vocabulary and finish rules as the Saber.
static func _parametric(root: Node3D, mat: ShaderMaterial, r: Dictionary) -> void:
	var L: float = r["len"]
	var H: float = r["h"]
	var W: float = r.get("width", 0.046)
	var extras: Array = r.get("extras", [])
	var pistol: bool = r["stock"] == "none"
	var body := _kit()
	# Receiver: machined upper over a polymer lower; front edge angled.
	body.uv2_flag = Vector2(1, 0)
	var front := L * 0.72
	var back := -L * 0.28
	profile(body, [Vector2(back, 0.0), Vector2(front, 0.0), Vector2(front + 0.02, H * 0.45), Vector2(front, H), Vector2(back + 0.03, H), Vector2(back, H * 0.8)], W, Vector3(0, 0.02, 0), 0.004)
	body.uv2_flag = Vector2.ZERO
	if not pistol:
		profile(body, [Vector2(back + 0.04, 0.0), Vector2(front - 0.06, 0.0), Vector2(front - 0.05, 0.028), Vector2(back + 0.04, 0.028)], W * 0.9, Vector3(0, -0.006, 0), 0.004)
	# Grip.
	profile(body, [Vector2(-0.025, 0.005), Vector2(0.035, 0.005), Vector2(0.005, -0.12), Vector2(-0.055, -0.125), Vector2(-0.06, -0.11)], W * 0.75, Vector3.ZERO, 0.006)
	profile(body, [Vector2(0.035, 0.0), Vector2(0.095, 0.0), Vector2(0.095, -0.048), Vector2(0.03, -0.048), Vector2(0.03, -0.04), Vector2(0.087, -0.04), Vector2(0.087, -0.008), Vector2(0.035, -0.008)], 0.01, Vector3.ZERO, 0.002)
	var bore_y := 0.02 + H * 0.62
	# Barrel past the receiver.
	var muzzle_z := -front
	if float(r["barrel"]) > 0.0:
		body.uv2_flag = Vector2(1, 0)
		var rad := 0.011 if not pistol else 0.009
		if "double_barrel" in extras:
			tube(body, rad, -front, -front - float(r["barrel"]) - 0.02, bore_y + 0.01, -0.01, 12)
			tube(body, rad, -front, -front - float(r["barrel"]) - 0.02, bore_y + 0.01, 0.01, 12)
		elif "spin" in extras:
			for i: int in 6:
				var a := TAU * i / 6.0
				tube(body, 0.011, -front + 0.04, -front - float(r["barrel"]), bore_y + sin(a) * 0.03, cos(a) * 0.03, 10)
			tube(body, 0.05, -front + 0.02, -front - 0.04, bore_y, 0.0, 16, 0.006)
			tube(body, 0.05, -front - float(r["barrel"]) + 0.05, -front - float(r["barrel"]) + 0.02, bore_y, 0.0, 16, 0.006)
		else:
			tube(body, rad, -front, -front - float(r["barrel"]), bore_y, 0.0, 14)
		muzzle_z = -front - float(r["barrel"])
		body.uv2_flag = Vector2.ZERO
	# Handguard for long guns (with the class-accent panel).
	if not pistol:
		var hg := minf(float(r["barrel"]) * 0.7 + 0.12, L * 0.55)
		profile(body, [Vector2(front - 0.01, 0.0), Vector2(front + hg, 0.004), Vector2(front + hg + 0.01, H * 0.3), Vector2(front + hg, H * 0.95), Vector2(front - 0.01, H * 0.95)], W * 1.08, Vector3(0, 0.02, 0), 0.006)
	# Muzzle devices.
	body.uv2_flag = Vector2(1, 0)
	if "suppressor" in extras:
		tube(body, 0.022, muzzle_z, muzzle_z - (0.2 if not pistol else 0.12), bore_y, 0.0, 16, 0.004)
		muzzle_z -= 0.2 if not pistol else 0.12
	elif "brake" in extras:
		tube(body, 0.018 if pistol else 0.022, muzzle_z, muzzle_z - 0.07, bore_y, 0.0, 10, 0.004)
		muzzle_z -= 0.07
	body.uv2_flag = Vector2.ZERO
	# Pistol slide.
	if "slide" in extras:
		body.uv2_flag = Vector2(1, 0)
		profile(body, [Vector2(back + 0.005, 0.0), Vector2(front + 0.015, 0.0), Vector2(front + 0.015, 0.03), Vector2(back + 0.02, 0.03)], W * 1.05, Vector3(0, 0.02 + H - 0.005, 0), 0.003)
		body.uv2_flag = Vector2.ZERO
	# Stock.
	match str(r["stock"]):
		"fixed":
			profile(body, [Vector2(back - 0.3, -0.07), Vector2(back - 0.25, -0.075), Vector2(back - 0.05, -0.015), Vector2(back, 0.0), Vector2(back, H * 0.9), Vector2(back - 0.18, H), Vector2(back - 0.3, H + 0.01)], W * 0.85, Vector3(0, 0.02, 0), 0.006)
		"skeleton":
			profile(body, [Vector2(back - 0.27, -0.06), Vector2(back - 0.24, -0.06), Vector2(back - 0.02, 0.01), Vector2(back, 0.0), Vector2(back, 0.03), Vector2(back - 0.24, 0.0)], W * 0.7, Vector3(0, 0.02, 0), 0.004)
			profile(body, [Vector2(back - 0.27, H * 0.7), Vector2(back, H * 0.75), Vector2(back, H * 0.95), Vector2(back - 0.27, H * 0.95)], W * 0.7, Vector3(0, 0.02, 0), 0.004)
			profile(body, [Vector2(back - 0.29, -0.065), Vector2(back - 0.26, -0.065), Vector2(back - 0.26, H + 0.01), Vector2(back - 0.29, H + 0.01)], W * 0.85, Vector3(0, 0.02, 0), 0.004)
		"folding":
			body.uv2_flag = Vector2(1, 0)
			tube(body, 0.006, -back, -back + 0.2, 0.05, -W * 0.4, 8, 0.0)
			tube(body, 0.006, -back, -back + 0.2, 0.05, W * 0.4, 8, 0.0)
			body.box(Vector3(W * 0.9, 0.08, 0.02), Vector3(0, 0.03, -back + 0.2), 0.004)
			body.uv2_flag = Vector2.ZERO
	# Sight.
	var top := 0.02 + H
	match str(r["sight"]):
		"iron":
			profile(body, [Vector2(back + 0.03, 0.0), Vector2(back + 0.05, 0.0), Vector2(back + 0.045, 0.02), Vector2(back + 0.035, 0.02)], 0.03, Vector3(0, top, 0), 0.002)
			profile(body, [Vector2(front - 0.03, 0.0), Vector2(front - 0.01, 0.0), Vector2(front - 0.015, 0.022), Vector2(front - 0.025, 0.022)], 0.01, Vector3(0, top, 0), 0.002)
		"holo":
			profile(body, [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.1, 0.012), Vector2(0.0, 0.012)], 0.034, Vector3(0, top, 0), 0.002)
			profile(body, [Vector2(0.015, 0.0), Vector2(0.045, 0.0), Vector2(0.04, 0.05), Vector2(0.02, 0.05)], 0.046, Vector3(0, top + 0.008, 0), 0.003)
			profile(body, [Vector2(0.07, 0.0), Vector2(0.1, 0.0), Vector2(0.095, 0.055), Vector2(0.075, 0.055)], 0.046, Vector3(0, top + 0.008, 0), 0.003)
		"scope2", "scope_long":
			var slen := 0.22 if r["sight"] == "scope2" else 0.34
			var srad := 0.022 if r["sight"] == "scope2" else 0.028
			body.uv2_flag = Vector2(1, 0)
			tube(body, srad, 0.06, -slen + 0.06, top + 0.045, 0.0, 18, 0.004)
			tube(body, srad + 0.008, 0.07, 0.03, top + 0.045, 0.0, 18, 0.004)
			tube(body, srad + 0.01, -slen + 0.09, -slen + 0.04, top + 0.045, 0.0, 18, 0.004)
			body.box(Vector3(0.02, 0.03, 0.02), Vector3(0, top + 0.015, -0.01), 0.004)
			body.box(Vector3(0.02, 0.03, 0.02), Vector3(0, top + 0.015, -slen + 0.12), 0.004)
			body.uv2_flag = Vector2.ZERO
	# Accent panel + Rift strip (class accent / emissive skin channels).
	body.with_color(ACCENT)
	for sx: float in [-1.0, 1.0]:
		profile(body, [Vector2(back * 0.3, 0.0), Vector2(front * 0.55, 0.0), Vector2(front * 0.6, H * 0.4), Vector2(back * 0.3, H * 0.4)], 0.003, Vector3(sx * (W * 0.5 + 0.001), 0.02 + H * 0.25, 0), 0.0012)
	body.with_color(EMIT)
	body.box(Vector3(0.004, 0.006, front * 0.5), Vector3(W * 0.5 + 0.003, 0.02 + H * 0.75, -front * 0.3), 0.001)
	body.with_color(BASE)
	# Extras.
	if "pump" in extras:
		profile(body, [Vector2(front + 0.04, -0.012), Vector2(front + 0.2, -0.012), Vector2(front + 0.2, 0.03), Vector2(front + 0.04, 0.03)], W * 1.2, Vector3(0, -0.005, 0), 0.008)
	if "carry_handle" in extras:
		profile(body, [Vector2(-0.05, 0.0), Vector2(0.18, 0.0), Vector2(0.16, 0.05), Vector2(-0.03, 0.05)], 0.02, Vector3(0, top + 0.03, 0), 0.004)
	if "bipod" in extras:
		body.uv2_flag = Vector2(1, 0)
		for sx: float in [-1.0, 1.0]:
			body.set_transform(Transform3D(Basis(Vector3.BACK, sx * 0.25), Vector3(sx * 0.03, bore_y - 0.09, muzzle_z + 0.18)))
			body.cylinder(0.007, 0.16, Vector3.ZERO, 6, 0.002)
		body.reset_transform()
		body.uv2_flag = Vector2.ZERO
	if "bolt" in extras:
		body.uv2_flag = Vector2(1, 0)
		body.set_transform(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(W * 0.5 + 0.03, 0.02 + H * 0.7, 0.04)))
		body.cylinder(0.006, 0.06, Vector3.ZERO, 8, 0.002)
		body.reset_transform()
		body.ellipsoid(Vector3(0.012, 0.012, 0.012), Vector3(W * 0.5 + 0.06, 0.02 + H * 0.7, 0.04), 8, 6)
		body.uv2_flag = Vector2.ZERO
	_mesh_node(root, "body", body, mat)
	# Magazine as its own node (reload choreography moves it).
	var mag := _kit()
	var mag_pos := Vector3(0, -0.035, 0)
	match str(r["mag"]):
		"pistol":
			mag_pos = Vector3(0, -0.12, 0.012)
			profile(mag, [Vector2(-0.045, 0.0), Vector2(0.005, 0.0), Vector2(0.0, 0.02), Vector2(-0.05, 0.02)], W * 0.8, Vector3.ZERO, 0.003)
		"pistol_long":
			mag_pos = Vector3(0, -0.12, 0.012)
			profile(mag, [Vector2(-0.045, 0.0), Vector2(0.005, 0.0), Vector2(0.015, -0.07), Vector2(-0.035, -0.07)], W * 0.8, Vector3.ZERO, 0.003)
		"cylinder":
			mag_pos = Vector3(0, 0.02 + H * 0.5, -0.06)
			mag.uv2_flag = Vector2(1, 0)
			mag.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
			mag.cylinder(0.03, 0.065, Vector3.ZERO, 8, 0.006)
			mag.reset_transform()
		"straight":
			profile(mag, [Vector2(0.025, 0.0), Vector2(0.09, 0.0), Vector2(0.09, -0.17), Vector2(0.025, -0.17)], W * 0.7, Vector3.ZERO, 0.004)
		"curved", "curved_short":
			var depth := 0.19 if r["mag"] == "curved" else 0.13
			profile(mag, [Vector2(0.025, 0.0), Vector2(0.11, 0.0), Vector2(0.13, -depth), Vector2(0.05, -depth - 0.01)], W * 0.72, Vector3.ZERO, 0.004)
		"box":
			profile(mag, [Vector2(0.02, 0.0), Vector2(0.1, 0.0), Vector2(0.1, -0.09), Vector2(0.02, -0.09)], W * 0.78, Vector3.ZERO, 0.004)
		"drum":
			mag.set_transform(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.07, -0.06)))
			mag.cylinder(0.075, W * 1.25, Vector3.ZERO, 20, 0.01)
			mag.reset_transform()
		"drum_side":
			mag.set_transform(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-W * 0.9, -0.02, -0.05)))
			mag.cylinder(0.09, 0.07, Vector3.ZERO, 22, 0.01)
			mag.reset_transform()
		"tube":
			mag_pos = Vector3(0, bore_y - 0.035, 0)
			mag.uv2_flag = Vector2(1, 0)
			mag.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -front - 0.1)))
			mag.cylinder(0.013, 0.28, Vector3.ZERO, 10, 0.003)
			mag.reset_transform()
	var mag_node := Node3D.new()
	mag_node.name = "magazine"
	mag_node.position = mag_pos
	root.add_child(mag_node)
	_mesh_node(mag_node, "mesh", mag, mat)
	var trig := _kit()
	trig.uv2_flag = Vector2(1, 0)
	profile(trig, [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.006, -0.03), Vector2(-0.004, -0.028)], 0.006, Vector3.ZERO, 0.001)
	var trig_node := Node3D.new()
	trig_node.name = "trigger"
	trig_node.position = Vector3(0, -0.006, -0.055)
	root.add_child(trig_node)
	_mesh_node(trig_node, "mesh", trig, mat)
	var ch_node := Node3D.new()
	ch_node.name = "charging_handle"
	ch_node.position = Vector3(0, 0.02 + H, 0.0)
	root.add_child(ch_node)
	var sight_y := top + (0.045 if str(r["sight"]).begins_with("scope") else (0.04 if r["sight"] == "holo" else 0.018))
	_socket(root, "grip", Vector3(0, -0.055, 0.02), Vector3(deg_to_rad(15), 0, 0))
	_socket(root, "muzzle", Vector3(0, bore_y, muzzle_z - 0.01))
	_socket(root, "eject", Vector3(W * 0.5 + 0.005, 0.02 + H * 0.7, -0.03))
	_socket(root, "mag", mag_pos)
	_socket(root, "sight_aim", Vector3(0, sight_y, 0.0))
	if pistol:
		_socket(root, "left_hand_ik", Vector3(-0.02, -0.06, 0.03), Vector3(deg_to_rad(10), deg_to_rad(20), deg_to_rad(-60)))
	else:
		_socket(root, "left_hand_ik", Vector3(-0.01, 0.0, -front - minf(float(r["barrel"]) * 0.35, 0.12)), Vector3(deg_to_rad(-10), 0, deg_to_rad(-80)))


## Tactical knife: chunky blade with a fuller, wrapped grip, guard.
static func _knife(root: Node3D, mat: ShaderMaterial) -> void:
	var k := _kit()
	k.uv2_flag = Vector2(1, 0)
	profile(k, [Vector2(0.0, 0.0), Vector2(0.17, 0.004), Vector2(0.2, 0.022), Vector2(0.15, 0.034), Vector2(0.0, 0.034)], 0.006, Vector3(0, -0.01, 0), 0.0015)
	k.uv2_flag = Vector2.ZERO
	k.box(Vector3(0.05, 0.016, 0.03), Vector3(0, 0.007, 0.0), 0.004)
	profile(k, [Vector2(-0.11, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 0.03), Vector2(-0.11, 0.028)], 0.026, Vector3(0, -0.008, 0), 0.006)
	k.with_color(ACCENT)
	profile(k, [Vector2(-0.1, 0.0), Vector2(-0.02, 0.0), Vector2(-0.02, 0.006), Vector2(-0.1, 0.006)], 0.028, Vector3(0, 0.004, 0), 0.002)
	_mesh_node(root, "body", k, mat)
	root.rotation = Vector3(0, 0, 0)
	_socket(root, "grip", Vector3(0, 0.005, 0.06), Vector3(deg_to_rad(80), 0, 0))
	_socket(root, "muzzle", Vector3(0, 0.0, -0.2))
	_socket(root, "eject", Vector3(0, 0, 0))
	_socket(root, "sight_aim", Vector3(0, 0.05, 0))
	_socket(root, "left_hand_ik", Vector3(-0.15, -0.1, 0.1), Vector3(0, 0, deg_to_rad(-60)))


## Placeholder silhouette (only used for unknown ids).
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
