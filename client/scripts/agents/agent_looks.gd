## AgentLooks: code-built outfits for each agent, layered over the shared AgentBody anatomy.
## Each agent has one signature colour and one signature shape (spec §6.1); clothing is smooth
## FormKit shells grown from the body's ring sets, hard gear keeps bevelled MeshKit edges
## (vertex alpha = painted edge wear in M_Character).
class_name AgentLooks
extends RefCounted

const SKIN_TONES: Dictionary = AgentBody.SKIN_TONES


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
			# Unknown ids (training dummy) get the base body in their configured colour.
			var agents: Dictionary = SharedConfig.load_all()["data"].get("agents", {})
			var color := "#8899AA"
			for a: Dictionary in agents.get("agents", []):
				if a["id"] == agent_id:
					color = a["signatureColor"]
			var pal := _palette(Color(color), "light")
			AgentBody.build(rig, pal, {"mats": {"torso": "signature", "upper_arm": "cloth", "legs": "cloth_light"}})
			_hair(rig, pal, AgentBody.forms({})["head"], "crop")
	return rig


static func _palette(signature: Color, skin: String) -> Dictionary:
	return {
		"skin": {"color": SKIN_TONES[skin], "roughness": 0.55, "sss": 0.7, "rim_strength": 0.25},
		"cloth": {"color": Color("#2B3440"), "roughness": 0.85, "sheen": 0.5},
		"cloth_light": {"color": Color("#56606C"), "roughness": 0.85, "sheen": 0.4},
		"leather": {"color": Color("#3A2C25"), "roughness": 0.5, "edge_wear": 0.45},
		"armor": {"color": Color("#454D55"), "roughness": 0.38, "metallic": 0.45, "edge_wear": 0.5},
		"signature": {"color": signature, "roughness": 0.6, "sheen": 0.35},
		"boots": {"color": Color("#2C2725"), "roughness": 0.55, "edge_wear": 0.4},
		"gloves": {"color": Color("#2E3237"), "roughness": 0.55},
		"hair": {"color": Color("#3A2A20"), "roughness": 0.45},
		"webbing": {"color": Color("#23272C"), "roughness": 0.8},
		"metal": {"color": Color("#B8BCC2"), "roughness": 0.3, "metallic": 0.85, "edge_wear": 0.4},
		"rift": {"color": Color("#222222"), "emissive": signature.lightened(0.2), "emissive_energy": 3.0},
	}


static func _mat(rig: AgentRig, pal: Dictionary, id: String) -> ShaderMaterial:
	return rig.material(id, pal[id])


## Flat strap (webbing, harness, belts) following points over a surface. `up` = surface normal
## at the first point; the strap's thin side faces it.
static func _strap(k: FormKit, pts: PackedVector3Array, width: float, thick: float = 0.006, up: Vector3 = Vector3.BACK) -> void:
	var radii := PackedFloat32Array()
	for _i: int in pts.size():
		radii.append(width * 0.5)
	k.tube(pts, radii, 6, thick / width, up, false)


## Points on the front (or back, when back = true) surface of a loft along a polyline in x/y.
static func _on_surface(rings: Array, xy: PackedVector2Array, lift: float, back: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector2 in xy:
		var r := FormKit.at(rings, p.y)
		var u := clampf(absf(p.x - r[FormKit.R_CX]) / maxf(r[FormKit.R_RX], 0.0001), 0.0, 0.999)
		var n := r[FormKit.R_N]
		var k := pow(maxf(0.0, 1.0 - pow(u, n)), 1.0 / n)
		var z := r[FormKit.R_CZ] + (k * r[FormKit.R_ZB] + lift if back else -k * r[FormKit.R_ZF] - lift)
		out.append(Vector3(p.x, p.y, z))
	return out


## Hair styles on the head bone. hr = head rings.
static func _hair(rig: AgentRig, pal: Dictionary, hr: Array, style: String) -> void:
	var hair := _mat(rig, pal, "hair")
	var front := 0.168 if style == "crop" else 0.16
	rig.part("head", hair, func(k: FormKit) -> void: AgentBody.hair_cap(k, hr, front, 0.06, 0.01), "hair")


## Loose cargo trousers over the legs: thigh and shin shells, outer-thigh pockets with flaps.
static func _cargo_pants(rig: AgentRig, pal: Dictionary, f: Dictionary, mat_id: String, pocket_id: String, opts: Dictionary = {}) -> void:
	var mat := _mat(rig, pal, mat_id)
	var pocket := _mat(rig, pal, pocket_id)
	var loose: float = opts.get("loose", 0.012)
	var th := FormKit.grown(f["thigh"], loose)
	var sh := FormKit.grown(f["shin"], loose * 0.8)
	rig.part("hips", mat, func(k: FormKit) -> void:
		k.loft(FormKit.grown(f["pelvis"], loose * 0.5), 18, 1, true, true), "trousers_seat")
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var outer := 0.0 if sx > 0.0 else PI
		rig.part("thigh_" + side, mat, func(k: FormKit) -> void:
			k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * 0.006, 0, 0)))
			k.loft(th, 16, 1, false, true)
			k.reset_transform(), "trouser_thigh")
		rig.part("shin_" + side, mat, func(k: FormKit) -> void:
			k.loft(FormKit.slice(sh, -0.33, 0.05, 0.0, 6), 16, 1, true, true), "trouser_shin")
		if opts.get("pockets", true):
			rig.part("thigh_" + side, pocket, func(k: FormKit) -> void:
				k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * 0.006, 0, 0)))
				k.panel(th, -0.27, -0.12, outer - 0.55, outer + 0.55, 0.012, 4, 8)
				k.color = Color(0.85, 0.85, 0.85)
				k.panel(th, -0.135, -0.105, outer - 0.6, outer + 0.6, 0.02, 2, 8)
				k.reset_transform(), "cargo_pocket")


# ====================================================================== KESTREL

