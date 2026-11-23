## Client-side ability visuals and feedback (spec §9.4, §11). The server owns every effect; this
## renders AbilityEvent messages: smokes are opaque layered domes, walls have visible thickness, the
## edge of every effect glows ally cyan or enemy red (team readability always wins), and the local
## player gets blind / near-sight / blackout / detain screen effects. Barriers are also added to the
## client SimWorld so prediction collides with them exactly like the server.
class_name AbilityFx
extends Node3D

const EVENT_SPAWN := 1
const EVENT_END := 2
const EVENT_BLIND := 3
const EVENT_REVEAL := 4
const EVENT_HEAL := 5
const EVENT_MOVE := 6
const EVENT_PULSE := 7
const EVENT_DAMAGE := 8
const EVENT_BLACKOUT := 9
const EVENT_NEARSIGHT := 10
const EVENT_DETAIN := 11

## Element per ability (drives the generic cast/impact sounds until bespoke ones land).
const ELEMENT: Dictionary = {
	"updraft": "dash", "flare_round": "flash", "slipstream": "dash", "talon_barrage": "dash",
	"burnout": "fire", "afterimage": "flash", "gearshift": "dash", "redline": "fire",
	"eclipse_veil": "rift", "nebula_mine": "trap", "starfall": "smoke", "gravity_well": "rift",
	"vent": "smoke", "basalt_pillar": "trap", "geyser_smoke": "smoke", "eruption": "fire",
	"hawk": "scan", "dust_burst": "flash", "echo_arrow": "scan", "apex_hunt": "scan",
	"tripwire_trace": "trap", "static": "scan", "ping": "scan", "blackout": "rift",
	"barricade": "trap", "mend": "heal", "lattice": "trap", "second_wind": "heal",
	"proximity_charge": "trap", "sentry_drill": "trap", "alarm_spike": "scan", "lockdown": "rift",
}

var session: Node  ## NetSession (my_team, remotes, roster, world, player, hud)
var effects: Dictionary = {}  ## effect id -> Node3D
var barrier_boxes: Dictionary = {}  ## effect id -> SimWorld box index
var _overlay: ColorRect
var _overlay_layer: CanvasLayer
var _blind_t := 0.0
var _blind_total := 1.0
var _near_t := 0.0
var detained_t := 0.0
var blackout_t := 0.0


func _ready() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 30
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(1, 1, 1, 0)
	_overlay_layer.add_child(_overlay)


func handle(msg: Dictionary) -> void:
	var data: Dictionary = {}
	var raw: PackedByteArray = msg["data"]
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		data = parsed
	var ability: String = msg["ability"]
	var pos: Vector3 = msg["pos"]
	var caster := int(msg["casterId"])
	match int(msg["event"]):
		EVENT_SPAWN:
			_spawn(int(data.get("eid", 0)), ability, caster, pos, data)
			Sfx.play_3d("abilities", "%s_cast" % ELEMENT.get(ability, "rift"), pos, 0.0 if _is_enemy(caster) else -3.0, "Abilities", 60.0)
		EVENT_END:
			_end(int(data.get("eid", data.get("id", 0))))
		EVENT_PULSE:
			_pulse(ability, caster, pos, data)
		EVENT_REVEAL:
			var target := int(data.get("target", -1))
			var rp: RemotePlayer = session.get("remotes").get(target)
			if rp != null:
				rp.reveal(float(data.get("dur", 1.5)))
		EVENT_MOVE:
			var eid := int(data.get("eid", 0))
			if effects.has(eid):
				(effects[eid] as Node3D).position = pos
			elif str(data.get("kind", "")) in ["dash", "updraft", "sprint"]:
				_ring(pos + Vector3(0, 0.1, 0), 1.6, _agent_color(caster), 0.35)
				Sfx.play_3d("abilities", "dash_cast", pos, -2.0, "Abilities", 40.0)
		EVENT_HEAL:
			_ring(pos + Vector3(0, 0.1, 0), 1.2, Color("#7CF29A"), 0.8)
			Sfx.play_3d("abilities", "heal_impact", pos, -2.0, "Abilities", 40.0)
		EVENT_DAMAGE:
			if effects.has(int(data.get("from", -1))):
				var from := (effects[int(data["from"])] as Node3D).global_position + Vector3(0, 0.6, 0)
				(session.get("effects") as Effects).tracer(from, pos, Color(1.0, 0.6, 0.25))
		EVENT_BLIND:
			_blind_total = maxf(0.3, float(data.get("dur", 1.5)))
			_blind_t = _blind_total
			Sfx.play_2d("abilities", "flash_impact", -2.0, "Abilities")
		EVENT_NEARSIGHT:
			_near_t = float(data.get("dur", 2.5))
		EVENT_BLACKOUT:
			blackout_t = float(data.get("dur", 8.0))
			(session.get("hud") as Hud).message("BLACKOUT — SYSTEMS OFFLINE", 2.0)
		EVENT_DETAIN:
			detained_t = float(data.get("dur", 8.0))
			(session.get("hud") as Hud).message("DETAINED", 2.0)


