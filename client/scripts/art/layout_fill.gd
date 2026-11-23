## LayoutFill: turns a list of walkable rectangles into a map footprint. Every 2 m cell inside the
## bounds that is neither walkable nor reserved becomes building mass; masses are merged greedily
## into blocks (max 7x7 cells) and handed to a `build(min_xz, max_xz, faces: PackedStringArray,
## rng)` callable, where `faces` lists the facades ("n","s","e","w") that look onto walkable space.
class_name LayoutFill
extends RefCounted

const CELL := 2.0

var bounds: Rect2
var walk: Array  ## [x0, z0, x1, z1, floor_y, name]
var reserved: Array  ## [x0, z0, x1, z1]
var _grid := PackedByteArray()
var _nx := 0
var _nz := 0


func _init(p_bounds: Rect2, p_walk: Array, p_reserved: Array = []) -> void:
	bounds = p_bounds
	walk = p_walk
	reserved = p_reserved
	_nx = int(bounds.size.x / CELL)
	_nz = int(bounds.size.y / CELL)
	_grid.resize(_nx * _nz)
	for iz: int in _nz:
		for ix: int in _nx:
			var c := cell_rect(ix, iz).get_center()
			var v := 0
			for r: Array in reserved:
				if c.x > r[0] and c.x < r[2] and c.y > r[1] and c.y < r[3]:
					v = 2
			for w: Array in walk:
				if c.x > w[0] and c.x < w[2] and c.y > w[1] and c.y < w[3]:
					v = 1
			_grid[iz * _nx + ix] = v


func cell_rect(ix: int, iz: int) -> Rect2:
	return Rect2(bounds.position.x + ix * CELL, bounds.position.y + iz * CELL, CELL, CELL)


func at(ix: int, iz: int) -> int:
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return 3
	return _grid[iz * _nx + ix]


func fill(build: Callable, seed_value: int = 2040, max_cells: int = 7) -> void:
	var used := PackedByteArray()
	used.resize(_nx * _nz)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for iz: int in _nz:
		for ix: int in _nx:
			if at(ix, iz) != 0 or used[iz * _nx + ix] == 1:
				continue
			var w := 1
			while w < max_cells and at(ix + w, iz) == 0 and used[iz * _nx + ix + w] == 0:
				w += 1
			var d := 1
			var ok := true
			while d < max_cells and ok:
				for k: int in w:
					if at(ix + k, iz + d) != 0 or used[(iz + d) * _nx + ix + k] == 1:
						ok = false
						break
				if ok:
					d += 1
			for dz: int in d:
				for dx: int in w:
					used[(iz + dz) * _nx + ix + dx] = 1
			var r0 := cell_rect(ix, iz)
			var faces := PackedStringArray()
			if _row_has(ix, ix + w - 1, iz - 1):
				faces.append("n")
			if _row_has(ix, ix + w - 1, iz + d):
				faces.append("s")
			if _col_has(iz, iz + d - 1, ix - 1):
				faces.append("w")
			if _col_has(iz, iz + d - 1, ix + w):
				faces.append("e")
			build.call(Vector2(r0.position.x, r0.position.y), Vector2(r0.position.x + w * CELL, r0.position.y + d * CELL), faces, rng)


func _row_has(x0: int, x1: int, iz: int) -> bool:
	for ix: int in range(x0, x1 + 1):
		if at(ix, iz) == 1:
			return true
	return false


func _col_has(z0: int, z1: int, ix: int) -> bool:
	for iz: int in range(z0, z1 + 1):
		if at(ix, iz) == 1:
			return true
	return false
