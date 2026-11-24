## AgentBody: the shared stylised anatomy every agent is dressed on (spec §6.1). Smooth FormKit
## lofts in bone space: heroic ~7.5-head proportions, tapered torso, shaped limbs, a face with
## clear brow/nose/jaw planes and large readable eyes, block-out hands with fingers and thumb,
## shaped boots. Outfits (AgentLooks) layer shells over the ring sets returned by forms().
class_name AgentBody
extends RefCounted

const SKIN_TONES: Dictionary = {
	"fair": Color("#EDC6AA"), "light": Color("#DDAA86"), "tan": Color("#BA845E"),
	"brown": Color("#8E5A3C"), "deep": Color("#5C3826"),
}


static func _r(y: float, rx: float, zf: float, zb: float = -1.0, cz: float = 0.0, n: float = 2.0, shade: float = 1.0) -> PackedFloat32Array:
	return FormKit.ring(y, rx, zf, zb, cz, n, shade)


## Ring sets (bone space) for a body spec {fem, bulk}. Outfits grow shells from these.
static func forms(spec: Dictionary) -> Dictionary:
	var fem: bool = spec.get("fem", false)
	var b: float = spec.get("bulk", 1.0)
	var f: Dictionary = {}
	var hw := 0.17 if fem else 0.158
	f["pelvis"] = [
		_r(-0.17, 0.05, 0.045, 0.05, 0.0, 2.0, 0.78),
		_r(-0.135, 0.128 * b, 0.084, 0.09, 0.004, 2.2, 0.86),
		_r(-0.075, hw * b, 0.096, 0.096, 0.0, 2.4, 0.95),
		_r(0.0, (hw - 0.01) * b, 0.094, 0.094, 0.0, 2.4),
		_r(0.08, (0.128 if fem else 0.14) * b, 0.09, 0.094, 0.0, 2.3),
		_r(0.14, (0.124 if fem else 0.14) * b, 0.088, 0.09, 0.0, 2.3),
	]
	f["abdomen"] = [
		_r(-0.08, (0.13 if fem else 0.14) * b, 0.09, 0.092, 0.0, 2.3),
		_r(0.03, (0.118 if fem else 0.138) * b, 0.084, 0.088, 0.0, 2.3),
		_r(0.14, (0.126 if fem else 0.148) * b, 0.092, 0.092, 0.0, 2.4),
		_r(0.25, (0.138 if fem else 0.158) * b, 0.104, 0.096, 0.0, 2.4),
	]
	f["chest"] = [
		_r(-0.07, (0.126 if fem else 0.146) * b, 0.092, 0.09, 0.0, 2.4),
		_r(0.03, (0.14 if fem else 0.163) * b, (0.118 if fem else 0.108) * b, 0.096 * b, 0.0, 2.5),
		_r(0.09, (0.154 if fem else 0.182) * b, (0.12 if fem else 0.115) * b, 0.1 * b, 0.0, 2.6),
		_r(0.15, (0.162 if fem else 0.196) * b, 0.104 * b, 0.102 * b, 0.006, 2.9),
		_r(0.2, (0.158 if fem else 0.192) * b, 0.09 * b, 0.094 * b, 0.01, 3.2),
		_r(0.235, (0.12 if fem else 0.142) * b, 0.07, 0.078, 0.012, 2.6),
		_r(0.258, 0.068, 0.054, 0.06, 0.014, 2.2),
		_r(0.27, 0.054, 0.048, 0.054, 0.014, 2.0),
	]
	var a := (0.95 if fem else 1.1) * b
	f["upper_arm"] = [
		_r(0.06, 0.028 * a, 0.028 * a, 0.028 * a),
		_r(0.04, 0.056 * a, 0.056 * a, 0.054 * a),
		_r(-0.01, 0.066 * a, 0.064 * a, 0.062 * a),
		_r(-0.08, 0.058 * a, 0.056 * a, 0.054 * a),
		_r(-0.16, 0.052 * a, 0.054 * a, 0.05 * a),
		_r(-0.25, 0.046 * a, 0.046 * a, 0.044 * a),
		_r(-0.31, 0.043 * a, 0.042 * a, 0.042 * a),
	]
	f["forearm"] = [
		_r(0.035, 0.042 * a, 0.042 * a, 0.042 * a),
		_r(-0.03, 0.049 * a, 0.046 * a, 0.047 * a),
		_r(-0.1, 0.046 * a, 0.04 * a, 0.042 * a),
		_r(-0.19, 0.037 * a, 0.031 * a, 0.033 * a),
		_r(-0.255, 0.032 * a, 0.026 * a, 0.027 * a),
	]
	var l := (0.94 if fem else 1.0) * b
	f["thigh"] = [
		_r(0.09, 0.084 * l, 0.08 * l, 0.078 * l, 0.004, 2.2),
		_r(0.02, 0.1 * l, 0.094 * l, 0.094 * l, 0.0, 2.2),
		_r(-0.1, 0.094 * l, 0.09 * l, 0.092 * l),
		_r(-0.25, 0.08 * l, 0.078 * l, 0.074 * l, 0.0, 2.0, 0.96),
		_r(-0.38, 0.066 * l, 0.066 * l, 0.06 * l, 0.0, 2.0, 0.93),
		_r(-0.46, 0.062 * l, 0.064 * l, 0.058 * l, 0.0, 2.0, 0.92),
	]
	f["shin"] = [
		_r(0.03, 0.062 * l, 0.066 * l, 0.058 * l, 0.0, 2.0, 0.92),
		_r(-0.06, 0.06 * l, 0.058 * l, 0.07 * l, 0.0, 2.0, 0.9),
		_r(-0.15, 0.058 * l, 0.05 * l, 0.072 * l, 0.0, 2.0, 0.88),
		_r(-0.27, 0.05 * l, 0.043 * l, 0.055 * l, 0.0, 2.0, 0.84),
		_r(-0.38, 0.043 * l, 0.038 * l, 0.042 * l, 0.0, 2.0, 0.8),
		_r(-0.44, 0.042 * l, 0.036 * l, 0.04 * l, 0.0, 2.0, 0.78),
	]
	var jw := 0.9 if fem else 1.0
	f["head"] = [
		_r(-0.006, 0.02 * jw, 0.012, 0.014, -0.06, 2.2),
		_r(0.003, 0.038 * jw, 0.024, 0.03, -0.054, 2.5),
		_r(0.018, 0.056 * jw, 0.044, 0.054, -0.036, 2.7),
		_r(0.035, 0.066 * jw, 0.066, 0.07, -0.021, 2.6),
		_r(0.055, 0.072, 0.082, 0.086, -0.012, 2.4),
		_r(0.075, 0.0755, 0.09, 0.095, -0.007, 2.4),
		_r(0.1, 0.077, 0.094, 0.1, -0.004, 2.25),
		_r(0.125, 0.079, 0.095, 0.104, 0.0, 2.15),
		_r(0.155, 0.078, 0.088, 0.103, 0.004, 2.05),
		_r(0.185, 0.068, 0.07, 0.09, 0.008, 2.0),
		_r(0.208, 0.046, 0.045, 0.06, 0.01, 2.0),
		_r(0.22, 0.008, 0.008, 0.012, 0.01, 2.0),
	]
	f["neck"] = [
		_r(-0.07, (0.056 if fem else 0.062) * b, 0.052, 0.056, 0.014),
		_r(0.03, (0.049 if fem else 0.056) * b, 0.046, 0.05, 0.012),
		_r(0.14, (0.044 if fem else 0.05) * b, 0.042, 0.048, 0.016),
	]
	return f


