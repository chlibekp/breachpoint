## Procedural first-person animation (spec §6.3, §7.3): weapon sway from mouse movement, inertia lag,
## walk/run bob, landing dip, strafe tilt (2–3°), a spring-damped recoil kick, ADS in/out, and clip
## choreography for draw, reload (tactical/empty, with the magazine node moving), inspect showcase.
## Every procedural layer is tunable/disableable through Settings ("gameplay" section).
class_name ViewmodelAnimator
extends RefCounted

var vm: Viewmodel
# Springs (position + rotation) for recoil and inertia.
var _kick_pos := Vector3.ZERO
var _kick_vel := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _kick_rot_vel := Vector3.ZERO
var _sway := Vector2.ZERO
var _bob_t := 0.0
var _land := 0.0
var _tilt := 0.0
var ads := 0.0
var clip := ""  ## "", "draw", "reload", "reload_empty", "inspect"
var clip_t := 0.0
var clip_len := 0.0
var _mag_rest := Vector3.ZERO
var _ch_rest := Vector3.ZERO


func _init(viewmodel: Viewmodel) -> void:
	vm = viewmodel


func on_equip(equip_time: float) -> void:
	_play("draw", minf(equip_time, 0.75))
	var mag := vm.weapon.get_node_or_null("magazine") as Node3D
	_mag_rest = mag.position if mag != null else Vector3.ZERO
	var ch := vm.weapon.get_node_or_null("charging_handle") as Node3D
	_ch_rest = ch.position if ch != null else Vector3.ZERO


func on_reload(reload_time: float, empty: bool) -> void:
	_play("reload_empty" if empty else "reload", reload_time)


func on_inspect() -> void:
	if clip == "":
		_play("inspect", 3.2)


func cancel_clip() -> void:
	clip = ""
	_reset_parts()


## Recoil kick: back + up with a spring return, scaled by calibre (weapons.json recoil.cameraPunch).
func on_fire(punch: float) -> void:
	_kick_vel += Vector3(randf_range(-0.02, 0.02), 0.05, 0.45) * punch
	_kick_rot_vel += Vector3(0.9 * punch, randf_range(-0.25, 0.25) * punch, randf_range(-0.3, 0.3) * punch) * 6.0
	if clip == "inspect":
		cancel_clip()


func on_land(strength: float) -> void:
	_land = minf(1.0, _land + strength)


func _play(clip_name: String, length: float) -> void:
	clip = clip_name
	clip_t = 0.0
	clip_len = maxf(0.05, length)


func _reset_parts() -> void:
	var mag := vm.weapon.get_node_or_null("magazine") as Node3D if vm.weapon != null else null
	if mag != null:
		mag.position = _mag_rest
		mag.rotation = Vector3.ZERO
		mag.visible = true
	var ch := vm.weapon.get_node_or_null("charging_handle") as Node3D if vm.weapon != null else null
	if ch != null:
		ch.position = _ch_rest


