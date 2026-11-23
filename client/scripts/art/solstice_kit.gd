## SOLSTICE modular kit (spec §8.2, §8.5 step 3): lime-washed buildings, stone trims, teal shutters,
## terracotta roofs, voussoir arches and Mediterranean props, all built on a 0.5 m grid with
## chamfered, chunky forms (art bible §4.1). Palette: docs/art/maps/solstice.md.
class_name SolsticeKit
extends RefCounted

const TEX := "res://assets/maps/solstice/textures"
const TEX_SHARED := "res://assets/shared/textures"


static func setup_materials(mb: MapBuilder) -> void:
	mb.add_material("plaster", MapBuilder.env_material(TEX, "Plaster_Cream", 4.0, {"gradient_top": 7.0, "edge_strength": 0.5}))
	mb.add_material("plaster_terra", MapBuilder.env_material(TEX, "Plaster_Terracotta", 4.0, {"gradient_top": 7.0, "edge_strength": 0.45}))
	mb.add_material("plaster_sand", MapBuilder.env_material(TEX, "Plaster_Sand", 4.0, {"gradient_top": 7.0, "edge_strength": 0.5}))
	mb.add_material("trim", MapBuilder.env_material(TEX_SHARED, "Concrete", 2.0, {"tint": Color("#F6EBD3"), "edge_strength": 0.6, "gradient_strength": 0.05}))
	mb.add_material("brick", MapBuilder.env_material(TEX, "Brick_Warm", 4.0, {"gradient_top": 5.0}))
	mb.add_material("roof", MapBuilder.env_material(TEX, "RoofTile", 3.0, {"gradient_strength": 0.0, "dust_amount": 0.15}))
	mb.add_material("wood", MapBuilder.env_material(TEX, "WoodPlank", 2.0, {"edge_strength": 0.5, "gradient_strength": 0.06}))
	mb.add_material("shutter", MapBuilder.env_material(TEX, "WoodShutter_Teal", 1.5, {"edge_strength": 0.4, "gradient_strength": 0.0}))
	mb.add_material("metal_teal", MapBuilder.env_material(TEX, "MetalPainted_Teal", 2.0, {"edge_strength": 0.6, "gradient_strength": 0.0}))
	mb.add_material("metal_rust", MapBuilder.env_material(TEX, "MetalPainted_Rust", 2.0, {"edge_strength": 0.6, "gradient_strength": 0.0}))
	mb.add_material("stone", MapBuilder.env_material(TEX, "Flagstone", 3.0, {"triplanar": true, "tint": Color("#E8DDC8"), "gradient_strength": 0.08}))
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/master/M_Env_Blend.gdshader")
	for layer: Array in [["a", "Flagstone", 4.0], ["b", "Cobble", 2.5], ["c", "Sand", 4.0]]:
		floor_mat.set_shader_parameter("%s_albedo" % layer[0], load("%s/T_%s_A.png" % [TEX, layer[1]]))
		floor_mat.set_shader_parameter("%s_normal" % layer[0], load("%s/T_%s_N.png" % [TEX, layer[1]]))
		floor_mat.set_shader_parameter("%s_orm" % layer[0], load("%s/T_%s_ORM.png" % [TEX, layer[1]]))
		floor_mat.set_shader_parameter("%s_tile" % layer[0], layer[2])
	floor_mat.set_shader_parameter("noise_b_amount", 0.75)
	floor_mat.set_shader_parameter("noise_scale", 7.0)
	mb.add_material("floor", floor_mat)
	var interior := StandardMaterial3D.new()
	interior.albedo_color = Color("#3B302A")
	interior.roughness = 0.95
	mb.add_material("interior", interior)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#B85A4E")
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.backlight_enabled = false
	mb.add_material("cloth", cloth)
	var cloth2 := cloth.duplicate() as StandardMaterial3D
	cloth2.albedo_color = Color("#E8DCC4")
	mb.add_material("cloth_light", cloth2)
	var cloth3 := cloth.duplicate() as StandardMaterial3D
	cloth3.albedo_color = Color("#4E8FA3")
	mb.add_material("cloth_blue", cloth3)
	var foliage := ShaderMaterial.new()
	foliage.shader = load("res://shaders/master/M_Foliage.gdshader")
	mb.add_material("foliage", foliage)
	var pot := MapBuilder.env_material(TEX, "Plaster_Terracotta", 1.0, {"use_uv": false, "tint": Color("#D07A4E"), "gradient_strength": 0.0})
	mb.add_material("pot", pot)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#3A6E86")
	glass.roughness = 0.12
	glass.metallic_specular = 0.8
	glass.emission_enabled = true
	glass.emission = Color("#2BA6A4")
	glass.emission_energy_multiplier = 0.25
	mb.add_material("glass", glass)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("#3E4448")
	iron.roughness = 0.5
	iron.metallic = 0.6
	mb.add_material("iron", iron)