## KESTREL — Norwegian ex-rescue pilot. Signature colour: signal orange.
## Signature shape: cropped flight jacket with a tall shearling collar and a shoulder-mounted
## twin-thruster pack whose nacelles rise in a V behind the shoulders.
static func _kestrel(rig: AgentRig) -> void:
	var pal := _palette(Color("#FF7A1A"), "fair")
	pal["signature"] = {"color": Color("#F2701A"), "roughness": 0.62, "sheen": 0.45}
	pal["cloth"] = {"color": Color("#27303A"), "roughness": 0.8, "sheen": 0.5}  # flight suit, deep slate
	pal["cloth_light"] = {"color": Color("#36404C"), "roughness": 0.82, "sheen": 0.45}
	pal["hair"] = {"color": Color("#E6CB98"), "roughness": 0.62}  # ash blonde
	pal["gloves"] = {"color": Color("#2A2D31"), "roughness": 0.5}
	pal["cream"] = {"color": Color("#D8CBB2"), "roughness": 0.9, "sheen": 0.6}
	pal["sig_dark"] = {"color": Color("#B8501C"), "roughness": 0.7, "sheen": 0.4}
	pal["reflect"] = {"color": Color("#C9CDD2"), "roughness": 0.25, "metallic": 0.5, "emissive": Color("#FFFFFF"), "emissive_energy": 0.15}
	pal["rift"] = {"color": Color("#331a0a"), "emissive": Color("#FFA14A"), "emissive_energy": 4.0}
	var spec := {
		"fem": true, "iris": Color("#3F7FA8"), "brow": Color("#B8925E"),
		"mats": {"torso": "cloth", "legs": "", "upper_arm": "", "forearm": "signature", "hands": "gloves"},
	}
	var f := AgentBody.build(rig, pal, spec)
	var sig := _mat(rig, pal, "signature")
	var cream := _mat(rig, pal, "cream")
	var leather := _mat(rig, pal, "leather")
	var armor := _mat(rig, pal, "armor")
	var webbing := _mat(rig, pal, "webbing")
	var metal := _mat(rig, pal, "metal")
	var rift := _mat(rig, pal, "rift")
	var chest: Array = f["chest"]
	var abd: Array = f["abdomen"]
	# Cropped flight jacket: shell over chest and upper abdomen, ends above the belt with a hem band.
	var jacket_c := FormKit.grown(chest.slice(0, 6), 0.02)
	rig.part("chest", sig, func(k: FormKit) -> void:
		k.loft(jacket_c, 18, 2, false, true), "jacket")
	rig.part("spine", sig, func(k: FormKit) -> void:
		k.loft(FormKit.slice(abd, 0.075, 0.25, 0.02, 4), 18, 1, false, false)
		# Ribbed hem band, cinched.
		k.color = Color(0.8, 0.78, 0.78)
		k.loft(FormKit.slice(abd, 0.045, 0.085, 0.015, 2), 18, 0, true, true), "jacket_low")
	# Bomber sleeves: puffed shells with a shoulder yoke and an elbow seam.
	for side: String in ["l", "r"]:
		var sxs := -1.0 if side == "l" else 1.0
		rig.part("upper_arm_" + side, sig, func(k: FormKit) -> void:
			k.loft(FormKit.grown(f["upper_arm"], 0.012, 1.04), 14, 1, false, true), "sleeve")
		rig.part("forearm_" + side, sig, func(k: FormKit) -> void:
			k.loft(FormKit.slice(f["forearm"], -0.19, 0.04, 0.012, 5), 14, 1, false, true)
			k.color = Color(0.8, 0.78, 0.78)
			k.loft(FormKit.slice(f["forearm"], 0.0, 0.035, 0.016, 2), 14, 0, true, true), "sleeve_low")
		rig.part("shoulder_" + side, sig, func(k: FormKit) -> void:
			k.ellipsoid(Vector3(0.062, 0.064, 0.078), Vector3(sxs * 0.03, -0.008, 0.0), 14, 8), "yoke")
		# Reflective rescue bands on the upper sleeves.
		rig.part("upper_arm_" + side, _mat(rig, pal, "reflect"), func(k: FormKit) -> void:
			k.loft(FormKit.slice(FormKit.grown(f["upper_arm"], 0.012, 1.04), -0.16, -0.125, 0.007, 3), 14, 0, false, false), "reflect")
	# Tall collar (signature): orange stand collar open at the throat, shearling lining + rim.
	var copts := {"y0": 0.225, "height": 0.085, "rx": 0.09, "rzf": 0.078, "rzb": 0.08, "cz": 0.018, "flare": 0.016, "gap": 0.42, "front_drop": 0.4, "thick": 0.012}
	rig.part("chest", sig, func(k: FormKit) -> void: AgentBody.collar(k, true, copts), "collar")
	rig.part("chest", cream, func(k: FormKit) -> void: AgentBody.collar(k, false, copts), "collar_lining")
	# Flight-suit inner collar visible in the opening.
	rig.part("chest", _mat(rig, pal, "cloth"), func(k: FormKit) -> void:
		k.loft([FormKit.ring(0.22, 0.07, 0.062, 0.066, 0.016, 2.0), FormKit.ring(0.262, 0.058, 0.054, 0.058, 0.016, 2.0), FormKit.ring(0.27, 0.056, 0.052, 0.056, 0.016, 2.0)], 16, 0, false, false), "suit_collar")
	# Colour blocking: burnt-orange side panels (chest + waist) and a chest pocket.
	var sig_dark := _mat(rig, pal, "sig_dark")
	rig.part("chest", sig_dark, func(k: FormKit) -> void:
		for c: float in [0.0, PI]:
			k.panel(jacket_c, -0.07, 0.13, c - 0.55, c + 0.55, 0.002, 5, 8)
		k.panel(jacket_c, 0.04, 0.115, -PI * 0.5 - 0.62, -PI * 0.5 - 0.22, 0.004, 3, 5), "side_panels")
	rig.part("spine", sig_dark, func(k: FormKit) -> void:
		for c: float in [0.0, PI]:
			k.panel(FormKit.grown(abd, 0.02), 0.085, 0.25, c - 0.55, c + 0.55, 0.002, 4, 8), "side_panels_low")
	# Jacket front: zipper track + chest pocket flaps.
	rig.part("chest", webbing, func(k: FormKit) -> void:
		_strap(k, _on_surface(jacket_c, PackedVector2Array([Vector2(0.012, 0.25), Vector2(0.012, 0.12), Vector2(0.01, 0.0), Vector2(0.01, -0.07)]), 0.001), 0.012, 0.004, Vector3.FORWARD), "zip")
	rig.part("spine", webbing, func(k: FormKit) -> void:
		_strap(k, _on_surface(FormKit.grown(abd, 0.017), PackedVector2Array([Vector2(0.01, 0.25), Vector2(0.01, 0.07)]), 0.001), 0.012, 0.004, Vector3.FORWARD))
	# Harness: shoulder straps over the jacket into a chest buckle (rescue-pilot rig).
	rig.part("chest", webbing, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var front := _on_surface(jacket_c, PackedVector2Array([Vector2(sx * 0.098, 0.2), Vector2(sx * 0.088, 0.13), Vector2(sx * 0.06, 0.06), Vector2(sx * 0.045, -0.02), Vector2(sx * 0.05, -0.07)]), 0.004)
			var pts := PackedVector3Array([Vector3(sx * 0.1, 0.09, 0.118), Vector3(sx * 0.105, 0.2, 0.11), Vector3(sx * 0.105, 0.262, 0.03)])
			pts.append_array(front)
			_strap(k, pts, 0.034, 0.008, Vector3.BACK)
		# Chest strap.
		_strap(k, _on_surface(jacket_c, PackedVector2Array([Vector2(-0.1, 0.1), Vector2(-0.05, 0.1), Vector2(0.0, 0.1), Vector2(0.05, 0.1), Vector2(0.1, 0.1)]), 0.008), 0.026, 0.007, Vector3.FORWARD), "harness")
	rig.part("chest", metal, func(k: FormKit) -> void:
		var z := FormKit.front_z(jacket_c, 0.0, 0.1)
		k.box(Vector3(0.05, 0.042, 0.016), Vector3(0, 0.1, z - 0.012), 0.008)
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(0.036, 0.022, 0.01), Vector3(sx * 0.085, 0.13, FormKit.front_z(jacket_c, sx * 0.085, 0.13) - 0.01), 0.004), "buckles")
	# Orange signature shoulder patch.
	rig.part("upper_arm_l", cream, func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-0.058, -0.08, 0)))
		k.extrude(PackedVector2Array([Vector2(-0.022, 0.018), Vector2(0.0, 0.004), Vector2(0.022, 0.018), Vector2(0.022, 0.0), Vector2(0.0, -0.016), Vector2(-0.022, 0.0)]), 0.006, Vector3.ZERO, 0.002)
		k.reset_transform(), "patch")
	# Shearling cuffs + forearm sleeves pushed up.
	for side: String in ["l", "r"]:
		rig.part("forearm_" + side, cream, func(k: FormKit) -> void:
			k.loft(FormKit.slice(f["forearm"], -0.235, -0.175, 0.019, 3), 14, 1, true, true), "cuff")
	# Thruster pack (signature): compact back unit + two nacelles in a V above the shoulders.
	rig.part("chest", armor, func(k: FormKit) -> void:
		k.loft([
			FormKit.ring(-0.02, 0.1, 0.03, 0.04, 0.13, 3.2, 0.8),
			FormKit.ring(0.06, 0.125, 0.04, 0.06, 0.14, 3.4),
			FormKit.ring(0.18, 0.13, 0.04, 0.065, 0.14, 3.4),
			FormKit.ring(0.24, 0.1, 0.035, 0.05, 0.135, 3.0),
		], 16, 1, true, true)
		for sx: float in [-1.0, 1.0]:
			k.set_transform(_nacelle_xf(sx))
			k.loft([
				FormKit.ring(-0.16, 0.052, 0.052, 0.052, 0.0, 2.0),
				FormKit.ring(-0.12, 0.06, 0.06, 0.06, 0.0, 2.0),
				FormKit.ring(-0.02, 0.064, 0.064, 0.064, 0.0, 2.0),
				FormKit.ring(0.1, 0.058, 0.058, 0.058, 0.0, 2.0),
				FormKit.ring(0.15, 0.046, 0.046, 0.046, 0.0, 2.0),
			], 16, 1, true, true)
			k.reset_transform(), "thruster_pack")
	rig.part("chest", sig, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(_nacelle_xf(sx))
			# Orange cowl band + intake ring.
			k.loft([FormKit.ring(-0.005, 0.068, 0.068), FormKit.ring(0.055, 0.067, 0.067)], 16, 0, true, true)
			k.loft([FormKit.ring(0.13, 0.054, 0.054), FormKit.ring(0.165, 0.05, 0.05)], 16, 0, true, true)
			k.reset_transform()
		# Orange top plate on the pack body.
		k.loft([FormKit.ring(0.205, 0.118, 0.042, 0.063, 0.14, 3.2), FormKit.ring(0.245, 0.1, 0.037, 0.052, 0.135, 3.0)], 16, 0, true, true), "pack_trim")
	rig.part("chest", metal, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(_nacelle_xf(sx))
			# Flared nozzle bell.
			k.lathe(PackedVector2Array([Vector2(0.05, -0.16), Vector2(0.058, -0.19), Vector2(0.064, -0.215)]), 16, Vector3.ZERO, true, false, false)
			k.reset_transform(), "nozzles")
	rig.part("chest", rift, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(_nacelle_xf(sx))
			k.cylinder(0.05, 0.012, Vector3(0, -0.17, 0), 16, 0.003)
			k.reset_transform()
		# Status strip on the pack.
		k.box(Vector3(0.12, 0.012, 0.008), Vector3(0, 0.12, 0.21), 0.003), "nozzle_glow")
	# Flight-suit trousers with cargo pockets.
	_cargo_pants(rig, pal, f, "cloth_light", "cloth")
	# Belt, holster and kit.
	var pelvis: Array = FormKit.grown(f["pelvis"], 0.006)
	rig.part("hips", leather, func(k: FormKit) -> void:
		k.loft(FormKit.slice(pelvis, 0.06, 0.11, 0.012, 2), 18, 0, true, true)
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(0.06, 0.07, 0.035), Vector3(sx * 0.118, 0.035, FormKit.front_z(pelvis, sx * 0.118, 0.04) - 0.012), 0.012)
		k.box(Vector3(0.11, 0.08, 0.04), Vector3(0.0, 0.05, 0.12), 0.012), "belt")
	rig.part("hips", metal, func(k: FormKit) -> void:
		k.box(Vector3(0.045, 0.038, 0.012), Vector3(0, 0.085, FormKit.front_z(pelvis, 0.0, 0.085) - 0.018), 0.006), "buckle")
	rig.part("thigh_r", leather, func(k: FormKit) -> void:
		var th: Array = FormKit.grown(f["thigh"], 0.012)
		k.set_transform(Transform3D(Basis.IDENTITY, Vector3(0.006, 0, 0)))
		k.loft(FormKit.slice(th, -0.07, -0.045, 0.006, 2), 16, 0, true, true)
		k.loft(FormKit.slice(th, -0.3, -0.275, 0.006, 2), 16, 0, true, true)
		k.reset_transform()
		k.set_transform(Transform3D(Basis(Vector3.UP, -0.25), Vector3(0.0, 0, -0.03)))
		k.box(Vector3(0.05, 0.19, 0.1), Vector3(0.112, -0.17, 0.0), 0.02)
		k.reset_transform(), "holster")
	# Knee pads (orange-rimmed).
	for side: String in ["l", "r"]:
		rig.part("shin_" + side, armor, func(k: FormKit) -> void:
			k.loft([
				FormKit.ring(-0.07, 0.04, 0.012, 0.012, -0.058, 2.4),
				FormKit.ring(-0.03, 0.058, 0.022, 0.02, -0.062, 2.6),
				FormKit.ring(0.04, 0.06, 0.024, 0.02, -0.06, 2.6),
				FormKit.ring(0.075, 0.042, 0.014, 0.012, -0.054, 2.4),
			], 14, 1, true, true), "kneepad")
	# Hair: ash-blonde swept-back undercut with a loose forelock, goggles pushed up.
	var hr: Array = f["head"]
	_kestrel_hair(rig, pal, hr)
	var lens := rig.material("lens", {"color": Color("#FF8A2A"), "roughness": 0.1, "metallic": 0.2, "emissive": Color("#FF7A1A"), "emissive_energy": 0.5})
	rig.part("head", leather, func(k: FormKit) -> void:
		var band := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i: int in 21:
			var a := TAU * i / 20.0
			var y := 0.135 - sin(a) * 0.012
			var r := FormKit.at(hr, y)
			var g := 0.011
			band.append(Vector3(cos(a) * (r[FormKit.R_RX] + g), y, r[FormKit.R_CZ] + sin(a) * ((r[FormKit.R_ZB] if sin(a) > 0.0 else r[FormKit.R_ZF]) + g)))
			radii.append(0.011)
		k.tube(band, radii, 6, 0.4, Vector3.UP), "goggle_band")
	rig.part("head", armor, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -(PI * 0.5 - 0.5)) * Basis(Vector3.FORWARD, 0.0), Vector3(sx * 0.034, 0.148, FormKit.front_z(hr, sx * 0.034, 0.148) - 0.014)))
			k.lathe(PackedVector2Array([Vector2(0.024, -0.014), Vector2(0.026, 0.004), Vector2(0.022, 0.012)]), 14, Vector3.ZERO, true, true, false)
			k.reset_transform()
		k.box(Vector3(0.02, 0.012, 0.012), Vector3(0, 0.15, FormKit.front_z(hr, 0.0, 0.15) - 0.016), 0.004), "goggles")
	rig.part("head", lens, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -(PI * 0.5 - 0.5)), Vector3(sx * 0.034, 0.148, FormKit.front_z(hr, sx * 0.034, 0.148) - 0.014)))
			k.ellipsoid(Vector3(0.021, 0.006, 0.021), Vector3(0, 0.012, 0), 12, 4)
			k.reset_transform(), "goggle_lens")


static func _nacelle_xf(sx: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, sx * -0.3) * Basis(Vector3.RIGHT, 0.2), Vector3(sx * 0.13, 0.25, 0.19)) * Transform3D(Basis.from_scale(Vector3(0.78, 0.78, 0.78)), Vector3.ZERO)


static func _kestrel_hair(rig: AgentRig, pal: Dictionary, hr: Array) -> void:
	var hair := _mat(rig, pal, "hair")
	var under := rig.material("hair_under", {"color": (pal["hair"]["color"] as Color).darkened(0.3), "roughness": 0.7})
	# Short undercut on the sides/back (darker, close to the skull).
	rig.part("head", under, func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.15, 0.035, 0.005, 0.85), "undercut")
	rig.part("head", hair, func(k: FormKit) -> void:
		# Swept-back top with a lifted front.
		AgentBody.hair_mass(k, hr, {"front": -0.094, "back": 0.1, "vol_front": 0.03, "vol_mid": 0.026, "vol_back": 0.012, "side": 0.012, "depth": 0.065, "lift": 0.012})
		# Chunky clumps riding the top, painted highlight mid-strand.
		for i: int in 6:
			var u := (i - 2.5) / 2.5
			var x0 := u * 0.05
			var pts := PackedVector3Array()
			for j: int in 7:
				var t := float(j) / 6.0
				var z := lerpf(-0.07, 0.085, t)
				var x := x0 * lerpf(1.0, 1.35, t)
				var h := AgentBody.skull_top(hr, z) + lerpf(0.034, 0.006, t) - absf(u) * 0.014 + sin(t * PI) * 0.004
				pts.append(Vector3(x, h, z))
			k.tube(pts, PackedFloat32Array([0.014, 0.019, 0.019, 0.016, 0.012, 0.007, 0.002]), 7, 0.32, Vector3.UP,
				true, PackedFloat32Array([0.92, 1.0, 1.0, 0.94, 0.88, 0.84, 0.8])), "hair")


# ====================================================================== shared outfit helpers

## Racing/side stripe panels down both sides of a ring set (angles 0 and PI).
static func _side_stripes(k: FormKit, rings: Array, y0: float, y1: float, half: float, grow: float) -> void:
	for c: float in [0.0, PI]:
		k.panel(rings, y0, y1, c - half, c + half, grow, 4, 4)


