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
		rig.part("upper_arm_" + side, m.call(opts.get("sleeve_mat", "cloth")), func(k: MeshKit) -> void: k.capsule(0.052, 0.062, 0.32, Vector3(0, -0.14, 0), 10, 3))
		rig.part("forearm_" + side, m.call(opts.get("forearm_mat", "cloth")), func(k: MeshKit) -> void: k.capsule(0.042, 0.052, 0.28, Vector3(0, -0.12, 0), 10, 3))
		rig.part("hand_" + side, m.call("gloves"), func(k: MeshKit) -> void:
			k.box(Vector3(0.075, 0.09, 0.035), Vector3(0, -0.05, 0), 0.015)
			k.box(Vector3(0.025, 0.05, 0.025), Vector3(sx * -0.04, -0.03, -0.02), 0.008))
		rig.part("thigh_" + side, legs, func(k: MeshKit) -> void: k.capsule(0.07, 0.09, 0.47, Vector3(0, -0.2, 0), 10, 3))
		rig.part("shin_" + side, legs, func(k: MeshKit) -> void: k.capsule(0.05, 0.07, 0.45, Vector3(0, -0.2, 0), 10, 3))
		rig.part("shin_" + side, m.call("armor"), func(k: MeshKit) -> void: k.box(Vector3(0.12, 0.16, 0.06), Vector3(0, -0.02, -0.06), 0.025))  # knee guard
		rig.part("foot_" + side, m.call("boots"), func(k: MeshKit) -> void:
			k.box(Vector3(0.11, 0.1, 0.25), Vector3(0, -0.01, -0.05), 0.03)
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
