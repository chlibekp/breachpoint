## AgentLooks: code-built outfits for each agent on the shared AgentRig. Each agent has one
## signature colour and one signature shape (spec §6.1). Body pieces are chunky, bevelled forms
## with painted edge highlights (M_Character reads vertex alpha), ~7.5 heads tall.
class_name AgentLooks
extends RefCounted

const SKIN_TONES: Dictionary = {
	"fair": Color("#E9C2A6"), "light": Color("#D9A984"), "tan": Color("#B9825C"),
	"brown": Color("#8E5A3C"), "deep": Color("#5E3A27"),
}


static func build(agent_id: String) -> AgentRig:
	var rig := AgentRig.new()
	rig.agent_id = agent_id
	match agent_id:
		"kestrel":
			_kestrel(rig)
		"mamba":
			_mamba(rig)
		"vesper":
			_vesper(rig)
		"haldor":
			_haldor(rig)
		"orin":
			_orin(rig)
		"sable":
			_sable(rig)
		"imani":
			_imani(rig)
		"tomas":
			_tomas(rig)
		_:
			# Other agents are filled in milestone 7; fall back to the base body in their colour.
			var agents: Dictionary = SharedConfig.load_all()["data"].get("agents", {})
			var color := "#8899AA"
			for a: Dictionary in agents.get("agents", []):
				if a["id"] == agent_id:
					color = a["signatureColor"]
			_base_body(rig, _palette(Color(color), "light"))
	return rig


static func _palette(signature: Color, skin: String) -> Dictionary:
	return {
		"skin": {"color": SKIN_TONES[skin], "roughness": 0.55},
		"cloth": {"color": Color("#2B3440"), "roughness": 0.85},
		"cloth_light": {"color": Color("#5B6673"), "roughness": 0.85},
		"leather": {"color": Color("#3A2E28"), "roughness": 0.55},
		"armor": {"color": Color("#454D55"), "roughness": 0.4, "metallic": 0.4},
		"signature": {"color": signature, "roughness": 0.6},
		"boots": {"color": Color("#2A2624"), "roughness": 0.6},
		"gloves": {"color": Color("#30343A"), "roughness": 0.5},
		"hair": {"color": Color("#3A2A20"), "roughness": 0.5},
		"rift": {"color": Color("#222"), "emissive": signature.lightened(0.2), "emissive_energy": 3.0},
	}


