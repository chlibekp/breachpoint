## SOLSTICE full layout (milestone 6, spec §8.1/§8.2). Loaded by build_solstice.gd.
## Lanes/chokes/sites are declared as walkable rectangles; every other 2 m cell inside the map
## bounds becomes building mass (merged into varied SOLSTICE buildings whose windows face walkable
## space). Timings at 6.75 m/s: attackers -> A ~125 m (18.5 s), -> B ~120 m (18 s);
## defenders -> A ~64 m (9.5 s), -> B ~52 m (8 s); defender rotate A<->B ~108 m (16 s).
extends RefCounted

const CELL := 2.0
const BOUNDS := Rect2(-64, -64, 132, 154)  ## x, z, w, d

var mb: MapBuilder
var map_root: Node3D

## Walkable rectangles: [x0, z0, x1, z1, floor_y, name]
var walk: Array = [
	[-16, 66, 16, 88, 0.0, "Attacker Spawn"],
	[-44, 66, -16, 76, 0.0, "A Lobby"],
	[-44, 2, -32, 76, 0.0, "A Main"],
	[-56, -38, -16, 2, 0.0, "A Site"],
	[-18, -12, -10, -4, 0.0, "A Link"],
	[-10, -24, 0, 66, 0.0, "Mid"],
	[-10, -48, 0, -24, 0.0, "Mid Top"],
	[-18, -62, 20, -48, 0.0, "Defender Spawn"],
	[-46, -50, -18, -38, 0.0, "A Back"],
	[13, -50, 19, -32, 0.0, "B Back"],
	[16, 62, 30, 70, 0.0, "B Lobby Route"],
	[20, 20, 28, 62, 0.0, "B Long"],
	[-60, -40, -56, 4, 0.0, "_harbour"],
	[0, -10, 2, -6, 0.0, "_bmain_mouth"],
	[-64, -40, -60, 4, 0.0, "_harbour_water"],
	[66, -64, 68, 90, 0.0, "_edge"],
]
## Extra nav rectangles for the hand-built B corner (its callouts are names, not a lane graph).
const NAV_EXTRA: Array = [
	[10, -32, 50, 8, "B Plaza"],
	[-4, -10, 10, -6, "B Main Passage"],
	[20, 8, 28, 20, "B Lobby"],
]

## Reserved rectangles: hand-built areas (B-site corner) — neither walkable nor auto-filled.
var reserved: Array = [
	[2, -32, 57, 8],  ## B plaza, west/east buildings, B Main passage (build_b_site)
	[19, -42, 45, -32],  ## cathedral + bell tower
	[9, 6, 37, 14],  ## south houses + B Lobby gap
	[20, 14, 28, 20],  ## B Lobby floor
	[45, 8, 57, 14],  ## east house 2
]

var _grid: PackedByteArray  ## 0 = solid, 1 = walkable, 2 = reserved
var _nx := 0
var _nz := 0


func build(builder: MapBuilder, root: Node3D) -> void:
	mb = builder
	map_root = root
	_rasterise()
	_floors()
	_fill_buildings()
	_mid_terrace()
	_a_site()
	_spawns()
	_b_back_and_long()
	_boundary()
	_markers()


func _cell_rect(ix: int, iz: int) -> Rect2:
	return Rect2(BOUNDS.position.x + ix * CELL, BOUNDS.position.y + iz * CELL, CELL, CELL)


func _rasterise() -> void:
	_nx = int(BOUNDS.size.x / CELL)
	_nz = int(BOUNDS.size.y / CELL)
	_grid = PackedByteArray()
	_grid.resize(_nx * _nz)
	for iz: int in _nz:
		for ix: int in _nx:
			var c := _cell_rect(ix, iz).get_center()
			var v := 0
			for r: Array in reserved:
				if c.x > r[0] and c.x < r[2] and c.y > r[1] and c.y < r[3]:
					v = 2
			for w: Array in walk:
				if c.x > w[0] and c.x < w[2] and c.y > w[1] and c.y < w[3]:
					v = 1
			_grid[iz * _nx + ix] = v


func _at(ix: int, iz: int) -> int:
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return 3
	return _grid[iz * _nx + ix]