## mouse_delta in pixels this frame; vel_local = player velocity in view space; speed_frac 0..1.
func update(delta: float, mouse_delta: Vector2, vel_local: Vector3, grounded: bool, speed_frac: float, ads_target: bool) -> void:
	if vm.weapon == null:
		return
	var sway_on: bool = Settings.get_value("gameplay", "viewmodel_sway")
	var tilt_on: bool = Settings.get_value("gameplay", "strafe_tilt")
	ads = move_toward(ads, 1.0 if ads_target and clip == "" else 0.0, delta / 0.16)
	var ads_e := ease(ads, -2.0)
	# Sway + inertia lag from mouse movement (reduced while aiming).
	if sway_on:
		_sway = _sway.lerp(mouse_delta * 0.0009 * (1.0 - ads_e * 0.8), 1.0 - exp(-delta * 18.0))
	else:
		_sway = Vector2.ZERO
	# Bob.
	var bob_amt := clampf(speed_frac, 0.0, 1.0) * (1.0 if grounded else 0.0) * (1.0 - ads_e * 0.85)
	_bob_t += delta * (6.0 + 5.0 * speed_frac) * (1.0 if bob_amt > 0.05 else 0.0)
	var bob := Vector3(sin(_bob_t) * 0.006, -absf(cos(_bob_t)) * 0.008, 0) * bob_amt
	# Landing dip.
	_land = move_toward(_land, 0.0, delta * 4.0)
	var dip := Vector3(0, -0.03 * ease(_land, 0.5), 0)
	# Strafe tilt (2–3°).
	_tilt = lerpf(_tilt, -clampf(vel_local.x / 6.75, -1, 1) * deg_to_rad(2.5) if tilt_on else 0.0, 1.0 - exp(-delta * 10.0))
	# Recoil springs.
	var k := 220.0
	var c := 22.0
	_kick_vel += (-_kick_pos * k - _kick_vel * c) * delta
	_kick_pos += _kick_vel * delta
	_kick_rot_vel += (-_kick_rot * k - _kick_rot_vel * c) * delta
	_kick_rot += _kick_rot_vel * delta
	var base := Viewmodel.HIP_POSITION.lerp(Viewmodel.ADS_POSITION, ads_e)
	var pos := base + bob + dip + Vector3(-_sway.x, _sway.y, 0) * 0.6 + Vector3(_kick_pos.x, _kick_pos.y * 0.4, _kick_pos.z * 0.12)
	var rot := Vector3(-_sway.y * 1.5 + _kick_rot.x * 0.05, -_sway.x * 1.5 + _kick_rot.y * 0.03, _tilt + _kick_rot.z * 0.02)
	# Clip choreography on top.
	if clip != "":
		clip_t += delta
		var t := clampf(clip_t / clip_len, 0.0, 1.0)
		var r := _clip_pose(t)
		pos += r[0]
		rot += r[1]
		if clip_t >= clip_len:
			cancel_clip()
	vm.pivot.position = pos
	vm.pivot.rotation = rot


## Returns [position offset, rotation offset] for the active clip at normalised time t.
func _clip_pose(t: float) -> Array:
	var mag := vm.weapon.get_node_or_null("magazine") as Node3D
	var ch := vm.weapon.get_node_or_null("charging_handle") as Node3D
	match clip:
		"draw":
			# Weighty draw: rises from below with a slight roll, overshoot and settle (< 0.75 s).
			var e := 1.0 - pow(1.0 - t, 3.0)
			var settle := sin(t * PI * 2.0) * (1.0 - t) * 0.08
			return [Vector3(0.05, -0.28, 0.05) * (1.0 - e), Vector3(-0.9 * (1.0 - e) + settle, 0.3 * (1.0 - e), 0.5 * (1.0 - e))]
		"reload", "reload_empty":
			# Tilt in, drop the mag (separate node), insert a fresh one, (empty: rack the charging handle).
			var tilt_in := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.78, 1.0, t))
			if mag != null:
				var out_t := smoothstep(0.18, 0.32, t)
				var in_t := smoothstep(0.45, 0.62, t)
				mag.visible = not (t > 0.32 and t < 0.45)
				mag.position = _mag_rest + Vector3(0, -0.28, 0.06) * (out_t * (1.0 - in_t)) + Vector3(0, -0.25, 0.05) * (1.0 - in_t) * float(t > 0.45)
			if ch != null and clip == "reload_empty":
				var pull := smoothstep(0.7, 0.78, t) * (1.0 - smoothstep(0.8, 0.86, t))
				ch.position = _ch_rest + Vector3(0, 0, 0.07) * pull
			var seat := (smoothstep(0.6, 0.64, t) - smoothstep(0.64, 0.72, t)) * 0.02
			return [Vector3(-0.03, -0.04 + seat, 0.02) * tilt_in, Vector3(0.15, 0.25, 0.6) * tilt_in]
		"inspect":
			# Showcase: roll to the side, present the receiver, flip to the other side, return.
			var a := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.85, 1.0, t))
			var flip := smoothstep(0.4, 0.62, t)
			return [Vector3(-0.1, 0.04, 0.06) * a, Vector3(0.25 * a, (0.9 - 1.9 * flip) * a, (0.9 - 1.6 * flip) * a)]
	return [Vector3.ZERO, Vector3.ZERO]