# ------------------------------------------------------------------ architecture

## A building block with plinth, floor bands, top cornice and parapet. `faces` lists the facades that
## get windows: any of "n","s","e","w" (n = -Z). Returns the top height.
static func building(mb: MapBuilder, min_xz: Vector2, max_xz: Vector2, floors: int, wall: String = "plaster", faces: PackedStringArray = ["n", "s", "e", "w"], roof: String = "tiles", seed_value: int = 0) -> float:
	var floor_h := 3.4
	var h := floors * floor_h + 0.6
	var size := Vector3(max_xz.x - min_xz.x, h, max_xz.y - min_xz.y)
	var c := Vector3((min_xz.x + max_xz.x) * 0.5, h * 0.5, (min_xz.y + max_xz.y) * 0.5)
	mb.block(wall, size, c, 0.0, "stone", 0.06)
	# Plinth (stone base, slightly proud) — strong horizontal trim, darker base (art bible §4.1/4.3).
	mb.block("trim", Vector3(size.x + 0.16, 0.7, size.z + 0.16), Vector3(c.x, 0.35, c.z), 0.0, "stone", 0.05, false, Color("#D9CDB5"))
	for f: int in range(1, floors):
		mb.block("trim", Vector3(size.x + 0.12, 0.22, size.z + 0.12), Vector3(c.x, f * floor_h, c.z), 0.0, "stone", 0.04, false)
	# Top cornice: thick, stepped.
	mb.block("trim", Vector3(size.x + 0.5, 0.3, size.z + 0.5), Vector3(c.x, h - 0.05, c.z), 0.0, "stone", 0.06, false)
	mb.block("trim", Vector3(size.x + 0.3, 0.22, size.z + 0.3), Vector3(c.x, h - 0.32, c.z), 0.0, "stone", 0.05, false)
	if roof == "tiles":
		_hip_roof(mb, Vector3(c.x, h + 0.1, c.z), Vector2(size.x + 0.6, size.z + 0.6))
	else:
		# Flat terrace with parapet.
		for side: Array in [[Vector3(0, 0, -1), size.x], [Vector3(0, 0, 1), size.x], [Vector3(-1, 0, 0), size.z], [Vector3(1, 0, 0), size.z]]:
			var n: Vector3 = side[0]
			var length: float = side[1]
			var off := Vector3(n.x * (size.x * 0.5 + 0.05), 0, n.z * (size.z * 0.5 + 0.05))
			var dims := Vector3(length + 0.4, 0.8, 0.3) if n.x == 0 else Vector3(0.3, 0.8, length + 0.4)
			mb.block(wall, dims, Vector3(c.x, h + 0.45, c.z) + off, 0.0, "stone", 0.05, false)
	# Windows on each requested facade, per floor.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + int(min_xz.x * 31 + min_xz.y * 17)
	for face: String in faces:
		var normal := {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0)}[face] as Vector3
		var along := Vector3(absf(normal.z), 0, absf(normal.x))
		var length := size.x if normal.x == 0 else size.z
		var face_pos := c + Vector3(normal.x * size.x * 0.5, 0, normal.z * size.z * 0.5)
		var count := maxi(1, int(length / 3.2))
		var spacing := length / count
		for f: int in range(1 if floors > 1 else 0, floors):
			for w: int in count:
				if rng.randf() < 0.18:
					continue
				var t := -length * 0.5 + spacing * (w + 0.5)
				var p := Vector3(face_pos.x, f * floor_h + 1.55, face_pos.z) + along * t
				window(mb, p, normal, rng.randf() < 0.6, rng.randf() < 0.25 and f > 0)
	return h


