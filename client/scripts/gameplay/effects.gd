## Pooled combat effects (spec §7.3, §9.4): stylised muzzle flash flipbook + short light (desktop),
## tracers, per-surface impacts (decal + sparks/dust), shell casings with a landing tink.
## No allocations in the hot loop: every effect is drawn from a fixed-size ring pool.
class_name Effects
extends Node3D

const POOL_TRACERS := 48
const POOL_IMPACTS := 96
const POOL_SHELLS := 32
const POOL_BURSTS := 24

var _tracers: Array[MeshInstance3D] = []
var _tracer_life: PackedFloat32Array
var _impacts: Array[MeshInstance3D] = []
var _shells: Array[MeshInstance3D] = []
var _shell_state: Array[Dictionary] = []
var _bursts: Array[CPUParticles3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_light: OmniLight3D
var _i_tracer := 0
var _i_impact := 0
var _i_shell := 0
var _i_burst := 0
var _decal_mats: Dictionary = {}
var _web := false
var world: SimWorld


func _ready() -> void:
	_web = RenderingServer.get_current_rendering_method() != "forward_plus"
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.albedo_color = Color(1.0, 0.82, 0.5, 0.9)
	tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
	tracer_mesh.material = tracer_mat
	_tracer_life.resize(POOL_TRACERS)
	for i: int in POOL_TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tracer_mesh
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	for kind: String in ["Concrete", "Metal", "Wood", "Glass"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/vfx/T_BulletHole_%s.png" % kind)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		_decal_mats[kind.to_lower()] = m
	for i: int in POOL_IMPACTS:
		var d := MeshInstance3D.new()
		d.mesh = quad
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		_impacts.append(d)
	# Shell casings: tiny brass cylinders.
	var k := MeshKit.new()
	k.cylinder(0.0045, 0.03, Vector3.ZERO, 8, 0.001)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#C9A04A")
	brass.metallic = 0.9
	brass.roughness = 0.35
	var shell_mesh := k.commit(brass)
	for i: int in POOL_SHELLS:
		var s := MeshInstance3D.new()
		s.mesh = shell_mesh
		s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		_shells.append(s)
		_shell_state.append({"v": Vector3.ZERO, "life": 0.0, "spin": Vector3.ZERO, "landed": false})
	for i: int in POOL_BURSTS:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.amount = 10
		p.lifetime = 0.35
		p.direction = Vector3(0, 0, 1)
		p.spread = 35.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		var pm := QuadMesh.new()
		pm.size = Vector2(0.05, 0.05)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.vertex_color_use_as_albedo = true
		mm.albedo_texture = load("res://assets/vfx/T_Dot.png")
		pm.material = mm
		p.mesh = pm
		add_child(p)
		_bursts.append(p)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.35)
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)


## Muzzle flash at a world transform (flipbook card facing the camera + short light on desktop).
func muzzle_flash(xf: Transform3D, scale_factor: float = 1.0, viewmodel_layer: bool = false) -> void:
	var flash := _flash_card()
	flash.global_transform = xf
	flash.scale = Vector3.ONE * scale_factor * randf_range(0.85, 1.15)
	flash.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	flash.layers = 2 if viewmodel_layer else 1
	var mat := flash.material_override as ShaderMaterial
	mat.set_shader_parameter("frame", float(randi() % 3))
	mat.set_shader_parameter("viewmodel", viewmodel_layer)
	flash.visible = true
	flash.set_meta("life", 0.05)
	if not _web:
		_flash_light.global_position = xf.origin
		_flash_light.light_energy = 2.5


