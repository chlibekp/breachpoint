## FormKit: organic, smooth-shaded builders for code-built characters, on top of MeshKit.
## - loft(): stacked superellipse rings along +Y (torsos, limbs, heads, boots, coats). Each ring
##   has its own centre, half-width, front/back depth, squareness and a shade (vertex-colour
##   darkening, used as painted ambient occlusion toward the feet and inside crevices).
## - tube(): a swept, tapered (optionally flattened) tube along a 3D polyline (hair clumps, straps,
##   cables, braids, fingers, collars). Frames are parallel-transported so tubes never twist.
## Smooth normals come from the ring grid, so the inverted-hull outline stays unbroken.
## The model faces -Z: ring "front" depth (zf) is on the -Z side, "back" depth (zb) on +Z.
class_name FormKit
extends MeshKit

## Ring layout (PackedFloat32Array): [y, rx, zf, zb, cx, cz, n, shade]
const R_Y := 0
const R_RX := 1
const R_ZF := 2
const R_ZB := 3
const R_CX := 4
const R_CZ := 5
const R_N := 6
const R_SHADE := 7


## One loft ring. zb < 0 means "same as zf". n = superellipse exponent (2 = ellipse, 3+ = boxier).
static func ring(y: float, rx: float, zf: float, zb: float = -1.0, cz: float = 0.0, n: float = 2.0, shade: float = 1.0, cx: float = 0.0) -> PackedFloat32Array:
	return PackedFloat32Array([y, rx, zf, zb if zb >= 0.0 else zf, cx, cz, n, shade])


static func _se(v: float, n: float) -> float:
	return signf(v) * pow(absf(v), 2.0 / n)


static func ring_point(r: PackedFloat32Array, a: float) -> Vector3:
	return _ring_point(r, a)


static func _ring_point(r: PackedFloat32Array, a: float) -> Vector3:
	var c := cos(a)
	var s := sin(a)
	var x := _se(c, r[R_N]) * r[R_RX]
	var zs := _se(s, r[R_N])
	var z := zs * (r[R_ZB] if zs > 0.0 else r[R_ZF])
	return Vector3(r[R_CX] + x, r[R_Y], r[R_CZ] + z)


## Front-surface z of a loft at (x, y): used to seat faces, buttons and decals on curved forms.
static func front_z(rings: Array, x: float, y: float) -> float:
	var r := _ring_at(rings, y)
	var u := clampf(absf(x - r[R_CX]) / maxf(r[R_RX], 0.0001), 0.0, 1.0)
	var n := r[R_N]
	return r[R_CZ] - r[R_ZF] * pow(maxf(0.0, 1.0 - pow(u, n)), 1.0 / n)


## Side-surface x (+X side) of a loft at (y, z offset 0).
static func side_x(rings: Array, y: float) -> float:
	var r := _ring_at(rings, y)
	return r[R_CX] + r[R_RX]


## Interpolated ring of a loft at height y.
static func at(rings: Array, y: float) -> PackedFloat32Array:
	return _ring_at(rings, y)


static func _ring_at(rings: Array, y: float) -> PackedFloat32Array:
	# Limb ring sets run top to bottom; sample them in ascending order.
	var r0: PackedFloat32Array = rings[0]
	var rn: PackedFloat32Array = rings[rings.size() - 1]
	if r0[R_Y] > rn[R_Y]:
		rings = rings.duplicate()
		rings.reverse()
	var lo: PackedFloat32Array = rings[0]
	var hi: PackedFloat32Array = rings[rings.size() - 1]
	if y <= lo[R_Y]:
		return lo
	if y >= hi[R_Y]:
		return hi
	for i: int in rings.size() - 1:
		var a: PackedFloat32Array = rings[i]
		var b: PackedFloat32Array = rings[i + 1]
		if y >= a[R_Y] and y <= b[R_Y]:
			var t := (y - a[R_Y]) / maxf(b[R_Y] - a[R_Y], 0.00001)
			var out := PackedFloat32Array()
			out.resize(8)
			for f: int in 8:
				out[f] = lerpf(a[f], b[f], t)
			return out
	return hi


