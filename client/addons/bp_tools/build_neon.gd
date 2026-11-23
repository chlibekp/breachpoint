## Builds NEON DISTRICT (spec §8.3): a dense East-Asian city block at night after rain.
## A = metro concourse (turnstiles, tiled pillars, a stationary train), B = market street (food
## stalls, scooters, a parking deck), Mid = covered arcade (vending machines, noodle bar) with an
## S-bend. Rift twist: a slow-turning monolith above the block projecting glitching hologram ads.
## Palette (docs/art/maps/neon_district.md): deep indigo base, sodium amber secondary, sparing
## magenta/cyan neon kept above head height so characters stay the brightest thing on screen.
## Street/arcade lights are dynamic (unshadowed, clustered) so the night look holds before and
## without a lightmap bake; the LightmapGI adds bounce from the moon only.
## Run: godot --headless --path client -s res://addons/bp_tools/build_neon.gd
extends SceneTree

const OUT := "res://scenes/maps/neon.tscn"
const TEX := "res://assets/maps/neon/textures"
const SOL := "res://assets/maps/solstice/textures"
const SHARED := "res://assets/shared/textures"
const BOUNDS := Rect2(-62, -64, 124, 154)
## Original shop and brand names (all fictional).
const SIGNS: PackedStringArray = ["MIRA NOODLE", "KAIRO TELECOM", "SOLACE 24", "BYTE ARCADE", "HANA FLOWERS", "OKORO RAMEN", "LUMA PHARMACY", "TIDE KARAOKE", "NAMI TEA", "VOLT REPAIR", "SORA BOOKS", "PRISM TRANSIT"]

var mb: MapBuilder
var map_root: Node3D
var _sign_i := 0

var walk: Array = [
	[-16, 66, 16, 88, 0.0, "Attacker Spawn"],
	[-48, 58, -16, 68, 0.0, "A Long"],
	[-48, -10, -36, 58, 0.0, "A Ramp"],
	[-58, -42, -18, -10, 0.0, "A Concourse"],
	[-20, -24, -8, -18, 0.0, "A Link"],
	[-8, -30, 4, 66, 0.0, "Mid Arcade"],
	[-8, -48, 4, -30, 0.0, "Mid Top"],
	[-22, -62, 22, -48, 0.0, "Defender Spawn"],
	[-44, -50, -22, -42, 0.0, "A Back"],
	[18, -52, 26, -38, 0.0, "B Back"],
	[16, -38, 58, -6, 0.0, "B Market"],
	[4, -22, 16, -16, 0.0, "B Main"],
	[16, 58, 32, 68, 0.0, "B Route"],
	[22, -6, 30, 58, 0.0, "B Alley"],
]


func _init() -> void:
	map_root = Node3D.new()
	map_root.name = "Neon"
	mb = MapBuilder.new("neon", map_root)
	_materials()
	var lf := LayoutFill.new(BOUNDS, walk)
	for w: Array in walk:
		mb.block("asphalt", Vector3(w[2] - w[0], 0.6, w[3] - w[1]), Vector3((w[0] + w[2]) * 0.5, -0.3, (w[1] + w[3]) * 0.5), 0, "stone", 0.0)
	lf.fill(_tower, 7)
	_metro()
	_market()
	_arcade()
	_spawns_and_markers()
	_vista()
	_lighting()
	mb.finalize(ProjectSettings.globalize_path("res://").path_join("../shared/maps").simplify_path(), 0.22)
	var err := SceneIO.save(map_root, OUT, "res://scripts/maps/map_runtime.gd")
	var text := FileAccess.get_file_as_string(OUT).replace('script = ExtResource("bp_root_script")\n', 'script = ExtResource("bp_root_script")\nmap_id = "neon"\ncharacter_fill = 7.0\ncharacter_lift = 3.0\n')
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("saved %s: %s" % [OUT, error_string(err)])
	map_root.free()
	quit(0 if err == OK else 1)