## Shared base body: torso, pelvis, limbs, hands, boots, head. `pal` maps material ids to specs.
static func _base_body(rig: AgentRig, pal: Dictionary, opts: Dictionary = {}) -> void:
	var m := func(id: String) -> ShaderMaterial: return rig.material(id, pal[id])
	var cloth: ShaderMaterial = m.call(opts.get("torso_mat", "cloth"))
	var legs: ShaderMaterial = m.call(opts.get("legs_mat", "cloth_light"))
	# Pelvis + belt.
	rig.part("hips", legs, func(k: MeshKit) -> void: k.box(Vector3(0.34, 0.2, 0.22), Vector3(0, 0.0, 0), 0.06))
	rig.part("hips", m.call("leather"), func(k: MeshKit) -> void: k.box(Vector3(0.37, 0.07, 0.25), Vector3(0, 0.08, 0), 0.02))
	# Torso: tapered chest block + abdomen.
	rig.part("spine", cloth, func(k: MeshKit) -> void: k.box(Vector3(0.3, 0.22, 0.2), Vector3(0, 0.08, 0), 0.07))
	rig.part("chest", cloth, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.15, -0.02), Vector2(0.15, -0.02), Vector2(0.21, 0.2), Vector2(0.18, 0.28), Vector2(-0.18, 0.28), Vector2(-0.21, 0.2)]), 0.24, Vector3.ZERO, 0.05))
	# Neck + head (stylised-realistic: simplified planes, big readable features).
	rig.part("neck", m.call("skin"), func(k: MeshKit) -> void: k.cylinder(0.055, 0.12, Vector3(0, 0.02, 0), 10, 0.01))
	rig.part("head", m.call("skin"), func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.095, 0.12, 0.105), Vector3(0, 0.11, -0.005), 16, 10)
		k.box(Vector3(0.12, 0.05, 0.07), Vector3(0, 0.035, -0.06), 0.025)  # jaw
		k.box(Vector3(0.03, 0.045, 0.03), Vector3(0, 0.1, -0.105), 0.01)  # nose
		k.ellipsoid(Vector3(0.018, 0.03, 0.02), Vector3(-0.098, 0.105, 0.0), 6, 4)  # ears
		k.ellipsoid(Vector3(0.018, 0.03, 0.02), Vector3(0.098, 0.105, 0.0), 6, 4))
	var eye := rig.material("eye", {"color": Color("#1E2026"), "roughness": 0.2})
	rig.part("head", eye, func(k: MeshKit) -> void:
		k.box(Vector3(0.028, 0.012, 0.01), Vector3(-0.035, 0.128, -0.1), 0.004)
		k.box(Vector3(0.028, 0.012, 0.01), Vector3(0.035, 0.128, -0.1), 0.004))
	var brow := rig.material("brow", pal["hair"])
	rig.part("head", brow, func(k: MeshKit) -> void:
		k.box(Vector3(0.036, 0.01, 0.012), Vector3(-0.036, 0.148, -0.1), 0.004)
		k.box(Vector3(0.036, 0.01, 0.012), Vector3(0.036, 0.148, -0.1), 0.004))
	# Arms (sleeves) + gloves.
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		rig.part("shoulder_" + side, cloth, func(k: MeshKit) -> void: k.ellipsoid(Vector3(0.075, 0.07, 0.08), Vector3(sx * 0.03, -0.02, 0), 10, 6))
		rig.part("upper_arm_" + side, m.call(opts.get("sleeve_mat", "cloth")), func(k: MeshKit) -> void: k.capsule(0.062, 0.074, 0.32, Vector3(0, -0.14, 0), 10, 3))
		rig.part("forearm_" + side, m.call(opts.get("forearm_mat", "cloth")), func(k: MeshKit) -> void: k.capsule(0.05, 0.062, 0.28, Vector3(0, -0.12, 0), 10, 3))
		rig.part("hand_" + side, m.call("gloves"), func(k: MeshKit) -> void:
			k.box(Vector3(0.075, 0.09, 0.035), Vector3(0, -0.05, 0), 0.015)
			k.box(Vector3(0.025, 0.05, 0.025), Vector3(sx * -0.04, -0.03, -0.02), 0.008))
		rig.part("thigh_" + side, legs, func(k: MeshKit) -> void: k.capsule(0.088, 0.112, 0.47, Vector3(0, -0.2, 0), 10, 3))
		rig.part("shin_" + side, legs, func(k: MeshKit) -> void: k.capsule(0.066, 0.088, 0.45, Vector3(0, -0.2, 0), 10, 3))
		rig.part("shin_" + side, m.call("armor"), func(k: MeshKit) -> void: k.box(Vector3(0.12, 0.16, 0.06), Vector3(0, -0.02, -0.06), 0.025))  # knee guard
		rig.part("foot_" + side, m.call("boots"), func(k: MeshKit) -> void:
			k.box(Vector3(0.13, 0.12, 0.27), Vector3(0, -0.01, -0.05), 0.035)
			k.box(Vector3(0.12, 0.035, 0.27), Vector3(0, -0.055, -0.05), 0.012))