## Builds the base body. `mats`: torso, pelvis, legs, upper_arm, forearm, hands ("skin" for bare),
## boots, neck. A material id of "" skips that piece (an outfit replaces it).
static func build(rig: AgentRig, pal: Dictionary, spec: Dictionary) -> Dictionary:
	var f := forms(spec)
	var mats: Dictionary = spec.get("mats", {})
	var m := func(id: String) -> ShaderMaterial: return rig.material(id, pal[id])
	var torso_id: String = mats.get("torso", "cloth")
	var legs_id: String = mats.get("legs", "cloth_light")
	var pelvis_id: String = mats.get("pelvis", legs_id)
	if torso_id != "":
		rig.part("spine", m.call(torso_id), func(k: FormKit) -> void: k.loft(f["abdomen"], 18, 1, false, false), "abdomen")
		rig.part("chest", m.call(torso_id), func(k: FormKit) -> void: k.loft(f["chest"], 18, 2, true, true), "chest")
	if pelvis_id != "":
		rig.part("hips", m.call(pelvis_id), func(k: FormKit) -> void: k.loft(f["pelvis"], 18, 1, true, true), "pelvis")
	var neck_id: String = mats.get("neck", "skin")
	rig.part("neck", m.call(neck_id), func(k: FormKit) -> void: k.loft(f["neck"], 12, 1, false, false), "neck")
	head(rig, pal, spec, f["head"])
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var ms: Dictionary = mats.duplicate()
		ms.merge(spec.get("mats_" + side, {}), true)
		var ua_id: String = ms.get("upper_arm", torso_id if torso_id != "" else "cloth")
		var fa_id: String = ms.get("forearm", ua_id)
		if ua_id != "":
			rig.part("upper_arm_" + side, m.call(ua_id), func(k: FormKit) -> void: k.loft(f["upper_arm"], 14, 1, false, true))
		if fa_id != "":
			rig.part("forearm_" + side, m.call(fa_id), func(k: FormKit) -> void: k.loft(f["forearm"], 14, 1, true, true))
		var hand_id: String = ms.get("hands", "gloves")
		rig.part("hand_" + side, m.call(hand_id), func(k: FormKit) -> void: hand(k, sx, spec), "hand")
		if legs_id != "":
			rig.part("thigh_" + side, m.call(legs_id), func(k: FormKit) -> void:
				k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * 0.006, 0, 0)))
				k.loft(f["thigh"], 16, 1, false, true), "thigh")
			rig.part("shin_" + side, m.call(legs_id), func(k: FormKit) -> void: k.loft(f["shin"], 16, 1, true, true), "shin")
		var boots_id: String = mats.get("boots", "boots")
		if boots_id != "":
			rig.part("foot_" + side, m.call(boots_id), func(k: FormKit) -> void: boot(k, spec.get("boot", {})), "boot")
			rig.part("shin_" + side, m.call(boots_id), func(k: FormKit) -> void:
				var top: float = (spec.get("boot", {}) as Dictionary).get("shaft", -0.31)
				k.loft(FormKit.slice(f["shin"], -0.45, top, 0.017, 4, 0.85), 16, 1, true, true)
				k.color = Color(0.78, 0.78, 0.78)
				k.loft(FormKit.slice(f["shin"], top - 0.016, top + 0.004, 0.022, 2), 16, 0, true, true), "boot_shaft")
	return f


