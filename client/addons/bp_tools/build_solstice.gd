## Builds SOLSTICE (spec §8.2) from the SolsticeKit into res://scenes/maps/solstice.tscn and exports
## collision + meta to /shared/maps. Milestone 2 builds the B-site corner (cathedral plaza) at full
## art quality; milestone 6 adds the rest of the map through the `sections` list below.
## Run: godot --headless --path client -s res://addons/bp_tools/build_solstice.gd
extends SceneTree

const OUT := "res://scenes/maps/solstice.tscn"
## World offset of the B-site corner (local 0..40 x 0..40).
const B := Vector3(10, 0, -32)

var mb: MapBuilder
var map_root: Node3D


func _init() -> void:
	map_root = Node3D.new()
	map_root.name = "Solstice"
	mb = MapBuilder.new("solstice", map_root)
	SolsticeKit.setup_materials(mb)
	var sections: Array[Callable] = [build_b_site, build_vista]
	if FileAccess.file_exists("res://addons/bp_tools/solstice_full.gd"):
		var full: Object = load("res://addons/bp_tools/solstice_full.gd").new()
		sections.append(func() -> void: full.call("build", mb, map_root))
	for s: Callable in sections:
		s.call()
	_lighting()
	mb.finalize(ProjectSettings.globalize_path("res://").path_join("../shared/maps").simplify_path(), 0.2)
	map_root.set("map_id", "solstice")
	var err := SceneIO.save(map_root, OUT, "res://scripts/maps/map_runtime.gd")
	# Set the exported map_id in the saved scene (script is attached post-save).
	var text := FileAccess.get_file_as_string(OUT)
	text = text.replace('script = ExtResource("bp_root_script")\n', 'script = ExtResource("bp_root_script")\nmap_id = "solstice"\n')
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("saved %s: %s" % [OUT, error_string(err)])
	map_root.free()
	quit(0 if err == OK else 1)


func p(x: float, y: float, z: float) -> Vector3:
	return B + Vector3(x, y, z)


# ------------------------------------------------------------------ B site: cathedral plaza