## KESTREL — Norwegian ex-rescue pilot. Signature colour: signal orange.
## Signature shape: cropped flight jacket with a tall collar and a shoulder-mounted thruster pack.
static func _kestrel(rig: AgentRig) -> void:
	var orange := Color("#FF7A1A")
	var pal := _palette(orange, "fair")
	pal["signature"] = {"color": Color("#F2741E"), "roughness": 0.62}
	pal["cloth"] = {"color": Color("#283039"), "roughness": 0.8}  # flight suit, deep slate
	pal["cloth_light"] = {"color": Color("#3B4450"), "roughness": 0.82}
	pal["hair"] = {"color": Color("#E3C58E"), "roughness": 0.45}  # ash blonde
	pal["rift"] = {"color": Color("#331a0a"), "emissive": Color("#FFA14A"), "emissive_energy": 4.0}
	_base_body(rig, pal, {"sleeve_mat": "signature", "torso_mat": "cloth"})
	var sig := rig.material("signature", pal["signature"])
	var leather := rig.material("leather", pal["leather"])
	var armor := rig.material("armor", pal["armor"])
	var hair := rig.material("hair", pal["hair"])
	var rift := rig.material("rift", pal["rift"])
	var cream := rig.material("cream", {"color": Color("#E9E1D0"), "roughness": 0.7})
	# Cropped flight jacket: shell over the chest, ends above the belt, big tall collar.
	rig.part("chest", sig, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.17, -0.06), Vector2(0.17, -0.06), Vector2(0.235, 0.2), Vector2(0.2, 0.3), Vector2(-0.2, 0.3), Vector2(-0.235, 0.2)]), 0.27, Vector3(0, 0, 0.005), 0.05)
		# tall collar (signature)
		k.extrude(PackedVector2Array([Vector2(-0.13, 0.0), Vector2(0.13, 0.0), Vector2(0.15, 0.16), Vector2(-0.15, 0.16)]), 0.24, Vector3(0, 0.27, 0.02), 0.03), "jacket")
	rig.part("chest", cream, func(k: MeshKit) -> void:
		# Shearling lining visible at the open collar and cuffs.
		k.box(Vector3(0.2, 0.05, 0.2), Vector3(0, 0.43, 0.03), 0.02)
		k.box(Vector3(0.04, 0.24, 0.02), Vector3(0, 0.12, -0.14), 0.008), "lining")
	rig.part("chest", leather, func(k: MeshKit) -> void:
		# Harness straps over the jacket (role-readable gear).
		k.set_transform(Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.07, 0.12, -0.142)))
		k.box(Vector3(0.05, 0.36, 0.015), Vector3.ZERO, 0.006)
		k.set_transform(Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.07, 0.12, -0.142)))
		k.box(Vector3(0.05, 0.36, 0.015), Vector3.ZERO, 0.006)
		k.reset_transform()
		k.box(Vector3(0.09, 0.09, 0.03), Vector3(0, 0.04, -0.15), 0.01))
	# Cuffs on the sleeves.
	for side: String in ["l", "r"]:
		rig.part("forearm_" + side, cream, func(k: MeshKit) -> void: k.cylinder(0.058, 0.06, Vector3(0, -0.02, 0), 10, 0.015))
		rig.part("upper_arm_" + side, armor, func(k: MeshKit) -> void: k.box(Vector3(0.13, 0.12, 0.12), Vector3(0, -0.04, 0), 0.04))
	# Thruster pack (signature shape): yoke over the shoulders + two angled thrusters with glowing nozzles.
	rig.part("chest", armor, func(k: MeshKit) -> void:
		k.box(Vector3(0.34, 0.2, 0.1), Vector3(0, 0.18, 0.17), 0.04)
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * 0.22), Vector3(sx * 0.17, 0.26, 0.21)))
			k.cylinder(0.075, 0.34, Vector3.ZERO, 12, 0.02)
			k.cylinder(0.085, 0.06, Vector3(0, 0.15, 0), 12, 0.015)
			k.reset_transform(), "thruster_pack")
	rig.part("chest", sig, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * 0.22), Vector3(sx * 0.17, 0.26, 0.21)))
			k.cylinder(0.078, 0.08, Vector3(0, 0.02, 0), 12, 0.015)
			k.reset_transform())
	rig.part("chest", rift, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * 0.22), Vector3(sx * 0.17, 0.26, 0.21)))
			k.cylinder(0.05, 0.02, Vector3(0, -0.18, 0), 12, 0.004)
			k.reset_transform())
	# Hair: chunky swept-back clumps + undercut, painted highlight via lighter top clump.
	rig.part("head", hair, func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.1, 0.07, 0.11), Vector3(0, 0.19, 0.01), 12, 6)
		for i: int in 5:
			var x := -0.06 + i * 0.03
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.5 - i * 0.03) * Basis(Vector3.BACK, (i - 2) * 0.08), Vector3(x, 0.22, -0.03)))
			k.ellipsoid(Vector3(0.028, 0.03, 0.08), Vector3(0, 0, 0.03), 8, 5)
		k.reset_transform(), "hair")
	# Flight goggles pushed up on the forehead (orange lenses).
	var lens := rig.material("lens", {"color": Color("#FF9A3A"), "roughness": 0.15, "emissive": Color("#FF8A2A"), "emissive_energy": 0.6})
	rig.part("head", leather, func(k: MeshKit) -> void: k.box(Vector3(0.21, 0.025, 0.22), Vector3(0, 0.2, 0.0), 0.01))
	rig.part("head", lens, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.5), Vector3(sx * 0.042, 0.215, -0.1)))
			k.cylinder(0.03, 0.025, Vector3.ZERO, 12, 0.006)
			k.reset_transform())
	# Thigh holster + pouches.
	rig.part("thigh_r", leather, func(k: MeshKit) -> void: k.box(Vector3(0.06, 0.18, 0.12), Vector3(0.09, -0.12, 0), 0.02))
	rig.part("hips", leather, func(k: MeshKit) -> void:
		k.box(Vector3(0.08, 0.08, 0.05), Vector3(-0.12, 0.04, -0.12), 0.015)
		k.box(Vector3(0.08, 0.08, 0.05), Vector3(0.12, 0.04, -0.12), 0.015))