## Stripe on the outer side of a limb (sx = +1 right limb, -1 left).
static func _outer_stripe(k: FormKit, rings: Array, y0: float, y1: float, sx: float, half: float, grow: float) -> void:
	var c := 0.0 if sx > 0.0 else PI
	k.panel(rings, y0, y1, c - half, c + half, grow, 5, 4)


## Braid: a tube with a rhythmic bulge (plaited look) along `pts`.
static func _braid(k: FormKit, pts: PackedVector3Array, r: float) -> void:
	var dense := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := (pts.size() - 1) * 3 + 1
	for i: int in n:
		var t := float(i) / (n - 1) * (pts.size() - 1)
		var a := int(floor(t))
		var b := mini(a + 1, pts.size() - 1)
		dense.append(pts[a].lerp(pts[b], t - a))
		radii.append(r * (0.82 + 0.18 * absf(sin(i * PI * 0.5))) * lerpf(1.0, 0.75, float(i) / n))
	k.tube(dense, radii, 6)


# ====================================================================== MAMBA

## MAMBA — Kenyan street racer turned Rift runner. Acid green.
## Signature shape: big racing hood with a wrap-around glowing visor; sleek knee guards; livery
## chevron stripes on a satin-black suit.
static func _mamba(rig: AgentRig) -> void:
	var green := Color("#9BE22B")
	var pal := _palette(green, "deep")
	pal["cloth"] = {"color": Color("#22262B"), "roughness": 0.64, "sheen": 0.3}
	pal["signature"] = {"color": green, "roughness": 0.42, "sheen": 0.45}
	pal["armor"] = {"color": Color("#2C3238"), "roughness": 0.28, "metallic": 0.45, "edge_wear": 0.55}
	pal["gloves"] = {"color": Color("#16181B"), "roughness": 0.45}
	pal["boots"] = {"color": Color("#E4E8EC"), "roughness": 0.5}
	pal["hood"] = {"color": Color("#86C928"), "roughness": 0.7, "sheen": 0.5}
	pal["hood_in"] = {"color": Color("#15181B"), "roughness": 0.8}
	pal["visor"] = {"color": Color("#10200A"), "roughness": 0.05, "metallic": 0.3, "emissive": Color("#B6FF3A"), "emissive_energy": 2.4}
	var spec := {
		"fem": false, "bulk": 0.97, "iris": Color("#3A2416"), "brow": Color("#120C0A"),
		"mats": {"torso": "cloth", "legs": "cloth", "upper_arm": "cloth", "forearm": "cloth", "hands": "gloves"},
		"boot": {"shaft": -0.395, "toe": 0.21},
	}
	var f := AgentBody.build(rig, pal, spec)
	var sig := _mat(rig, pal, "signature")
	var armor := _mat(rig, pal, "armor")
	var hood := _mat(rig, pal, "hood")
	var cloth := _mat(rig, pal, "cloth")
	var chest := FormKit.grown(f["chest"], 0.003)
	# Livery: chevron down the chest, side stripes on torso, arms and legs.
	rig.part("chest", sig, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			_strap(k, _on_surface(chest, PackedVector2Array([Vector2(sx * 0.14, 0.2), Vector2(sx * 0.09, 0.12), Vector2(sx * 0.035, 0.03), Vector2(sx * 0.008, -0.02)]), 0.002), 0.036, 0.004, Vector3.FORWARD)
		_side_stripes(k, chest, -0.07, 0.2, 0.16, 0.002), "livery")
	rig.part("spine", sig, func(k: FormKit) -> void: _side_stripes(k, FormKit.grown(f["abdomen"], 0.003), -0.08, 0.25, 0.16, 0.002))
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		rig.part("upper_arm_" + side, sig, func(k: FormKit) -> void: _outer_stripe(k, f["upper_arm"], -0.3, 0.02, sx, 0.2, 0.003))
		rig.part("forearm_" + side, sig, func(k: FormKit) -> void: _outer_stripe(k, f["forearm"], -0.24, 0.02, sx, 0.22, 0.003))
		rig.part("thigh_" + side, sig, func(k: FormKit) -> void:
			k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * 0.006, 0, 0)))
			_outer_stripe(k, f["thigh"], -0.44, 0.04, sx, 0.16, 0.003)
			k.reset_transform())
		rig.part("shin_" + side, sig, func(k: FormKit) -> void: _outer_stripe(k, f["shin"], -0.4, 0.0, sx, 0.16, 0.003))
		# Sleek knee guards: armour shell with a green inset.
		rig.part("shin_" + side, armor, func(k: FormKit) -> void:
			k.loft([
				FormKit.ring(-0.12, 0.035, 0.01, 0.01, -0.052, 2.4),
				FormKit.ring(-0.07, 0.056, 0.022, 0.02, -0.058, 2.6),
				FormKit.ring(0.02, 0.064, 0.026, 0.022, -0.064, 2.6),
				FormKit.ring(0.07, 0.05, 0.02, 0.016, -0.062, 2.4),
				FormKit.ring(0.09, 0.02, 0.01, 0.01, -0.058, 2.2),
			], 14, 1, true, true), "knee_guard")
		rig.part("shin_" + side, sig, func(k: FormKit) -> void:
			k.loft([FormKit.ring(-0.06, 0.016, 0.006, 0.006, -0.084, 2.2), FormKit.ring(0.04, 0.02, 0.008, 0.008, -0.092, 2.2), FormKit.ring(0.06, 0.012, 0.005, 0.005, -0.088, 2.0)], 8, 1, true, true), "knee_inset")
		rig.part("hand_" + side, sig, func(k: FormKit) -> void:
			k.ellipsoid(Vector3(0.02, 0.012, 0.03), Vector3(sx * 0.016, -0.09, 0.0), 8, 5), "knuckle")
	# Racing collar + spine protector.
	rig.part("chest", sig, func(k: FormKit) -> void:
		k.loft([FormKit.ring(0.235, 0.078, 0.066, 0.07, 0.014, 2.2), FormKit.ring(0.275, 0.064, 0.058, 0.064, 0.016, 2.0), FormKit.ring(0.29, 0.062, 0.056, 0.062, 0.016, 2.0)], 16, 0, false, true), "collar")
	rig.part("chest", armor, func(k: FormKit) -> void:
		for i: int in 4:
			var y := 0.17 - i * 0.075
			k.loft([FormKit.ring(y - 0.03, 0.05, 0.01, 0.018, 0.112 - i * 0.004, 2.8), FormKit.ring(y + 0.03, 0.055, 0.01, 0.02, 0.112 - i * 0.004, 2.8)], 12, 0, true, true), "spine_plate")
	rig.part("spine", armor, func(k: FormKit) -> void:
		k.loft([FormKit.ring(0.02, 0.045, 0.01, 0.016, 0.092, 2.8), FormKit.ring(0.08, 0.05, 0.01, 0.018, 0.092, 2.8)], 12, 0, true, true))
	# Signature hood: deep racing hood framing the face, peak over the visor.
	var hr: Array = f["head"]
	var hood_rings := [
		FormKit.ring(-0.06, 0.112, 0.094, 0.12, 0.03, 2.2),
		FormKit.ring(0.0, 0.106, 0.104, 0.128, 0.016, 2.2),
		FormKit.ring(0.08, 0.104, 0.11, 0.13, 0.01, 2.2),
		FormKit.ring(0.16, 0.1, 0.114, 0.126, 0.008, 2.2),
		FormKit.ring(0.215, 0.086, 0.104, 0.112, 0.012, 2.2),
		FormKit.ring(0.255, 0.058, 0.07, 0.086, 0.02, 2.1),
		FormKit.ring(0.274, 0.02, 0.02, 0.03, 0.026, 2.0),
	]
	var gaps := PackedFloat32Array([0.62, 0.68, 0.66, 0.5, 0.3, 0.1, 0.0])
	rig.part("head", hood, func(k: FormKit) -> void: AgentBody.open_shell(k, hood_rings, true, gaps, 0.014, 26, -PI * 0.5, true, PackedFloat32Array([0.8, 0.88, 0.95, 1, 1, 1, 1])), "hood")
	rig.part("head", _mat(rig, pal, "hood_in"), func(k: FormKit) -> void: AgentBody.open_shell(k, hood_rings, false, gaps, 0.014, 26), "hood_lining")
	rig.part("head", _mat(rig, pal, "visor"), func(k: FormKit) -> void:
		k.panel(hr, 0.082, 0.118, -PI * 0.5 - 1.2, -PI * 0.5 + 1.2, 0.014, 3, 16), "visor")
	rig.part("head", armor, func(k: FormKit) -> void:
		k.panel(hr, 0.118, 0.126, -PI * 0.5 - 1.25, -PI * 0.5 + 1.25, 0.016, 1, 16)
		k.panel(hr, 0.075, 0.082, -PI * 0.5 - 1.25, -PI * 0.5 + 1.25, 0.016, 1, 16), "visor_frame")
	# Drawstring toggles.
	rig.part("chest", cloth, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.strand(PackedVector3Array([Vector3(sx * 0.05, 0.3, -0.085), Vector3(sx * 0.046, 0.24, -0.112), Vector3(sx * 0.044, 0.2, -0.12)]), 0.004, 0.004, 5), "drawstring")


# ====================================================================== VESPER

