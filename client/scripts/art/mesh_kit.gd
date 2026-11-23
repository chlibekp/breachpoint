## MeshKit: procedural, bevelled mesh builders for BREACHPOINT's code-built art (DECISIONS.md:
## "art pipeline without Blender"). Every builder chamfers its edges (art bible §4.1) and writes
## vertex alpha = 0 on bevel faces so master shaders can paint worn, lighter edges.
## Vertex colour RGB is a free channel (tint for environment, mask channels for weapons).
## All sizes in metres (1 unit = 1 m).
class_name MeshKit
extends RefCounted

var st := SurfaceTool.new()
var color := Color(1, 1, 1, 1)
var uv2_flag := Vector2.ZERO  ## written to UV2 (weapon shader reads UV2.x as "metal part")
var _xf := Transform3D.IDENTITY
var _started := false


func _init() -> void:
	begin()


func begin() -> void:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_started = true


## Sets the transform applied to every vertex added after this call.
func set_transform(xf: Transform3D) -> MeshKit:
	_xf = xf
	return self


func reset_transform() -> MeshKit:
	_xf = Transform3D.IDENTITY
	return self


func with_color(c: Color) -> MeshKit:
	color = c
	return self


func commit(material: Material = null, existing: ArrayMesh = null) -> ArrayMesh:
	st.generate_tangents()
	if material != null:
		st.set_material(material)
	var mesh := st.commit(existing)
	begin()
	return mesh


# ------------------------------------------------------------------ primitives

func _vert(p: Vector3, n: Vector3, uv: Vector2, edge: bool) -> void:
	var c := color
	if edge:
		c.a = 0.0
	st.set_color(c)
	st.set_normal((_xf.basis.inverse().transposed() * n).normalized())
	st.set_uv(uv)
	st.set_uv2(uv2_flag)
	st.add_vertex(_xf * p)


func _planar_uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z)
	if a.x >= a.z:
		return Vector2(p.z * signf(n.x), -p.y)
	return Vector2(-p.x * signf(n.z), -p.y)


## Adds a triangle with a flat normal; fixes winding so the face points along `n`.
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3 = Vector3.ZERO, edge: bool = false) -> void:
	var fn := (b - a).cross(c - a)
	if n == Vector3.ZERO:
		n = fn.normalized()
	# Godot treats clockwise triangles (seen from the front) as front faces.
	if fn.dot(n) > 0.0:
		var t := b
		b = c
		c = t
	_vert(a, n, _planar_uv(a, n), edge)
	_vert(b, n, _planar_uv(b, n), edge)
	_vert(c, n, _planar_uv(c, n), edge)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3 = Vector3.ZERO, edge: bool = false) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	tri(a, b, c, n, edge)
	tri(a, c, d, n, edge)


## Smooth-shaded triangle with per-vertex normals (n are outward normals).
func tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, edge: bool = false) -> void:
	var fn := (b - a).cross(c - a)
	if fn.dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	_vert(a, na, _planar_uv(a, na), edge)
	_vert(b, nb, _planar_uv(b, nb), edge)
	_vert(c, nc, _planar_uv(c, nc), edge)


# ------------------------------------------------------------------ shapes

## Chamfered box centred at `center`. bevel is clamped to half the smallest dimension.
func box(size: Vector3, center: Vector3 = Vector3.ZERO, bevel: float = 0.03) -> MeshKit:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	var i := h - Vector3(b, b, b)
	var o := center
	if b <= 0.0005:
		for axis: int in 3:
			for s: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = h[(axis + 1) % 3]
				var v := Vector3.ZERO
				v[(axis + 2) % 3] = h[(axis + 2) % 3]
				var c := o + n * h[axis]
				quad(c - u - v, c + u - v, c + u + v, c - u + v, n)
		return self
	# 6 faces
	for axis: int in 3:
		for s: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			var u := Vector3.ZERO
			u[a1] = i[a1]
			var v := Vector3.ZERO
			v[a2] = i[a2]
			var c := o + n * h[axis]
			quad(c - u - v, c + u - v, c + u + v, c - u + v, n)
	# 12 edges
	for axis: int in 3:  # axis along which the edge runs
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				var p1 := Vector3.ZERO
				p1[a1] = s1 * h[a1]
				p1[a2] = s2 * i[a2]
				var p2 := Vector3.ZERO
				p2[a1] = s1 * i[a1]
				p2[a2] = s2 * h[a2]
				var run := Vector3.ZERO
				run[axis] = i[axis]
				var n := Vector3.ZERO
				n[a1] = s1
				n[a2] = s2
				quad(o + p1 - run, o + p1 + run, o + p2 + run, o + p2 - run, n.normalized(), true)
	# 8 corners
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				tri(o + Vector3(sx * h.x, sy * i.y, sz * i.z), o + Vector3(sx * i.x, sy * h.y, sz * i.z), o + Vector3(sx * i.x, sy * i.y, sz * h.z), n, true)
	return self