## Short-hair cap + optional clumps, shared by several agents.
static func _hair(rig: AgentRig, color: Color, clumps: int, long_back: bool = false) -> void:
	var hair := rig.material("hair", {"color": color, "roughness": 0.45})
	rig.part("head", hair, func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.1, 0.07, 0.11), Vector3(0, 0.19, 0.01), 12, 6)
		for i: int in clumps:
			var x := -0.07 + i * 0.14 / maxf(1.0, clumps - 1.0)
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.4) * Basis(Vector3.BACK, (i - clumps * 0.5) * 0.1), Vector3(x, 0.21, -0.02)))
			k.ellipsoid(Vector3(0.03, 0.03, 0.07), Vector3(0, 0, 0.03), 8, 5)
		k.reset_transform()
		if long_back:
			k.ellipsoid(Vector3(0.09, 0.14, 0.05), Vector3(0, 0.08, 0.09), 10, 6))


## MAMBA — Kenyan street racer turned Rift runner. Acid green; hooded racing suit, glowing visor,
## sleek knee guards.
static func _mamba(rig: AgentRig) -> void:
	var green := Color("#9BE22B")
	var pal := _palette(green, "deep")
	pal["cloth"] = {"color": Color("#22272C"), "roughness": 0.5}  # racing suit: satin black
	pal["cloth_light"] = {"color": Color("#2E343B"), "roughness": 0.5}
	pal["armor"] = {"color": Color("#3A4148"), "roughness": 0.35, "metallic": 0.3}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var sig := rig.material("signature", {"color": green, "roughness": 0.45})
	var visor := rig.material("visor", {"color": Color("#0E1A08"), "roughness": 0.1, "emissive": Color("#B6FF3A"), "emissive_energy": 3.0})
	# Racing stripes down the suit and legs.
	rig.part("chest", sig, func(k: MeshKit) -> void:
		k.box(Vector3(0.05, 0.3, 0.02), Vector3(-0.07, 0.12, -0.125), 0.008)
		k.box(Vector3(0.05, 0.3, 0.02), Vector3(0.07, 0.12, -0.125), 0.008))
	for side: String in ["l", "r"]:
		rig.part("thigh_" + side, sig, func(k: MeshKit) -> void: k.box(Vector3(0.025, 0.4, 0.17), Vector3(0.09 if side == "r" else -0.09, -0.2, 0), 0.008))
		rig.part("shin_" + side, sig, func(k: MeshKit) -> void: k.box(Vector3(0.14, 0.2, 0.08), Vector3(0, -0.04, -0.07), 0.035))  # sleek knee guards
	# Signature shape: big hood + glowing visor band.
	rig.part("head", sig, func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.13, 0.15, 0.14), Vector3(0, 0.13, 0.03), 14, 8)
		k.box(Vector3(0.2, 0.08, 0.12), Vector3(0, 0.0, 0.07), 0.03), "hood")
	rig.part("head", visor, func(k: MeshKit) -> void: k.box(Vector3(0.19, 0.04, 0.03), Vector3(0, 0.125, -0.1), 0.012))