## VESPER — French astronomer. Deep violet.
## Signature shape: long tailored coat with a split skirt, a star-chart cape that falls to the
## calves, and a floating brass orrery over the right shoulder.
static func _vesper(rig: AgentRig) -> void:
	var violet := Color("#6B3FD6")
	var pal := _palette(violet, "light")
	pal["cloth"] = {"color": Color("#1E1A2B"), "roughness": 0.75, "sheen": 0.4}
	pal["coat"] = {"color": Color("#43308A"), "roughness": 0.62, "sheen": 0.55}
	pal["lining"] = {"color": Color("#9A7CF0"), "roughness": 0.4, "sheen": 0.5}
	pal["brass"] = {"color": Color("#D2A852"), "roughness": 0.28, "metallic": 0.9, "edge_wear": 0.4}
	pal["star"] = {"color": Color("#262150"), "roughness": 0.6, "sheen": 0.5}
	pal["starglow"] = {"color": Color("#B9A6FF"), "emissive": Color("#C9B8FF"), "emissive_energy": 2.2, "no_outline": true}
	pal["gloves"] = {"color": Color("#241D38"), "roughness": 0.5}
	pal["boots"] = {"color": Color("#1E1A26"), "roughness": 0.45, "edge_wear": 0.5}
	pal["hair"] = {"color": Color("#2E1E18"), "roughness": 0.62}
	var spec := {
		"fem": true, "iris": Color("#6E5A9E"), "brow": Color("#2A1A14"),
		"mats": {"torso": "cloth", "legs": "cloth", "upper_arm": "", "forearm": "", "hands": "gloves"},
		"boot": {"shaft": -0.12, "toe": 0.2},
	}
	var f := AgentBody.build(rig, pal, spec)
	var coat := _mat(rig, pal, "coat")
	var lining := _mat(rig, pal, "lining")
	var brass := _mat(rig, pal, "brass")
	var star := _mat(rig, pal, "star")
	var glow := _mat(rig, pal, "starglow")
	var jc := FormKit.grown(f["chest"].slice(0, 6), 0.018)
	rig.part("chest", coat, func(k: FormKit) -> void: k.loft(jc, 18, 2, false, true), "coat")
	rig.part("spine", coat, func(k: FormKit) -> void: k.loft(FormKit.grown(f["abdomen"], 0.018), 18, 1, false, false))
	# Split coat skirt to the knees.
	var skirt := [
		FormKit.ring(0.14, 0.142, 0.106, 0.108, 0.0, 2.3),
		FormKit.ring(0.0, 0.176, 0.114, 0.118, 0.0, 2.3),
		FormKit.ring(-0.15, 0.19, 0.122, 0.132, 0.0, 2.2),
		FormKit.ring(-0.35, 0.208, 0.132, 0.15, 0.0, 2.1),
		FormKit.ring(-0.55, 0.226, 0.142, 0.166, 0.004, 2.0),
	]
	var sg := PackedFloat32Array([0.06, 0.1, 0.2, 0.3, 0.4])
	rig.part("hips", coat, func(k: FormKit) -> void: AgentBody.open_shell(k, skirt, true, sg, 0.012, 26, -PI * 0.5, true, PackedFloat32Array([1, 1, 0.95, 0.9, 0.85])), "coat_skirt")
	rig.part("hips", lining, func(k: FormKit) -> void: AgentBody.open_shell(k, skirt, false, sg, 0.012, 26), "coat_lining")
	# Coat sleeves with turned-back lined cuffs and brass piping.
	for side: String in ["l", "r"]:
		rig.part("upper_arm_" + side, coat, func(k: FormKit) -> void: k.loft(FormKit.grown(f["upper_arm"], 0.01), 14, 1, false, true), "sleeve")
		rig.part("forearm_" + side, coat, func(k: FormKit) -> void: k.loft(FormKit.grown(f["forearm"], 0.01), 14, 1, true, true), "sleeve_low")
		rig.part("forearm_" + side, lining, func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.25, -0.17, 0.02, 3), 14, 1, true, true), "cuff")
		rig.part("forearm_" + side, brass, func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.172, -0.162, 0.022, 2), 14, 0, true, true), "cuff_trim")
		rig.part("shoulder_" + side, coat, func(k: FormKit) -> void:
			k.ellipsoid(Vector3(0.066, 0.06, 0.076), Vector3((-1.0 if side == "l" else 1.0) * 0.03, -0.006, 0.0), 14, 8), "shoulder")
	# High collar (lined) and double-breasted brass buttons, belt.
	var copts := {"y0": 0.22, "height": 0.1, "rx": 0.088, "rzf": 0.078, "rzb": 0.08, "cz": 0.018, "flare": 0.02, "gap": 0.5, "front_drop": 0.35, "thick": 0.012}
	rig.part("chest", coat, func(k: FormKit) -> void: AgentBody.collar(k, true, copts), "collar")
	rig.part("chest", lining, func(k: FormKit) -> void: AgentBody.collar(k, false, copts), "collar_lining")
	rig.part("chest", brass, func(k: FormKit) -> void:
		for row: int in 4:
			var y := 0.17 - row * 0.065
			for sx: float in [-1.0, 1.0]:
				var x := sx * 0.048
				k.ellipsoid(Vector3(0.009, 0.009, 0.005), Vector3(x, y, FormKit.front_z(jc, x, y) - 0.002), 8, 5)
		k.loft(FormKit.slice(jc, -0.065, -0.05, 0.004, 2), 18, 0, true, true), "buttons")
	rig.part("spine", brass, func(k: FormKit) -> void:
		var ab := FormKit.grown(f["abdomen"], 0.018)
		for row: int in 2:
			var y := 0.2 - row * 0.07
			for sx: float in [-1.0, 1.0]:
				var x := sx * 0.045
				k.ellipsoid(Vector3(0.009, 0.009, 0.005), Vector3(x, y, FormKit.front_z(ab, x, y) - 0.002), 8, 5)
		k.loft(FormKit.slice(ab, 0.02, 0.045, 0.004, 2), 18, 0, true, true)
		k.box(Vector3(0.045, 0.034, 0.012), Vector3(0, 0.033, FormKit.front_z(ab, 0.0, 0.033) - 0.008), 0.005), "belt")
	# Star-chart cape: navy outside with a glowing constellation, violet lining.
	var cape := [
		FormKit.ring(0.235, 0.168, 0.1, 0.122, 0.0, 2.4),
		FormKit.ring(0.12, 0.205, 0.11, 0.148, 0.01, 2.3),
		FormKit.ring(-0.2, 0.232, 0.12, 0.18, 0.02, 2.2),
		FormKit.ring(-0.6, 0.258, 0.13, 0.205, 0.03, 2.1),
		FormKit.ring(-0.94, 0.276, 0.14, 0.225, 0.04, 2.0),
	]
	var cg := PackedFloat32Array([1.62, 1.66, 1.78, 1.88, 1.96])
	rig.part("chest", star, func(k: FormKit) -> void: AgentBody.open_shell(k, cape, true, cg, 0.012, 22, -PI * 0.5, true, PackedFloat32Array([1, 1, 0.95, 0.9, 0.85])), "cape")
	rig.part("chest", lining, func(k: FormKit) -> void: AgentBody.open_shell(k, cape, false, cg, 0.012, 22), "cape_lining")
	rig.part("chest", glow, func(k: FormKit) -> void:
		# Constellation: stars on the cape surface joined by thin light lines.
		var pts: Array[Vector2] = [Vector2(0.1, 0.42), Vector2(-0.2, 0.35), Vector2(-0.45, 0.5), Vector2(-0.62, 0.28), Vector2(-0.8, 0.45), Vector2(-0.3, 0.75), Vector2(-0.55, 0.85), Vector2(0.0, 0.62)]
		var world := PackedVector3Array()
		for p: Vector2 in pts:
			var r := FormKit.at(cape, p.x)
			var a := PI * 0.5 + (p.y - 0.55) * 2.0
			var q := FormKit.ring_point(r, a)
			var c := Vector3(r[FormKit.R_CX], p.x, r[FormKit.R_CZ])
			q += Vector3(q.x - c.x, 0, q.z - c.z).normalized() * 0.009
			world.append(q)
			k.ellipsoid(Vector3(0.008, 0.008, 0.008), q, 6, 4)
		for e: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(1, 7), Vector2i(7, 5), Vector2i(5, 6), Vector2i(6, 4)]:
			k.strand(PackedVector3Array([world[e.x], world[e.y]]), 0.0022, 0.0022, 4), "constellation")
	# Floating orrery over the right shoulder.
	var o := Vector3(0.3, 0.52, 0.06)
	rig.part("chest", brass, func(k: FormKit) -> void:
		for ring_i: int in 3:
			var rr := 0.13 - ring_i * 0.03
			var xf := Transform3D(Basis(Vector3.RIGHT, 0.4 + ring_i * 0.7) * Basis(Vector3.BACK, ring_i * 0.9), o)
			var loop := PackedVector3Array()
			var rad := PackedFloat32Array()
			for j: int in 25:
				var a := TAU * j / 24.0
				loop.append(xf * Vector3(cos(a) * rr, 0, sin(a) * rr))
				rad.append(0.007)
			k.tube(loop, rad, 6, 1.0, Vector3.UP, false)
			k.ellipsoid(Vector3(0.02, 0.02, 0.02) * (1.0 - ring_i * 0.2), xf * Vector3(rr, 0, 0), 8, 6)
		k.strand(PackedVector3Array([o + Vector3(0, -0.1, 0), o + Vector3(0, 0.1, 0)]), 0.003, 0.003, 5), "orrery")
	rig.part("chest", glow, func(k: FormKit) -> void: k.ellipsoid(Vector3(0.032, 0.032, 0.032), o, 10, 8), "orrery_core")
	# Hair: dark chin-length bob swept to one side, low bun with a brass pin.
	var hr: Array = f["head"]
	var hair := _mat(rig, pal, "hair")
	rig.part("head", hair, func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.17, 0.0, 0.01, 0.82, 0.07)
		AgentBody.hair_mass(k, hr, {"front": -0.09, "back": 0.11, "vol_front": 0.022, "vol_mid": 0.02, "vol_back": 0.016, "side": 0.02, "depth": 0.08, "drop": 0.06})
		# Side-swept fringe and bob panels framing the face.
		for sx: float in [-1.0, 1.0]:
			var x0 := sx * 0.074
			k.tube(FormKit.bezier3(Vector3(sx * 0.03, 0.2, -0.085), Vector3(x0, 0.17, -0.09), Vector3(x0 + sx * 0.012, 0.08, -0.06), Vector3(x0 + sx * 0.004, 0.025, -0.04), 8),
				PackedFloat32Array([0.016, 0.022, 0.024, 0.024, 0.022, 0.018, 0.012, 0.005]), 8, 0.55, Vector3(sx, 0, 0))
		k.tube(FormKit.bezier3(Vector3(-0.06, 0.205, -0.07), Vector3(0.0, 0.215, -0.11), Vector3(0.05, 0.17, -0.105), Vector3(0.075, 0.13, -0.08), 7),
			PackedFloat32Array([0.012, 0.02, 0.022, 0.02, 0.016, 0.01, 0.004]), 8, 0.4, Vector3.FORWARD)
		k.ellipsoid(Vector3(0.05, 0.042, 0.04), Vector3(0, 0.06, 0.12), 12, 8), "hair")
	rig.part("head", brass, func(k: FormKit) -> void:
		k.strand(PackedVector3Array([Vector3(-0.07, 0.05, 0.12), Vector3(0.07, 0.08, 0.13)]), 0.004, 0.004, 6)
		k.ellipsoid(Vector3(0.01, 0.01, 0.01), Vector3(0.072, 0.08, 0.13), 8, 6), "hairpin")


# ====================================================================== HALDOR