static func _hip_roof(mb: MapBuilder, base: Vector3, footprint: Vector2) -> void:
	# Low-pitch hip roof as a stack of shrinking chamfered slabs (reads as terracotta tiers) plus a ridge.
	var steps := 4
	for i: int in steps:
		var t := float(i) / steps
		var s := Vector2(footprint.x * (1.0 - t * 0.55), footprint.y * (1.0 - t * 0.55))
		mb.block("roof", Vector3(s.x, 0.32, s.y), base + Vector3(0, 0.16 + i * 0.3, 0), 0.0, "stone", 0.12, i == 0)
	mb.block("roof", Vector3(footprint.x * 0.4, 0.22, footprint.y * 0.4), base + Vector3(0, steps * 0.3 + 0.1, 0), 0.0, "stone", 0.1, false, Color(0.92, 0.9, 0.88))


## Window: stone surround, dark recess, sill, optional open shutters and balcony.
static func window(mb: MapBuilder, center: Vector3, normal: Vector3, shutters_open: bool, balcony: bool) -> void:
	var yaw := rad_to_deg(atan2(normal.x, normal.z))
	var right := Vector3(normal.z, 0, -normal.x)
	var w := 1.1
	var h := 1.7
	# Recess (dark interior) slightly proud of the wall to avoid z-fighting.
	mb.block("interior", Vector3(w, h, 0.06), center + normal * 0.03, yaw, "stone", 0.0, false)
	# Surround: chunky frame.
	mb.block("trim", Vector3(w + 0.36, 0.2, 0.16), center + Vector3(0, h * 0.5 + 0.1, 0) + normal * 0.07, yaw, "stone", 0.04, false)
	mb.block("trim", Vector3(w + 0.5, 0.14, 0.26), center - Vector3(0, h * 0.5 + 0.07, 0) + normal * 0.12, yaw, "stone", 0.035, false)
	for s: float in [-1.0, 1.0]:
		mb.block("trim", Vector3(0.18, h, 0.14), center + right * s * (w * 0.5 + 0.09) + normal * 0.06, yaw, "stone", 0.03, false)
	if shutters_open:
		for s: float in [-1.0, 1.0]:
			var hinge := center + right * s * (w * 0.5 + 0.2) + normal * 0.08
			var leaf_c := hinge + right * s * 0.3 + normal * 0.1
			mb.block("shutter", Vector3(0.58, h - 0.05, 0.05), leaf_c, yaw + s * 20.0, "wood", 0.012, false)
	else:
		mb.block("shutter", Vector3(w, h - 0.06, 0.05), center + normal * 0.09, yaw, "wood", 0.012, false)
	if balcony:
		var slab_c := center - Vector3(0, h * 0.5 + 0.12, 0) + normal * 0.6
		mb.block("trim", Vector3(w + 1.0, 0.16, 1.1), slab_c, yaw, "stone", 0.04, false)
		for i: int in 9:
			var px := -0.5 * (w + 0.9) + (w + 0.9) * i / 8.0
			mb.shape("iron", MapBuilder.xf(slab_c + right * px + normal * 0.5 + Vector3(0, 0.5, 0)), func(k: MeshKit) -> void: k.cylinder(0.018, 0.9, Vector3.ZERO, 6, 0.004))
		mb.block("iron", Vector3(w + 0.95, 0.05, 0.06), slab_c + normal * 0.5 + Vector3(0, 0.97, 0), yaw, "stone", 0.01, false)
		pot_plant(mb, slab_c + right * (w * 0.5) + normal * 0.25 + Vector3(0, 0.08, 0), 0.22, false)