## VESPER — French astronomer. Deep violet; long tailored coat, star-chart cape, floating orrery.
static func _vesper(rig: AgentRig) -> void:
	var violet := Color("#6B3FD6")
	var pal := _palette(violet, "light")
	pal["cloth"] = {"color": Color("#2A2240"), "roughness": 0.7}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var coat := rig.material("coat", {"color": Color("#3A2A6E"), "roughness": 0.65})
	var star := rig.material("star", {"color": Color("#1B1630"), "roughness": 0.6, "emissive": Color("#B9A6FF"), "emissive_energy": 1.6})
	var brass := rig.material("brass", {"color": Color("#C9A04A"), "roughness": 0.3, "metallic": 0.9})
	_hair(rig, Color("#2B1E1A"), 3, true)
	# Long tailored coat: torso shell + skirt panels that reach the knees (signature silhouette).
	rig.part("chest", coat, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.17, -0.06), Vector2(0.17, -0.06), Vector2(0.23, 0.22), Vector2(0.19, 0.3), Vector2(-0.19, 0.3), Vector2(-0.23, 0.22)]), 0.27, Vector3(0, 0, 0.005), 0.05))
	rig.part("hips", coat, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.2, 0.12), Vector2(0.2, 0.12), Vector2(0.26, -0.5), Vector2(-0.26, -0.5)]), 0.3, Vector3(0, 0, 0.0), 0.03))
	# Star-chart cape on the back with a glowing constellation.
	rig.part("chest", star, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.24, 0.3), Vector2(0.24, 0.3), Vector2(0.3, -0.75), Vector2(-0.3, -0.75)]), 0.02, Vector3(0, 0, 0.16), 0.008))
	# Floating orrery over the shoulder (rings + spheres).
	rig.part("chest", brass, func(k: MeshKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.3, 0.55, 0.12)))
		k.cylinder(0.12, 0.012, Vector3.ZERO, 20, 0.003)
		k.set_transform(Transform3D(Basis(Vector3.BACK, 0.7), Vector3(0.3, 0.55, 0.12)))
		k.cylinder(0.09, 0.012, Vector3.ZERO, 20, 0.003)
		k.reset_transform()
		k.ellipsoid(Vector3(0.035, 0.035, 0.035), Vector3(0.3, 0.55, 0.12), 8, 6), "orrery")