## HALDOR — Icelandic geothermal engineer. Steam white and basalt black.
## Signature shape: bulky quilted heat-suit under a basalt plate rig, twin exhaust stacks rising
## above the head, and a gauntlet nozzle on the right forearm.
static func _haldor(rig: AgentRig) -> void:
	var pal := _palette(Color("#E8E4DC"), "fair")
	pal["suit"] = {"color": Color("#DDD7CB"), "roughness": 0.8, "sheen": 0.45}
	pal["basalt"] = {"color": Color("#26272B"), "roughness": 0.5, "metallic": 0.25, "edge_wear": 0.55}
	pal["vent"] = {"color": Color("#331a0a"), "emissive": Color("#FF7A3A"), "emissive_energy": 3.0}
	pal["hair"] = {"color": Color("#B98552"), "roughness": 0.62}
	pal["boots"] = {"color": Color("#26272B"), "roughness": 0.55, "edge_wear": 0.5}
	var spec := {
		"fem": false, "bulk": 1.14, "iris": Color("#5C8AA0"), "brow": Color("#9A6A40"),
		"mats": {"torso": "suit", "legs": "suit", "upper_arm": "suit", "forearm": "suit", "hands": "basalt"},
		"boot": {"shaft": -0.25, "toe": 0.22, "chunk": 1.5}, "hand_scale": 1.2,
	}
	var f := AgentBody.build(rig, pal, spec)
	var suit := _mat(rig, pal, "suit")
	var basalt := _mat(rig, pal, "basalt")
	var vent := _mat(rig, pal, "vent")
	# Quilted padding: puffed shells with darker stitch lines.
	rig.part("chest", suit, func(k: FormKit) -> void:
		var pad := FormKit.grown(f["chest"].slice(0, 6), 0.03)
		k.loft(pad, 18, 2, false, true)
		k.color = Color(0.72, 0.7, 0.68)
		for y: float in [-0.02, 0.06, 0.14]:
			k.loft(FormKit.slice(pad, y, y + 0.01, 0.002, 2), 18, 0, false, false), "padding")
	rig.part("spine", suit, func(k: FormKit) -> void:
		var pad := FormKit.grown(f["abdomen"], 0.028)
		k.loft(pad, 18, 1, false, false)
		k.color = Color(0.72, 0.7, 0.68)
		for y: float in [0.03, 0.12]:
			k.loft(FormKit.slice(pad, y, y + 0.01, 0.002, 2), 18, 0, false, false))
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		rig.part("upper_arm_" + side, suit, func(k: FormKit) -> void:
			var pad := FormKit.grown(f["upper_arm"], 0.018)
			k.loft(pad, 14, 1, false, true)
			k.color = Color(0.72, 0.7, 0.68)
			k.loft(FormKit.slice(pad, -0.13, -0.12, 0.002, 2), 14, 0, false, false), "pad_arm")
		rig.part("thigh_" + side, suit, func(k: FormKit) -> void:
			k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * 0.006, 0, 0)))
			k.loft(FormKit.grown(f["thigh"], 0.016), 16, 1, false, true)
			k.reset_transform(), "pad_leg")
		# Basalt pauldrons (layered), knee plates, left bracer.
		rig.part("shoulder_" + side, basalt, func(k: FormKit) -> void:
			for layer: int in 2:
				k.set_transform(Transform3D(Basis(Vector3.BACK, sx * (-0.35 - layer * 0.25)), Vector3(sx * (0.05 + layer * 0.03), 0.02 - layer * 0.05, 0.0)))
				k.loft([
					FormKit.ring(-0.03, 0.085, 0.09, 0.09, 0.0, 2.6, 0.8),
					FormKit.ring(0.0, 0.092, 0.098, 0.098, 0.0, 2.6),
					FormKit.ring(0.03, 0.07, 0.076, 0.076, 0.0, 2.4),
					FormKit.ring(0.045, 0.02, 0.02, 0.02, 0.0, 2.0),
				], 16, 1, true, true)
				k.reset_transform(), "pauldron")
		rig.part("shin_" + side, basalt, func(k: FormKit) -> void:
			k.loft([
				FormKit.ring(-0.16, 0.05, 0.016, 0.012, -0.066, 2.6),
				FormKit.ring(-0.03, 0.066, 0.026, 0.02, -0.072, 2.8),
				FormKit.ring(0.06, 0.06, 0.024, 0.018, -0.07, 2.6),
				FormKit.ring(0.09, 0.03, 0.012, 0.01, -0.064, 2.2),
			], 14, 1, true, true), "knee_plate")
	rig.part("forearm_l", basalt, func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.22, -0.02, 0.022, 4), 14, 1, true, true), "bracer")
	# Gauntlet nozzle (signature): heavy right gauntlet with a vent barrel along the forearm.
	rig.part("forearm_r", basalt, func(k: FormKit) -> void:
		k.loft(FormKit.grown(FormKit.slice(f["forearm"], -0.26, 0.02, 0.0, 5), 0.032, 1.05), 16, 1, true, true)
		k.set_transform(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.12, -0.075)))
		k.loft([
			FormKit.ring(-0.17, 0.034, 0.034, 0.034, 0.0, 2.0),
			FormKit.ring(-0.12, 0.03, 0.03, 0.03, 0.0, 2.0),
			FormKit.ring(0.06, 0.03, 0.03, 0.03, 0.0, 2.0),
			FormKit.ring(0.1, 0.022, 0.022, 0.022, 0.0, 2.0),
		], 14, 1, true, true)
		k.reset_transform(), "gauntlet")
	rig.part("forearm_r", vent, func(k: FormKit) -> void:
		k.cylinder(0.024, 0.01, Vector3(0, -0.295, -0.075), 14, 0.002)
		for i: int in 3:
			k.loft(FormKit.slice(FormKit.grown(f["forearm"], 0.034, 1.05), -0.06 - i * 0.04, -0.05 - i * 0.04, 0.0, 2), 16, 0, false, false), "gauntlet_vents")
	# Basalt plate rig: chest plate, back frame and twin exhaust stacks (signature).
	var plate := FormKit.grown(f["chest"].slice(0, 6), 0.046)
	rig.part("chest", basalt, func(k: FormKit) -> void:
		k.loft(FormKit.slice(plate, 0.0, 0.19, 0.0, 4), 18, 1, true, true)
		k.loft([
			FormKit.ring(-0.04, 0.13, 0.04, 0.07, 0.17, 3.2, 0.8),
			FormKit.ring(0.1, 0.15, 0.05, 0.08, 0.17, 3.4),
			FormKit.ring(0.24, 0.13, 0.045, 0.07, 0.165, 3.0),
		], 16, 1, true, true)
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * -0.12), Vector3(sx * 0.1, 0.0, 0.22)))
			k.loft([
				FormKit.ring(0.05, 0.052, 0.052, 0.052, 0.0, 2.0),
				FormKit.ring(0.3, 0.048, 0.048, 0.048, 0.0, 2.0),
				FormKit.ring(0.56, 0.044, 0.044, 0.044, 0.0, 2.0),
				FormKit.ring(0.6, 0.056, 0.056, 0.056, 0.0, 2.0),
				FormKit.ring(0.66, 0.056, 0.056, 0.056, 0.0, 2.0),
			], 14, 1, true, true)
			k.reset_transform(), "stacks")
	rig.part("chest", suit, func(k: FormKit) -> void:
		# Steam-white bands on the stacks and a chest emblem plate.
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * -0.12), Vector3(sx * 0.1, 0.0, 0.22)))
			k.loft([FormKit.ring(0.36, 0.052, 0.052), FormKit.ring(0.42, 0.052, 0.052)], 14, 0, true, true)
			k.reset_transform()
		k.panel(plate, 0.06, 0.15, -PI * 0.5 - 0.3, -PI * 0.5 + 0.3, 0.004, 3, 6), "stack_bands")
	rig.part("chest", vent, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * -0.12), Vector3(sx * 0.1, 0.0, 0.22)))
			k.cylinder(0.044, 0.01, Vector3(0, 0.662, 0), 14, 0.002)
			k.loft([FormKit.ring(0.5, 0.047, 0.047), FormKit.ring(0.53, 0.047, 0.047)], 14, 0, true, true)
			k.reset_transform(), "stack_vents")
	# Belt.
	rig.part("hips", basalt, func(k: FormKit) -> void:
		var pv := FormKit.grown(f["pelvis"], 0.012)
		k.loft(FormKit.slice(pv, 0.07, 0.13, 0.008, 2), 18, 0, true, true)
		k.box(Vector3(0.07, 0.06, 0.02), Vector3(0, 0.1, FormKit.front_z(pv, 0.0, 0.1) - 0.016), 0.01), "belt")
	# Head: auburn crop with a short braid, full beard and moustache.
	var hr: Array = f["head"]
	var hair := _mat(rig, pal, "hair")
	rig.part("head", hair, func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.165, 0.03, 0.007, 0.8, 0.02)
		AgentBody.hair_mass(k, hr, {"front": -0.09, "back": 0.1, "vol_front": 0.02, "vol_mid": 0.022, "vol_back": 0.01, "side": 0.006, "depth": 0.05})
		_braid(k, FormKit.bezier(Vector3(0, 0.17, 0.1), Vector3(0, 0.12, 0.135), Vector3(0, 0.0, 0.12), 5), 0.013), "hair")
	rig.part("head", rig.material("beard", {"color": Color("#A8703F"), "roughness": 0.6}), func(k: FormKit) -> void:
		AgentBody.beard(k, hr, 0.028, 0.085, 0.014, 1.75, -0.012, 0.03)
		for sx: float in [-1.0, 1.0]:
			k.tube(FormKit.bezier(Vector3(sx * 0.003, 0.058, FormKit.front_z(hr, 0.0, 0.058) - 0.01), Vector3(sx * 0.026, 0.058, FormKit.front_z(hr, 0.026, 0.058) - 0.011), Vector3(sx * 0.036, 0.032, FormKit.front_z(hr, 0.036, 0.032) - 0.01), 6),
				PackedFloat32Array([0.008, 0.009, 0.009, 0.008, 0.006, 0.004]), 7, 0.7, Vector3.FORWARD), "beard")


# ====================================================================== ORIN