func _floors() -> void:
	for w: Array in walk:
		if str(w[5]).begins_with("_"):
			continue
		var size := Vector3(w[2] - w[0], 0.6, w[3] - w[1])
		var center := Vector3((w[0] + w[2]) * 0.5, float(w[4]) - 0.3, (w[1] + w[3]) * 0.5)
		mb.block("floor", size, center, 0, "stone", 0.0)


## Greedy rectangle merge of solid cells into buildings (max 7 x 7 cells = 14 m).
func _fill_buildings() -> void:
	var used := PackedByteArray()
	used.resize(_nx * _nz)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2040
	var walls := ["plaster", "plaster", "plaster_sand", "plaster_terra"]
	for iz: int in _nz:
		for ix: int in _nx:
			if _at(ix, iz) != 0 or used[iz * _nx + ix] == 1:
				continue
			var w := 1
			while w < 7 and _at(ix + w, iz) == 0 and used[iz * _nx + ix + w] == 0:
				w += 1
			var d := 1
			var ok := true
			while d < 7 and ok:
				for k: int in w:
					if _at(ix + k, iz + d) != 0 or used[(iz + d) * _nx + ix + k] == 1:
						ok = false
						break
				if ok:
					d += 1
			for dz: int in d:
				for dx: int in w:
					used[(iz + dz) * _nx + ix + dx] = 1
			var r0 := _cell_rect(ix, iz)
			var min_xz := Vector2(r0.position.x, r0.position.y)
			var max_xz := min_xz + Vector2(w * CELL, d * CELL)
			# Windows only where the facade looks onto walkable space.
			var faces := PackedStringArray()
			if _row_has(ix, ix + w - 1, iz - 1, 1):
				faces.append("n")
			if _row_has(ix, ix + w - 1, iz + d, 1):
				faces.append("s")
			if _col_has(iz, iz + d - 1, ix - 1, 1):
				faces.append("w")
			if _col_has(iz, iz + d - 1, ix + w, 1):
				faces.append("e")
			var floors := 2 + int(rng.randf() < 0.45) if not faces.is_empty() else 3
			var wall: String = walls[rng.randi() % walls.size()]
			if faces.is_empty():
				# Interior mass nobody sees up close: plain block + roof (cheap).
				var h := floors * 3.4 + 0.6
				mb.block("vista_" + wall if mb.materials.has("vista_" + wall) else wall, Vector3(w * CELL, h, d * CELL), Vector3((min_xz.x + max_xz.x) * 0.5, h * 0.5, (min_xz.y + max_xz.y) * 0.5), 0, "stone", 0.1, true)
				continue
			SolsticeKit.building(mb, min_xz, max_xz, floors, wall, faces, "tiles" if rng.randf() < 0.7 else "flat", rng.randi())


func _row_has(x0: int, x1: int, iz: int, v: int) -> bool:
	for ix: int in range(x0, x1 + 1):
		if _at(ix, iz) == v:
			return true
	return false


func _col_has(z0: int, z1: int, ix: int, v: int) -> bool:
	for iz: int in range(z0, z1 + 1):
		if _at(ix, iz) == v:
			return true
	return false