## Head: skull/face loft, eyes (sclera, iris, pupil, catch-light), lash line, brows, nose, lips,
## ears. spec: fem, iris (Color), brow (Color), lip (Color), skin (tone id).
static func head(rig: AgentRig, pal: Dictionary, spec: Dictionary, hr: Array) -> void:
	var fem: bool = spec.get("fem", false)
	var skin: ShaderMaterial = rig.material("skin", pal["skin"])
	rig.part("head", skin, func(k: FormKit) -> void:
		k.loft(hr, 20, 2, true, false)
		# Nose: bridge to tip, plus soft nostril wings.
		var zb := FormKit.front_z(hr, 0.0, 0.1)
		var zt := FormKit.front_z(hr, 0.0, 0.068)
		var nose_len := 0.012 if fem else 0.017
		k.tube(PackedVector3Array([Vector3(0, 0.106, zb + 0.004), Vector3(0, 0.09, zb - 0.004), Vector3(0, 0.073, zt - nose_len), Vector3(0, 0.064, zt - nose_len + 0.006)]),
			PackedFloat32Array([0.005, 0.006, 0.0078 if fem else 0.0098, 0.0058]), 9, 1.0, Vector3.FORWARD)
		k.color = Color(1.0, 0.92, 0.9)
		for sx: float in [-1.0, 1.0]:
			k.ellipsoid(Vector3(0.0062, 0.0052, 0.006), Vector3(sx * 0.0078, 0.067, zt - nose_len * 0.25), 8, 5)
			# Ears.
			k.color = Color(1.0, 0.86, 0.82)
			var ex := FormKit.side_x(hr, 0.085)
			k.set_transform(Transform3D(Basis(Vector3.UP, sx * 0.35), Vector3(sx * (ex - 0.004), 0.087, 0.012)))
			k.ellipsoid(Vector3(0.011, 0.027, 0.018), Vector3.ZERO, 8, 6)
			k.reset_transform()
			k.color = Color(1.0, 0.92, 0.9)
		k.color = Color.WHITE
		# Jaw/chin plane (masculine squarer chin).
		if not fem:
			k.ellipsoid(Vector3(0.026, 0.014, 0.014), Vector3(0, -0.012, FormKit.front_z(hr, 0.0, -0.012) + 0.01), 10, 6), "face")
	var eye_white := rig.material("eye_white", {"color": Color("#EEE8E0"), "roughness": 0.25, "no_outline": true, "rim_strength": 0.0})
	var iris := rig.material("iris", {"color": spec.get("iris", Color("#5A3A22")), "roughness": 0.15, "no_outline": true, "rim_strength": 0.0})
	var dark := rig.material("lash", {"color": Color("#17110F"), "roughness": 0.4, "no_outline": true, "rim_strength": 0.0})
	var glint := rig.material("glint", {"color": Color.WHITE, "emissive": Color.WHITE, "emissive_energy": 0.6, "no_outline": true})
	var ey := 0.097
	var ex := 0.034
	var er := Vector3(0.0165, 0.0115 if fem else 0.0105, 0.009)
	rig.part("head", eye_white, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var z := FormKit.front_z(hr, sx * ex, ey)
			k.set_transform(Transform3D(Basis(Vector3.BACK, sx * -0.12) * Basis(Vector3.UP, sx * 0.25), Vector3(sx * ex, ey, z + 0.0045)))
			k.ellipsoid(er, Vector3.ZERO, 12, 8)
			k.reset_transform(), "eyes")
	rig.part("head", iris, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var z := FormKit.front_z(hr, sx * (ex - 0.002), ey)
			k.ellipsoid(Vector3(0.0085, 0.0092, 0.004), Vector3(sx * (ex - 0.002), ey - 0.0005, z - 0.0042), 10, 6), "iris")
	rig.part("head", dark, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var z := FormKit.front_z(hr, sx * (ex - 0.002), ey)
			k.ellipsoid(Vector3(0.0042, 0.0048, 0.002), Vector3(sx * (ex - 0.002), ey - 0.0005, z - 0.0075), 8, 4)
			# Upper lash line: thick, winged at the outer corner (reads as eyes from a distance).
			var pts := PackedVector3Array()
			for i: int in 7:
				var t := float(i) / 6.0
				var x := lerpf(0.017, 0.054 if fem else 0.051, t)
				var y := ey + 0.0055 + sin(t * PI) * 0.0055 - (0.0 if t < 0.8 else (t - 0.8) * (0.01 if fem else 0.016))
				pts.append(Vector3(sx * x, y, FormKit.front_z(hr, sx * x, y) - 0.0042 + absf(t - 0.45) * 0.004))
			k.tube(pts, PackedFloat32Array([0.0014, 0.0026, 0.003, 0.003, 0.0028, 0.0024 if fem else 0.0018, 0.0012]), 6, 0.6, Vector3.FORWARD)
			# Lower lid hint.
			var low := PackedVector3Array()
			for i: int in 5:
				var t := float(i) / 4.0
				var x := lerpf(0.022, 0.048, t)
				var y := ey - 0.0085 - sin(t * PI) * 0.002
				low.append(Vector3(sx * x, y, FormKit.front_z(hr, sx * x, y) - 0.002))
			k.strand(low, 0.0007, 0.0009, 5, 0.6, Vector3.FORWARD)
		# Mouth line.
		var mouth := PackedVector3Array()
		for i: int in 7:
			var t := float(i) / 6.0 * 2.0 - 1.0
			var x := t * (0.018 if fem else 0.02)
			var y := 0.043 + absf(t) * 0.0022 - (1.0 - t * t) * 0.0012
			mouth.append(Vector3(x, y, FormKit.front_z(hr, x, y) - 0.0016))
		k.strand(mouth, 0.0011, 0.0011, 5, 0.6, Vector3.FORWARD), "lashes")
	rig.part("head", glint, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var z := FormKit.front_z(hr, sx * (ex - 0.002), ey)
			k.ellipsoid(Vector3(0.0018, 0.0018, 0.001), Vector3(sx * (ex - 0.002) + 0.003, ey + 0.003, z - 0.0086), 6, 4), "glint")
	var lip := rig.material("lip", {"color": spec.get("lip", (pal["skin"]["color"] as Color).darkened(0.1).lerp(Color("#B0505A"), 0.2)), "roughness": 0.4, "no_outline": true, "sss": 0.5})
	rig.part("head", lip, func(k: FormKit) -> void:
		var w := 0.0175 if fem else 0.017
		# Upper and lower lip pads.
		k.ellipsoid(Vector3(w, 0.0036, 0.005), Vector3(0, 0.0472, FormKit.front_z(hr, 0.0, 0.0472) + 0.0028), 10, 5)
		k.ellipsoid(Vector3(w * 0.8, 0.0052 if fem else 0.0042, 0.0056), Vector3(0, 0.0378, FormKit.front_z(hr, 0.0, 0.0378) + 0.0028), 10, 5), "lips")
	var brow := rig.material("brow", {"color": spec.get("brow", Color("#3A2A20")), "roughness": 0.6, "no_outline": true})
	rig.part("head", brow, func(k: FormKit) -> void:
		for sx: float in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			for i: int in 6:
				var t := float(i) / 5.0
				var x := lerpf(0.012, 0.058, t)
				var y := ey + 0.021 + sin(t * PI * 0.85) * (0.006 if fem else 0.0035) - t * 0.002
				pts.append(Vector3(sx * x, y, FormKit.front_z(hr, sx * x, y) - 0.0015))
			var w := 0.0034 if fem else 0.0046
			k.tube(pts, PackedFloat32Array([w * 1.1, w * 1.15, w, w * 0.9, w * 0.7, w * 0.4]), 6, 0.5, Vector3.FORWARD), "brows")