func _is_enemy(caster: int) -> bool:
	var my_team: int = session.get("my_team")
	if caster == int(session.get("my_id")):
		return false
	var roster: Dictionary = session.get("roster")
	return int(roster.get(caster, {}).get("team", 1 - my_team)) != my_team


func _team_edge(caster: int) -> Color:
	var colors: Dictionary = Settings.team_colors()
	return colors["enemy"] if _is_enemy(caster) else colors["ally"]


func _agent_color(caster: int) -> Color:
	var roster: Dictionary = session.get("roster")
	var agent_id: String = str(roster.get(caster, {}).get("agent", "kestrel"))
	return Color(str(Data.get_agent(agent_id).get("signatureColor", "#8899AA")))


func _wall_mat(caster: int, alpha_cut: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/master/M_AbilityWall.gdshader")
	var c := _agent_color(caster)
	m.set_shader_parameter("body_color", c.lerp(Color(0.85, 0.85, 0.88), 0.45))
	m.set_shader_parameter("body_color_b", c.lerp(Color(0.25, 0.27, 0.32), 0.55))
	m.set_shader_parameter("team_color", _team_edge(caster))
	m.set_shader_parameter("alpha_cut", alpha_cut)
	return m


func _spawn(eid: int, ability: String, caster: int, pos: Vector3, data: Dictionary) -> void:
	var kind: String = data.get("kind", "")
	var r := float(data.get("r", 1.0))
	var node := Node3D.new()
	node.position = pos
	match kind:
		"smoke":
			# Opaque, volumetric-looking: three nested domes with a stepped noise shader (spec §9.4).
			for i: int in 3:
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				var rr := r * (1.0 - i * 0.07)
				sm.radius = rr
				sm.height = rr * (1.6 if data.has("column") else 1.75)
				sm.radial_segments = 32
				sm.rings = 16
				mi.mesh = sm
				mi.material_override = _wall_mat(caster)
				mi.position = Vector3(0, rr * 0.55 + (1.5 if data.has("column") else 0.0), 0)
				mi.rotation.y = i * 0.7
				node.add_child(mi)
		"wall":
			var k := MeshKit.new()
			var a := Vector3(0, 0, 0)
			var b := Vector3(float(data.get("x2", pos.x)) - pos.x, 0, float(data.get("z2", pos.z)) - pos.z)
			var h := float(data.get("h", 4.5))
			var curve := float(data.get("curve", 2.5))
			var side := Vector3(-b.z, 0, b.x).normalized()
			var segs := 16
			for i: int in segs:
				var t0 := float(i) / segs
				var t1 := float(i + 1) / segs
				var p0 := a.lerp(b, t0) + side * sin(t0 * PI) * curve
				var p1 := a.lerp(b, t1) + side * sin(t1 * PI) * curve
				var dir := p1 - p0
				k.set_transform(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), (p0 + p1) * 0.5 + Vector3(0, h * 0.5, 0)))
				k.box(Vector3(dir.length() + 0.08, h, 0.5), Vector3.ZERO, 0.1)
			k.reset_transform()
			var wall := MeshInstance3D.new()
			wall.mesh = k.commit(_wall_mat(caster))
			node.add_child(wall)
		"slow", "pull", "burn", "detain", "reveal_pulse":
			if kind == "pull":
				var sphere := MeshInstance3D.new()
				var sm2 := SphereMesh.new()
				sm2.radius = r
				sm2.height = r * 2
				sphere.mesh = sm2
				var rm := ShaderMaterial.new()
				rm.shader = load("res://shaders/master/M_RiftEnergy.gdshader")
				rm.set_shader_parameter("edge_color", _team_edge(caster))
				sphere.material_override = rm
				node.add_child(sphere)
			elif kind == "burn":
				var to := Vector3(float(data.get("x2", pos.x)), pos.y, float(data.get("z2", pos.z))) - pos
				var fire := CPUParticles3D.new()
				fire.amount = int(80 * float(QualityManager.tier.get("particleScale", 1.0)))
				fire.lifetime = 0.7
				fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				fire.emission_box_extents = Vector3(r, 0.05, to.length() * 0.5)
				fire.direction = Vector3.UP
				fire.initial_velocity_min = 1.0
				fire.initial_velocity_max = 2.5
				fire.gravity = Vector3(0, 1, 0)
				fire.color = Color("#FFB347")
				fire.position = to * 0.5
				fire.rotation.y = atan2(to.x, to.z)
				var fq := QuadMesh.new()
				fq.size = Vector2(0.35, 0.5)
				var fm := StandardMaterial3D.new()
				fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
				fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				fm.vertex_color_use_as_albedo = true
				fm.albedo_texture = load("res://assets/vfx/T_SmokePuff.png")
				fq.material = fm
				fire.mesh = fq
				node.add_child(fire)
			elif kind != "reveal_pulse":
				var line := data.has("line") and float(data["line"]) > 0.0
				if line:
					var to2 := Vector3(float(data.get("x2", pos.x)), pos.y, float(data.get("z2", pos.z))) - pos
					var beam := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(0.03, 0.03, to2.length())
					beam.mesh = bm
					beam.material_override = _glow(_team_edge(caster), 2.0)
					beam.position = to2 * 0.5 + Vector3(0, 0.5, 0)
					beam.rotation.y = atan2(to2.x, to2.z)
					node.add_child(beam)
				else:
					node.add_child(_disc(r, _agent_color(caster), _team_edge(caster), kind == "detain"))
		"barrier":
			var w := float(data.get("w", 2.0))
			var h2 := float(data.get("h", 2.0))
			var d := float(data.get("d", 0.5))
			var yaw := float(data.get("yaw", 0.0))
			var mk := MeshKit.new()
			mk.box(Vector3(w, h2, d), Vector3(0, h2 * 0.5, 0), 0.08)
			var bmi := MeshInstance3D.new()
			bmi.mesh = mk.commit(_wall_mat(caster))
			bmi.rotation.y = yaw
			node.add_child(bmi)
			var world: SimWorld = session.get("world")
			if world != null:
				world.add_box(pos.x, h2 * 0.5, pos.z, w * 0.5, h2 * 0.5, d * 0.5, yaw, 0)
				barrier_boxes[eid] = world.count() - 1
			# Deploy animation: grows out of the ground.
			bmi.scale = Vector3(1, 0.05, 1)
			create_tween().tween_property(bmi, "scale", Vector3.ONE, float(data.get("deploy", 0.5)))
		"sensor", "turret", "tether":
			var dev := MeshKit.new()
			dev.with_color(Color(1, 0, 0))
			dev.cylinder(0.16, 0.18 if kind != "turret" else 0.5, Vector3(0, 0.12 if kind != "turret" else 0.3, 0), 10, 0.03)
			dev.with_color(Color(0, 0, 1))
			dev.cylinder(0.07, 0.06, Vector3(0, 0.24 if kind != "turret" else 0.58, 0), 10, 0.01)
			if kind == "turret":
				dev.with_color(Color(1, 0, 0))
				dev.box(Vector3(0.1, 0.1, 0.45), Vector3(0, 0.5, -0.25), 0.02)
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/master/M_Weapon.gdshader")
			mat.set_shader_parameter("emissive_color", _team_edge(caster))
			mat.set_shader_parameter("emissive_energy", 2.5)
			var dmi := MeshInstance3D.new()
			dmi.mesh = dev.commit(mat)
			node.add_child(dmi)
		"decoy":
			var roster: Dictionary = session.get("roster")
			var rig := AgentLooks.build(str(roster.get(caster, {}).get("agent", "mamba")))
			rig.set_rim(_team_edge(caster), 1.5)
			node.add_child(rig)
			var anim := AgentAnimator.new()
			anim.setup(rig)
			anim.velocity_local = Vector3(0, 0, -6.75)
			rig.add_child(anim)
			rig.rotation.y = atan2(-float(data.get("vx", 0.0)), -float(data.get("vz", -1.0)))
			node.set_meta("vel", Vector3(float(data.get("vx", 0.0)), 0, float(data.get("vz", 0.0))))
		"hawk":
			var bird := MeshKit.new()
			bird.ellipsoid(Vector3(0.12, 0.08, 0.22), Vector3.ZERO, 10, 6)
			bird.box(Vector3(0.9, 0.03, 0.18), Vector3(0, 0.02, 0.02), 0.01)
			var hm := MeshInstance3D.new()
			hm.mesh = bird.commit(_glow(Color("#C8913A"), 0.4))
			node.add_child(hm)
			node.set_meta("vel", Vector3(float(data.get("vx", 0.0)), 0, float(data.get("vz", 0.0))))
		"flash":
			var spark := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.12
			s.height = 0.24
			spark.mesh = s
			spark.material_override = _glow(Color(1.0, 0.95, 0.8), 4.0)
			node.add_child(spark)
		"heal":
			node.add_child(_disc(r, Color("#7CF29A"), _team_edge(caster), false))
		_:
			pass
	add_child(node)
	effects[eid] = node
	node.set_meta("ability", ability)