## Smooth loft through `rings` (bottom to top). `segments` around; `sub` extra Catmull-Rom
## subdivisions between rings for smooth silhouettes. Caps: flat fans at open ends.
func loft(rings: Array, segments: int = 16, sub: int = 1, cap_bottom: bool = true, cap_top: bool = true) -> FormKit:
	var rs: Array = _subdivide(rings, sub)
	var nr := rs.size()
	var grid: Array[PackedVector3Array] = []
	var shades := PackedFloat32Array()
	for i: int in nr:
		var row := PackedVector3Array()
		var r: PackedFloat32Array = rs[i]
		for j: int in segments:
			row.append(_ring_point(r, TAU * j / segments + PI * 0.5))
		grid.append(row)
		shades.append(r[R_SHADE])
	var normals: Array[PackedVector3Array] = []
	for i: int in nr:
		var row_n := PackedVector3Array()
		var r: PackedFloat32Array = rs[i]
		var centre := Vector3(r[R_CX], r[R_Y], r[R_CZ])
		for j: int in segments:
			var gi: PackedVector3Array = grid[i]
			var gu: PackedVector3Array = grid[mini(i + 1, nr - 1)]
			var gd: PackedVector3Array = grid[maxi(i - 1, 0)]
			var p: Vector3 = gi[j]
			var around: Vector3 = gi[(j + 1) % segments] - gi[(j - 1 + segments) % segments]
			var up: Vector3 = gu[j] - gd[j]
			var n := around.cross(up)
			if n.length() < 1e-7 or around.length() < 1e-5:
				var axis := Vector3(0, 1, 0)
				if i == 0:
					axis = -axis
				n = axis
			n = n.normalized()
			if n.dot(p - centre) < 0.0 and around.length() >= 1e-5:
				n = -n
			row_n.append(n)
		normals.append(row_n)
	var base := color
	for i: int in nr - 1:
		var g0: PackedVector3Array = grid[i]
		var g1: PackedVector3Array = grid[i + 1]
		var n0: PackedVector3Array = normals[i]
		var n1: PackedVector3Array = normals[i + 1]
		for j: int in segments:
			var j1 := (j + 1) % segments
			_tri_s(g0[j], g1[j], g1[j1], n0[j], n1[j], n1[j1], shades[i], shades[i + 1], shades[i + 1], base)
			_tri_s(g0[j], g1[j1], g0[j1], n0[j], n1[j1], n0[j1], shades[i], shades[i + 1], shades[i], base)
	if cap_bottom:
		_cap(rs[0], grid[0], Vector3.DOWN, shades[0], base)
	if cap_top:
		_cap(rs[nr - 1], grid[nr - 1], Vector3.UP, shades[nr - 1], base)
	color = base
	return self


func _cap(r: PackedFloat32Array, row: PackedVector3Array, n: Vector3, shade: float, base: Color) -> void:
	if r[R_RX] < 0.003:
		return
	var c := Vector3(r[R_CX], r[R_Y], r[R_CZ])
	for j: int in row.size():
		_tri_s(c, row[j], row[(j + 1) % row.size()], n, n, n, shade, shade, shade, base)


## Catmull-Rom subdivision of ring parameters for smooth profiles.
static func _subdivide(rings: Array, sub: int) -> Array:
	if sub <= 0 or rings.size() < 2:
		return rings
	var out: Array = []
	var n := rings.size()
	for i: int in n - 1:
		var p0: PackedFloat32Array = rings[maxi(i - 1, 0)]
		var p1: PackedFloat32Array = rings[i]
		var p2: PackedFloat32Array = rings[i + 1]
		var p3: PackedFloat32Array = rings[mini(i + 2, n - 1)]
		out.append(p1)
		for s: int in range(1, sub + 1):
			var t := float(s) / (sub + 1)
			var r := PackedFloat32Array()
			r.resize(8)
			for f: int in 8:
				var v := 0.5 * ((2.0 * p1[f]) + (-p0[f] + p2[f]) * t + (2.0 * p0[f] - 5.0 * p1[f] + 4.0 * p2[f] - p3[f]) * t * t + (-p0[f] + 3.0 * p1[f] - 3.0 * p2[f] + p3[f]) * t * t * t)
				r[f] = v
			# Never let interpolation overshoot into negative radii.
			r[R_RX] = maxf(r[R_RX], 0.0)
			r[R_ZF] = maxf(r[R_ZF], 0.0)
			r[R_ZB] = maxf(r[R_ZB], 0.0)
			r[R_N] = maxf(r[R_N], 1.2)
			out.append(r)
	out.append(rings[n - 1])
	return out