## Arched doorway / passage: two piers, a voussoir arch with keystone. `collide_piers` adds collision.
static func arch_gate(mb: MapBuilder, center: Vector3, normal: Vector3, span: float, pier_h: float, depth: float, mat: String = "trim") -> void:
	var yaw := rad_to_deg(atan2(normal.x, normal.z))
	var right := Vector3(normal.z, 0, -normal.x)
	var pier_w := 0.7
	for s: float in [-1.0, 1.0]:
		var pc := center + right * s * (span * 0.5 + pier_w * 0.5) + Vector3(0, pier_h * 0.5, 0)
		mb.block(mat, Vector3(pier_w, pier_h, depth), pc, yaw, "stone", 0.05)
		mb.block(mat, Vector3(pier_w + 0.14, 0.24, depth + 0.14), pc + Vector3(0, pier_h * 0.5 - 0.12, 0), yaw, "stone", 0.04, false)
		mb.block(mat, Vector3(pier_w + 0.14, 0.4, depth + 0.14), pc - Vector3(0, pier_h * 0.5 - 0.2, 0), yaw, "stone", 0.04, false)
	var arch_xf := MapBuilder.xf(center + Vector3(0, pier_h, 0), yaw)
	mb.shape(mat, arch_xf, func(k: MeshKit) -> void:
		k.arch(span, 0.55, depth, Vector3.ZERO, 11, 0.03)
		k.box(Vector3(0.42, 0.72, depth + 0.1), Vector3(0, span * 0.5 + 0.3, 0), 0.04))
	# Arch collision approximated by a lintel block over the opening's top third.
	mb.collider(Vector3(span + 0.2, 0.6, depth), center + Vector3(0, pier_h + span * 0.5 + 0.1, 0), yaw, "stone")


## Straight flight of chunky steps rising along `dir`.
static func stairs(mb: MapBuilder, start: Vector3, dir: Vector3, width: float, rise: float, steps: int, mat: String = "trim") -> void:
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	var step_h := rise / steps
	var step_d := 0.32
	for i: int in steps:
		var top := step_h * (i + 1)
		var c := start + dir * (step_d * (i + 0.5)) + Vector3(0, top * 0.5, 0)
		mb.block(mat, Vector3(width, top, step_d + 0.01), c, yaw, "stone", 0.025, false)
	# Each step is its own box collider; step height (≤0.4 m, spec §10.1) lets players walk up.
	for i: int in steps:
		var top := step_h * (i + 1)
		mb.collider(Vector3(width, top, step_d), start + dir * (step_d * (i + 0.5)) + Vector3(0, top * 0.5, 0), yaw, "stone")


# ------------------------------------------------------------------ props (hero props near sightlines)

static func crate(mb: MapBuilder, center: Vector3, size: float = 1.2, yaw: float = 0.0) -> void:
	mb.block("wood", Vector3(size, size, size), center, yaw, "wood", 0.05, true)
	# Frame battens on two faces (chunky, readable).
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	for face: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var n := b * face
		var right := b * Vector3(face.z, 0, -face.x)
		var off := n * (size * 0.5 + 0.02)
		var yaw_f := yaw + rad_to_deg(atan2(face.x, face.z))
		mb.block("wood", Vector3(size + 0.04, 0.12, 0.06), center + off + Vector3(0, size * 0.44, 0), yaw_f, "wood", 0.02, false, Color(0.82, 0.78, 0.74))
		mb.block("wood", Vector3(size + 0.04, 0.12, 0.06), center + off - Vector3(0, size * 0.44, 0), yaw_f, "wood", 0.02, false, Color(0.82, 0.78, 0.74))
		var diag := Basis(n, PI * 0.25)
		var dxf := Transform3D(diag * Basis(Vector3.UP, deg_to_rad(yaw_f)), center + off)
		mb.shape("wood", dxf, func(k: MeshKit) -> void: k.box(Vector3(size * 1.2, 0.1, 0.05), Vector3.ZERO, 0.015), Color(0.85, 0.8, 0.76))
		var _r := right


static func barrel(mb: MapBuilder, base: Vector3, radius: float = 0.38, height: float = 1.0) -> void:
	var prof := PackedVector2Array([Vector2(radius * 0.86, 0), Vector2(radius * 0.95, height * 0.2), Vector2(radius, height * 0.5), Vector2(radius * 0.95, height * 0.8), Vector2(radius * 0.86, height)])
	mb.shape("wood", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(prof, 16))
	for y: float in [0.12, 0.88]:
		mb.shape("iron", MapBuilder.xf(base + Vector3(0, height * y, 0)), func(k: MeshKit) -> void: k.cylinder(radius * (0.97 if y < 0.5 else 0.97), 0.06, Vector3.ZERO, 16, 0.01))
	mb.collider(Vector3(radius * 1.8, height, radius * 1.8), base + Vector3(0, height * 0.5, 0), 0.0, "wood")