func _materials() -> void:
	mb.add_material("asphalt", MapBuilder.env_material(TEX, "Asphalt_Wet", 5.0, {"gradient_strength": 0.0}))
	mb.add_material("sidewalk", MapBuilder.env_material(TEX, "Sidewalk", 3.0, {"gradient_strength": 0.0}))
	mb.add_material("concrete", MapBuilder.env_material(TEX, "Concrete_Dark", 4.0, {"gradient_top": 14.0, "edge_strength": 0.4}))
	mb.add_material("plaster", MapBuilder.env_material(TEX, "Plaster_Slate", 4.0, {"gradient_top": 14.0, "edge_strength": 0.4}))
	mb.add_material("brick", MapBuilder.env_material(TEX, "Brick_Dark", 4.0, {"gradient_top": 10.0}))
	mb.add_material("tile", MapBuilder.env_material(TEX, "MetroTile", 2.0, {"gradient_strength": 0.05, "edge_strength": 0.5}))
	mb.add_material("tile_teal", MapBuilder.env_material(TEX, "MetroTile_Teal", 2.0, {"gradient_strength": 0.05}))
	mb.add_material("metal", MapBuilder.env_material(TEX, "MetalPainted_Indigo", 2.0, {"gradient_strength": 0.0, "edge_strength": 0.6}))
	mb.add_material("metal_teal", mb.materials["metal"])  # SolsticeKit.sign_board backing plate
	mb.add_material("metal_amber", MapBuilder.env_material(TEX, "MetalPainted_Amber", 2.0, {"gradient_strength": 0.0, "edge_strength": 0.6}))
	mb.add_material("wood", MapBuilder.env_material(SOL, "WoodPlank", 2.0, {"tint": Color("#B08870")}))
	mb.add_material("trim", MapBuilder.env_material(SHARED, "FacilityPanel_Dark", 1.0, {"tint": Color("#8A90A0"), "edge_strength": 0.6}))
	var window := StandardMaterial3D.new()
	window.albedo_color = Color("#1A1C2C")
	window.emission_enabled = true
	window.emission = Color("#FFC98A")
	window.emission_energy_multiplier = 0.35
	mb.add_material("window_lit", window)
	var window_dark := StandardMaterial3D.new()
	window_dark.albedo_color = Color("#232638")
	window_dark.roughness = 0.15
	mb.add_material("window_dark", window_dark)
	for c: Array in [["neon_magenta", "#FF3FA4"], ["neon_cyan", "#38E1FF"], ["neon_amber", "#FFB347"], ["neon_white", "#F2F4FF"]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c[1])
		m.emission_enabled = true
		m.emission = Color(c[1])
		m.emission_energy_multiplier = 3.0
		mb.add_material(c[0], m, false)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#7A2E3A")
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	mb.add_material("cloth", cloth)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#2A3448")
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	mb.add_material("glass", glass)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("#3A3F48")
	iron.roughness = 0.45
	iron.metallic = 0.7
	mb.add_material("iron", iron)
	var rift := ShaderMaterial.new()
	rift.shader = load("res://shaders/master/M_RiftEnergy.gdshader")
	rift.set_shader_parameter("core_color", Color("#7A4CFF"))
	rift.set_shader_parameter("edge_color", Color("#38E1FF"))
	mb.add_material("vista_rift", rift, false)
	mb.add_material("vista_concrete", mb.materials["concrete"])
	mb.add_material("vista_window", window)


# ------------------------------------------------------------------ kit

