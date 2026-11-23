## Builds THE RANGE (spec §8.4): a clean PRISM training facility. Shooting lane with targets at
## 10/20/30/50 m, a strafing-bot track, a plant/defuse practice site and an ability sandbox.
## Run: godot --headless --path client -s res://addons/bp_tools/build_range.gd
extends SceneTree

const OUT := "res://scenes/maps/range.tscn"
const TEX := "res://assets/shared/textures"

var mb: MapBuilder
var map_root: Node3D


func _init() -> void:
	map_root = Node3D.new()
	map_root.name = "Range"
	mb = MapBuilder.new("range", map_root)
	_materials()
	_build()
	_lighting()
	mb.finalize(ProjectSettings.globalize_path("res://").path_join("../shared/maps").simplify_path(), 0.2)
	var err := SceneIO.save(map_root, OUT, "res://scripts/maps/map_runtime.gd")
	var text := FileAccess.get_file_as_string(OUT).replace('script = ExtResource("bp_root_script")\n', 'script = ExtResource("bp_root_script")\nmap_id = "range"\n')
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("saved %s: %s" % [OUT, error_string(err)])
	map_root.free()
	quit(0 if err == OK else 1)


func _materials() -> void:
	mb.add_material("panel", MapBuilder.env_material(TEX, "FacilityPanel", 4.0, {"gradient_top": 9.0, "edge_strength": 0.4}))
	mb.add_material("panel_dark", MapBuilder.env_material(TEX, "FacilityPanel_Dark", 4.0, {"gradient_top": 9.0, "edge_strength": 0.5}))
	mb.add_material("floor", MapBuilder.env_material(TEX, "Concrete", 6.0, {"tint": Color("#D8D6D0"), "gradient_strength": 0.0, "roughness_mult": 0.7}))
	mb.add_material("floor_dark", MapBuilder.env_material(TEX, "Concrete", 6.0, {"tint": Color("#6E747A"), "gradient_strength": 0.0, "roughness_mult": 0.6}))
	mb.add_material("trim", MapBuilder.env_material(TEX, "FacilityPanel_Dark", 1.0, {"tint": Color("#9AA4AE"), "edge_strength": 0.7}))
	mb.add_material("metal", MapBuilder.env_material("res://assets/maps/solstice/textures", "MetalPainted_Teal", 2.0, {"tint": Color("#6F8C95"), "gradient_strength": 0.0}))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#E8FBFF")
	glow.emission_enabled = true
	glow.emission = Color("#BFF6FF")
	glow.emission_energy_multiplier = 3.0
	mb.add_material("light_strip", glow, false)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("#2BA6A4")
	accent.emission_enabled = true
	accent.emission = Color("#2BA6A4")
	accent.emission_energy_multiplier = 1.2
	mb.add_material("accent", accent, false)
	var target := StandardMaterial3D.new()
	target.albedo_color = Color("#E9E4DA")
	target.roughness = 0.7
	mb.add_material("target_board", target)
	var site := StandardMaterial3D.new()
	site.albedo_color = Color("#C8643B")
	site.roughness = 0.8
	mb.add_material("site_paint", site)