## Lathe: rotates a 2D profile (x = radius, y = height) around +Y. Smooth around, faceted along
## the profile unless `smooth_profile`. Profile points flagged as edges via `edge_points`.
func lathe(profile: PackedVector2Array, segments: int = 16, center: Vector3 = Vector3.ZERO, _smooth_profile: bool = false, cap_top: bool = true, cap_bottom: bool = true) -> MeshKit:
	var n_prof := profile.size()
	for k: int in n_prof - 1:
		var p0 := profile[k]
		var p1 := profile[k + 1]
		var d := (p1 - p0).normalized()
		var pn := Vector2(d.y, -d.x)  # outward in profile space for an upward profile
		var steep := absf(d.y) > 0.6
		for s: int in segments:
			var a0 := TAU * s / segments
			var a1 := TAU * (s + 1) / segments
			var dir0 := Vector3(cos(a0), 0, sin(a0))
			var dir1 := Vector3(cos(a1), 0, sin(a1))
			var v00 := center + dir0 * p0.x + Vector3.UP * p0.y
			var v01 := center + dir1 * p0.x + Vector3.UP * p0.y
			var v10 := center + dir0 * p1.x + Vector3.UP * p1.y
			var v11 := center + dir1 * p1.x + Vector3.UP * p1.y
			var n0 := (dir0 * pn.x + Vector3.UP * pn.y).normalized()
			var n1 := (dir1 * pn.x + Vector3.UP * pn.y).normalized()
			var is_edge := not steep and absf(d.y) > 0.05
			tri_smooth(v00, v10, v11, n0, n0, n1, is_edge)
			tri_smooth(v00, v11, v01, n0, n1, n1, is_edge)
	if cap_bottom and profile[0].x > 0.001:
		_disc(center + Vector3.UP * profile[0].y, profile[0].x, segments, Vector3.DOWN)
	if cap_top and profile[n_prof - 1].x > 0.001:
		_disc(center + Vector3.UP * profile[n_prof - 1].y, profile[n_prof - 1].x, segments, Vector3.UP)
	return self


func _disc(c: Vector3, r: float, segments: int, n: Vector3) -> void:
	for s: int in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		tri(c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, n)


## Chamfered cylinder along +Y.
func cylinder(radius: float, height: float, center: Vector3 = Vector3.ZERO, segments: int = 16, bevel: float = 0.01) -> MeshKit:
	var b := minf(bevel, minf(radius * 0.4, height * 0.4))
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var prof := PackedVector2Array([Vector2(radius - b, y0), Vector2(radius, y0 + b), Vector2(radius, y1 - b), Vector2(radius - b, y1)])
	return lathe(prof, segments, center)


## Extrudes a simple 2D polygon (XY plane, counter-clockwise) along Z with chamfered rims.
func extrude(poly: PackedVector2Array, depth: float, center: Vector3 = Vector3.ZERO, bevel: float = 0.004) -> MeshKit:
	var n := poly.size()
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var inset := _inset_polygon(poly, bevel)
	var hz := depth * 0.5
	var bz := minf(bevel, hz * 0.9)
	var tris := Geometry2D.triangulate_polygon(inset)
	for zs: float in [1.0, -1.0]:
		var z := zs * hz
		for t: int in range(0, tris.size(), 3):
			var a := inset[tris[t]]
			var b := inset[tris[t + 1]]
			var c := inset[tris[t + 2]]
			tri(center + Vector3(a.x, a.y, z), center + Vector3(b.x, b.y, z), center + Vector3(c.x, c.y, z), Vector3(0, 0, zs))
	for k: int in n:
		var p0 := poly[k]
		var p1 := poly[(k + 1) % n]
		var i0 := inset[k]
		var i1 := inset[(k + 1) % n]
		var d := (p1 - p0).normalized()
		var side_n := Vector3(d.y, -d.x, 0)
		var zi := hz - bz
		quad(center + Vector3(p0.x, p0.y, -zi), center + Vector3(p1.x, p1.y, -zi), center + Vector3(p1.x, p1.y, zi), center + Vector3(p0.x, p0.y, zi), side_n)
		for zs: float in [1.0, -1.0]:
			var cn := (side_n + Vector3(0, 0, zs)).normalized()
			quad(center + Vector3(p0.x, p0.y, zs * zi), center + Vector3(p1.x, p1.y, zs * zi), center + Vector3(i1.x, i1.y, zs * hz), center + Vector3(i0.x, i0.y, zs * hz), cn, true)
	return self