## HALDOR — Icelandic geothermal engineer. Steam white + basalt black; bulky heat-suit, exhaust
## stacks on the back, gauntlet nozzle.
static func _haldor(rig: AgentRig) -> void:
	var white := Color("#E8E4DC")
	var pal := _palette(white, "fair")
	pal["cloth"] = {"color": Color("#D9D4CA"), "roughness": 0.75}
	pal["cloth_light"] = {"color": Color("#2B2B2E"), "roughness": 0.7}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var basalt := rig.material("basalt", {"color": Color("#2A2A2D"), "roughness": 0.55, "metallic": 0.2})
	var vent := rig.material("vent", {"color": Color("#331a0a"), "emissive": Color("#FF7A3A"), "emissive_energy": 2.5})
	_hair(rig, Color("#B98A5A"), 2)
	rig.part("head", rig.material("beard", {"color": Color("#A67A4C"), "roughness": 0.6}), func(k: MeshKit) -> void: k.ellipsoid(Vector3(0.08, 0.06, 0.05), Vector3(0, 0.03, -0.07), 10, 6))
	# Bulky heat-suit: padded chest + oversized shoulders.
	rig.part("chest", basalt, func(k: MeshKit) -> void:
		k.box(Vector3(0.46, 0.34, 0.32), Vector3(0, 0.13, 0.01), 0.09)
		k.ellipsoid(Vector3(0.12, 0.1, 0.12), Vector3(-0.24, 0.26, 0), 10, 6)
		k.ellipsoid(Vector3(0.12, 0.1, 0.12), Vector3(0.24, 0.26, 0), 10, 6))
	# Signature shape: twin exhaust stacks above the shoulders with glowing tops.
	rig.part("chest", basalt, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.cylinder(0.06, 0.55, Vector3(sx * 0.12, 0.42, 0.2), 12, 0.015), "stacks")
	rig.part("chest", vent, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.cylinder(0.045, 0.03, Vector3(sx * 0.12, 0.7, 0.2), 12, 0.006))
	# Gauntlet nozzle on the right forearm.
	rig.part("forearm_r", basalt, func(k: MeshKit) -> void:
		k.cylinder(0.075, 0.2, Vector3(0, -0.12, 0), 12, 0.02)
		k.cylinder(0.035, 0.1, Vector3(0, -0.27, -0.03), 10, 0.01))


## ORIN — Australian outback tracker. Dusty ochre; wide-brim hat, poncho, mechanical hawk drone.
static func _orin(rig: AgentRig) -> void:
	var ochre := Color("#C8913A")
	var pal := _palette(ochre, "tan")
	pal["cloth"] = {"color": Color("#5A4A38"), "roughness": 0.85}
	pal["cloth_light"] = {"color": Color("#6E6252"), "roughness": 0.85}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var poncho := rig.material("signature", {"color": ochre, "roughness": 0.8})
	var hat := rig.material("hat", {"color": Color("#7A5A36"), "roughness": 0.75})
	var drone := rig.material("drone", {"color": Color("#8C8F94"), "roughness": 0.35, "metallic": 0.7, "emissive": Color("#FFB04A"), "emissive_energy": 0.4})
	_hair(rig, Color("#3A2A20"), 2)
	# Poncho: wide flat cape over the shoulders with a stepped hem.
	rig.part("chest", poncho, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.12, 0.34), Vector2(0.12, 0.34), Vector2(0.36, 0.05), Vector2(0.3, -0.1), Vector2(-0.3, -0.1), Vector2(-0.36, 0.05)]), 0.36, Vector3(0, 0, 0.0), 0.04))
	# Signature shape: wide-brim hat.
	rig.part("head", hat, func(k: MeshKit) -> void:
		k.cylinder(0.25, 0.025, Vector3(0, 0.2, 0.0), 24, 0.008)
		k.lathe(PackedVector2Array([Vector2(0.11, 0.2), Vector2(0.1, 0.28), Vector2(0.07, 0.31), Vector2(0.0, 0.31)]), 16), "hat")
	# Mechanical hawk perched on the left shoulder.
	rig.part("shoulder_l", drone, func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.05, 0.05, 0.09), Vector3(-0.02, 0.09, 0), 10, 6)
		k.box(Vector3(0.3, 0.015, 0.07), Vector3(-0.02, 0.1, 0.03), 0.005)
		k.box(Vector3(0.03, 0.03, 0.05), Vector3(-0.02, 0.12, -0.08), 0.008), "hawk")