func _build() -> void:
	# Hall: 36 m wide (x -18..18), 80 m long (z +8 .. -72), walls 9 m, open roof with beams.
	mb.block("floor", Vector3(36, 0.6, 80), Vector3(0, -0.3, -32), 0, "stone", 0.0)
	mb.block("floor_dark", Vector3(10, 0.02, 64), Vector3(0, 0.01, -40), 0, "stone", 0.0, false)
	for sx: float in [-1.0, 1.0]:
		mb.block("panel", Vector3(0.8, 9, 80), Vector3(sx * 18.4, 4.5, -32), 0, "stone", 0.06)
		mb.block("trim", Vector3(1.1, 0.4, 80), Vector3(sx * 18.2, 0.2, -32), 0, "stone", 0.04, false)
		mb.block("trim", Vector3(1.1, 0.3, 80), Vector3(sx * 18.2, 6.0, -32), 0, "stone", 0.04, false)
		mb.block("light_strip", Vector3(0.12, 0.12, 76), Vector3(sx * 17.95, 6.3, -32), 0, "stone", 0.02, false)
		# Pilasters.
		for z: float in range(4, -72, -8):
			mb.block("panel_dark", Vector3(1.4, 9, 1.0), Vector3(sx * 17.7, 4.5, z), 0, "stone", 0.06)
	mb.block("panel_dark", Vector3(37.6, 9, 0.8), Vector3(0, 4.5, -72.4), 0, "stone", 0.06)
	mb.block("panel", Vector3(37.6, 9, 0.8), Vector3(0, 4.5, 8.4), 0, "stone", 0.06)
	# Roof beams (open sky between them, so the sun lights the hall).
	for z: float in range(4, -72, -8):
		mb.block("trim", Vector3(36.8, 0.6, 0.5), Vector3(0, 9.2, z), 0, "metal_heavy", 0.05, false)
	# Shooting booth: low counter + dividers at z = 0 (stand behind it, shoot toward -Z).
	mb.block("panel_dark", Vector3(10, 1.05, 0.8), Vector3(0, 0.525, -0.5), 0, "stone", 0.05)
	mb.block("accent", Vector3(10, 0.05, 0.84), Vector3(0, 1.07, -0.5), 0, "stone", 0.01, false)
	for x: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		mb.block("trim", Vector3(0.12, 2.4, 1.4), Vector3(x, 1.2, 0.2), 0, "metal_thin", 0.02)
	# Distance markers (lane floor) + target stands at 10/20/30/50 m.
	for d: int in [10, 20, 30, 50]:
		var z := -float(d) - 1.0
		mb.block("accent", Vector3(10, 0.02, 0.15), Vector3(0, 0.02, z + 0.8), 0, "stone", 0.0, false)
		var lbl := Label3D.new()
		lbl.text = "%d M" % d
		lbl.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
		lbl.font_size = 128
		lbl.pixel_size = 0.008
		lbl.rotation_degrees = Vector3(-90, 0, 0)
		lbl.position = Vector3(-6.5, 0.03, z + 0.8)
		lbl.modulate = Color(0.95, 0.97, 1.0, 0.8)
		mb._add(map_root, lbl)
		mb.meta.get_or_add("targets", []).append({"distance": d, "pos": MapBuilder._v(Vector3(0, 0, z))})
	# Strafing track at 15 m: rails left-right.
	mb.block("metal", Vector3(14, 0.1, 0.3), Vector3(0, 0.05, -15.5), 0, "metal_thin", 0.02, false)
	mb.meta["strafeTrack"] = {"a": MapBuilder._v(Vector3(-6, 0, -16)), "b": MapBuilder._v(Vector3(6, 0, -16))}
	mb.meta["movingBots"] = [MapBuilder._v(Vector3(-4, 0, -26)), MapBuilder._v(Vector3(4, 0, -38))]
	# Plant/defuse practice site (west bay) with hard cover crates and site paint.
	mb.block("site_paint", Vector3(10, 0.02, 10), Vector3(-11, 0.012, -45), 0, "stone", 0.0, false)
	for c: Array in [[Vector3(-13.5, 0.6, -42), 1.2], [Vector3(-12.3, 0.6, -42.3), 1.2], [Vector3(-8.5, 0.6, -48), 1.2], [Vector3(-13.0, 1.8, -42.2), 1.2]]:
		mb.block("metal", Vector3(c[1], c[1], c[1]), c[0], 0, "metal_heavy", 0.06)
	mb.block("panel_dark", Vector3(0.6, 2.2, 6), Vector3(-6.2, 1.1, -45), 0, "stone", 0.05)
	mb.site("A", Vector3(-11, 1, -45), Vector3(10, 3, 10))
	mb.plant_zone("A", Vector3(-11, 1, -45), Vector3(9, 2, 9))
	# Ability sandbox (east bay): open floor with a few walls to throw utility against.
	mb.block("floor_dark", Vector3(12, 0.02, 20), Vector3(11, 0.012, -52), 0, "stone", 0.0, false)
	mb.block("panel", Vector3(6, 3.5, 0.5), Vector3(11, 1.75, -48), 0, "stone", 0.05)
	mb.block("panel", Vector3(0.5, 3.5, 6), Vector3(8, 1.75, -57), 0, "stone", 0.05)
	mb.block("metal", Vector3(2, 1, 4), Vector3(14, 0.5, -58), 0, "metal_thin", 0.05)
	mb.callout("Lane", Vector3(0, 2, -30), Vector3(10, 4, 60))
	mb.callout("Plant Practice", Vector3(-11, 2, -45), Vector3(10, 4, 10))
	mb.callout("Ability Sandbox", Vector3(11, 2, -52), Vector3(12, 4, 20))
	# PRISM signage.
	for s: Array in [["PRISM TRAINING FACILITY", Vector3(0, 7.2, -71.95), 1.0], ["PLANT PRACTICE", Vector3(-17.95, 3.4, -45), 0.6], ["ABILITY SANDBOX", Vector3(17.95, 3.4, -52), 0.6]]:
		var l := Label3D.new()
		l.text = s[0]
		l.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
		l.font_size = 128
		l.pixel_size = float(s[2]) * 0.008
		l.position = s[1]
		l.modulate = Color("#ECE8E1")
		l.shaded = true
		var pos: Vector3 = s[1]
		if absf(pos.x) > 17:
			l.rotation_degrees.y = 90.0 if pos.x < 0 else -90.0
		mb._add(map_root, l)
	mb.spawn("attack", Vector3(0, 0, 3), 0)
	mb.spawn("defense", Vector3(0, 0, 3), 0)
	mb.bookmark("Booth", Vector3(0, 1.62, 2.5), Vector3(0, 1.2, -30))
	mb.bookmark("Lane side", Vector3(-8, 2.5, -8), Vector3(2, 1, -30))
	mb.bookmark("Plant practice", Vector3(-4, 1.62, -38), Vector3(-12, 0.5, -46))
	mb.bookmark("Sandbox", Vector3(4, 1.62, -44), Vector3(12, 1, -54))
	mb.bookmark("Overview", Vector3(14, 8, 6), Vector3(-2, 0, -36), 70.0)


func _lighting() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky/S_Stylized.gdshader")
	sky_mat.set_shader_parameter("cloud_cover", 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.3
	env.glow_intensity = 0.3
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	mb._add(map_root, we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#FFF1DC")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	sun.rotation_degrees = Vector3(-58, 30, 0)
	mb._add(map_root, sun)
	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_LOW
	lm.bounces = 2
	lm.texel_scale = 0.6
	mb._add(map_root, lm)