## Swept tube along `pts` with per-point radius. `flat` < 1 squashes the cross-section along the
## binormal (hair clumps, straps). `up` orients the flat side. Ends are closed with small domes
## when `round_ends`, otherwise flat caps.
func tube(pts: PackedVector3Array, radii: PackedFloat32Array, segments: int = 8, flat: float = 1.0, up: Vector3 = Vector3.UP, round_ends: bool = true, shades: PackedFloat32Array = PackedFloat32Array()) -> FormKit:
	var n := pts.size()
	if n < 2:
		return self
	var tangents := PackedVector3Array()
	for i: int in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		tangents.append(t)
	var nrm := (up - tangents[0] * up.dot(tangents[0]))
	if nrm.length() < 0.01:
		nrm = Vector3.RIGHT - tangents[0] * tangents[0].x
	nrm = nrm.normalized()
	var rows: Array[PackedVector3Array] = []
	var nrows: Array[PackedVector3Array] = []
	for i: int in n:
		if i > 0:
			# Parallel transport the frame.
			var axis := tangents[i - 1].cross(tangents[i])
			if axis.length() > 1e-6:
				var ang := tangents[i - 1].angle_to(tangents[i])
				nrm = nrm.rotated(axis.normalized(), ang)
			nrm = (nrm - tangents[i] * nrm.dot(tangents[i])).normalized()
		var bin := tangents[i].cross(nrm).normalized()
		var row := PackedVector3Array()
		var row_n := PackedVector3Array()
		for j: int in segments:
			var a := TAU * j / segments
			var off := nrm * cos(a) * radii[i] * flat + bin * sin(a) * radii[i]
			row.append(pts[i] + off)
			row_n.append((nrm * cos(a) / maxf(flat, 0.05) + bin * sin(a)).normalized())
		rows.append(row)
		nrows.append(row_n)
	var base := color
	for i: int in n - 1:
		var s0 := shades[i] if i < shades.size() else 1.0
		var s1 := shades[i + 1] if i + 1 < shades.size() else 1.0
		var g0: PackedVector3Array = rows[i]
		var g1: PackedVector3Array = rows[i + 1]
		var m0: PackedVector3Array = nrows[i]
		var m1: PackedVector3Array = nrows[i + 1]
		for j: int in segments:
			var j1 := (j + 1) % segments
			_tri_s(g0[j], g1[j], g1[j1], m0[j], m1[j], m1[j1], s0, s1, s1, base)
			_tri_s(g0[j], g1[j1], g0[j1], m0[j], m1[j1], m0[j1], s0, s1, s0, base)
	for e: int in 2:
		var idx := 0 if e == 0 else n - 1
		var dir := -tangents[0] if e == 0 else tangents[n - 1]
		var row: PackedVector3Array = rows[idx]
		var row_n: PackedVector3Array = nrows[idx]
		var sh := (shades[idx] if idx < shades.size() else 1.0)
		var tip := pts[idx] + dir * (radii[idx] * (0.8 if round_ends else 0.0))
		for j: int in segments:
			var j1 := (j + 1) % segments
			if round_ends:
				_tri_s(tip, row[j], row[j1], dir, (row_n[j] + dir).normalized(), (row_n[j1] + dir).normalized(), sh, sh, sh, base)
			else:
				_tri_s(tip, row[j], row[j1], dir, dir, dir, sh, sh, sh, base)
	color = base
	return self


## Convenience: tube with linearly interpolated radius from r0 to r1.
func strand(pts: PackedVector3Array, r0: float, r1: float, segments: int = 7, flat: float = 1.0, up: Vector3 = Vector3.UP) -> FormKit:
	var radii := PackedFloat32Array()
	for i: int in pts.size():
		radii.append(lerpf(r0, r1, float(i) / maxf(1.0, pts.size() - 1.0)))
	return tube(pts, radii, segments, flat, up)