## Mid "Stepped Alley" (spec §8.2): raised terrace with steps, an arched bridge overhead,
## laundry lines and potted plants.
func _mid_terrace() -> void:
	var x0 := -10.0
	var x1 := 0.0
	var cx := (x0 + x1) * 0.5
	var top := 1.2
	mb.block("trim", Vector3(x1 - x0, top, 28.0), Vector3(cx, top * 0.5, 16.0), 0, "stone", 0.04)
	SolsticeKit.stairs(mb, Vector3(x0, 0, 33.3), Vector3(0, 0, -1), x1 - x0, top, 4)
	SolsticeKit.stairs(mb, Vector3(x0, 0, -1.3), Vector3(0, 0, 1), x1 - x0, top, 4)
	# Arched bridge over the alley.
	for z: float in [14.0, 16.4]:
		SolsticeKit.arch_gate(mb, Vector3(cx, top, z), Vector3(0, 0, 1), x1 - x0 - 1.4, 2.6, 0.6)
	mb.block("trim", Vector3(x1 - x0 + 0.4, 0.5, 3.0), Vector3(cx, top + 2.6 + (x1 - x0 - 1.4) * 0.5 + 0.5, 15.2), 0, "stone", 0.05, false)
	SolsticeKit.laundry_line(mb, Vector3(x0 + 0.1, 6.0, 24), Vector3(x1 - 0.1, 6.3, 24.5), 4, 31)
	SolsticeKit.laundry_line(mb, Vector3(x0 + 0.1, 5.4, 6), Vector3(x1 - 0.1, 5.6, 6.2), 3, 32)
	SolsticeKit.canopy(mb, Vector3(cx, 5.2, 40), Vector2(x1 - x0 - 0.4, 3.5), 0, "cloth")
	for p: Vector3 in [Vector3(x0 + 0.8, top, 26), Vector3(x1 - 0.8, top, 9), Vector3(x0 + 0.8, 0, 52), Vector3(x1 - 0.8, 0, -16)]:
		SolsticeKit.pot_plant(mb, p, 0.42)
	SolsticeKit.crate(mb, Vector3(x1 - 1.0, top + 0.6, 20.0), 1.2, 10)
	SolsticeKit.crate(mb, Vector3(x0 + 1.2, 0.6, 46.0), 1.2, -8)
	SolsticeKit.barrel(mb, Vector3(x0 + 1.0, 0, -20))
	SolsticeKit.sign_board(mb, map_root, "Mid", Vector3(x0 + 0.05, 3.4, 36), Vector3(1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "A Link", Vector3(-10.05, 3.0, -8), Vector3(1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "Mid Top", Vector3(x0 + 0.05, 3.0, -30), Vector3(1, 0, 0))


## A site: harbour warehouse with stacked cargo, cranes and a boathouse (spec §8.2).
func _a_site() -> void:
	# Quay edge + harbour water to the west (invisible wall stops players dropping in).
	mb.collider(Vector3(0.4, 4, 44), Vector3(-60.2, 2, -18), 0, "invisible")
	mb.block("floor", Vector3(4, 0.6, 44), Vector3(-58, -0.3, -18), 0, "stone", 0.0)
	mb.shape("vista_water", MapBuilder.xf(Vector3(-62, -1.4, -18)), func(k: MeshKit) -> void:
		k.quad(Vector3(-200, 0, -120), Vector3(2, 0, -120), Vector3(2, 0, 100), Vector3(-200, 0, 100), Vector3.UP))
	mb.block("trim", Vector3(1.2, 1.0, 40), Vector3(-59.4, -0.5, -18), 0, "stone", 0.05)
	mb.block("trim", Vector3(1.4, 0.4, 40), Vector3(-59.4, 0.2, -18), 0, "stone", 0.04, false)
	for z: float in range(-36, 2, 4):
		mb.block("iron", Vector3(0.3, 0.5, 0.3), Vector3(-59.0, 0.25, z), 0, "metal_heavy", 0.03)  # bollards
	# Warehouse shed: open-fronted, steel frame, corrugated roof; site interior under it.
	var shed_c := Vector3(-44, 0, -26)
	for x: float in [-54.0, -46.0, -38.0]:
		for z: float in [-34.0, -18.0]:
			mb.block("metal_rust", Vector3(0.5, 7.0, 0.5), shed_c * 0.0 + Vector3(x, 3.5, z), 0, "metal_heavy", 0.04)
	mb.block("metal_rust", Vector3(18, 0.4, 18), Vector3(-46, 7.2, -26), 0, "metal_heavy", 0.06, false)
	mb.block("roof", Vector3(19, 0.3, 19), Vector3(-46, 7.55, -26), 0, "metal_thin", 0.1, false, Color(0.75, 0.82, 0.85))
	mb.block("plaster_sand", Vector3(18, 7, 0.6), Vector3(-46, 3.5, -35.7), 0, "stone", 0.06)
	# Stacked cargo (hard cover, readable blocks) — teal/rust containers.
	var cont := func(c: Vector3, yaw: float, mat: String) -> void:
		mb.block(mat, Vector3(6.0, 2.6, 2.4), c + Vector3(0, 1.3, 0), yaw, "metal_heavy", 0.06)
		for i: int in 9:
			var b := Basis(Vector3.UP, deg_to_rad(yaw))
			mb.block(mat, Vector3(0.12, 2.3, 2.46), c + b * Vector3(-2.6 + i * 0.65, 1.3, 0), yaw, "metal_thin", 0.01, false, Color(0.85, 0.85, 0.85))
	cont.call(Vector3(-50, 0, -22), 90.0, "metal_teal")
	cont.call(Vector3(-50, 2.6, -22), 90.0, "metal_rust")
	cont.call(Vector3(-41, 0, -29), 0.0, "metal_rust")
	cont.call(Vector3(-33, 0, -14), 15.0, "metal_teal")
	cont.call(Vector3(-24, 0, -30), 90.0, "metal_teal")
	SolsticeKit.crate(mb, Vector3(-44.5, 0.6, -18.5), 1.2, 5)
	SolsticeKit.crate(mb, Vector3(-43.3, 0.6, -18.2), 1.2, -10)
	SolsticeKit.crate(mb, Vector3(-28, 0.6, -6), 1.2, 0)
	SolsticeKit.crate(mb, Vector3(-28, 1.8, -6), 1.2, 20)
	SolsticeKit.barrel(mb, Vector3(-36, 0, -33))
	SolsticeKit.barrel(mb, Vector3(-35.2, 0, -33.6))
	# Crane: tall steel frame with a jib over the water (landmark, no gameplay collision up high).
	mb.block("metal_teal", Vector3(1.0, 16, 1.0), Vector3(-56, 8, -4), 0, "metal_heavy", 0.06)
	mb.block("metal_teal", Vector3(14, 0.8, 0.8), Vector3(-60, 16.2, -4), 0, "metal_heavy", 0.05, false)
	mb.block("metal_rust", Vector3(2.2, 2.0, 2.2), Vector3(-56, 14.8, -4), 0, "metal_heavy", 0.06, false)
	SolsticeKit.pipe(mb, Vector3(-65, 16, -4), Vector3(-65, 9, -4), 0.03, "iron")
	# Boathouse at the north-west corner.
	SolsticeKit.building(mb, Vector2(-62, -50), Vector2(-50, -40), 1, "plaster_terra", ["e", "s"], "tiles", 77)
	SolsticeKit.sign_board(mb, map_root, "A Main", Vector3(-38, 3.2, 1.9), Vector3(0, 0, -1))
	SolsticeKit.sign_board(mb, map_root, "A Site", Vector3(-46, 5.5, -35.35), Vector3(0, 0, 1), 0.8)
	SolsticeKit.sign_board(mb, map_root, "A Back", Vector3(-30, 3.0, -37.95), Vector3(0, 0, 1))
	var lbl := Label3D.new()
	lbl.text = "A"
	lbl.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	lbl.font_size = 256
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.95, 0.92, 0.85, 0.55)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(-38, 0.02, -20)
	map_root.add_child(lbl)
	lbl.owner = map_root
	mb.site("A", Vector3(-40, 2, -19), Vector3(36, 4, 34))
	mb.plant_zone("A", Vector3(-40, 1, -20), Vector3(20, 2, 18))
	mb.rift_orb(Vector3(-24, 0.9, -36))


func _spawns() -> void:
	for i: int in 5:
		mb.spawn("attack", Vector3(-8 + i * 4, 0.05, 80), 0)
		mb.spawn("defense", Vector3(-8 + i * 4, 0.05, -55), 180)
	mb.buy_zone("attack", Vector3(0, 1, 77), Vector3(32, 4, 22))
	mb.buy_zone("defense", Vector3(1, 1, -55), Vector3(38, 4, 14))
	# Spawn dressing: PRISM drop-pods / supply crates.
	for x: float in [-12.0, 12.0]:
		SolsticeKit.crate(mb, Vector3(x, 0.6, 84), 1.2, 0)
		SolsticeKit.crate(mb, Vector3(x, 0.6, -60), 1.2, 0)
	mb.meta["barriers"] = [
		{"team": "attack", "center": MapBuilder._v(Vector3(-38, 2, 66.2)), "size": MapBuilder._v(Vector3(12, 4, 0.4))},
		{"team": "attack", "center": MapBuilder._v(Vector3(-5, 2, 66.2)), "size": MapBuilder._v(Vector3(10, 4, 0.4))},
		{"team": "attack", "center": MapBuilder._v(Vector3(16.2, 2, 66)), "size": MapBuilder._v(Vector3(0.4, 4, 8))},
		{"team": "defense", "center": MapBuilder._v(Vector3(-5, 2, -47.8)), "size": MapBuilder._v(Vector3(10, 4, 0.4))},
		{"team": "defense", "center": MapBuilder._v(Vector3(-18.2, 2, -44)), "size": MapBuilder._v(Vector3(0.4, 4, 12))},
		{"team": "defense", "center": MapBuilder._v(Vector3(15, 2, -47.8)), "size": MapBuilder._v(Vector3(10, 4, 0.4))},
	]


func _b_back_and_long() -> void:
	# B Long dog-leg cover (keeps attacker B timing at ~18 s and breaks the long sightline).
	SolsticeKit.low_wall(mb, Vector3(25, 0, 40), 5.0, 0)
	SolsticeKit.crate(mb, Vector3(22, 0.6, 30), 1.2, 0)
	SolsticeKit.crate(mb, Vector3(22, 1.8, 30), 1.2, 30)
	SolsticeKit.market_stall(mb, Vector3(26.5, 0, 52), 270, "cloth_blue")
	SolsticeKit.sign_board(mb, map_root, "B Long", Vector3(20.05, 3.0, 50), Vector3(1, 0, 0))
	SolsticeKit.sign_board(mb, map_root, "B Back", Vector3(10.05, 3.0, -40), Vector3(1, 0, 0))
	# Close the old B Link alcove east (it becomes a post-plant pocket).
	mb.block("plaster_sand", Vector3(0.6, 5, 4.4), Vector3(56.2, 2.5, 2.0), 0, "stone", 0.05)


func _boundary() -> void:
	# Tall perimeter so nobody leaves the playable space (backs of buildings, never one-way).
	var r := BOUNDS
	for spec: Array in [[Vector3(r.position.x + r.size.x * 0.5, 6, r.position.y - 0.5), Vector3(r.size.x, 12, 1)], [Vector3(r.position.x + r.size.x * 0.5, 6, r.end.y + 0.5), Vector3(r.size.x, 12, 1)], [Vector3(r.position.x - 0.5, 6, r.position.y + r.size.y * 0.5), Vector3(1, 12, r.size.y)], [Vector3(r.end.x + 0.5, 6, r.position.y + r.size.y * 0.5), Vector3(1, 12, r.size.y)]]:
		mb.collider(spec[1], spec[0], 0, "stone")


func _markers() -> void:
	for w: Array in walk:
		if str(w[5]).begins_with("_"):
			continue
		mb.nav_rect(w[5], w[0], w[1], w[2], w[3])
		mb.callout(w[5], Vector3((w[0] + w[2]) * 0.5, 2, (w[1] + w[3]) * 0.5), Vector3(w[2] - w[0], 4, w[3] - w[1]))
	for n: Array in NAV_EXTRA:
		mb.nav_rect(n[4], n[0], n[1], n[2], n[3])
	var eye := 1.62
	mb.bookmark("Attacker spawn", Vector3(0, eye, 84), Vector3(0, 2, 60))
	mb.bookmark("A Lobby", Vector3(-20, eye, 72), Vector3(-40, 2, 70))
	mb.bookmark("A Main push", Vector3(-38, eye, 30), Vector3(-38, 2, 0))
	mb.bookmark("A site from main", Vector3(-38, eye, 1), Vector3(-46, 2, -24))
	mb.bookmark("A containers", Vector3(-30, eye, -24), Vector3(-50, 3, -22))
	mb.bookmark("A quay crane", Vector3(-46, eye, -6), Vector3(-58, 12, -4))
	mb.bookmark("A Link", Vector3(-8, eye, -8), Vector3(-30, 2, -14))
	mb.bookmark("Mid stepped alley", Vector3(-5, eye, 50), Vector3(-5, 3, 10))
	mb.bookmark("Mid bridge", Vector3(-5, 1.2 + eye, 26), Vector3(-5, 4, 10))
	mb.bookmark("Mid top", Vector3(-5, eye, -40), Vector3(-5, 2, -10))
	mb.bookmark("Defender spawn", Vector3(0, eye, -58), Vector3(0, 2, -40))
	mb.bookmark("B Back", Vector3(15, eye, -46), Vector3(22, 2, -20))
	mb.bookmark("B Long", Vector3(24, eye, 60), Vector3(24, 2, 20))
	mb.bookmark("Bay vista", Vector3(-58, 4, 0), Vector3(-120, 10, -10))