## SABLE — Korean signal hacker. Electric cyan-blue, distinct from ally cyan by a white trim;
## oversized jacket, cables, holographic tablet.
static func _sable(rig: AgentRig) -> void:
	var blue := Color("#2F8CFF")
	var pal := _palette(blue, "light")
	pal["cloth"] = {"color": Color("#1F2633"), "roughness": 0.7}
	_base_body(rig, pal, {"sleeve_mat": "signature", "torso_mat": "cloth"})
	var sig := rig.material("signature", {"color": blue, "roughness": 0.6})
	var trim := rig.material("trim", {"color": Color("#F4F6FA"), "roughness": 0.6})
	var cable := rig.material("cable", {"color": Color("#1A1C20"), "roughness": 0.4})
	var holo := rig.material("holo", {"color": Color("#0B1E33"), "emissive": Color("#6FC3FF"), "emissive_energy": 2.4})
	_hair(rig, Color("#141217"), 4, true)
	# Oversized jacket (signature silhouette) with a white trim band.
	rig.part("chest", sig, func(k: MeshKit) -> void:
		k.extrude(PackedVector2Array([Vector2(-0.2, -0.16), Vector2(0.2, -0.16), Vector2(0.27, 0.22), Vector2(0.22, 0.32), Vector2(-0.22, 0.32), Vector2(-0.27, 0.22)]), 0.31, Vector3(0, 0, 0.005), 0.06))
	rig.part("chest", trim, func(k: MeshKit) -> void:
		k.box(Vector3(0.42, 0.035, 0.32), Vector3(0, -0.15, 0.005), 0.01)
		k.box(Vector3(0.03, 0.46, 0.02), Vector3(0.0, 0.08, -0.16), 0.006))
	# Cables looping from the back to the wrist.
	rig.part("chest", cable, func(k: MeshKit) -> void:
		for i: int in 3:
			k.set_transform(Transform3D(Basis(Vector3.BACK, 0.4 + i * 0.15), Vector3(0.16 + i * 0.02, 0.0, 0.14)))
			k.cylinder(0.012, 0.42, Vector3.ZERO, 6, 0.0)
		k.reset_transform())
	# Holographic tablet on the left forearm.
	rig.part("forearm_l", holo, func(k: MeshKit) -> void: k.box(Vector3(0.14, 0.02, 0.18), Vector3(0, -0.14, -0.06), 0.006))


## IMANI — Nigerian combat medic. Warm gold; field medic armour, glowing medkit backpack,
## braided hair with beads.
static func _imani(rig: AgentRig) -> void:
	var gold := Color("#F2B632")
	var pal := _palette(gold, "deep")
	pal["cloth"] = {"color": Color("#2E3A33"), "roughness": 0.8}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var sig := rig.material("signature", {"color": gold, "roughness": 0.45, "metallic": 0.3})
	var white := rig.material("medwhite", {"color": Color("#EDEBE6"), "roughness": 0.5})
	var glow := rig.material("medglow", {"color": Color("#3a2a00"), "emissive": Color("#FFD36A"), "emissive_energy": 2.8})
	var bead := rig.material("bead", {"color": Color("#F2B632"), "roughness": 0.3, "metallic": 0.6})
	# Field medic armour plates.
	rig.part("chest", sig, func(k: MeshKit) -> void:
		k.box(Vector3(0.34, 0.2, 0.06), Vector3(0, 0.16, -0.13), 0.03)
		k.ellipsoid(Vector3(0.1, 0.07, 0.11), Vector3(-0.22, 0.26, 0), 10, 6)
		k.ellipsoid(Vector3(0.1, 0.07, 0.11), Vector3(0.22, 0.26, 0), 10, 6))
	# Signature shape: glowing medkit backpack.
	rig.part("chest", white, func(k: MeshKit) -> void: k.box(Vector3(0.32, 0.36, 0.17), Vector3(0, 0.12, 0.2), 0.05), "medkit")
	rig.part("chest", glow, func(k: MeshKit) -> void:
		k.box(Vector3(0.18, 0.05, 0.02), Vector3(0, 0.14, 0.29), 0.01)
		k.box(Vector3(0.05, 0.18, 0.02), Vector3(0, 0.14, 0.29), 0.01))
	# Braided hair with beads.
	var hair := rig.material("hair", {"color": Color("#1E1410"), "roughness": 0.5})
	rig.part("head", hair, func(k: MeshKit) -> void:
		k.ellipsoid(Vector3(0.105, 0.075, 0.115), Vector3(0, 0.19, 0.01), 12, 6)
		for i: int in 7:
			var a := -1.2 + i * 0.4
			k.capsule(0.017, 0.015, 0.26, Vector3(sin(a) * 0.09, 0.05, 0.04 + cos(a) * 0.06), 6, 2))
	rig.part("head", bead, func(k: MeshKit) -> void:
		for i: int in 7:
			var a := -1.2 + i * 0.4
			k.ellipsoid(Vector3(0.022, 0.022, 0.022), Vector3(sin(a) * 0.09, -0.08, 0.04 + cos(a) * 0.06), 6, 4))