## Quadratic Bézier sampled into `count` points (for curved strands, straps and cables).
static func bezier(a: Vector3, ctrl: Vector3, b: Vector3, count: int = 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in count:
		var t := float(i) / (count - 1)
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out


## Cubic Bézier sampled into `count` points.
static func bezier3(a: Vector3, c1: Vector3, c2: Vector3, b: Vector3, count: int = 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in count:
		var t := float(i) / (count - 1)
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	return out


## Smooth triangle with per-vertex shade (vertex colour RGB multiplier, alpha 1 = no edge wear).
func _tri_s(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, sa: float, sb: float, sc: float, base: Color) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-14:
		return
	if fn.dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
		var ts := sb
		sb = sc
		sc = ts
	color = Color(base.r * sa, base.g * sa, base.b * sa, base.a)
	_vert(a, na, _planar_uv(a, na), false)
	color = Color(base.r * sb, base.g * sb, base.b * sb, base.a)
	_vert(b, nb, _planar_uv(b, nb), false)
	color = Color(base.r * sc, base.g * sc, base.b * sc, base.a)
	_vert(c, nc, _planar_uv(c, nc), false)
	color = base



## Point on a loft surface at height y and ring angle a (a = -PI/2 is straight ahead, -Z).
static func surface_point(rings: Array, y: float, a: float) -> Vector3:
	return _ring_point(_ring_at(rings, y), a)


## Triangulates a grid of rows (each a closed loop of the same length when `closed`), with smooth
## normals from the grid and outward orientation away from `inside`. Per-row shade.
func patch(rows: Array, inside: Vector3, shades: PackedFloat32Array = PackedFloat32Array(), closed: bool = true, flip: bool = false, centers: PackedVector3Array = PackedVector3Array()) -> FormKit:
	var nr := rows.size()
	var first: PackedVector3Array = rows[0]
	var nc := first.size()
	var normals: Array[PackedVector3Array] = []
	for i: int in nr:
		var row: PackedVector3Array = rows[i]
		var rn := PackedVector3Array()
		var ins := centers[i] if i < centers.size() else inside
		for j: int in nc:
			var jp := (j + 1) % nc if closed else mini(j + 1, nc - 1)
			var jm := (j - 1 + nc) % nc if closed else maxi(j - 1, 0)
			var around := row[jp] - row[jm]
			var ru: PackedVector3Array = rows[mini(i + 1, nr - 1)]
			var rd: PackedVector3Array = rows[maxi(i - 1, 0)]
			var up: Vector3 = ru[j] - rd[j]
			var n := around.cross(up)
			if n.length() < 1e-9:
				n = row[j] - ins
			n = n.normalized()
			if (n.dot(row[j] - ins) < 0.0) != flip:
				n = -n
			rn.append(n)
		normals.append(rn)
	var base := color
	var cols := nc if closed else nc - 1
	for i: int in nr - 1:
		var g0: PackedVector3Array = rows[i]
		var g1: PackedVector3Array = rows[i + 1]
		var n0: PackedVector3Array = normals[i]
		var n1: PackedVector3Array = normals[i + 1]
		var s0 := shades[i] if i < shades.size() else 1.0
		var s1 := shades[i + 1] if i + 1 < shades.size() else 1.0
		for j: int in cols:
			var j1 := (j + 1) % nc
			_tri_s(g0[j], g1[j], g1[j1], n0[j], n1[j], n1[j1], s0, s1, s1, base)
			_tri_s(g0[j], g1[j1], g0[j1], n0[j], n1[j1], n0[j1], s0, s1, s0, base)
	color = base
	return self


## Colour-block panel on a loft surface: the patch between heights y0..y1 and ring angles a0..a1
## (a = -PI/2 is the front, 0 is +X, PI/2 the back), lifted by `grow`. Edges are slightly sunk
## so the panel reads as a sewn-on piece rather than a floating sheet.
func panel(rings: Array, y0: float, y1: float, a0: float, a1: float, grow: float = 0.003, rows: int = 5, cols: int = 10) -> FormKit:
	var grid_rows: Array = []
	var mid := _ring_at(rings, (y0 + y1) * 0.5)
	var inside := Vector3(mid[R_CX], (y0 + y1) * 0.5, mid[R_CZ])
	for i: int in rows + 1:
		var y := lerpf(y0, y1, float(i) / rows)
		var r := _ring_at(rings, y)
		var row := PackedVector3Array()
		for j: int in cols + 1:
			var a := lerpf(a0, a1, float(j) / cols)
			var p := _ring_point(r, a)
			var c := Vector3(r[R_CX], y, r[R_CZ])
			var d := Vector3(p.x - c.x, 0, p.z - c.z).normalized()
			row.append(p + d * grow)
		grid_rows.append(row)
	return patch(grid_rows, inside, PackedFloat32Array(), false)


## Rings of `rings` between y0 and y1 (count samples), grown outward by `grow` (clothing layers,
## belts, cuffs and bands that hug an existing form).
static func slice(rings: Array, y0: float, y1: float, grow: float, count: int = 4, shade: float = -1.0) -> Array:
	var out: Array = []
	for i: int in count:
		var y := lerpf(y0, y1, float(i) / maxf(1.0, count - 1.0))
		var r := _ring_at(rings, y).duplicate()
		r[R_Y] = y
		r[R_RX] += grow
		r[R_ZF] += grow
		r[R_ZB] += grow
		if shade >= 0.0:
			r[R_SHADE] = shade
		out.append(r)
	return out


## Copy of `rings` with every radius grown and optional uniform scale (fit a shell over a form).
static func grown(rings: Array, grow: float, scale: float = 1.0) -> Array:
	var out: Array = []
	for r0: PackedFloat32Array in rings:
		var r := r0.duplicate()
		r[R_RX] = r[R_RX] * scale + grow
		r[R_ZF] = r[R_ZF] * scale + grow
		r[R_ZB] = r[R_ZB] * scale + grow
		out.append(r)
	return out