## ORIN — Australian outback tracker. Dusty ochre.
## Signature shape: wide-brim hat, striped poncho with a broad A-line, mechanical hawk perched on
## the left shoulder.
static func _orin(rig: AgentRig) -> void:
	var ochre := Color("#C8913A")
	var pal := _palette(ochre, "tan")
	pal["cloth"] = {"color": Color("#7D6B4E"), "roughness": 0.85, "sheen": 0.4}  # khaki shirt
	pal["cloth_light"] = {"color": Color("#54453A"), "roughness": 0.85, "sheen": 0.4}  # trousers
	pal["signature"] = {"color": ochre, "roughness": 0.85, "sheen": 0.6}
	pal["weave"] = {"color": Color("#6E3F22"), "roughness": 0.85, "sheen": 0.5}
	pal["cream"] = {"color": Color("#E2D2AE"), "roughness": 0.85, "sheen": 0.5}
	pal["hat"] = {"color": Color("#6B4B2F"), "roughness": 0.7, "sheen": 0.4}
	pal["drone"] = {"color": Color("#8C9096"), "roughness": 0.32, "metallic": 0.75, "edge_wear": 0.5}
	pal["eye_glow"] = {"color": Color("#3a2000"), "emissive": Color("#FFB04A"), "emissive_energy": 3.0}
	pal["hair"] = {"color": Color("#2E2018"), "roughness": 0.62}
	var spec := {
		"fem": false, "bulk": 1.02, "iris": Color("#4A3A22"), "brow": Color("#2A1C14"),
		"mats": {"torso": "cloth", "legs": "", "upper_arm": "cloth", "forearm": "skin", "hands": "gloves"},
	}
	pal["gloves"] = {"color": Color("#4A3828"), "roughness": 0.6}
	var f := AgentBody.build(rig, pal, spec)
	_cargo_pants(rig, pal, f, "cloth_light", "weave", {"loose": 0.014})
	var poncho := _mat(rig, pal, "signature")
	var weave := _mat(rig, pal, "weave")
	var cream := _mat(rig, pal, "cream")
	# Rolled shirt sleeves.
	for side: String in ["l", "r"]:
		rig.part("forearm_" + side, _mat(rig, pal, "cloth"), func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.04, 0.04, 0.014, 3), 14, 1, true, true), "rolled_sleeve")
	# Poncho (signature): wide A-line drape with woven stripes and a fringe hem.
	var pon := [
		FormKit.ring(0.272, 0.07, 0.062, 0.068, 0.016, 2.0),
		FormKit.ring(0.235, 0.17, 0.11, 0.118, 0.012, 2.4),
		FormKit.ring(0.17, 0.27, 0.15, 0.16, 0.01, 2.6),
		FormKit.ring(0.06, 0.315, 0.17, 0.18, 0.012, 2.6),
		FormKit.ring(-0.08, 0.335, 0.18, 0.19, 0.014, 2.6),
	]
	var pg := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	rig.part("chest", poncho, func(k: FormKit) -> void: AgentBody.open_shell(k, pon, true, pg, 0.012, 28, -PI * 0.5, true, PackedFloat32Array([1, 1, 1, 0.92, 0.85])), "poncho")
	rig.part("chest", weave, func(k: FormKit) -> void:
		AgentBody.open_shell(k, pon, false, pg, 0.012, 28)
		for band: Vector2 in [Vector2(0.11, 0.135), Vector2(-0.035, -0.01)]:
			var b := [FormKit.at(pon, band.x), FormKit.at(pon, band.y)]
			AgentBody.open_shell(k, b, true, PackedFloat32Array([0.0, 0.0]), 0.016, 28, -PI * 0.5, false), "poncho_weave")
	rig.part("chest", cream, func(k: FormKit) -> void:
		for band: Vector2 in [Vector2(0.14, 0.15), Vector2(0.095, 0.105), Vector2(-0.045, -0.038)]:
			var b := [FormKit.at(pon, band.x), FormKit.at(pon, band.y)]
			AgentBody.open_shell(k, b, true, PackedFloat32Array([0.0, 0.0]), 0.017, 28, -PI * 0.5, false), "poncho_stripes")
	rig.part("chest", weave, func(k: FormKit) -> void:
		# Fringe tassels along the hem.
		var hem: PackedFloat32Array = pon[pon.size() - 1]
		for j: int in 28:
			var a := TAU * j / 28.0
			var p := FormKit.ring_point(hem, a)
			k.strand(PackedVector3Array([p, p + Vector3(0, -0.045, 0)]), 0.006, 0.004, 4), "fringe")
	# Wide-brim hat (signature): pinched crown, brim with an upturned edge, leather band.
	var hr: Array = f["head"]
	var hat := _mat(rig, pal, "hat")
	rig.part("head", hat, func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0, 0.0, 0.0)))
		k.lathe(PackedVector2Array([Vector2(0.105, 0.155), Vector2(0.15, 0.158), Vector2(0.2, 0.163), Vector2(0.235, 0.175), Vector2(0.245, 0.186), Vector2(0.235, 0.19), Vector2(0.2, 0.172), Vector2(0.15, 0.168), Vector2(0.105, 0.168)]), 28, Vector3.ZERO, true, false, false)
		k.loft([
			FormKit.ring(0.16, 0.096, 0.1, 0.112, 0.008, 2.2),
			FormKit.ring(0.22, 0.09, 0.094, 0.104, 0.008, 2.3),
			FormKit.ring(0.27, 0.078, 0.08, 0.092, 0.01, 2.5),
			FormKit.ring(0.29, 0.05, 0.055, 0.065, 0.012, 2.6),
			FormKit.ring(0.284, 0.01, 0.01, 0.01, 0.012, 2.0),
		], 20, 1, false, true)
		k.reset_transform(), "hat")
	rig.part("head", _mat(rig, pal, "leather"), func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3.ZERO))
		k.loft([FormKit.ring(0.172, 0.1, 0.104, 0.116, 0.008, 2.2), FormKit.ring(0.192, 0.098, 0.102, 0.114, 0.008, 2.2)], 20, 0, false, false)
		k.reset_transform(), "hatband")
	rig.part("head", _mat(rig, pal, "hair"), func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.16, 0.03, 0.007, 0.8, 0.02), "hair")
	rig.part("head", rig.material("beard", {"color": (pal["skin"]["color"] as Color).lerp(Color("#2E2018"), 0.55), "roughness": 0.8}), func(k: FormKit) -> void:
		AgentBody.beard(k, hr, 0.03, 0.08, 0.004, 1.7)
		for sx: float in [-1.0, 1.0]:
			k.tube(FormKit.bezier(Vector3(sx * 0.003, 0.057, FormKit.front_z(hr, 0.0, 0.057) - 0.006), Vector3(sx * 0.022, 0.057, FormKit.front_z(hr, 0.022, 0.057) - 0.006), Vector3(sx * 0.03, 0.04, FormKit.front_z(hr, 0.03, 0.04) - 0.004), 5),
				PackedFloat32Array([0.005, 0.006, 0.006, 0.005, 0.003]), 6, 0.6, Vector3.FORWARD), "stubble")
	# Mechanical hawk drone perched on the left shoulder.
	var drone := _mat(rig, pal, "drone")
	rig.part("shoulder_l", drone, func(k: FormKit) -> void:
		var b := Vector3(-0.07, 0.17, 0.02)
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.5), b))
		k.loft([
			FormKit.ring(-0.09, 0.012, 0.01, 0.01, 0.0, 2.0),
			FormKit.ring(-0.05, 0.036, 0.034, 0.03, 0.0, 2.2),
			FormKit.ring(0.0, 0.044, 0.044, 0.038, 0.0, 2.3),
			FormKit.ring(0.05, 0.034, 0.034, 0.03, -0.004, 2.2),
			FormKit.ring(0.075, 0.016, 0.016, 0.016, -0.006, 2.0),
		], 12, 1, true, true)
		k.reset_transform()
		# Head + hooked beak.
		k.ellipsoid(Vector3(0.026, 0.026, 0.03), b + Vector3(0, 0.07, -0.04), 10, 6)
		k.tube(FormKit.bezier(b + Vector3(0, 0.072, -0.068), b + Vector3(0, 0.07, -0.09), b + Vector3(0, 0.05, -0.088), 5), PackedFloat32Array([0.009, 0.007, 0.005, 0.003, 0.0015]), 6)
		# Folded wings and tail feathers (flat blades).
		for sx: float in [-1.0, 1.0]:
			k.tube(FormKit.bezier(b + Vector3(sx * 0.036, 0.04, -0.02), b + Vector3(sx * 0.05, 0.0, 0.05), b + Vector3(sx * 0.03, -0.06, 0.11), 6), PackedFloat32Array([0.03, 0.034, 0.03, 0.024, 0.014, 0.004]), 8, 0.25, Vector3(sx, 0, 0))
		for t: int in 3:
			k.tube(PackedVector3Array([b + Vector3((t - 1) * 0.012, -0.05, 0.06), b + Vector3((t - 1) * 0.022, -0.12, 0.12)]), PackedFloat32Array([0.014, 0.012]), 6, 0.25, Vector3.BACK, true)
		# Talons gripping the shoulder.
		for sx: float in [-1.0, 1.0]:
			k.strand(PackedVector3Array([b + Vector3(sx * 0.018, -0.04, 0), b + Vector3(sx * 0.02, -0.075, -0.012)]), 0.006, 0.004, 5), "hawk")
	rig.part("shoulder_l", _mat(rig, pal, "eye_glow"), func(k: FormKit) -> void:
		var b := Vector3(-0.07, 0.17, 0.02)
		for sx: float in [-1.0, 1.0]:
			k.ellipsoid(Vector3(0.006, 0.006, 0.006), b + Vector3(sx * 0.019, 0.078, -0.052), 6, 4)
		k.panel([FormKit.ring(-0.1, 0.045, 0.045, 0.04, 0.0, 2.3), FormKit.ring(0.1, 0.045, 0.045, 0.04, 0.0, 2.3)], -0.004, 0.004, -PI * 0.5 - 0.5, -PI * 0.5 + 0.5, 0.0, 1, 4), "hawk_eyes")


# ====================================================================== SABLE

## SABLE — Korean signal hacker. Electric cyan-blue with white trim (separates her from ally cyan).
## Signature shape: oversized boxy jacket with dropped shoulders and long sleeves, big headphones,
## cables looping from a back module, holographic tablet on the left forearm.
static func _sable(rig: AgentRig) -> void:
	var blue := Color("#2F8CFF")
	var pal := _palette(blue, "light")
	pal["signature"] = {"color": blue, "roughness": 0.6, "sheen": 0.55}
	pal["trim"] = {"color": Color("#F4F6FA"), "roughness": 0.6, "sheen": 0.3}
	pal["cloth"] = {"color": Color("#1B1E26"), "roughness": 0.7, "sheen": 0.4}
	pal["cloth_light"] = {"color": Color("#252A34"), "roughness": 0.75, "sheen": 0.4}
	pal["cable"] = {"color": Color("#15171B"), "roughness": 0.55}
	pal["holo"] = {"color": Color("#0B2440"), "emissive": Color("#3FA8FF"), "emissive_energy": 1.4, "no_outline": true}
	pal["boots"] = {"color": Color("#EEF1F5"), "roughness": 0.55}
	pal["hair"] = {"color": Color("#16141A"), "roughness": 0.62}
	var spec := {
		"fem": true, "bulk": 0.96, "iris": Color("#2E2218"), "brow": Color("#16121A"),
		"mats": {"torso": "cloth", "legs": "cloth_light", "upper_arm": "", "forearm": "", "hands": "skin"},
		"boot": {"shaft": -0.38, "toe": 0.21, "chunk": 1.6},
	}
	var f := AgentBody.build(rig, pal, spec)
	var sig := _mat(rig, pal, "signature")
	var trim := _mat(rig, pal, "trim")
	var cable := _mat(rig, pal, "cable")
	var holo := _mat(rig, pal, "holo")
	# Oversized jacket: boxy shells over chest, abdomen and hips.
	var jc := FormKit.grown(f["chest"].slice(0, 6), 0.036)
	for r: PackedFloat32Array in jc:
		r[FormKit.R_N] = r[FormKit.R_N] + 0.4
	var ja := FormKit.grown(f["abdomen"], 0.04)
	var jp := FormKit.grown(FormKit.slice(f["pelvis"], -0.01, 0.14, 0.0, 3), 0.042)
	rig.part("chest", sig, func(k: FormKit) -> void: k.loft(jc, 18, 2, false, true), "jacket")
	rig.part("spine", sig, func(k: FormKit) -> void: k.loft(ja, 18, 1, false, false))
	rig.part("hips", sig, func(k: FormKit) -> void: k.loft(jp, 18, 1, false, false), "jacket_hem")
	rig.part("hips", trim, func(k: FormKit) -> void:
		k.loft(FormKit.slice(jp, -0.025, 0.005, 0.006, 2), 18, 0, true, true), "hem_trim")
	rig.part("chest", trim, func(k: FormKit) -> void:
		_strap(k, _on_surface(jc, PackedVector2Array([Vector2(0.014, 0.21), Vector2(0.014, 0.1), Vector2(0.012, -0.07)]), 0.002), 0.016, 0.004, Vector3.FORWARD)
		# White trim yoke across the shoulders.
		k.panel(jc, 0.17, 0.195, -PI * 0.5 - 1.25, -PI * 0.5 + 1.25, 0.004, 1, 12), "trim")
	rig.part("spine", trim, func(k: FormKit) -> void:
		_strap(k, _on_surface(ja, PackedVector2Array([Vector2(0.014, 0.25), Vector2(0.014, -0.08)]), 0.002), 0.016, 0.004, Vector3.FORWARD))
	rig.part("hips", trim, func(k: FormKit) -> void:
		_strap(k, _on_surface(jp, PackedVector2Array([Vector2(0.014, 0.14), Vector2(0.014, -0.01)]), 0.002), 0.016, 0.004, Vector3.FORWARD))
	# Dropped shoulders and long oversized sleeves that swallow the wrists.
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		rig.part("shoulder_" + side, sig, func(k: FormKit) -> void:
			k.ellipsoid(Vector3(0.085, 0.07, 0.095), Vector3(sx * 0.03, -0.02, 0.0), 14, 8), "drop_shoulder")
		rig.part("upper_arm_" + side, sig, func(k: FormKit) -> void: k.loft(FormKit.grown(f["upper_arm"], 0.026, 1.05), 14, 1, false, true), "sleeve")
		rig.part("forearm_" + side, sig, func(k: FormKit) -> void:
			var fr: Array = [FormKit.ring(0.04, 0.062, 0.062), FormKit.ring(-0.1, 0.06, 0.056), FormKit.ring(-0.22, 0.054, 0.05), FormKit.ring(-0.27, 0.052, 0.048)]
			k.loft(fr, 14, 1, true, true), "sleeve_low")
		rig.part("forearm_" + side, trim, func(k: FormKit) -> void:
			k.loft([FormKit.ring(-0.275, 0.054, 0.05), FormKit.ring(-0.25, 0.056, 0.052)], 14, 0, true, true)
			k.loft([FormKit.ring(-0.03, 0.065, 0.065), FormKit.ring(-0.015, 0.065, 0.065)], 14, 0, false, false), "cuff_trim")
	# Hood bunched behind the neck.
	rig.part("chest", sig, func(k: FormKit) -> void:
		k.tube(FormKit.bezier(Vector3(-0.1, 0.25, 0.0), Vector3(0.0, 0.3, 0.16), Vector3(0.1, 0.25, 0.0), 9), PackedFloat32Array([0.025, 0.035, 0.042, 0.045, 0.046, 0.045, 0.042, 0.035, 0.025]), 10, 0.75, Vector3.UP), "hood_roll")
	# Headphones around the neck (black cups with cyan rings).
	rig.part("chest", cable, func(k: FormKit) -> void:
		k.tube(FormKit.bezier(Vector3(-0.085, 0.3, -0.02), Vector3(0.0, 0.3, 0.12), Vector3(0.085, 0.3, -0.02), 8), PackedFloat32Array([0.008, 0.009, 0.009, 0.009, 0.009, 0.009, 0.009, 0.008]), 7, 0.6, Vector3.UP)
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * PI * 0.5) * Basis(Vector3.RIGHT, -0.4), Vector3(sx * 0.098, 0.285, -0.035)))
			k.loft([FormKit.ring(-0.016, 0.036, 0.04), FormKit.ring(0.0, 0.042, 0.046), FormKit.ring(0.016, 0.038, 0.042), FormKit.ring(0.02, 0.026, 0.03)], 14, 1, true, true)
			k.reset_transform()
		# Back signal module + cables looping to the front pocket.
		k.loft([FormKit.ring(0.0, 0.06, 0.02, 0.03, 0.16, 3.2), FormKit.ring(0.14, 0.065, 0.02, 0.032, 0.16, 3.2), FormKit.ring(0.16, 0.05, 0.016, 0.024, 0.158, 3.0)], 12, 1, true, true)
		for i: int in 3:
			var off := i * 0.018
			k.strand(FormKit.bezier3(Vector3(0.05, 0.02 + off, 0.18), Vector3(0.24 + off, -0.02, 0.17), Vector3(0.26 + off, -0.12, -0.02), Vector3(0.12, -0.08 - off, -0.15), 10), 0.0065, 0.0065, 6), "headphones")
	rig.part("chest", holo, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * PI * 0.5) * Basis(Vector3.RIGHT, -0.4), Vector3(sx * 0.098, 0.285, -0.035)))
			k.loft([FormKit.ring(0.021, 0.028, 0.032), FormKit.ring(0.024, 0.02, 0.024)], 14, 0, false, true)
			k.reset_transform()
		k.box(Vector3(0.08, 0.012, 0.006), Vector3(0, 0.1, 0.192), 0.002), "headphone_glow")
	# Holographic tablet (signature): projected panel above the left forearm.
	rig.part("forearm_l", trim, func(k: FormKit) -> void:
		k.loft([FormKit.ring(-0.2, 0.06, 0.056), FormKit.ring(-0.13, 0.062, 0.058)], 14, 0, true, true)
		k.box(Vector3(0.03, 0.06, 0.02), Vector3(0, -0.165, -0.06), 0.006), "wrist_rig")
	rig.part("forearm_l", holo, func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, -0.16, -0.13)))
		k.box(Vector3(0.15, 0.1, 0.004), Vector3.ZERO, 0.002)
		k.reset_transform()
		k.box(Vector3(0.004, 0.004, 0.06), Vector3(0, -0.16, -0.1), 0.001), "holo_tablet")
	# Hair: glossy black bob with blunt bangs and long front locks.
	var hr: Array = f["head"]
	rig.part("head", _mat(rig, pal, "hair"), func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.16, -0.02, 0.012, 0.8, 0.09)
		AgentBody.hair_mass(k, hr, {"front": -0.084, "back": 0.11, "vol_front": 0.018, "vol_mid": 0.024, "vol_back": 0.02, "side": 0.026, "depth": 0.11, "drop": 0.07})
		# Blunt bangs.
		k.loft([
			FormKit.ring(0.12, 0.074, 0.016, 0.02, -0.085, 2.6),
			FormKit.ring(0.16, 0.08, 0.022, 0.03, -0.08, 2.4),
			FormKit.ring(0.2, 0.06, 0.02, 0.03, -0.06, 2.2),
		], 14, 1, true, true)
		for sx: float in [-1.0, 1.0]:
			k.tube(FormKit.bezier3(Vector3(sx * 0.07, 0.16, -0.07), Vector3(sx * 0.088, 0.09, -0.07), Vector3(sx * 0.086, 0.02, -0.05), Vector3(sx * 0.07, -0.05, -0.04), 8),
				PackedFloat32Array([0.02, 0.024, 0.024, 0.022, 0.02, 0.016, 0.01, 0.004]), 8, 0.5, Vector3(sx, 0, 0)), "hair")