static func _inset_polygon(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(n)
	for k: int in n:
		var prev := poly[(k - 1 + n) % n]
		var cur := poly[k]
		var nxt := poly[(k + 1) % n]
		var e0 := (cur - prev).normalized()
		var e1 := (nxt - cur).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var bis := (n0 + n1)
		if bis.length() < 0.001:
			bis = n0
		bis = bis.normalized()
		var miter := d / maxf(0.3, bis.dot(n0))
		out[k] = cur + bis * miter
	return out


## Semicircular arch of chamfered voussoir blocks in the XY plane (span along X, depth along Z).
func arch(span: float, thickness: float, depth: float, base_center: Vector3, blocks: int = 9, bevel: float = 0.025) -> MeshKit:
	var r_in := span * 0.5
	var r_mid := r_in + thickness * 0.5
	var saved := _xf
	for k: int in blocks:
		var a := PI * (k + 0.5) / blocks
		var chord := 2.0 * r_mid * sin(PI / blocks * 0.5) - 0.01
		var pos := base_center + Vector3(cos(a) * r_mid, sin(a) * r_mid, 0)
		var basis := Basis(Vector3.BACK, a - PI * 0.5)
		_xf = saved * Transform3D(basis, pos)
		box(Vector3(chord, thickness, depth), Vector3.ZERO, bevel)
	_xf = saved
	return self


## Rounded "pill" (lathed hemispheres + body) along +Y, used for limbs.
func capsule(radius_bottom: float, radius_top: float, length: float, center: Vector3 = Vector3.ZERO, segments: int = 12, rings: int = 4) -> MeshKit:
	var prof := PackedVector2Array()
	var y0 := -length * 0.5
	var y1 := length * 0.5
	for k: int in rings + 1:
		var a := -PI * 0.5 + PI * 0.5 * k / rings
		prof.append(Vector2(cos(a) * radius_bottom, y0 + radius_bottom + sin(a) * radius_bottom))
	for k: int in rings + 1:
		var a := PI * 0.5 * k / rings
		prof.append(Vector2(cos(a) * radius_top, y1 - radius_top + sin(a) * radius_top))
	return lathe(prof, segments, center, true, false, false)


## Squashed sphere (ellipsoid), for heads/hair clumps/pouches.
func ellipsoid(radii: Vector3, center: Vector3 = Vector3.ZERO, segments: int = 14, rings: int = 8) -> MeshKit:
	var saved := _xf
	_xf = saved * Transform3D(Basis.from_scale(radii), center)
	var prof := PackedVector2Array()
	for k: int in rings + 1:
		var a := -PI * 0.5 + PI * k / rings
		prof.append(Vector2(cos(a), sin(a)))
	lathe(prof, segments, Vector3.ZERO, true, false, false)
	_xf = saved
	return self


# ------------------------------------------------------------------ helpers

## Builds a MeshInstance3D with collision box(es) helper for static kit pieces.
static func instance(mesh: Mesh, name: String, pos: Vector3 = Vector3.ZERO, rot_y_deg: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.y = rot_y_deg
	return mi


## Adds lightmap UV2 to a static mesh (editor builds only; xatlas). texel_size in metres per texel.
static func unwrap_for_lightmap(mesh: ArrayMesh, texel_size: float = 0.1) -> ArrayMesh:
	var err := mesh.lightmap_unwrap(Transform3D.IDENTITY, texel_size)
	if err != OK:
		push_warning("lightmap_unwrap failed: %s" % error_string(err))
	return mesh