func build_b_site() -> void:
	# Plaza floor (blend: flagstone + cobble patches), 0.6 m thick slab.
	mb.block("floor", Vector3(40, 0.6, 40), p(20, -0.3, 20), 0, "stone", 0.0)
	# Passage floors outside the plaza (B Main to the west, B Lobby to the south, B Link to the east).
	mb.block("floor", Vector3(10, 0.6, 4.4), p(-5, -0.3, 24), 0, "stone", 0.0)
	mb.block("floor", Vector3(8, 0.6, 12), p(14, -0.3, 46), 0, "stone", 0.0)
	mb.block("floor", Vector3(12, 0.6, 4.4), p(46, -0.3, 34), 0, "stone", 0.0)

	_cathedral()
	# West block (two houses) with the B Main archway between them.
	SolsticeKit.building(mb, Vector2(B.x - 8, B.z + 0), Vector2(B.x + 3, B.z + 21.8), 2, "plaster", ["e", "n"], "tiles", 1)
	SolsticeKit.building(mb, Vector2(B.x - 8, B.z + 26.2), Vector2(B.x + 3, B.z + 40), 2, "plaster_terra", ["e", "s"], "tiles", 2)
	SolsticeKit.arch_gate(mb, p(3.0, 0, 24), Vector3(1, 0, 0), 3.6, 2.6, 1.2)
	# Passage walls continuing west (enclose the B Main corridor).
	mb.block("plaster_sand", Vector3(7, 5.5, 0.6), p(-6.5, 2.75, 21.5), 0, "stone", 0.05)
	mb.block("plaster_sand", Vector3(7, 5.5, 0.6), p(-6.5, 2.75, 26.5), 0, "stone", 0.05)
	SolsticeKit.canopy(mb, p(-4.5, 4.8, 24), Vector2(4.8, 3.0), 90, "cloth")
	SolsticeKit.laundry_line(mb, p(-7, 4.4, 21.8), p(-7, 4.6, 26.2), 4, 7)

	# East block: three floors with B Balcony (heaven) walkway and stairs.
	SolsticeKit.building(mb, Vector2(B.x + 37, B.z - 2), Vector2(B.x + 47, B.z + 31.8), 3, "plaster", ["w"], "flat", 3)
	SolsticeKit.building(mb, Vector2(B.x + 37, B.z + 36.2), Vector2(B.x + 47, B.z + 44), 2, "plaster_sand", ["w", "s"], "tiles", 4)
	_balcony()

	# South edge: corner house, B Lobby gap, a shop with awning, and the sea balustrade.
	SolsticeKit.building(mb, Vector2(B.x - 1, B.z + 38), Vector2(B.x + 10, B.z + 46), 2, "plaster_sand", ["n", "e"], "tiles", 5)
	SolsticeKit.building(mb, Vector2(B.x + 18, B.z + 38.5), Vector2(B.x + 27, B.z + 45), 1, "plaster_terra", ["n"], "tiles", 6)
	mb.block("cloth_blue", Vector3(8.4, 0.08, 1.8), p(22.5, 3.0, 37.6), 0, "fabric", 0.0, false)
	for x: float in [19.0, 26.0]:
		mb.block("iron", Vector3(0.06, 3.0, 0.06), p(x, 1.5, 36.8), 0, "metal_thin", 0.01, false)
	_balustrade(p(27.5, 0, 39.6), 9.0)

	# Plaza dressing: fountain, market stalls, cover, planters, benches, lamps.
	SolsticeKit.fountain(mb, p(20, 0, 19), 2.4)
	SolsticeKit.market_stall(mb, p(8, 0, 8), 90, "cloth")
	SolsticeKit.market_stall(mb, p(31, 0, 31.5), 200, "cloth_light")
	SolsticeKit.crate(mb, p(27.2, 0.6, 11.5), 1.2, 8)
	SolsticeKit.crate(mb, p(28.5, 0.6, 11.0), 1.2, -4)
	SolsticeKit.crate(mb, p(27.8, 1.8, 11.3), 1.2, 15)
	SolsticeKit.crate(mb, p(11.5, 0.6, 29.5), 1.2, 0)
	SolsticeKit.crate(mb, p(11.5, 0.5, 31.0), 1.0, 25)
	SolsticeKit.barrel(mb, p(13.0, 0, 30.2))
	SolsticeKit.barrel(mb, p(29.8, 0, 12.6))
	SolsticeKit.low_wall(mb, p(14, 0, 14), 4.0, 90)
	SolsticeKit.low_wall(mb, p(26, 0, 25), 4.0, 0)
	for pp: Vector3 in [p(5.5, 0, 17), p(5.5, 0, 31), p(34.2, 0, 6), p(16, 0, 36.5), p(33.5, 0, 36.6)]:
		SolsticeKit.pot_plant(mb, pp, 0.45)
	SolsticeKit.bench(mb, p(20, 0, 34.5), 0)
	SolsticeKit.lamp_post(mb, p(6.5, 0, 5.5))
	SolsticeKit.lamp_post(mb, p(34, 0, 34))
	SolsticeKit.ac_unit(mb, p(37, 5.4, 4), Vector3(-1, 0, 0))
	SolsticeKit.ac_unit(mb, p(3, 4.8, 12), Vector3(1, 0, 0))
	SolsticeKit.pipe(mb, p(36.95, 0.2, 2.2), p(36.95, 10.6, 2.2), 0.06)
	SolsticeKit.pipe(mb, p(3.05, 0.2, 30.5), p(3.05, 7.2, 30.5), 0.05)
	SolsticeKit.laundry_line(mb, p(3.2, 6.2, 34), p(36.8, 7.8, 33), 9, 11)
	SolsticeKit.canopy(mb, p(20, 7.8, 7), Vector2(7.0, 5.0), 0, "cloth")

	# Signs (spec §8.1 callouts painted/signed in the world).
	SolsticeKit.sign_board(mb, map_root, "B Main", p(3.4, 3.9, 21.2), Vector3(1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "B Balcony", p(36.95, 5.6, 24.0), Vector3(-1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "B Lobby", p(10.4, 3.2, 37.95), Vector3(0, 0, -1))
	SolsticeKit.sign_board(mb, map_root, "B Link", p(36.95, 3.0, 31.0), Vector3(-1, 0, 0))
	_site_letter(p(20, 0.02, 19), "B")

	# Gameplay markers.
	mb.site("B", p(20, 2, 19), Vector3(26, 4, 26))
	mb.plant_zone("B", p(21, 1, 19), Vector3(18, 2, 20))
	mb.callout("B Site", p(20, 2, 19), Vector3(26, 4, 26))
	mb.callout("B Main", p(-4, 2, 24), Vector3(14, 4, 4.4))
	mb.callout("B Lobby", p(14, 2, 44), Vector3(8, 4, 10))
	mb.callout("B Link", p(44, 2, 34), Vector3(12, 4, 4.4))
	mb.callout("B Balcony", p(35.7, 5.4, 17), Vector3(2.6, 4, 19))
	mb.callout("Cathedral", p(20, 2, 3), Vector3(28, 4, 5))
	mb.callout("Fountain", p(20, 2, 19), Vector3(6, 4, 6))
	mb.rift_orb(p(33, 0.9, 8))
	_bookmarks()


func _cathedral() -> void:
	var x0 := B.x + 9.0
	var x1 := B.x + 35.0
	var z0 := B.z - 10.0
	var z1 := B.z + 3.0
	var h := 14.0
	var c := Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5)
	mb.block("plaster_sand", Vector3(x1 - x0, h, z1 - z0), c, 0, "stone", 0.08)
	var face_z := z1
	# Plinth, horizontal bands and a heavy cornice.
	mb.block("trim", Vector3(x1 - x0 + 0.3, 1.1, 0.5), Vector3(c.x, 0.55, face_z + 0.1), 0, "stone", 0.06, false, Color("#D6C9AF"))
	for y: float in [5.2, 9.6]:
		mb.block("trim", Vector3(x1 - x0 + 0.3, 0.35, 0.45), Vector3(c.x, y, face_z + 0.12), 0, "stone", 0.06, false)
	mb.block("trim", Vector3(x1 - x0 + 0.8, 0.6, 1.0), Vector3(c.x, h - 0.1, face_z + 0.25), 0, "stone", 0.08, false)
	# Gable (stepped pediment) above the centre bay.
	for i: int in 4:
		var w := 14.0 - i * 3.4
		mb.block("plaster_sand", Vector3(w, 1.2, 1.0), Vector3(c.x, h + 0.6 + i * 1.2, face_z - 0.4), 0, "stone", 0.06, i == 0)
		mb.block("trim", Vector3(w + 0.4, 0.25, 1.3), Vector3(c.x, h + 1.2 + i * 1.2, face_z - 0.3), 0, "stone", 0.05, false)
	# Bell tower on the east end.
	var tx := x1 - 3.5
	mb.block("plaster_sand", Vector3(6, 8, 6), Vector3(tx, h + 4, z0 + 4), 0, "stone", 0.08)
	mb.block("trim", Vector3(6.6, 0.5, 6.6), Vector3(tx, h + 8.2, z0 + 4), 0, "stone", 0.06, false)
	for nrm: Vector3 in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		SolsticeKit.arch_gate(mb, Vector3(tx, h + 4.4, z0 + 4) + nrm * 3.05, nrm, 2.0, 1.6, 0.3)
	mb.block("roof", Vector3(6.4, 0.5, 6.4), Vector3(tx, h + 8.7, z0 + 4), 0, "stone", 0.15, false)
	mb.block("roof", Vector3(4.0, 0.9, 4.0), Vector3(tx, h + 9.3, z0 + 4), 0, "stone", 0.2, false)
	mb.shape("metal_rust", MapBuilder.xf(Vector3(tx, h + 9.8, z0 + 4)), func(k: MeshKit) -> void: k.lathe(PackedVector2Array([Vector2(1.6, 0), Vector2(0.05, 2.4), Vector2(0.0, 2.45)]), 8))
	# Pilasters.
	for px: float in [x0 + 0.6, x0 + 8.0, x1 - 8.0, x1 - 0.6]:
		mb.block("trim", Vector3(1.0, h - 1.2, 0.5), Vector3(px, (h - 1.2) * 0.5 + 0.6, face_z + 0.2), 0, "stone", 0.06, false)
	# Grand portal: deep arch with closed timber doors.
	var portal := Vector3(c.x, 0, face_z + 0.35)
	SolsticeKit.arch_gate(mb, portal, Vector3(0, 0, 1), 4.2, 3.4, 1.0)
	mb.block("wood", Vector3(4.2, 5.4, 0.2), Vector3(c.x, 2.7, face_z - 0.1), 0, "wood", 0.03, false, Color(0.78, 0.66, 0.58))
	for s: float in [-1.0, 1.0]:
		for y: float in [1.2, 2.8, 4.4]:
			mb.block("iron", Vector3(1.6, 0.08, 0.06), Vector3(c.x + s * 1.0, y, face_z + 0.02), 0, "metal_thin", 0.01, false)
	# Rose window.
	var rose := Vector3(c.x, 7.6, face_z + 0.25)
	mb.shape("trim", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), rose), func(k: MeshKit) -> void: k.cylinder(1.6, 0.5, Vector3.ZERO, 24, 0.08))
	mb.shape("glass", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), rose + Vector3(0, 0, 0.06)), func(k: MeshKit) -> void: k.cylinder(1.25, 0.5, Vector3.ZERO, 24, 0.02))
	for i: int in 8:
		var a := TAU * i / 8.0
		mb.shape("trim", Transform3D(Basis(Vector3.BACK, a), rose + Vector3(0, 0, 0.32)), func(k: MeshKit) -> void: k.box(Vector3(0.1, 2.45, 0.1), Vector3.ZERO, 0.02))
	# Side windows (tall, arched heads).
	for wx: float in [x0 + 4.2, x1 - 4.2]:
		SolsticeKit.window(mb, Vector3(wx, 7.2, face_z), Vector3(0, 0, 1), false, false)
		SolsticeKit.window(mb, Vector3(wx, 2.6, face_z), Vector3(0, 0, 1), true, false)
	# Entrance steps.
	SolsticeKit.stairs(mb, Vector3(c.x - 6, 0, face_z + 2.6), Vector3(0, 0, -1), 12.0, 0.6, 3)
	mb.block("trim", Vector3(12.4, 0.6, 1.6), Vector3(c.x, 0.3, face_z + 0.8), 0, "stone", 0.05)