# ====================================================================== IMANI

## IMANI — Nigerian combat medic. Warm gold.
## Signature shape: gold field-medic armour (plate carrier, shoulder guards, bracers), a white
## medkit backpack with a glowing gold cross-hex, braids with gold beads gathered behind.
static func _imani(rig: AgentRig) -> void:
	var gold := Color("#F2B632")
	var pal := _palette(gold, "deep")
	pal["cloth"] = {"color": Color("#33413A"), "roughness": 0.8, "sheen": 0.45}
	pal["cloth_light"] = {"color": Color("#2B3630"), "roughness": 0.82, "sheen": 0.45}
	pal["signature"] = {"color": Color("#E8AE2E"), "roughness": 0.36, "metallic": 0.55, "edge_wear": 0.55}
	pal["medwhite"] = {"color": Color("#ECE9E2"), "roughness": 0.45, "edge_wear": 0.4}
	pal["medglow"] = {"color": Color("#3a2a00"), "emissive": Color("#FFD36A"), "emissive_energy": 3.0}
	pal["bead"] = {"color": Color("#F2B632"), "roughness": 0.25, "metallic": 0.8}
	pal["hair"] = {"color": Color("#1A120E"), "roughness": 0.62}
	pal["gloves"] = {"color": Color("#262B28"), "roughness": 0.5}
	var spec := {
		"fem": true, "iris": Color("#3A2416"), "brow": Color("#120C0A"), "lip": Color("#6A3A30"),
		"mats": {"torso": "cloth", "legs": "", "upper_arm": "cloth", "forearm": "cloth", "hands": "gloves"},
	}
	var f := AgentBody.build(rig, pal, spec)
	_cargo_pants(rig, pal, f, "cloth_light", "cloth", {"loose": 0.012})
	var sig := _mat(rig, pal, "signature")
	var white := _mat(rig, pal, "medwhite")
	var glow := _mat(rig, pal, "medglow")
	var web := _mat(rig, pal, "webbing")
	# Plate carrier: front/back plates over a webbing band, shoulder guards and bracers.
	var vest := FormKit.grown(f["chest"].slice(0, 6), 0.024)
	rig.part("chest", web, func(k: FormKit) -> void: k.loft(FormKit.slice(vest, -0.07, 0.16, 0.0, 4), 18, 1, true, true), "carrier")
	rig.part("chest", sig, func(k: FormKit) -> void:
		k.panel(vest, -0.03, 0.2, -PI * 0.5 - 0.85, -PI * 0.5 + 0.85, 0.016, 5, 10)
		k.panel(vest, -0.03, 0.2, PI * 0.5 - 0.85, PI * 0.5 + 0.85, 0.016, 5, 10)
		for sx: float in [-1.0, 1.0]:
			_strap(k, PackedVector3Array([Vector3(sx * 0.09, 0.18, 0.13), Vector3(sx * 0.1, 0.262, 0.05), Vector3(sx * 0.1, 0.262, -0.04), Vector3(sx * 0.09, 0.18, -0.13)]), 0.045, 0.01, Vector3.UP), "plates")
	rig.part("chest", white, func(k: FormKit) -> void:
		# Medic cross-hex on the chest plate.
		var z := FormKit.front_z(vest, 0.0, 0.12) - 0.018
		k.box(Vector3(0.05, 0.016, 0.006), Vector3(0, 0.12, z), 0.002)
		k.box(Vector3(0.016, 0.05, 0.006), Vector3(0, 0.12, z), 0.002), "emblem")
	rig.part("spine", web, func(k: FormKit) -> void:
		var ab := FormKit.grown(f["abdomen"], 0.016)
		k.loft(FormKit.slice(ab, 0.15, 0.25, 0.0, 2), 18, 0, true, false)
		for x: float in [-0.08, 0.0, 0.08]:
			k.box(Vector3(0.055, 0.07, 0.035), Vector3(x, 0.17, FormKit.front_z(ab, x, 0.17) - 0.012), 0.012), "pouches")
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		rig.part("shoulder_" + side, sig, func(k: FormKit) -> void:
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * -0.45), Vector3(sx * 0.06, 0.01, 0.0)))
			k.loft([
				FormKit.ring(-0.035, 0.07, 0.08, 0.08, 0.0, 2.6, 0.85),
				FormKit.ring(0.0, 0.078, 0.088, 0.088, 0.0, 2.6),
				FormKit.ring(0.025, 0.06, 0.07, 0.07, 0.0, 2.4),
				FormKit.ring(0.035, 0.02, 0.02, 0.02, 0.0, 2.0),
			], 16, 1, true, true)
			k.reset_transform(), "shoulder_guard")
		rig.part("forearm_" + side, sig, func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.21, -0.04, 0.016, 4), 14, 1, true, true), "bracer")
		rig.part("shin_" + side, sig, func(k: FormKit) -> void:
			k.loft([FormKit.ring(-0.08, 0.044, 0.014, 0.012, -0.062, 2.4), FormKit.ring(0.03, 0.06, 0.024, 0.02, -0.066, 2.6), FormKit.ring(0.07, 0.03, 0.012, 0.01, -0.06, 2.2)], 14, 1, true, true), "knee")
	rig.part("upper_arm_l", white, func(k: FormKit) -> void: k.loft(FormKit.slice(f["upper_arm"], -0.17, -0.1, 0.008, 2), 14, 0, true, true), "armband")
	rig.part("upper_arm_l", glow, func(k: FormKit) -> void: k.panel(FormKit.grown(f["upper_arm"], 0.008), -0.15, -0.12, PI - 0.25, PI + 0.25, 0.003, 1, 3), "armband_mark")
	# Medkit backpack (signature): rounded white case, gold glow cross-hex, vial rack.
	rig.part("chest", white, func(k: FormKit) -> void:
		k.loft([
			FormKit.ring(-0.06, 0.12, 0.04, 0.07, 0.18, 3.0, 0.8),
			FormKit.ring(0.0, 0.145, 0.05, 0.09, 0.19, 3.2),
			FormKit.ring(0.2, 0.15, 0.05, 0.095, 0.19, 3.2),
			FormKit.ring(0.27, 0.12, 0.045, 0.07, 0.185, 2.8),
			FormKit.ring(0.29, 0.06, 0.03, 0.04, 0.18, 2.4),
		], 18, 1, true, true), "medkit")
	rig.part("chest", glow, func(k: FormKit) -> void:
		k.box(Vector3(0.12, 0.032, 0.012), Vector3(0, 0.12, 0.285), 0.004)
		k.box(Vector3(0.032, 0.12, 0.012), Vector3(0, 0.12, 0.285), 0.004)
		for sx: float in [-1.0, 1.0]:
			for i: int in 3:
				k.cylinder(0.012, 0.09, Vector3(sx * 0.155, 0.05 + i * 0.07, 0.19), 8, 0.003), "medkit_glow")
	rig.part("chest", sig, func(k: FormKit) -> void:
		k.loft([FormKit.ring(0.05, 0.155, 0.055, 0.1, 0.19, 3.2), FormKit.ring(0.07, 0.155, 0.055, 0.1, 0.19, 3.2)], 18, 0, true, true)
		k.loft([FormKit.ring(0.18, 0.155, 0.055, 0.1, 0.19, 3.2), FormKit.ring(0.2, 0.155, 0.055, 0.1, 0.19, 3.2)], 18, 0, true, true), "medkit_trim")
	# Braids with gold beads, gathered at the crown and falling down the back.
	var hr: Array = f["head"]
	var hair := _mat(rig, pal, "hair")
	rig.part("head", hair, func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.165, 0.02, 0.006, 0.85, 0.02)
		# Cornrow ridges from the hairline to the crown.
		for i: int in 7:
			var u := (i - 3) / 3.0
			var pts := PackedVector3Array()
			for j: int in 6:
				var t := float(j) / 5.0
				var z := lerpf(-0.085, 0.09, t)
				var x := u * 0.06 * (1.0 - t * 0.6)
				pts.append(Vector3(x, AgentBody.skull_top(hr, z) + 0.004 - absf(u) * 0.02, z))
			k.strand(pts, 0.009, 0.008, 6)
		k.ellipsoid(Vector3(0.05, 0.04, 0.045), Vector3(0, 0.17, 0.1), 10, 8)
		# Hanging braids.
		for i: int in 9:
			var u := (i - 4) / 4.0
			var a := Vector3(u * 0.04, 0.16, 0.12)
			var e := Vector3(u * 0.11, -0.2 - (1.0 - absf(u)) * 0.06, 0.13 + absf(u) * 0.01)
			var pts := FormKit.bezier(a, Vector3(u * 0.09, 0.12, 0.17), e, 6)
			_braid(k, pts, 0.011), "hair")
	rig.part("head", _mat(rig, pal, "bead"), func(k: FormKit) -> void:
		for i: int in 9:
			var u := (i - 4) / 4.0
			var e := Vector3(u * 0.11, -0.2 - (1.0 - absf(u)) * 0.06, 0.13 + absf(u) * 0.01)
			k.ellipsoid(Vector3(0.014, 0.018, 0.014), e + Vector3(0, -0.01, 0), 8, 5)
			k.ellipsoid(Vector3(0.012, 0.012, 0.012), e + Vector3(0, 0.05, 0.005), 8, 5)
		k.loft([FormKit.ring(0.14, 0.045, 0.04, 0.04, 0.11), FormKit.ring(0.16, 0.048, 0.043, 0.043, 0.11)], 12, 0, true, true), "beads")