static func pot_plant(mb: MapBuilder, base: Vector3, radius: float = 0.35, collide: bool = true) -> void:
	var h := radius * 1.5
	var prof := PackedVector2Array([Vector2(radius * 0.6, 0), Vector2(radius * 0.8, h * 0.6), Vector2(radius, h * 0.9), Vector2(radius * 1.08, h * 0.92), Vector2(radius * 1.08, h), Vector2(radius * 0.9, h)])
	mb.shape("pot", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(prof, 14, Vector3.ZERO, false, false, true))
	# Chunky foliage clumps (stylised, not cards).
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.x * 100 + base.z * 7)
	for i: int in 4:
		var off := Vector3(rng.randf_range(-0.3, 0.3), h + radius * 0.6 + rng.randf_range(0, radius * 0.6), rng.randf_range(-0.3, 0.3)) * Vector3(radius, 1, radius) / Vector3(0.35, 1, 0.35)
		var r := radius * rng.randf_range(0.6, 0.9)
		mb.shape("foliage", MapBuilder.xf(base + off), func(k: MeshKit) -> void: k.ellipsoid(Vector3(r, r * 0.8, r), Vector3.ZERO, 10, 6), Color(rng.randf_range(0.85, 1.1), 1, rng.randf_range(0.8, 1.0)))
	if collide:
		mb.collider(Vector3(radius * 2, h, radius * 2), base + Vector3(0, h * 0.5, 0), 0.0, "stone")


static func fountain(mb: MapBuilder, base: Vector3, radius: float = 2.4) -> void:
	var basin := PackedVector2Array([Vector2(radius - 0.05, 0), Vector2(radius, 0.08), Vector2(radius, 0.62), Vector2(radius - 0.08, 0.72), Vector2(radius - 0.38, 0.72), Vector2(radius - 0.42, 0.6), Vector2(radius - 0.42, 0.3)])
	mb.shape("trim", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(basin, 32, Vector3.ZERO, false, false, false))
	mb.shape("stone", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(PackedVector2Array([Vector2(0, 0.3), Vector2(radius - 0.42, 0.3)]), 32, Vector3.ZERO, false, false, false))
	var column := PackedVector2Array([Vector2(0.55, 0.3), Vector2(0.55, 0.6), Vector2(0.32, 0.8), Vector2(0.28, 1.6), Vector2(0.9, 1.75), Vector2(1.0, 1.9), Vector2(0.9, 2.0), Vector2(0.25, 2.05), Vector2(0.2, 2.6), Vector2(0.38, 2.75), Vector2(0.0, 3.0)])
	mb.shape("trim", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(column, 20, Vector3.ZERO, false, false, false))
	mb.collider(Vector3(radius * 1.75, 0.72, radius * 1.75), base + Vector3(0, 0.36, 0), 0.0, "stone")
	mb.collider(Vector3(radius * 1.2, 0.72, radius * 1.2), base + Vector3(0, 0.36, 0), 45.0, "stone")
	mb.collider(Vector3(1.0, 2.0, 1.0), base + Vector3(0, 1.7, 0), 0.0, "stone")