## Block-out hand at the wrist bone: palm, four curled fingers and a thumb. Fingers run down -Y,
## the palm faces the body's midline (-sx), thumb forward (-Z). Slightly oversized (spec §6.1).
static func hand(k: FormKit, sx: float, spec: Dictionary) -> void:
	var s: float = (0.92 if spec.get("fem", false) else 1.0) * float(spec.get("hand_scale", 1.14))
	var palm := [
		_r(0.02 * s, 0.021 * s, 0.026 * s, 0.026 * s, 0.0, 2.4),
		_r(-0.02 * s, 0.024 * s, 0.036 * s, 0.034 * s, 0.0, 2.8),
		_r(-0.06 * s, 0.022 * s, 0.04 * s, 0.038 * s, 0.0, 3.0),
		_r(-0.088 * s, 0.019 * s, 0.038 * s, 0.036 * s, 0.0, 3.0),
		_r(-0.097 * s, 0.012 * s, 0.03 * s, 0.028 * s, 0.0, 2.4),
	]
	k.set_transform(Transform3D(Basis.IDENTITY, Vector3(sx * -0.004, 0, 0)))
	k.loft(palm, 12, 1, true, true)
	k.reset_transform()
	var lengths := [0.072, 0.08, 0.076, 0.062]
	for i: int in 4:
		var z := lerpf(-0.027, 0.027, i / 3.0) * s
		var ln: float = lengths[i] * s
		var base := Vector3(sx * -0.004, -0.09 * s, z)
		# Curled: first segment down, then hooking toward the palm side.
		var p1 := base + Vector3(sx * -0.006, -ln * 0.42, 0)
		var p2 := p1 + Vector3(sx * -0.022, -ln * 0.3, 0)
		var p3 := p2 + Vector3(sx * -0.024, -ln * 0.05, z * 0.1)
		k.tube(FormKit.bezier3(base, p1, p2, p3, 6), PackedFloat32Array([0.0108 * s, 0.0104 * s, 0.0098 * s, 0.0092 * s, 0.0086 * s, 0.008 * s]), 7, 0.9, Vector3(sx, 0, 0))
	# Thumb: from the heel of the palm, out and forward, tip curling in.
	var t0 := Vector3(sx * -0.012, -0.012 * s, -0.026 * s)
	k.tube(FormKit.bezier3(t0, t0 + Vector3(sx * -0.012, -0.022 * s, -0.018 * s), t0 + Vector3(sx * -0.024, -0.045 * s, -0.022 * s), t0 + Vector3(sx * -0.03, -0.062 * s, -0.012 * s), 6),
		PackedFloat32Array([0.016 * s, 0.013 * s, 0.0115 * s, 0.0105 * s, 0.0095 * s, 0.0085 * s]), 8, 0.9, Vector3(sx, 0, 0))