# ====================================================================== TOMAS

## TOMAS — Chilean mining engineer. Copper.
## Signature shape: copper hard hat with headlamp and goggles, loaded tool belt, mechanical right
## arm (copper plates, pistons, armoured hand).
static func _tomas(rig: AgentRig) -> void:
	var copper := Color("#C8743A")
	var pal := _palette(copper, "tan")
	pal["cloth"] = {"color": Color("#3A4454"), "roughness": 0.82, "sheen": 0.45}  # coveralls
	pal["signature"] = {"color": copper, "roughness": 0.32, "metallic": 0.8, "edge_wear": 0.6}
	pal["hardhat"] = {"color": Color("#D9823A"), "roughness": 0.35, "edge_wear": 0.5}
	pal["lens"] = {"color": Color("#223040"), "roughness": 0.08, "metallic": 0.3, "emissive": Color("#7FD1FF"), "emissive_energy": 0.5}
	pal["lamp"] = {"color": Color("#FFF2C0"), "emissive": Color("#FFE9A8"), "emissive_energy": 3.0}
	pal["hair"] = {"color": Color("#1E1612"), "roughness": 0.62}
	pal["boots"] = {"color": Color("#3A2E26"), "roughness": 0.6, "edge_wear": 0.5}
	var spec := {
		"fem": false, "bulk": 1.08, "iris": Color("#3A2416"), "brow": Color("#1E1612"),
		"mats": {"torso": "cloth", "legs": "", "upper_arm": "cloth", "forearm": "cloth", "hands": "gloves"},
		"mats_l": {"forearm": "skin", "hands": "gloves"},
		"mats_r": {"hands": "signature"},
		"boot": {"shaft": -0.27, "toe": 0.22, "chunk": 1.4}, "hand_scale": 1.18,
	}
	var f := AgentBody.build(rig, pal, spec)
	_cargo_pants(rig, pal, f, "cloth", "cloth", {"loose": 0.016, "pockets": false})
	var sig := _mat(rig, pal, "signature")
	var leather := _mat(rig, pal, "leather")
	var armor := _mat(rig, pal, "armor")
	var metal := _mat(rig, pal, "metal")
	var cloth := _mat(rig, pal, "cloth")
	# Coverall details: rolled left sleeve, chest pockets, reflective... (copper zip pulls).
	rig.part("forearm_l", cloth, func(k: FormKit) -> void: k.loft(FormKit.slice(f["forearm"], -0.05, 0.04, 0.016, 3), 14, 1, true, true), "rolled_sleeve")
	var ch := FormKit.grown(f["chest"], 0.004)
	rig.part("chest", _mat(rig, pal, "cloth_light"), func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.panel(ch, 0.06, 0.15, -PI * 0.5 + sx * 0.5 - 0.3, -PI * 0.5 + sx * 0.5 + 0.3, 0.006, 3, 5)
		_strap(k, _on_surface(ch, PackedVector2Array([Vector2(0.0, 0.25), Vector2(0.0, 0.1), Vector2(0.0, -0.07)]), 0.002), 0.012, 0.004, Vector3.FORWARD), "coverall_pockets")
	# Tool belt (signature): thick belt, pouches, hammer and wrench.
	var pv := FormKit.grown(f["pelvis"], 0.024)
	rig.part("hips", leather, func(k: FormKit) -> void:
		k.loft(FormKit.slice(pv, 0.04, 0.12, 0.006, 2), 18, 0, true, true)
		for a: float in [-PI * 0.5 - 0.7, -PI * 0.5 + 0.7, 0.15, PI - 0.15, PI * 0.5]:
			var r := FormKit.at(pv, 0.02)
			var p := FormKit.ring_point(r, a)
			var d := Vector3(p.x, 0, p.z).normalized()
			k.set_transform(Transform3D(Basis.looking_at(-d, Vector3.UP), p + d * 0.02 + Vector3(0, 0.0, 0)))
			k.box(Vector3(0.075, 0.09, 0.045), Vector3.ZERO, 0.012)
			k.box(Vector3(0.08, 0.03, 0.05), Vector3(0, 0.04, 0), 0.008)
			k.reset_transform(), "tool_belt")
	rig.part("hips", metal, func(k: FormKit) -> void:
		k.box(Vector3(0.05, 0.045, 0.014), Vector3(0, 0.08, FormKit.front_z(pv, 0.0, 0.08) - 0.014), 0.006)
		# Hammer hanging at the left hip, wrench at the right.
		var hp := Vector3(-0.2, -0.02, -0.03)
		k.strand(PackedVector3Array([hp + Vector3(0, 0.06, 0), hp + Vector3(0, -0.16, 0)]), 0.009, 0.009, 6)
		k.box(Vector3(0.03, 0.035, 0.1), hp + Vector3(0, 0.07, 0), 0.006)
		var wp := Vector3(0.205, -0.02, 0.02)
		k.box(Vector3(0.012, 0.18, 0.024), wp, 0.004)
		k.cylinder(0.022, 0.014, wp + Vector3(0, -0.09, 0), 10, 0.004), "tools")
	rig.part("hips", leather, func(k: FormKit) -> void:
		k.box(Vector3(0.02, 0.05, 0.11), Vector3(-0.2, 0.1, -0.03), 0.006), "hammer_handle")
	# Mechanical right arm (signature): copper plates, pistons, armoured shoulder.
	rig.part("shoulder_r", sig, func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.BACK, -0.4), Vector3(0.06, 0.01, 0.0)))
		k.loft([
			FormKit.ring(-0.04, 0.075, 0.085, 0.085, 0.0, 2.8, 0.85),
			FormKit.ring(0.0, 0.084, 0.094, 0.094, 0.0, 2.8),
			FormKit.ring(0.03, 0.064, 0.072, 0.072, 0.0, 2.5),
			FormKit.ring(0.04, 0.02, 0.02, 0.02, 0.0, 2.0),
		], 16, 1, true, true)
		k.reset_transform(), "mech_shoulder")
	rig.part("upper_arm_r", sig, func(k: FormKit) -> void:
		var ua := FormKit.grown(f["upper_arm"], 0.012)
		for i: int in 3:
			var y := -0.06 - i * 0.08
			k.loft(FormKit.slice(ua, y - 0.032, y + 0.032, 0.006, 3), 14, 1, true, true), "mech_upper")
	rig.part("forearm_r", sig, func(k: FormKit) -> void:
		k.loft(FormKit.grown(FormKit.slice(f["forearm"], -0.24, 0.03, 0.0, 5), 0.022, 1.08), 16, 1, true, true), "mech_fore")
	rig.part("forearm_r", armor, func(k: FormKit) -> void:
		k.loft(FormKit.slice(f["forearm"], 0.0, 0.05, 0.03, 2), 14, 0, true, true)
		for sx: float in [-1.0, 1.0]:
			k.strand(PackedVector3Array([Vector3(sx * 0.06, 0.02, 0.02), Vector3(sx * 0.062, -0.22, 0.02)]), 0.008, 0.008, 6)
		k.strand(PackedVector3Array([Vector3(0.0, 0.03, 0.062), Vector3(0.0, -0.22, 0.066)]), 0.01, 0.01, 6), "pistons")
	rig.part("upper_arm_r", metal, func(k: FormKit) -> void:
		k.strand(PackedVector3Array([Vector3(0.0, 0.02, 0.07), Vector3(0.0, -0.28, 0.06)]), 0.009, 0.009, 6), "piston_rod")
	rig.part("hand_r", armor, func(k: FormKit) -> void:
		k.ellipsoid(Vector3(0.03, 0.04, 0.046), Vector3(0.0, -0.045, 0.0), 10, 6), "mech_hand")
	# Hard hat (signature) with headlamp and goggles on the brim; hair, moustache and stubble.
	var hr: Array = f["head"]
	rig.part("head", _mat(rig, pal, "hair"), func(k: FormKit) -> void:
		AgentBody.hair_cap(k, hr, 0.15, 0.03, 0.006, 0.8, 0.03), "hair")
	rig.part("head", _mat(rig, pal, "hardhat"), func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 0, 0.006)))
		k.loft([
			FormKit.ring(0.142, 0.112, 0.14, 0.13, 0.0, 2.2, 0.85),
			FormKit.ring(0.152, 0.112, 0.14, 0.13, 0.0, 2.2),
			FormKit.ring(0.158, 0.096, 0.108, 0.114, 0.006, 2.2),
			FormKit.ring(0.2, 0.094, 0.104, 0.112, 0.008, 2.2),
			FormKit.ring(0.25, 0.082, 0.09, 0.098, 0.01, 2.2),
			FormKit.ring(0.285, 0.052, 0.058, 0.064, 0.012, 2.1),
			FormKit.ring(0.296, 0.01, 0.01, 0.01, 0.012, 2.0),
		], 22, 1, true, true)
		# Centre ridge.
		k.tube(FormKit.bezier(Vector3(0, 0.27, -0.07), Vector3(0, 0.31, 0.0), Vector3(0, 0.27, 0.08), 7), PackedFloat32Array([0.008, 0.012, 0.013, 0.013, 0.013, 0.012, 0.008]), 7, 0.8, Vector3.UP)
		k.reset_transform(), "hardhat")
	rig.part("head", metal, func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.06 + PI * 0.5), Vector3(0, 0.215, -0.108)))
		k.cylinder(0.022, 0.028, Vector3.ZERO, 14, 0.005)
		k.reset_transform(), "lamp_housing")
	rig.part("head", _mat(rig, pal, "lamp"), func(k: FormKit) -> void:
		k.set_transform(Transform3D(Basis(Vector3.RIGHT, -0.06 + PI * 0.5), Vector3(0, 0.215, -0.123)))
		k.cylinder(0.017, 0.004, Vector3.ZERO, 14, 0.001)
		k.reset_transform(), "lamp")
	rig.part("head", leather, func(k: FormKit) -> void:
		var band := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i: int in 21:
			var a := TAU * i / 20.0
			var y := 0.17
			var r := FormKit.at(hr, y)
			band.append(Vector3(cos(a) * (r[FormKit.R_RX] + 0.03), y + 0.012, r[FormKit.R_CZ] + sin(a) * ((r[FormKit.R_ZB] if sin(a) > 0.0 else r[FormKit.R_ZF]) + 0.03)))
			radii.append(0.009)
		k.tube(band, radii, 6, 0.45, Vector3.UP)
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(sx * 0.05, 0.188, -0.118)))
			k.lathe(PackedVector2Array([Vector2(0.022, -0.012), Vector2(0.024, 0.004), Vector2(0.02, 0.01)]), 12, Vector3.ZERO, true, true, false)
			k.reset_transform(), "goggles")
	rig.part("head", _mat(rig, pal, "lens"), func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.set_transform(Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(sx * 0.05, 0.188, -0.118)))
			k.ellipsoid(Vector3(0.019, 0.005, 0.019), Vector3(0, 0.01, 0), 10, 4)
			k.reset_transform(), "goggle_lens")
	rig.part("head", rig.material("beard", {"color": (pal["skin"]["color"] as Color).lerp(Color("#1E1612"), 0.5), "roughness": 0.8}), func(k: FormKit) -> void:
		AgentBody.beard(k, hr, 0.028, 0.078, 0.004, 1.7), "stubble")
	rig.part("head", _mat(rig, pal, "hair"), func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			k.tube(FormKit.bezier(Vector3(sx * 0.002, 0.059, FormKit.front_z(hr, 0.0, 0.059) - 0.009), Vector3(sx * 0.026, 0.059, FormKit.front_z(hr, 0.026, 0.059) - 0.009), Vector3(sx * 0.036, 0.036, FormKit.front_z(hr, 0.036, 0.036) - 0.006), 6),
				PackedFloat32Array([0.0075, 0.009, 0.009, 0.008, 0.006, 0.004]), 7, 0.7, Vector3.FORWARD), "moustache")