func _flash_card() -> MeshInstance3D:
	for f: MeshInstance3D in _flashes:
		if not f.visible:
			return f
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vfx/muzzle_flash.gdshader")
	m.set_shader_parameter("flipbook", load("res://assets/vfx/T_MuzzleFlash_Flipbook.png"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_flashes.append(mi)
	return mi


## A bullet tracer from `from` to `to` (visible to everyone; team-tinted on spectate).
func tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.82, 0.5)) -> void:
	var t := _tracers[_i_tracer]
	_i_tracer = (_i_tracer + 1) % POOL_TRACERS
	var dir := to - from
	var length := dir.length()
	if length < 0.5:
		return
	var seg := minf(length, 6.0)
	t.visible = true
	t.scale = Vector3(1, 1, seg)
	t.global_position = from + dir.normalized() * seg * 0.5
	t.look_at(to, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
	(t.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(color, 0.9)
	t.set_meta("from", from)
	t.set_meta("to", to)
	t.set_meta("t", 0.0)
	t.set_meta("speed", 420.0)
	_tracer_life[_i_tracer] = 1.0


## Surface impact: decal + particle burst + sound.
func impact(pos: Vector3, normal: Vector3, kind: String) -> void:
	var mat_key: String = {"concrete": "concrete", "metal": "metal", "wood": "wood", "glass": "glass"}.get(kind, "concrete")
	if kind != "flesh" and kind != "none" and kind != "water" and kind != "sand":
		var d := _impacts[_i_impact]
		_i_impact = (_i_impact + 1) % POOL_IMPACTS
		d.material_override = _decal_mats[mat_key]
		d.visible = true
		var n := normal.normalized()
		d.global_position = pos + n * 0.006
		var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
		d.look_at(pos + n, up)
		d.rotate_object_local(Vector3.FORWARD, randf() * TAU)
		d.rotate_object_local(Vector3.UP, PI)
	var colors := {"concrete": Color(0.85, 0.8, 0.7), "metal": Color(1.0, 0.75, 0.35), "wood": Color(0.6, 0.45, 0.3), "glass": Color(0.8, 0.95, 1.0), "flesh": Color(0.75, 0.15, 0.15), "sand": Color(0.85, 0.75, 0.55), "water": Color(0.8, 0.95, 1.0)}
	_burst(pos, normal, colors.get(kind, Color(0.8, 0.8, 0.8)), 14 if kind == "metal" else 9)
	Sfx.play_3d("impacts", kind if kind != "none" else "concrete", pos, -4.0, "SFX")


func _burst(pos: Vector3, normal: Vector3, color: Color, amount: int) -> void:
	var p := _bursts[_i_burst]
	_i_burst = (_i_burst + 1) % POOL_BURSTS
	p.global_position = pos
	var n := normal.normalized()
	p.global_basis = Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD)
	p.color = color
	p.amount = maxi(2, int(amount * float(QualityManager.tier.get("particleScale", 1.0))))
	p.restart()


func eject_shell(xf: Transform3D, right: Vector3) -> void:
	var s := _shells[_i_shell]
	var st := _shell_state[_i_shell]
	_i_shell = (_i_shell + 1) % POOL_SHELLS
	s.global_transform = xf
	s.visible = true
	st["v"] = right * randf_range(1.6, 2.4) + Vector3.UP * randf_range(1.2, 1.8)
	st["spin"] = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	st["life"] = 1.6
	st["landed"] = false


func _process(delta: float) -> void:
	for i: int in POOL_TRACERS:
		var t := _tracers[i]
		if not t.visible:
			continue
		var from: Vector3 = t.get_meta("from")
		var to: Vector3 = t.get_meta("to")
		var total := from.distance_to(to)
		var prog: float = float(t.get_meta("t")) + delta * float(t.get_meta("speed"))
		t.set_meta("t", prog)
		if prog >= total:
			t.visible = false
			continue
		var dir := (to - from) / total
		var head := from + dir * minf(prog + t.scale.z * 0.5, total)
		t.global_position = head - dir * t.scale.z * 0.5
	for f: MeshInstance3D in _flashes:
		if f.visible:
			var life: float = float(f.get_meta("life")) - delta
			f.set_meta("life", life)
			if life <= 0.0:
				f.visible = false
	_flash_light.light_energy = move_toward(_flash_light.light_energy, 0.0, delta * 60.0)
	for i: int in POOL_SHELLS:
		var s := _shells[i]
		if not s.visible:
			continue
		var st := _shell_state[i]
		st["life"] = float(st["life"]) - delta
		if float(st["life"]) <= 0.0:
			s.visible = false
			continue
		if st["landed"]:
			continue
		var v: Vector3 = st["v"]
		v.y -= 9.8 * delta
		st["v"] = v
		s.global_position += v * delta
		s.rotation += (st["spin"] as Vector3) * delta
		if world != null:
			var g := SimMovement.ground_height(world, s.global_position.x, s.global_position.y + 0.2, s.global_position.z, 0.02)
			if s.global_position.y <= g + 0.005 and v.y < 0:
				s.global_position.y = g + 0.005
				st["landed"] = true
				Sfx.play_3d("weapons", "shell", s.global_position, -14.0, "Weapons")