func _disc(r: float, body: Color, edge: Color, dome: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if dome:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r
		sm.is_hemisphere = true
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(edge, 0.12)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		return mi
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.04
	cm.radial_segments = 40
	mi.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(body.lerp(edge, 0.4), 0.35)
	mi.material_override = dm
	mi.position.y = 0.03
	return mi


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _ring(pos: Vector3, r: float, c: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.92
	tm.outer_radius = r
	mi.mesh = tm
	mi.material_override = _glow(c, 2.5)
	mi.position = pos
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.6, life)
	tw.tween_callback(mi.queue_free)


func _pulse(ability: String, caster: int, pos: Vector3, data: Dictionary) -> void:
	var kind: String = str(data.get("kind", ""))
	match kind:
		"flash":
			_ring(pos, 0.8, Color(1, 0.97, 0.85), 0.25)
			Sfx.play_3d("abilities", "flash_impact", pos, 2.0, "Abilities", 60.0)
		"eruption", "explode":
			(session.get("effects") as Effects).impact(pos, Vector3.UP, "concrete")
			_ring(pos + Vector3(0, 0.1, 0), float(data.get("r", 3.0)), Color("#FF8A3A"), 0.4)
			Sfx.play_3d("abilities", "fire_impact", pos, 4.0, "Abilities", 80.0)
		"detain":
			_ring(pos + Vector3(0, 0.2, 0), float(data.get("r", 30.0)), _team_edge(caster), 0.6)
		_:
			var rr := minf(float(data.get("r", 10.0)), 40.0)
			_ring(pos + Vector3(0, 0.3, 0), rr * 0.25, _team_edge(caster), 0.6)
			Sfx.play_3d("abilities", "%s_impact" % ELEMENT.get(ability, "scan"), pos, 0.0, "Abilities", 60.0)


func _end(eid: int) -> void:
	if effects.has(eid):
		var n: Node3D = effects[eid]
		effects.erase(eid)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3(1, 0.02, 1), 0.25)
		tw.tween_callback(n.queue_free)
	if barrier_boxes.has(eid):
		var world: SimWorld = session.get("world")
		var i: int = barrier_boxes[eid]
		if world != null and i < world.count():
			world.hx[i] = 0.0
			world.hy[i] = 0.0
			world.hz[i] = 0.0
			world.cy[i] = -1000.0
		barrier_boxes.erase(eid)


func _process(delta: float) -> void:
	for eid: int in effects:
		var n: Node3D = effects[eid]
		if n.has_meta("vel"):
			n.position += (n.get_meta("vel") as Vector3) * delta
	_blind_t = maxf(0.0, _blind_t - delta)
	_near_t = maxf(0.0, _near_t - delta)
	detained_t = maxf(0.0, detained_t - delta)
	blackout_t = maxf(0.0, blackout_t - delta)
	# Blind: full white that holds, then fades (readable, not a soft haze).
	var blind_a := clampf(_blind_t / maxf(0.25, _blind_total * 0.4), 0.0, 1.0)
	var near_a := clampf(_near_t, 0.0, 1.0) * 0.82
	if blind_a > near_a:
		_overlay.color = Color(1, 1, 1, blind_a)
	else:
		_overlay.color = Color(0.05, 0.06, 0.1, near_a)