func _balcony() -> void:
	var y := 3.4
	var x0 := 34.4
	var x1 := 37.0
	mb.block("trim", Vector3(x1 - x0, 0.35, 18.5), p((x0 + x1) * 0.5, y - 0.17, 17.5), 0, "stone", 0.05)
	# Corbels under the slab.
	for z: float in range(9, 27, 3):
		mb.block("trim", Vector3(0.9, 0.7, 0.35), p(x1 - 0.45, y - 0.65, z), 0, "stone", 0.04, false)
	# Railing (bullet-penetrable iron), solid cap.
	for z: float in range(9, 27):
		mb.shape("iron", MapBuilder.xf(p(x0 + 0.08, y + 0.5, z + 0.5)), func(k: MeshKit) -> void: k.cylinder(0.025, 1.0, Vector3.ZERO, 6, 0.005))
	mb.block("iron", Vector3(0.1, 0.08, 18.5), p(x0 + 0.08, y + 1.02, 17.5), 0, "metal_thin", 0.01, false)
	mb.collider(Vector3(0.1, 1.05, 18.5), p(x0 + 0.08, y + 0.52, 17.5), 0, "metal_thin")
	# Half-wall cover at the balcony's north end.
	mb.block("plaster", Vector3(x1 - x0, 1.1, 0.4), p((x0 + x1) * 0.5, y + 0.55, 8.4), 0, "stone", 0.04)
	# Stairs from the plaza up to the balcony (north-bound).
	SolsticeKit.stairs(mb, p(35.7 - 1.25, 0, 30.2), Vector3(0, 0, -1), 2.5, y, 11, "trim")
	mb.block("trim", Vector3(2.5, y, 0.4), p(35.7, y * 0.5, 30.4), 0, "stone", 0.04)