## Market stall: timber frame, counter, sagging cloth canopy.
static func market_stall(mb: MapBuilder, center: Vector3, yaw: float, cloth: String = "cloth") -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var w := 3.0
	var d := 1.8
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := center + b * Vector3(sx * w * 0.5, 1.25, sz * d * 0.5)
			mb.block("wood", Vector3(0.14, 2.5 + (0.3 if sz < 0 else 0.0), 0.14), p + Vector3(0, 0.15 if sz < 0 else 0.0, 0), yaw, "wood", 0.02, false)
	mb.block("wood", Vector3(w, 1.0, 0.9), center + b * Vector3(0, 0.5, d * 0.25), yaw, "wood", 0.04)
	mb.block("wood", Vector3(w + 0.2, 0.08, 1.0), center + b * Vector3(0, 1.02, d * 0.25), yaw, "wood", 0.02, false, Color(0.9, 0.85, 0.8))
	# Produce crates on the counter (colour accents, low saturation).
	for i: int in 3:
		var cp := center + b * Vector3(-0.9 + i * 0.9, 1.2, d * 0.25)
		mb.block("wood", Vector3(0.7, 0.28, 0.5), cp, yaw + 4.0 * (i - 1), "wood", 0.02, false)
		mb.shape("foliage", MapBuilder.xf(cp + Vector3(0, 0.16, 0)), func(k: MeshKit) -> void: k.ellipsoid(Vector3(0.3, 0.1, 0.2), Vector3.ZERO, 8, 4), [Color(1.4, 0.6, 0.4), Color(1.5, 1.2, 0.4), Color(0.9, 1.1, 0.6)][i])
	# Canopy: subdivided sagging sheet.
	var canopy_xf := Transform3D(b, center + Vector3(0, 2.62, 0))
	mb.shape(cloth, canopy_xf, func(k: MeshKit) -> void: _cloth_sheet(k, Vector2(w + 0.5, d + 0.6), 0.18, 0.22))


## Sagging cloth sheet in XZ, tilted (front lower by `tilt`), sag in the middle.
static func _cloth_sheet(k: MeshKit, size: Vector2, sag: float, tilt: float, nx: int = 8, nz: int = 6) -> void:
	var pts: Array[Vector3] = []
	for iz: int in nz + 1:
		for ix: int in nx + 1:
			var u := float(ix) / nx
			var v := float(iz) / nz
			var y := -sag * sin(u * PI) * (0.6 + 0.4 * sin(v * PI)) - tilt * v
			pts.append(Vector3((u - 0.5) * size.x, y, (v - 0.5) * size.y))
	for iz: int in nz:
		for ix: int in nx:
			var a := pts[iz * (nx + 1) + ix]
			var b2 := pts[iz * (nx + 1) + ix + 1]
			var c := pts[(iz + 1) * (nx + 1) + ix + 1]
			var d := pts[(iz + 1) * (nx + 1) + ix]
			var n := (c - a).cross(b2 - d).normalized()
			if n.y < 0:
				n = -n
			k.quad(a, b2, c, d, n)


## Overhead canopy cloth strung between two walls (R1 reference), no collision.
static func canopy(mb: MapBuilder, center: Vector3, size: Vector2, yaw: float, mat: String = "cloth") -> void:
	mb.shape(mat, MapBuilder.xf(center, yaw), func(k: MeshKit) -> void: _cloth_sheet(k, size, 0.5, 0.0, 10, 6))
	for s: float in [-1.0, 1.0]:
		var b := Basis(Vector3.UP, deg_to_rad(yaw))
		mb.shape("wood", Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), center + b * Vector3(s * size.x * 0.5, 0.02, 0)), func(k: MeshKit) -> void: k.cylinder(0.05, size.y + 0.2, Vector3.ZERO, 8, 0.01))