## Tall city building: shopfront ground floor (dark glass, sign, awning), lit/unlit window grid
## above, rooftop clutter (AC units, water tank). Signs stay above head height (2.8 m+).
func _tower(min_xz: Vector2, max_xz: Vector2, faces: PackedStringArray, rng: RandomNumberGenerator) -> void:
	var floors := rng.randi_range(4, 8) if not faces.is_empty() else 6
	var fh := 3.2
	var h := floors * fh
	var size := Vector3(max_xz.x - min_xz.x, h, max_xz.y - min_xz.y)
	var c := Vector3((min_xz.x + max_xz.x) * 0.5, h * 0.5, (min_xz.y + max_xz.y) * 0.5)
	var wall: String = ["concrete", "plaster", "brick"][rng.randi() % 3]
	if faces.is_empty():
		mb.block("vista_concrete", size, c, 0, "stone", 0.1)
		return
	mb.block(wall, size, c, 0, "stone", 0.06)
	mb.block("trim", Vector3(size.x + 0.3, 0.3, size.z + 0.3), Vector3(c.x, h + 0.15, c.z), 0, "stone", 0.05, false)
	for face: String in faces:
		var n := {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0)}[face] as Vector3
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var length := size.x if n.x == 0 else size.z
		var fc := c + Vector3(n.x * size.x * 0.5, 0, n.z * size.z * 0.5)
		var yaw := rad_to_deg(atan2(n.x, n.z))
		# Shopfront: recessed dark glass band + amber-lit interior strip + sign + awning.
		mb.block("glass", Vector3(length - 0.8, 2.4, 0.08), Vector3(fc.x, 1.4, fc.z) + n * 0.04, yaw, "glass", 0.01, false)
		mb.block("window_lit", Vector3(length - 1.2, 0.25, 0.05), Vector3(fc.x, 2.45, fc.z) + n * 0.09, yaw, "glass", 0.0, false)
		if length > 4.0 and rng.randf() < 0.85:
			_sign(Vector3(fc.x, 3.3, fc.z) + n * 0.15, n, yaw, rng)
		if rng.randf() < 0.5:
			mb.block("cloth", Vector3(length - 1.0, 0.08, 1.2), Vector3(fc.x, 2.75, fc.z) + n * 0.6, yaw, "fabric", 0.0, false)
		# Window grid above.
		var cols := maxi(1, int(length / 2.6))
		for f: int in range(1, floors):
			for k: int in cols:
				var t := -length * 0.5 + length * (k + 0.5) / cols
				var lit := rng.randf() < 0.35
				mb.block("window_lit" if lit else "window_dark", Vector3(1.4, 1.5, 0.06), fc + along * t + Vector3(0, f * fh + 1.5, 0) + n * 0.03, yaw, "glass", 0.0, false)
		# AC units + vertical sign blade on some facades.
		if rng.randf() < 0.6:
			mb.block("metal", Vector3(0.9, 0.6, 0.4), fc + along * (length * 0.3) + Vector3(0, fh * 2 + 0.6, 0) + n * 0.2, yaw, "metal_thin", 0.03, false)
		if rng.randf() < 0.35 and floors > 4:
			var blade: String = ["neon_magenta", "neon_cyan", "neon_amber"][rng.randi() % 3]
			mb.block(blade, Vector3(0.18, fh * 2.2, 0.8), fc - along * (length * 0.35) + Vector3(0, fh * 2.6, 0) + n * 0.5, yaw, "metal_thin", 0.02, false)
	# Rooftop: water tank + clutter.
	if rng.randf() < 0.5:
		mb.shape("metal_amber", MapBuilder.xf(Vector3(c.x, h + 0.3, c.z)), func(k: MeshKit) -> void: k.cylinder(1.0, 2.2, Vector3(0, 1.1, 0), 14, 0.06))