func _balustrade(center: Vector3, length: float) -> void:
	mb.block("trim", Vector3(length, 0.3, 0.6), center + Vector3(0, 0.15, 0), 0, "stone", 0.04)
	mb.block("trim", Vector3(length + 0.2, 0.18, 0.66), center + Vector3(0, 1.05, 0), 0, "stone", 0.04, false)
	var count := int(length / 0.4)
	for i: int in count:
		var x := -length * 0.5 + (i + 0.5) * length / count
		var prof := PackedVector2Array([Vector2(0.1, 0), Vector2(0.12, 0.12), Vector2(0.07, 0.25), Vector2(0.13, 0.45), Vector2(0.06, 0.62), Vector2(0.09, 0.66)])
		mb.shape("trim", MapBuilder.xf(center + Vector3(x, 0.3, 0)), func(k: MeshKit) -> void: k.lathe(prof, 8))
	mb.collider(Vector3(length, 1.15, 0.6), center + Vector3(0, 0.57, 0), 0, "stone")


func _site_letter(center: Vector3, letter: String) -> void:
	var decal_label := Label3D.new()
	decal_label.name = "SiteLetter_%s" % letter
	decal_label.text = letter
	decal_label.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	decal_label.font_size = 256
	decal_label.pixel_size = 0.012
	decal_label.modulate = Color(0.95, 0.92, 0.85, 0.55)
	decal_label.outline_size = 0
	decal_label.shaded = true
	decal_label.rotation_degrees = Vector3(-90, 0, 0)
	decal_label.position = center + Vector3(-4.2, 0.0, 4.6)
	map_root.add_child(decal_label)
	decal_label.owner = map_root