static func laundry_line(mb: MapBuilder, a: Vector3, b: Vector3, items: int, seed_value: int) -> void:
	var dir := b - a
	var length := dir.length()
	var mid := (a + b) * 0.5 - Vector3(0, 0.25, 0)
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	mb.shape("iron", Transform3D(basis, (a + b) * 0.5 - Vector3(0, 0.12, 0)), func(k: MeshKit) -> void: k.cylinder(0.012, length, Vector3.ZERO, 4, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mats := ["cloth_light", "cloth_blue", "cloth", "cloth_light"]
	for i: int in items:
		var t := (i + 0.5) / items
		var p := a.lerp(b, t) - Vector3(0, 0.25 * sin(t * PI) + 0.05, 0)
		var w := rng.randf_range(0.5, 0.9)
		var h := rng.randf_range(0.6, 1.0)
		var yaw := rad_to_deg(atan2(dir.x, dir.z)) + 90.0
		mb.block(mats[rng.randi() % mats.size()], Vector3(w, h, 0.02), p - Vector3(0, h * 0.5, 0), yaw, "fabric", 0.0, false)
	var _m := mid


static func lamp_post(mb: MapBuilder, base: Vector3) -> void:
	var prof := PackedVector2Array([Vector2(0.18, 0), Vector2(0.18, 0.3), Vector2(0.08, 0.45), Vector2(0.06, 3.2), Vector2(0.1, 3.3), Vector2(0.0, 3.35)])
	mb.shape("iron", MapBuilder.xf(base), func(k: MeshKit) -> void: k.lathe(prof, 10))
	mb.block("iron", Vector3(0.7, 0.06, 0.06), base + Vector3(0.3, 3.1, 0), 0.0, "metal_thin", 0.01, false)
	mb.shape("glass", MapBuilder.xf(base + Vector3(0.6, 2.85, 0)), func(k: MeshKit) -> void: k.lathe(PackedVector2Array([Vector2(0.1, 0), Vector2(0.16, 0.2), Vector2(0.1, 0.3), Vector2(0.0, 0.32)]), 8))
	mb.collider(Vector3(0.3, 3.3, 0.3), base + Vector3(0, 1.65, 0), 0.0, "metal_heavy")


static func ac_unit(mb: MapBuilder, center: Vector3, normal: Vector3) -> void:
	var yaw := rad_to_deg(atan2(normal.x, normal.z))
	mb.block("trim", Vector3(0.9, 0.62, 0.36), center + normal * 0.18, yaw, "metal_thin", 0.03, false, Color(0.95, 0.95, 0.97))
	mb.shape("iron", MapBuilder.xf(center + normal * 0.37 + Vector3(0.12, 0, 0) * 0.0, yaw) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), func(k: MeshKit) -> void: k.cylinder(0.22, 0.03, Vector3.ZERO, 16, 0.005))


static func pipe(mb: MapBuilder, a: Vector3, b: Vector3, radius: float = 0.05, mat: String = "metal_rust") -> void:
	var dir := b - a
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5)
	mb.shape(mat, Transform3D(basis, (a + b) * 0.5), func(k: MeshKit) -> void: k.cylinder(radius, dir.length(), Vector3.ZERO, 8, 0.01))


## Low wall with a capping stone (classic Mediterranean cover).
static func low_wall(mb: MapBuilder, center: Vector3, length: float, yaw: float, height: float = 1.05, mat: String = "plaster_sand") -> void:
	mb.block(mat, Vector3(length, height, 0.5), center + Vector3(0, height * 0.5, 0), yaw, "stone", 0.05)
	mb.block("trim", Vector3(length + 0.12, 0.14, 0.64), center + Vector3(0, height + 0.05, 0), yaw, "stone", 0.04, false)


static func bench(mb: MapBuilder, center: Vector3, yaw: float) -> void:
	mb.block("trim", Vector3(2.0, 0.12, 0.5), center + Vector3(0, 0.46, 0), yaw, "stone", 0.03, false)
	for s: float in [-0.75, 0.75]:
		mb.block("trim", Vector3(0.18, 0.42, 0.42), center + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(s, 0.21, 0), yaw, "stone", 0.02, false)
	mb.collider(Vector3(2.0, 0.52, 0.5), center + Vector3(0, 0.26, 0), yaw, "stone")


## Painted callout sign (spec §8.1: every area is named in the world).
static func sign_board(mb: MapBuilder, root: Node3D, text: String, pos: Vector3, normal: Vector3, size: float = 0.5) -> void:
	var yaw := rad_to_deg(atan2(normal.x, normal.z))
	mb.block("metal_teal", Vector3(text.length() * size * 0.42 + 0.4, size + 0.2, 0.05), pos, yaw, "metal_thin", 0.015, false)
	var label := Label3D.new()
	label.name = "Sign_%s" % text.replace(" ", "")
	label.text = text.to_upper()
	label.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	label.font_size = 96
	label.pixel_size = size / 96.0 * 0.9
	label.modulate = Color("#F3ECDD")
	label.outline_size = 0
	label.shaded = true
	label.position = pos + normal * 0.03
	label.rotation_degrees.y = yaw
	root.add_child(label)
	label.owner = root