func _sign(pos: Vector3, normal: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var text := SIGNS[_sign_i % SIGNS.size()]
	_sign_i += 1
	var col: String = ["neon_magenta", "neon_cyan", "neon_amber", "neon_white"][rng.randi() % 4]
	var w := maxf(2.0, float(text.length()) * 0.28)
	mb.block("trim", Vector3(w + 0.3, 0.75, 0.12), pos, yaw, "metal_thin", 0.03, false)
	mb.block(col, Vector3(w + 0.1, 0.05, 0.14), pos + Vector3(0, 0.36, 0), yaw, "metal_thin", 0.0, false)
	mb.block(col, Vector3(w + 0.1, 0.05, 0.14), pos - Vector3(0, 0.36, 0), yaw, "metal_thin", 0.0, false)
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	l.font_size = 96
	l.pixel_size = 0.005
	l.modulate = Color(_neon_hex(col)) * 2.2
	l.shaded = false
	l.position = pos + normal * 0.08
	l.rotation_degrees.y = yaw
	mb._add(map_root, l)


static func _neon_hex(key: String) -> String:
	return {"neon_magenta": "#FF6FC0", "neon_cyan": "#7FEFFF", "neon_amber": "#FFC777", "neon_white": "#F2F4FF"}.get(key, "#FFFFFF")


## Sodium street lamp; the arm points along `arm` (unit XZ direction) over the walkway.
func _lamp(pos: Vector3, arm: Vector3 = Vector3.RIGHT) -> void:
	var yaw := rad_to_deg(atan2(-arm.z, arm.x))
	mb.shape("iron", MapBuilder.xf(pos, yaw), func(k: MeshKit) -> void:
		k.lathe(PackedVector2Array([Vector2(0.14, 0), Vector2(0.12, 0.3), Vector2(0.06, 0.4), Vector2(0.05, 4.4), Vector2(0.0, 4.45)]), 10)
		k.box(Vector3(1.2, 0.08, 0.1), Vector3(0.55, 4.3, 0), 0.02))
	mb.block("neon_amber", Vector3(0.5, 0.08, 0.25), pos + arm * 1.05 + Vector3(0, 4.24, 0), yaw, "metal_thin", 0.02, false)
	mb.collider(Vector3(0.3, 4.4, 0.3), pos + Vector3(0, 2.2, 0), 0, "metal_heavy")
	var light := OmniLight3D.new()
	light.position = pos + arm * 1.05 + Vector3(0, 4.0, 0)
	light.light_color = Color("#FFB45A")
	light.light_energy = 3.0
	light.omni_range = 12.0
	light.omni_attenuation = 1.4
	light.light_bake_mode = Light3D.BAKE_DYNAMIC
	mb._add(map_root, light)


func _vending(pos: Vector3, yaw: float, col: String) -> void:
	mb.block("metal", Vector3(1.0, 1.9, 0.8), pos + Vector3(0, 0.95, 0), yaw, "metal_heavy", 0.05)
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	mb.block(col, Vector3(0.75, 1.1, 0.04), pos + Vector3(0, 1.15, 0) + b * Vector3(0, 0, 0.41), yaw, "glass", 0.01, false)


func _scooter(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	mb.shape("metal_amber", MapBuilder.xf(pos, yaw), func(k: MeshKit) -> void:
		k.box(Vector3(0.36, 0.35, 1.2), Vector3(0, 0.55, 0), 0.1)
		k.box(Vector3(0.3, 0.12, 0.6), Vector3(0, 0.8, 0.2), 0.05)
		k.box(Vector3(0.1, 0.7, 0.1), Vector3(0, 0.9, -0.55), 0.03)
		k.box(Vector3(0.6, 0.05, 0.05), Vector3(0, 1.25, -0.55), 0.02))
	for z: float in [-0.5, 0.5]:
		mb.shape("iron", Transform3D(b * Basis(Vector3.BACK, PI * 0.5), pos + b * Vector3(0, 0.22, z)), func(k: MeshKit) -> void: k.cylinder(0.22, 0.1, Vector3.ZERO, 14, 0.03))
	mb.collider(Vector3(0.6, 1.0, 1.4), pos + Vector3(0, 0.5, 0), yaw, "metal_thin")


func _stall(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	mb.block("wood", Vector3(2.6, 1.0, 1.0), pos + Vector3(0, 0.5, 0), yaw, "wood", 0.04)
	for sx: float in [-1.2, 1.2]:
		mb.block("iron", Vector3(0.08, 2.6, 0.08), pos + b * Vector3(sx, 1.3, 0.45), yaw, "metal_thin", 0.01, false)
	mb.block("cloth", Vector3(3.0, 0.08, 1.6), pos + Vector3(0, 2.6, 0) + b * Vector3(0, 0, -0.1), yaw, "fabric", 0.0, false)
	mb.block("neon_amber", Vector3(2.4, 0.06, 0.06), pos + Vector3(0, 2.5, 0) + b * Vector3(0, 0, 0.62), yaw, "metal_thin", 0.0, false)
	for i: int in 3:
		mb.shape("metal", MapBuilder.xf(pos + b * Vector3(-0.8 + i * 0.8, 1.05, 0)), func(k: MeshKit) -> void: k.cylinder(0.2, 0.25, Vector3(0, 0.12, 0), 12, 0.03))


# ------------------------------------------------------------------ A: metro concourse

func _metro() -> void:
	var x0 := -58.0
	var x1 := -18.0
	var z0 := -42.0
	var z1 := -10.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Tiled floor + roof slab (indoor site) on columns; walls around except the entrances.
	mb.block("tile", Vector3(x1 - x0, 0.02, z1 - z0), Vector3(cx, 0.01, cz), 0, "stone", 0.0, false)
	mb.block("concrete", Vector3(x1 - x0 + 1, 0.6, z1 - z0 + 1), Vector3(cx, 6.3, cz), 0, "stone", 0.1)
	mb.block("neon_white", Vector3(x1 - x0 - 4, 0.08, 0.3), Vector3(cx, 5.95, cz - 6), 0, "metal_thin", 0.0, false)
	mb.block("neon_white", Vector3(x1 - x0 - 4, 0.08, 0.3), Vector3(cx, 5.95, cz + 6), 0, "metal_thin", 0.0, false)
	for x: float in range(int(x0) + 8, int(x1) - 2, 8):
		for z: float in [cz - 6.0, cz + 6.0]:
			mb.block("tile_teal", Vector3(1.2, 6.0, 1.2), Vector3(x, 3.0, z), 0, "stone", 0.06)
			mb.block("trim", Vector3(1.4, 0.3, 1.4), Vector3(x, 0.15, z), 0, "stone", 0.04, false)
	# Stationary train along the west wall (hard cover, readable silhouette).
	mb.block("metal", Vector3(3.2, 3.6, 24), Vector3(x0 + 2.0, 1.8, cz), 0, "metal_heavy", 0.25)
	mb.block("neon_cyan", Vector3(0.05, 0.12, 23), Vector3(x0 + 3.62, 2.9, cz), 0, "metal_thin", 0.0, false)
	for z: float in range(int(cz) - 10, int(cz) + 11, 3):
		mb.block("window_lit", Vector3(0.05, 1.0, 1.6), Vector3(x0 + 3.61, 2.2, z), 0, "glass", 0.0, false)
	mb.block("trim", Vector3(2.0, 0.9, 30), Vector3(x0 + 4.8, 0.45, cz), 0, "stone", 0.05)  # platform edge cover
	# Turnstile lines (plant-site cover, waist high).
	for i: int in 6:
		mb.block("metal", Vector3(0.35, 1.05, 1.6), Vector3(cx + 4 + i * 1.4, 0.525, cz), 0, "metal_thin", 0.04)
		mb.block("neon_cyan", Vector3(0.36, 0.05, 0.2), Vector3(cx + 4 + i * 1.4, 1.08, cz - 0.7), 0, "metal_thin", 0.0, false)
	# Ticket booth.
	mb.block("tile", Vector3(4, 2.6, 3), Vector3(cx - 6, 1.3, cz + 10), 0, "stone", 0.06)
	mb.block("window_lit", Vector3(3.0, 1.0, 0.05), Vector3(cx - 6, 1.7, cz + 8.48), 0, "glass", 0.0, false)
	_vending(Vector3(x1 - 3, 0, z0 + 2), 0, "neon_magenta")
	_vending(Vector3(x1 - 4.2, 0, z0 + 2), 0, "neon_cyan")
	SolsticeKit.sign_board(mb, map_root, "A Concourse", Vector3(cx, 4.6, z0 + 0.6), Vector3(0, 0, 1), 0.8)
	var lbl := Label3D.new()
	lbl.text = "A"
	lbl.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	lbl.font_size = 256
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.9, 0.95, 1.0, 0.5)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(cx + 2, 0.03, cz + 3)
	mb._add(map_root, lbl)
	mb.site("A", Vector3(cx, 2, cz), Vector3(x1 - x0, 4, z1 - z0))
	mb.plant_zone("A", Vector3(cx + 4, 1, cz), Vector3(16, 2, 14))
	var light := OmniLight3D.new()
	light.position = Vector3(cx, 5.2, cz)
	light.light_color = Color("#DDF4FF")
	light.light_energy = 1.6
	light.omni_range = 22.0
	light.light_bake_mode = Light3D.BAKE_DYNAMIC
	mb._add(map_root, light)


# ------------------------------------------------------------------ B: market street

func _market() -> void:
	var cx := 37.0
	var cz := -22.0
	mb.block("sidewalk", Vector3(40, 0.02, 3), Vector3(cx, 0.012, -37), 0, "stone", 0.0, false)
	_stall(Vector3(26, 0, -28), 90)
	_stall(Vector3(26, 0, -16), 90)
	_stall(Vector3(48, 0, -30), 270)
	_stall(Vector3(48, 0, -14), 270)
	_scooter(Vector3(33, 0, -9), 15)
	_scooter(Vector3(34.4, 0, -9.4), -10)
	_scooter(Vector3(42, 0, -33), 95)
	SolsticeKit.crate(mb, Vector3(37, 0.6, -22), 1.2, 10)
	SolsticeKit.crate(mb, Vector3(38.2, 0.6, -22.5), 1.2, -5)
	SolsticeKit.crate(mb, Vector3(37.6, 1.8, -22.2), 1.2, 25)
	# Parking structure deck on the east side (elevated position for defenders).
	mb.block("concrete", Vector3(6, 0.4, 24), Vector3(55, 3.4, -22), 0, "stone", 0.06)
	for z: float in [-32.0, -22.0, -12.0]:
		mb.block("concrete", Vector3(0.6, 3.2, 0.6), Vector3(52.5, 1.6, z), 0, "stone", 0.05)
	mb.block("metal", Vector3(0.1, 1.0, 24), Vector3(52.1, 4.1, -22), 0, "metal_thin", 0.02)
	SolsticeKit.stairs(mb, Vector3(53.5, 0, -6.6), Vector3(0, 0, -1), 3.0, 3.6, 12, "concrete")
	for x: float in [20.0, 30.0, 44.0, 54.0]:
		_lamp(Vector3(x, 0, -37.4), Vector3.BACK)
	_lamp(Vector3(16.6, 0, -10), Vector3.RIGHT)
	SolsticeKit.sign_board(mb, map_root, "B Market", Vector3(16.05, 3.6, -22), Vector3(1, 0, 0), 0.8)
	SolsticeKit.sign_board(mb, map_root, "Parking", Vector3(52.0, 5.4, -12), Vector3(-1, 0, 0))
	mb.site("B", Vector3(cx, 2, cz), Vector3(40, 4, 32))
	mb.plant_zone("B", Vector3(37, 1, -22), Vector3(18, 2, 18))
	mb.rift_orb(Vector3(52, 0.9, -40))


# ------------------------------------------------------------------ Mid: covered arcade

func _arcade() -> void:
	var x0 := -8.0
	var x1 := 4.0
	var cx := (x0 + x1) * 0.5
	# Glass canopy roof sections over the arcade (covered, rain-free strip).
	for z: float in range(-26, 62, 8):
		mb.block("glass", Vector3(x1 - x0 + 0.4, 0.12, 6.5), Vector3(cx, 5.6, z), 0, "glass", 0.02, false)
		mb.block("iron", Vector3(x1 - x0 + 0.4, 0.25, 0.25), Vector3(cx, 5.5, z + 3.4), 0, "metal_heavy", 0.03, false)
	# S-bend: two offset walls stop any spawn-to-spawn sightline.
	mb.block("brick", Vector3(8, 3.6, 0.6), Vector3(-4, 1.8, 14), 0, "stone", 0.05)
	mb.block("brick", Vector3(8, 3.6, 0.6), Vector3(0, 1.8, 22), 0, "stone", 0.05)
	# Vending machines, noodle bar counter, benches.
	_vending(Vector3(x0 + 0.6, 0, 34), 90, "neon_magenta")
	_vending(Vector3(x0 + 0.6, 0, 35.2), 90, "neon_cyan")
	_vending(Vector3(x1 - 0.6, 0, -6), 270, "neon_amber")
	mb.block("wood", Vector3(1.0, 1.05, 5.0), Vector3(x1 - 0.9, 0.525, 4), 0, "wood", 0.04)
	mb.block("neon_amber", Vector3(0.2, 0.05, 4.8), Vector3(x1 - 0.4, 1.08, 4), 0, "metal_thin", 0.0, false)
	SolsticeKit.sign_board(mb, map_root, "Noodle Bar", Vector3(x1 - 0.05, 3.4, 4), Vector3(-1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "Mid Arcade", Vector3(x0 + 0.05, 3.4, 44), Vector3(1, 0, 0))
	for z: float in [-20.0, 0.0, 28.0, 50.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(cx, 5.0, z)
		l.light_color = Color("#FFC27A")
		l.light_energy = 1.3
		l.omni_range = 9.0
		l.light_bake_mode = Light3D.BAKE_DYNAMIC
		mb._add(map_root, l)


func _spawns_and_markers() -> void:
	for i: int in 5:
		mb.spawn("attack", Vector3(-8 + i * 4, 0.05, 80), 0)
		mb.spawn("defense", Vector3(-8 + i * 4, 0.05, -56), 180)
	mb.buy_zone("attack", Vector3(0, 1, 77), Vector3(32, 4, 22))
	mb.buy_zone("defense", Vector3(0, 1, -55), Vector3(44, 4, 14))
	mb.rift_orb(Vector3(-2, 0.9, 30))
	for w: Array in walk:
		mb.callout(w[5], Vector3((w[0] + w[2]) * 0.5, 2, (w[1] + w[3]) * 0.5), Vector3(w[2] - w[0], 4, w[3] - w[1]))
		if w[5] != "Mid Arcade":
			mb.nav_rect(w[5], w[0], w[1], w[2], w[3])
	for n: Array in [[-8, 22.3, 4, 66, "Mid South"], [-8, 21.5, -4, 22.5, "Mid Gap S"], [-8, 14.3, 4, 21.7, "Mid Bend"], [0, 13.5, 4, 14.5, "Mid Gap N"], [-8, -30, 4, 13.7, "Mid North"]]:
		mb.nav_rect(n[4], n[0], n[1], n[2], n[3])
	_lamp(Vector3(-15.4, 0, 70), Vector3.RIGHT)
	_lamp(Vector3(15.4, 0, 70), Vector3.LEFT)
	_lamp(Vector3(-30, 0, 58.6), Vector3.BACK)
	_lamp(Vector3(-47.4, 0, 30), Vector3.RIGHT)
	_lamp(Vector3(-47.4, 0, 2), Vector3.RIGHT)
	_lamp(Vector3(29.4, 0, 40), Vector3.LEFT)
	_lamp(Vector3(29.4, 0, 12), Vector3.LEFT)
	_lamp(Vector3(24, 0, 67.4), Vector3.FORWARD)
	_lamp(Vector3(-21.4, 0, -55), Vector3.RIGHT)
	_lamp(Vector3(21.4, 0, -55), Vector3.LEFT)
	var eye := 1.62
	mb.bookmark("Attacker spawn", Vector3(0, eye, 84), Vector3(0, 3, 60))
	mb.bookmark("A Long", Vector3(-20, eye, 63), Vector3(-44, 3, 62))
	mb.bookmark("A Ramp", Vector3(-42, eye, 50), Vector3(-42, 2, 0))
	mb.bookmark("A Concourse", Vector3(-30, eye, -12), Vector3(-50, 2, -30))
	mb.bookmark("Metro train", Vector3(-46, eye, -20), Vector3(-56, 2, -34))
	mb.bookmark("Turnstiles", Vector3(-22, eye, -30), Vector3(-34, 1, -26))
	mb.bookmark("Mid Arcade", Vector3(-2, eye, 60), Vector3(-2, 2, 30))
	mb.bookmark("Noodle bar", Vector3(-6, eye, 0), Vector3(3, 1.5, 6))
	mb.bookmark("Mid S-bend", Vector3(-6, eye, 26), Vector3(2, 2, 10))
	mb.bookmark("B Alley", Vector3(26, eye, 50), Vector3(26, 2, 0))
	mb.bookmark("B Market", Vector3(22, eye, -8), Vector3(44, 2, -30))
	mb.bookmark("Parking deck", Vector3(55, 3.8 + eye, -12), Vector3(30, 1, -28))
	mb.bookmark("Market stalls", Vector3(36, eye, -36), Vector3(26, 2, -16))
	mb.bookmark("Defender spawn", Vector3(0, eye, -58), Vector3(0, 3, -40))
	mb.bookmark("Monolith", Vector3(0, eye, 40), Vector3(10, 45, -10))
	mb.bookmark("Overview", Vector3(70, 60, 90), Vector3(0, 0, 0), 60.0)


# ------------------------------------------------------------------ vista + Rift monolith

func _vista() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	# Skyline ring: tall blocks with lit window strips (horizon never empty).
	for i: int in 40:
		var a := TAU * i / 40.0
		var r := 150.0 + rng.randf_range(-15, 25)
		var p := Vector3(cos(a) * r, 0, sin(a) * r + 10)
		var h := rng.randf_range(30, 90)
		var s := Vector3(rng.randf_range(14, 26), h, rng.randf_range(14, 26))
		mb.block("vista_concrete", s, p + Vector3(0, h * 0.5 - 2, 0), rad_to_deg(-a), "stone", 0.3, false)
		for k: int in 4:
			mb.block("vista_window", Vector3(s.x * 0.8, 0.6, 0.2), p + Vector3(0, h * (0.2 + k * 0.18), 0) - Vector3(cos(a), 0, sin(a)) * (s.z * 0.5 + 0.1), rad_to_deg(-a) + 90, "stone", 0.0, false)
	# The Rift monolith: a tall hex prism hovering over the block, slowly turning (MapRuntime
	# animates nodes named "Spin_*"); hologram ad planes around it.
	var mono := MeshInstance3D.new()
	mono.name = "Spin_Monolith"
	var k := MeshKit.new()
	var hexagon := PackedVector2Array()
	for i: int in 6:
		hexagon.append(Vector2(cos(TAU * i / 6.0), sin(TAU * i / 6.0)) * 4.0)
	k.set_transform(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	k.extrude(hexagon, 26.0, Vector3.ZERO, 0.6)
	k.reset_transform()
	mono.mesh = k.commit(mb.materials["vista_rift"])
	mono.position = Vector3(8, 52, -6)
	mono.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mb._add(map_root, mono)
	var pivot := Node3D.new()
	pivot.name = "Spin_Holos"
	pivot.position = Vector3(8, 44, -6)
	mb._add(map_root, pivot)
	for i: int in 3:
		var holo := MeshInstance3D.new()
		holo.name = "Holo%d" % i
		var q := QuadMesh.new()
		q.size = Vector2(14, 8)
		holo.mesh = q
		var hm := ShaderMaterial.new()
		hm.shader = load("res://shaders/master/M_Hologram.gdshader")
		hm.set_shader_parameter("color", [Color("#FF3FA4"), Color("#38E1FF"), Color("#FFB347")][i])
		hm.set_shader_parameter("glitch", 0.35)
		holo.material_override = hm
		holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holo.position = Vector3(cos(TAU * i / 3.0) * 12, 0, sin(TAU * i / 3.0) * 12)
		holo.rotation.y = -TAU * i / 3.0 + PI * 0.5
		mb._add(pivot, holo)


func _lighting() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky/S_Stylized.gdshader")
	sky_mat.set_shader_parameter("zenith_color", Color("#0B0F26"))
	sky_mat.set_shader_parameter("horizon_color", Color("#3A2A5A"))
	sky_mat.set_shader_parameter("ground_color", Color("#14122A"))
	sky_mat.set_shader_parameter("sun_color", Color("#9FB4FF"))
	sky_mat.set_shader_parameter("cloud_light", Color("#4A4270"))
	sky_mat.set_shader_parameter("cloud_shadow", Color("#1A1836"))
	sky_mat.set_shader_parameter("cloud_cover", 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3A4070")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("#2A2E55")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	mb._add(map_root, we)
	var moon := DirectionalLight3D.new()
	moon.name = "Sun"
	moon.light_color = Color("#9DB0FF")
	moon.light_energy = 0.6
	moon.shadow_enabled = true
	moon.light_bake_mode = Light3D.BAKE_DYNAMIC
	moon.rotation_degrees = Vector3(-55, -30, 0)
	mb._add(map_root, moon)
	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_LOW
	lm.bounces = 2
	lm.texel_scale = 0.8
	mb._add(map_root, lm)
	# Rain (desktop GPU particles; auto-converted and halved on web).
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 2400
	rain.lifetime = 1.2
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.position = Vector3(0, 30, 10)
	rain.visibility_aabb = AABB(Vector3(-80, -35, -80), Vector3(160, 40, 160))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(70, 1, 80)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.015, 0.5)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.albedo_color = Color(0.7, 0.8, 1.0, 0.25)
	drop.material = dm
	rain.draw_pass_1 = drop
	mb._add(map_root, rain)