func _bookmarks() -> void:
	var eye := 1.62
	mb.bookmark("B Main entry", p(-6, eye, 24), p(16, 1.5, 20))
	mb.bookmark("B Main arch", p(1.5, eye, 24.5), p(25, 2.5, 10))
	mb.bookmark("Fountain to cathedral", p(20, eye, 30), p(20, 6, 0))
	mb.bookmark("Cathedral steps", p(20, eye + 0.6, 5.5), p(20, 1.0, 30))
	mb.bookmark("Balcony overwatch", p(36, 3.4 + eye, 10), p(12, 0.5, 30))
	mb.bookmark("Balcony stairs", p(35.7, eye, 33), p(35.7, 4, 20))
	mb.bookmark("B Lobby push", p(14, eye, 46), p(20, 1.5, 18))
	mb.bookmark("B Link", p(48, eye, 34), p(20, 1.5, 22))
	mb.bookmark("Market stall west", p(4.5, eye, 12), p(28, 1.5, 24))
	mb.bookmark("Crate stack", p(24, eye, 15), p(29, 1.5, 11))
	mb.bookmark("Sea balustrade", p(30, eye, 37), p(60, 5, 75))
	mb.bookmark("Default plant", p(22, eye, 23), p(10, 2, 8))
	mb.bookmark("Roofline", p(20, 9, 38), p(20, 8, -4))
	mb.bookmark("Fountain close", p(16.5, eye, 22.5), p(20, 1.2, 19))
	mb.bookmark("Bell tower", p(28, eye, 20), p(36.5, 18, -6))
	mb.bookmark("Laundry", p(18, eye, 37), p(18, 7, 32))
	mb.bookmark("Canopy", p(14, eye, 12), p(20, 7.5, 6))
	mb.bookmark("Corner low wall", p(26, eye, 29), p(14, 1, 14))
	mb.bookmark("Overview high", p(-4, 14, 44), p(22, 0, 16), 70.0)
	mb.bookmark("Overview east", p(46, 12, 46), p(18, 0, 14), 70.0)
	mb.bookmark("Doorway R1 study", p(-9, eye, 24), p(8, 2.4, 24))


# ------------------------------------------------------------------ vista (spec §8.6)

