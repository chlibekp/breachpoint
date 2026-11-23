## A remote player (other humans and bots) rendered with entity interpolation (spec §13.4):
## ~2 ticks behind the newest snapshot plus an adaptive jitter buffer. Drives the third-person rig.
class_name RemotePlayer
extends Node3D

const FLAG_GROUNDED := 1
const FLAG_ALIVE := 2
const FLAG_RELOADING := 4
const FLAG_FIRING := 8
const FLAG_PLANTING := 16
const FLAG_DEFUSING := 32
const FLAG_HAS_CHARGE := 64

var player_id: int = -1
var team: int = 0
var agent: String = "kestrel"
var display_name: String = ""
var rig: AgentRig
var anim: AgentAnimator
var weapon_index: int = -1
var buffer: Array = []  ## [{tick, pos, vel, yaw, pitch, flags, health}]
var alive := true
var health := 100
var yaw := 0.0
var pitch := 0.0
var crouch := 0.0
var last_seen_tick := 0
var _label: Label3D
var _charge_mesh: MeshInstance3D
var _reveal := 0.0
var ally := false


func setup(id: int, p_team: int, p_agent: String, p_name: String, is_ally: bool) -> void:
	player_id = id
	team = p_team
	agent = p_agent
	display_name = p_name
	ally = is_ally
	rig = AgentLooks.build(agent)
	add_child(rig)
	anim = AgentAnimator.new()
	anim.setup(rig)
	rig.add_child(anim)
	# Allies get a subtle cyan rim + name; enemies only get the red outline when revealed (spec §4.4).
	var colors: Dictionary = Settings.team_colors()
	rig.set_rim(colors["ally"] if ally else Color(1, 0.95, 0.88), 0.45 if ally else 0.3)
	_label = Label3D.new()
	_label.text = p_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font = load("res://assets/fonts/ChakraPetch-SemiBold.ttf")
	_label.font_size = 36
	_label.pixel_size = 0.004
	_label.position = Vector3(0, 2.1, 0)
	_label.modulate = colors["ally"]
	_label.outline_size = 6
	_label.no_depth_test = ally
	_label.visible = ally
	add_child(_label)


func push(tick: int, st: Dictionary) -> void:
	last_seen_tick = tick
	if not buffer.is_empty() and int(buffer[buffer.size() - 1]["tick"]) >= tick:
		return
	buffer.append({"tick": tick, "pos": st["pos"], "vel": st["vel"], "yaw": float(st["yaw"]), "pitch": float(st["pitch"]), "flags": int(st["flags"]), "health": int(st["health"]), "weapon": int(st["weapon"])})
	if buffer.size() > 32:
		buffer.pop_front()


## Samples the interpolation buffer at a fractional server tick.
func render_at(render_tick: float, weapon_ids: Array) -> void:
	if buffer.is_empty():
		visible = false
		return
	var a: Dictionary = buffer[0]
	var b: Dictionary = a
	for i: int in buffer.size():
		var e: Dictionary = buffer[i]
		if float(e["tick"]) <= render_tick:
			a = e
			b = buffer[mini(i + 1, buffer.size() - 1)]
	var span := float(int(b["tick"]) - int(a["tick"]))
	var t := clampf((render_tick - float(a["tick"])) / span, 0.0, 1.0) if span > 0.0 else 0.0
	if render_tick > float(b["tick"]):
		# Short extrapolation (max 2 ticks) to hide a late packet.
		var extra := minf(render_tick - float(b["tick"]), 2.0) / 64.0
		position = (b["pos"] as Vector3) + (b["vel"] as Vector3) * extra
	else:
		position = (a["pos"] as Vector3).lerp(b["pos"], t)
	yaw = lerp_angle(float(a["yaw"]), float(b["yaw"]), t)
	pitch = lerpf(float(a["pitch"]), float(b["pitch"]), t)
	var flags := int(b["flags"])
	alive = (flags & FLAG_ALIVE) != 0
	health = int(b["health"])
	crouch = float((flags >> 8) & 0xFF) / 255.0
	visible = true
	rig.rotation.y = yaw
	anim.aim_pitch = pitch
	anim.crouch = crouch
	anim.airborne = (flags & FLAG_GROUNDED) == 0
	anim.velocity_local = rig.global_basis.inverse() * (b["vel"] as Vector3)
	anim.dead = not alive
	if alive and anim.dead == false and anim.weapon == null:
		pass
	var widx := int(b["weapon"])
	if widx != weapon_index and widx >= 0 and widx < weapon_ids.size():
		weapon_index = widx
		var wid: String = weapon_ids[widx]
		anim.attach_weapon(WeaponBuilder.build(wid))
		var cls: String = Data.get_weapon(wid).get("class", "rifle")
		anim.weapon_class = cls
	if (flags & FLAG_HAS_CHARGE) != 0 and _charge_mesh == null:
		_charge_mesh = ChargeModel.build()
		_charge_mesh.scale = Vector3.ONE * 0.6
		_charge_mesh.position = Vector3(0, 1.25, 0.2)
		rig.bones["chest"].add_child(_charge_mesh)
	elif (flags & FLAG_HAS_CHARGE) == 0 and _charge_mesh != null:
		_charge_mesh.queue_free()
		_charge_mesh = null


func reveal(seconds: float) -> void:
	_reveal = maxf(_reveal, seconds)


func _process(delta: float) -> void:
	_reveal = maxf(0.0, _reveal - delta)
	if rig != null and not ally:
		rig.set_reveal(clampf(_reveal * 2.0, 0.0, 1.0))


func muzzle_position() -> Vector3:
	if anim != null and anim.weapon != null:
		var m := anim.weapon.get_node_or_null("muzzle") as Node3D
		if m != null:
			return m.global_position
	return global_position + Vector3(0, 1.45, 0)