## TOMAS — Chilean mining engineer. Copper; hard hat with goggles, tool belt, mechanical arm.
static func _tomas(rig: AgentRig) -> void:
	var copper := Color("#C8743A")
	var pal := _palette(copper, "tan")
	pal["cloth"] = {"color": Color("#3A4250"), "roughness": 0.8}
	pal["cloth_light"] = {"color": Color("#454B52"), "roughness": 0.8}
	_base_body(rig, pal, {"sleeve_mat": "cloth", "torso_mat": "cloth"})
	var sig := rig.material("signature", {"color": copper, "roughness": 0.35, "metallic": 0.75})
	var hat := rig.material("hardhat", {"color": Color("#E0A33A"), "roughness": 0.4})
	var lens := rig.material("lens", {"color": Color("#223"), "roughness": 0.1, "emissive": Color("#7FD1FF"), "emissive_energy": 0.6})
	var leather := rig.material("leather", pal["leather"])
	rig.part("head", rig.material("beard", {"color": Color("#2A1E16"), "roughness": 0.6}), func(k: MeshKit) -> void: k.ellipsoid(Vector3(0.075, 0.05, 0.05), Vector3(0, 0.03, -0.07), 10, 6))
	# Signature shape: hard hat with goggles.
	rig.part("head", hat, func(k: MeshKit) -> void:
		k.lathe(PackedVector2Array([Vector2(0.15, 0.17), Vector2(0.15, 0.19), Vector2(0.11, 0.2), Vector2(0.1, 0.28), Vector2(0.05, 0.31), Vector2(0.0, 0.31)]), 18), "hardhat")
	rig.part("head", lens, func(k: MeshKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.3), Vector3(sx * 0.045, 0.21, -0.11)))
			k.cylinder(0.03, 0.025, Vector3.ZERO, 12, 0.006)
			k.reset_transform())
	# Tool belt.
	rig.part("hips", leather, func(k: MeshKit) -> void:
		k.box(Vector3(0.4, 0.07, 0.27), Vector3(0, 0.07, 0), 0.02)
		for x: float in [-0.15, -0.05, 0.08, 0.16]:
			k.box(Vector3(0.06, 0.1, 0.05), Vector3(x, 0.0, -0.14), 0.012))
	# Mechanical right arm (copper plates + pistons).
	for b: String in ["upper_arm_r", "forearm_r"]:
		rig.part(b, sig, func(k: MeshKit) -> void:
			k.box(Vector3(0.12, 0.24, 0.12), Vector3(0, -0.13, 0), 0.03)
			k.cylinder(0.02, 0.22, Vector3(0.07, -0.13, 0.03), 8, 0.004), "mech_" + b)