func build_vista() -> void:
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/master/M_Water.gdshader")
	water.set_shader_parameter("wave_normal", load("res://assets/maps/solstice/textures/T_Sand_N.png"))
	mb.add_material("vista_water", water, false)
	var cliff := MapBuilder.env_material("res://assets/maps/solstice/textures", "Plaster_Sand", 9.0, {"triplanar": true, "tint": Color("#C9B48F"), "gradient_strength": 0.25, "gradient_top": 30.0, "gradient_bottom": -25.0})
	mb.add_material("vista_cliff", cliff)
	for key: String in ["plaster", "plaster_sand", "plaster_terra", "roof"]:
		mb.add_material("vista_" + key, mb.materials[key])
	var rift := ShaderMaterial.new()
	rift.shader = load("res://shaders/master/M_RiftEnergy.gdshader")
	mb.add_material("vista_rift", rift, false)
	# Sea far below the cliff town.
	mb.shape("vista_water", MapBuilder.xf(Vector3(60, -22, 70)), func(k: MeshKit) -> void:
		for ix: int in 8:
			for iz: int in 8:
				var x0 := -400.0 + ix * 100.0
				var z0 := -400.0 + iz * 100.0
				k.quad(Vector3(x0, 0, z0), Vector3(x0 + 100, 0, z0), Vector3(x0 + 100, 0, z0 + 100), Vector3(x0, 0, z0 + 100), Vector3.UP))
	# Cliff face under the plaza's south-east edge and around the bay.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 16:
		var a := deg_to_rad(-30.0 + i * 13.0)
		var r := 140.0 + rng.randf_range(-20, 20)
		var c := Vector3(60, -22, 70) + Vector3(cos(a) * r, 0, sin(a) * r * 0.8)
		var s := Vector3(rng.randf_range(30, 55), rng.randf_range(25, 60), rng.randf_range(20, 35))
		mb.block("vista_cliff", s, c + Vector3(0, s.y * 0.4, 0), rad_to_deg(a) + rng.randf_range(-20, 20), "stone", 2.5, false)
	for i: int in 5:
		var c := p(28 + i * 6.0, -12, 44 + rng.randf_range(0, 3))
		mb.block("vista_cliff", Vector3(9, 22, 6), c, rng.randf_range(-10, 10), "stone", 1.2, false)
	# Distant town on the hillside (simple blocks with roofs; low cost, horizon never empty).
	for i: int in 22:
		var bx := -70.0 + rng.randf_range(-30, 30)
		var bz := -60.0 + i * 7.0 + rng.randf_range(-3, 3)
		var by := -6.0 + rng.randf_range(-4, 6)
		var bs := Vector3(rng.randf_range(6, 11), rng.randf_range(6, 12), rng.randf_range(6, 10))
		var wall := ["plaster", "plaster_sand", "plaster_terra"][rng.randi() % 3] as String
		mb.block("vista_" + wall, bs, Vector3(bx, by + bs.y * 0.5, bz), rng.randf_range(-15, 15), "stone", 0.2, false)
		mb.block("vista_roof", Vector3(bs.x + 0.6, 0.6, bs.z + 0.6), Vector3(bx, by + bs.y + 0.3, bz), 0, "stone", 0.2, false)
	# The Rift twist: a frozen wave of crystal hanging over the bay.
	var wave_c := Vector3(75, 10, 95)
	for i: int in 26:
		var t := float(i) / 25.0
		var arc := Vector3(lerpf(-45, 45, t), sin(t * PI) * 28.0 + rng.randf_range(-3, 3), -cos(t * PI) * 6.0 + rng.randf_range(-4, 4))
		var height := rng.randf_range(8, 22) * (0.6 + sin(t * PI) * 0.6)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.3, 0.9))
		var shard := PackedVector2Array([Vector2(0, -height * 0.5), Vector2(1.6, -height * 0.2), Vector2(1.2, height * 0.35), Vector2(0, height * 0.5), Vector2(-1.4, height * 0.3), Vector2(-1.5, -height * 0.25)])
		mb.shape("vista_rift", Transform3D(tilt, wave_c + arc), func(k: MeshKit) -> void: k.extrude(shard, 2.2, Vector3.ZERO, 0.3))


# ------------------------------------------------------------------ lighting

func _lighting() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky/S_Stylized.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.4
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.2
	env.ssao_light_affect = 0.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#BFD0DE")
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 420.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_color_correction = load("res://assets/maps/solstice/lut/LUT_Solstice.png")
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	mb._add(map_root, we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#FFE0B0")  # ~5200 K golden late-morning sun
	sun.light_energy = 1.7
	sun.light_indirect_energy = 1.5
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	sun.rotation_degrees = Vector3(-42, 152, 0)
	mb._add(map_root, sun)

	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 3
	lm.use_denoiser = true
	lm.directional = false
	lm.texel_scale = 1.0
	lm.max_texture_size = 4096
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	lm.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	mb._add(map_root, lm)

	var probe := ReflectionProbe.new()
	probe.name = "ReflectionProbe_BSite"
	probe.position = p(20, 4, 20)
	probe.size = Vector3(44, 14, 44)
	probe.box_projection = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	mb._add(map_root, probe)

	# Ambient life: drifting dust motes in the sun (desktop GPU particles, auto-converted on web).
	var motes := GPUParticles3D.new()
	motes.name = "DustMotes"
	motes.amount = 160
	motes.lifetime = 9.0
	motes.position = p(20, 3, 20)
	motes.visibility_aabb = AABB(Vector3(-22, -4, -22), Vector3(44, 10, 44))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 3, 18)
	pm.gravity = Vector3(0.05, -0.02, 0.03)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.direction = Vector3(1, 0.2, 0.4)
	pm.spread = 60.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	motes.process_material = pm
	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2(0.025, 0.025)
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.albedo_color = Color(1.0, 0.95, 0.82, 0.5)
	mote_mesh.material = mote_mat
	motes.draw_pass_1 = mote_mesh
	mb._add(map_root, motes)

	# Spawn points (local dev/look-dev use until the full map lands).
	mb.spawn("attack", p(14, 0.1, 48), 180)
	mb.spawn("defense", p(20, 0.1, 6), 0)