## Shaped combat boot on the foot bone (ankle origin); the sole bottom sits AgentAnimator.ANKLE_Y
## below the ankle. opts: toe (length), chunk (sole thickness).
static func boot(k: FormKit, opts: Dictionary) -> void:
	var toe: float = opts.get("toe", 0.2)
	var chunk: float = opts.get("chunk", 1.0)
	# Loft along the foot: loft +Y maps to -Z (toe), loft -Z maps to -Y (sole side), cz = height.
	k.set_transform(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	k.loft([
		_r(-0.08, 0.026, 0.02, 0.02, -0.032, 2.2),
		_r(-0.07, 0.046, 0.03, 0.05, -0.03, 2.4),
		_r(-0.03, 0.05, 0.036, 0.08, -0.026, 2.5),
		_r(0.03, 0.052, 0.035, 0.056, -0.03, 2.6),
		_r(0.09, 0.055, 0.032, 0.036, -0.035, 2.6),
		_r(toe - 0.04, 0.05, 0.028, 0.027, -0.04, 2.5),
		_r(toe - 0.01, 0.038, 0.022, 0.019, -0.045, 2.3),
		_r(toe + 0.006, 0.012, 0.01, 0.01, -0.049, 2.0),
	], 14, 1, true, true)
	# Toe cap and heel counter: darker, slightly proud.
	k.color = Color(0.72, 0.72, 0.72)
	k.loft([
		_r(toe - 0.075, 0.053, 0.028, 0.024, -0.04, 2.6),
		_r(toe - 0.04, 0.052, 0.029, 0.029, -0.041, 2.5),
		_r(toe - 0.01, 0.04, 0.023, 0.021, -0.045, 2.3),
		_r(toe + 0.008, 0.012, 0.011, 0.011, -0.049, 2.0),
	], 14, 1, true, true)
	k.loft([
		_r(-0.083, 0.03, 0.016, 0.016, -0.045, 2.2),
		_r(-0.074, 0.049, 0.022, 0.03, -0.045, 2.4),
		_r(-0.045, 0.053, 0.026, 0.03, -0.045, 2.5),
	], 14, 1, true, true)
	# Sole: wider, flatter slab with a darker tone.
	var c := chunk
	k.color = Color(0.5, 0.5, 0.5)
	k.loft([
		_r(-0.086, 0.036, 0.011 * c, 0.011 * c, -0.064, 3.0),
		_r(-0.074, 0.056, 0.012 * c, 0.012 * c, -0.064, 3.4),
		_r(0.02, 0.058, 0.011 * c, 0.011 * c, -0.064, 3.4),
		_r(0.09, 0.062, 0.011 * c, 0.011 * c, -0.064, 3.4),
		_r(toe - 0.02, 0.053, 0.011 * c, 0.011 * c, -0.064, 3.0),
		_r(toe + 0.014, 0.02, 0.01 * c, 0.01 * c, -0.064, 2.4),
	], 14, 1, true, true)
	k.color = Color.WHITE
	k.reset_transform()


## Hair cap hugging the skull above a curved hairline: `front_y` at the forehead, `back_y` at the
## nape, `side_dip` lowers it over the ears (sideburns). Exact surface offset by `grow`.
static func hair_cap(k: FormKit, hr: Array, front_y: float, back_y: float, grow: float = 0.009, shade_low: float = 0.8, side_dip: float = 0.0) -> void:
	var cols := 24
	var nrows := 9
	var rows: Array = []
	var shades := PackedFloat32Array()
	for i: int in nrows:
		var t := float(i) / (nrows - 1)
		var row := PackedVector3Array()
		for j: int in cols:
			var a := TAU * j / cols
			var fw := -sin(a)  # +1 at the front (-Z), -1 at the back
			var hl := lerpf(back_y, front_y, fw * 0.5 + 0.5) - side_dip * pow(cos(a), 2.0)
			var y := lerpf(hl, 0.221, 1.0 - pow(1.0 - t, 1.6))
			var p := FormKit.surface_point(hr, y, a)
			var c := Vector3(0, 0.09, 0.0)
			var dir := (p - c).normalized()
			row.append(p + dir * grow * lerpf(1.0, 0.8, t))
		rows.append(row)
		shades.append(lerpf(shade_low, 1.0, t))
	k.patch(rows, Vector3(0, 0.09, 0), shades)


## Skull top height at depth z (x = 0) for head rings `hr`.
static func skull_top(hr: Array, z: float) -> float:
	var y := 0.222
	var best_y := 0.12
	var best_ext := 0.0
	while y > 0.06:
		var r := FormKit.at(hr, y)
		if z >= r[FormKit.R_CZ] - r[FormKit.R_ZF] and z <= r[FormKit.R_CZ] + r[FormKit.R_ZB]:
			return y
		# Past the forehead/occiput: fall back to the height where the head reaches furthest.
		var ext := (r[FormKit.R_ZF] - r[FormKit.R_CZ]) if z < 0.0 else (r[FormKit.R_ZB] + r[FormKit.R_CZ])
		if ext > best_ext:
			best_ext = ext
			best_y = y
		y -= 0.002
	return best_y


## Skull half-width at height y and depth z.
static func skull_width(hr: Array, y: float, z: float) -> float:
	var r := FormKit.at(hr, y)
	var d := z - r[FormKit.R_CZ]
	var ext := r[FormKit.R_ZB] if d > 0.0 else r[FormKit.R_ZF]
	var u := clampf(absf(d) / maxf(ext, 0.001), 0.0, 1.0)
	return r[FormKit.R_RX] * pow(maxf(0.0, 1.0 - pow(u, r[FormKit.R_N])), 1.0 / r[FormKit.R_N])


## Sculpted hair mass swept from front to back over the skull (a loft whose axis runs along Z).
## opts: front (z of the front edge), back (z of the back edge), vol_front / vol_mid / vol_back
## (height above the skull), side (extra width), depth (how far it sinks into the head),
## lift (extra front quiff height), drop (how far the back edge drops down the nape).
static func hair_mass(k: FormKit, hr: Array, opts: Dictionary) -> void:
	var zf: float = opts.get("front", -0.085)
	var zb: float = opts.get("back", 0.105)
	var vf: float = opts.get("vol_front", 0.03)
	var vm: float = opts.get("vol_mid", 0.026)
	var vb: float = opts.get("vol_back", 0.012)
	var side: float = opts.get("side", 0.01)
	var depth: float = opts.get("depth", 0.05)
	var lift: float = opts.get("lift", 0.0)
	var drop: float = opts.get("drop", 0.0)
	var n := 11
	var rings: Array = []
	for i: int in n:
		var t := float(i) / (n - 1)  # 0 = back, 1 = front
		var z := lerpf(zb, zf, t)
		var h := skull_top(hr, z)
		var vol := lerpf(vb, vm, smoothstep(0.0, 0.5, t)) if t < 0.5 else lerpf(vm, vf, smoothstep(0.5, 1.0, t))
		vol += lift * smoothstep(0.6, 0.95, t)
		var top := h + vol
		var bottom := h - depth * (1.0 - 0.75 * smoothstep(0.55, 1.0, t)) - drop * (1.0 - smoothstep(0.0, 0.35, t))
		var w := skull_width(hr, maxf(h - depth * 0.6, -0.01), z) + side
		var end_taper := sin(clampf(t, 0.0, 1.0) * PI)
		var taper := lerpf(0.35, 1.0, clampf(end_taper * 2.2, 0.0, 1.0))
		var c := (top + bottom) * 0.5
		var hh := (top - bottom) * 0.5 * lerpf(0.5, 1.0, clampf(end_taper * 3.0, 0.0, 1.0))
		rings.append(FormKit.ring(-z, w * taper, hh, hh, c, 2.3, lerpf(0.78, 1.0, smoothstep(0.0, 0.7, t))))
	k.set_transform(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	k.loft(rings, 18, 1, true, true)
	k.reset_transform()


## Stand-up collar around the neck base (chest-bone space), open at the front by `gap` radians
## each side. Outer shell, inner lining (second material via `lining` callable) and a rolled rim.
## Returns nothing; call twice with outer = true / false for the two materials.
static func collar(k: FormKit, outer: bool, opts: Dictionary) -> void:
	var y0: float = opts.get("y0", 0.235)
	var hgt: float = opts.get("height", 0.075)
	var rx: float = opts.get("rx", 0.088)
	var rzf: float = opts.get("rzf", 0.074)
	var rzb: float = opts.get("rzb", 0.078)
	var cz: float = opts.get("cz", 0.018)
	var flare: float = opts.get("flare", 0.014)
	var gap: float = opts.get("gap", 0.45)
	var front_drop: float = opts.get("front_drop", 0.45)
	var thick: float = opts.get("thick", 0.008)
	var cols := 22
	var nrows := 5
	var rows_out: Array = []
	var rows_in: Array = []
	var rim := PackedVector3Array()
	for i: int in nrows:
		var t := float(i) / (nrows - 1)
		var ro := PackedVector3Array()
		var ri := PackedVector3Array()
		for j: int in cols + 1:
			# From the right side of the opening, around the back, to the left side.
			var a := -PI * 0.5 + gap + (TAU - 2.0 * gap) * j / cols
			var from_front := absf(wrapf(a + PI * 0.5, -PI, PI))
			var h := hgt * lerpf(1.0 - front_drop, 1.0, smoothstep(gap, gap + 1.1, from_front))
			var y := y0 + h * t
			var g := flare * t * t
			var s := sin(a)
			var p := Vector3(cos(a) * (rx + g), y, cz + s * ((rzb if s > 0.0 else rzf) + g))
			var c := Vector3(0, y, cz)
			var d := Vector3(p.x - c.x, 0, p.z - c.z).normalized()
			ro.append(p + d * thick * 0.5)
			ri.append(p - d * thick * 0.5)
			if i == nrows - 1:
				rim.append(p)
		rows_out.append(ro)
		rows_in.append(ri)
	if outer:
		k.patch(rows_out, Vector3(0, y0 + hgt * 0.5, cz), PackedFloat32Array([0.85, 0.92, 1.0, 1.0, 1.0]), false)
	else:
		k.patch(rows_in, Vector3(0, y0 + hgt * 0.5, cz), PackedFloat32Array([0.6, 0.7, 0.82, 0.92, 1.0]), false, true)
		var radii := PackedFloat32Array()
		for _i: int in rim.size():
			radii.append(thick * 0.9)
		k.tube(rim, radii, 6)
		# Close the two front edges of the opening.
		for e: int in 2:
			var j := 0 if e == 0 else cols
			var edge := PackedVector3Array()
			for i: int in nrows:
				var ro_i: PackedVector3Array = rows_out[i]
				var ri_i: PackedVector3Array = rows_in[i]
				edge.append((ro_i[j] + ri_i[j]) * 0.5)
			var er := PackedFloat32Array()
			for _i: int in nrows:
				er.append(thick * 0.6)
			k.tube(edge, er, 6)


## Double-sided garment shell through `rings` (FormKit rings, any order) with an opening centred
## on `centre_angle` (default: the front, -PI/2) of half-width gaps[i] per ring (0 = closed).
## outer = true builds the outside (rim tube included on the first/last ring when `rim`), false the
## lining (normals inward). thick = shell thickness.
static func open_shell(k: FormKit, rings: Array, outer: bool, gaps: PackedFloat32Array, thick: float = 0.01, cols: int = 24, centre_angle: float = -PI * 0.5, rim: bool = true, shades: PackedFloat32Array = PackedFloat32Array()) -> void:
	var rows_o: Array[PackedVector3Array] = []
	var rows_i: Array[PackedVector3Array] = []
	var centres := PackedVector3Array()
	for i: int in rings.size():
		var r: PackedFloat32Array = rings[i]
		var g: float = gaps[i] if i < gaps.size() else gaps[gaps.size() - 1]
		var ro := PackedVector3Array()
		var ri := PackedVector3Array()
		var c := Vector3(r[FormKit.R_CX], r[FormKit.R_Y], r[FormKit.R_CZ])
		for j: int in cols + 1:
			var a := centre_angle + g + (TAU - 2.0 * g) * j / cols
			var p := FormKit.ring_point(r, a)
			var d := Vector3(p.x - c.x, 0, p.z - c.z).normalized()
			ro.append(p + d * thick * 0.5)
			ri.append(p - d * thick * 0.5)
		rows_o.append(ro)
		rows_i.append(ri)
		centres.append(c)
	var closed_ring := gaps[0] <= 0.0001 and gaps[gaps.size() - 1] <= 0.0001
	if outer:
		k.patch(rows_o, Vector3.ZERO, shades, false, false, centres)
	else:
		var sh := PackedFloat32Array()
		for i: int in rings.size():
			sh.append((shades[i] if i < shades.size() else 1.0) * 0.8)
		k.patch(rows_i, Vector3.ZERO, sh, false, true, centres)
		if rim:
			# Hem: rolled edge along the first and last rows, plus the opening edges.
			for e: int in 2:
				var idx := 0 if e == 0 else rings.size() - 1
				var ga: float = gaps[idx] if idx < gaps.size() else gaps[gaps.size() - 1]
				var r_e: PackedFloat32Array = rings[idx]
				if r_e[FormKit.R_RX] < 0.01:
					continue
				var edge := PackedVector3Array()
				var ro_e: PackedVector3Array = rows_o[idx]
				var ri_e: PackedVector3Array = rows_i[idx]
				for j: int in cols + 1:
					edge.append((ro_e[j] + ri_e[j]) * 0.5)
				var rr := PackedFloat32Array()
				rr.resize(edge.size())
				rr.fill(thick * 0.55)
				if ga > 0.0001 or e == 0:
					k.tube(edge, rr, 6)
			if not closed_ring:
				for side: int in 2:
					var j := 0 if side == 0 else cols
					var edge := PackedVector3Array()
					for i: int in rings.size():
						var ro_s: PackedVector3Array = rows_o[i]
						var ri_s: PackedVector3Array = rows_i[i]
						edge.append((ro_s[j] + ri_s[j]) * 0.5)
					var rr := PackedFloat32Array()
					rr.resize(edge.size())
					rr.fill(thick * 0.55)
					k.tube(edge, rr, 6)


## Beard / stubble on the lower face: surface patch from under the jaw up to a beard line that is
## `front_top` at the chin (below the mouth) and `side_top` along the cheeks to the sideburns.
## `cover` = half angle (from the front) the beard wraps around the jaw. Fullness grows outward.
static func beard(k: FormKit, hr: Array, front_top: float, side_top: float, grow: float, cover: float = 1.75, bottom: float = -0.012, chin_extra: float = 0.0) -> void:
	var cols := 22
	var nrows := 7
	var rows: Array[PackedVector3Array] = []
	var shades := PackedFloat32Array()
	var centres := PackedVector3Array()
	for i: int in nrows:
		var t := float(i) / (nrows - 1)
		var row := PackedVector3Array()
		for j: int in cols + 1:
			var a := -PI * 0.5 - cover + 2.0 * cover * j / cols
			var off := absf(a + PI * 0.5) / cover  # 0 at the front, 1 at the sideburn
			var top := lerpf(front_top, side_top, smoothstep(0.15, 0.55, off))
			var y := lerpf(bottom + off * 0.03, top, t)
			var p := FormKit.surface_point(hr, y, a)
			var c := Vector3(0, y, 0.0)
			var d := (p - c)
			d.y = 0.0
			d = d.normalized()
			var g := grow * (1.0 - t * 0.5) + chin_extra * (1.0 - off) * (1.0 - t)
			row.append(p + d * g + Vector3(0, -chin_extra * (1.0 - off) * (1.0 - t) * 0.6, 0))
		rows.append(row)
		shades.append(lerpf(0.85, 1.0, t))
		centres.append(Vector3(0, 0.05, 0.0))
	k.patch(rows, Vector3.ZERO, shades, false, false, centres)
