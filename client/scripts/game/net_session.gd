## Online match session (spec milestones 4–5): authoritative server, client-side prediction with
## reconciliation for the local player, entity interpolation for everyone else, server-confirmed
## hits, round flow (buy phase, plant/defuse, round end), buy menu, scoreboard, spectating and the
## death recap. Uses the Net autoload for the socket and the generated Protocol for messages.
class_name NetSession
extends Node3D

const INTERP_TICKS := 2.0
const SEND_REDUNDANCY := 3

var map_id := ""
var map: MapRuntime
var world: SimWorld
var effects: Effects
var ability_fx: AbilityFx
var player: LocalPlayer
var hud: Hud
var buy_menu: BuyMenu
var scoreboard: Scoreboard
var remotes: Dictionary = {}  ## id -> RemotePlayer
var roster: Dictionary = {}  ## id -> {name, team, agent}
var my_id := -1
var my_team := 0
var round_seed := 1
var round_num := 0
var phase := 0
var phase_ends_tick := 0
var scores := [0, 0]
var weapon_ids: Array = []
var charge_state := 0
var charge_node: Node3D
var charge_planted_tick := 0
var _last_snapshot_tick := 0
var _last_snapshot_time := 0.0
var _jitter := 0.0
var _beep_t := 0.0
var _recap: Dictionary = {}  ## attacker id -> damage this round
var _spectate_idx := 0


func _ready() -> void:
	effects = Effects.new()
	add_child(effects)
	ability_fx = AbilityFx.new()
	ability_fx.session = self
	add_child(ability_fx)
	for w: Dictionary in SharedConfig.read_json("res://data/config/weapons.json")["weapons"]:
		weapon_ids.append(w["id"])
	hud = Hud.new()
	add_child(hud)
	buy_menu = BuyMenu.new()
	buy_menu.purchase.connect(func(item: String) -> void: Net.send({"type": "BuyRequest", "item": item}))
	add_child(buy_menu)
	scoreboard = Scoreboard.new()
	add_child(scoreboard)
	Net.message_received.connect(_on_message)
	hud.message("CONNECTING…", 5.0)
	if Net.state != Net.State.ONLINE:
		var args := Game.parse_user_args(OS.get_cmdline_user_args())
		Net.connect_to(str(args.get("server", Settings.get_value("net", "server_url"))))
		while Net.state != Net.State.ONLINE:
			await get_tree().process_frame
			if Net.state == Net.State.FAILED:
				hud.message("SERVER UNREACHABLE (%s)" % Net.last_error, 10.0)
				return
	my_id = Net.player_id
	hud.message("JOINING MATCH…", 5.0)
	var agent: String = str(Settings.get_value("gameplay", "agent"))
	Net.send({"type": "JoinMatch", "ticket": Net.pending_ticket if Net.pending_ticket != "" else agent})
	Net.pending_ticket = ""


func _load_map(id: String) -> void:
	if map_id == id:
		return
	map_id = id
	map = (load("res://scenes/maps/%s.tscn" % id) as PackedScene).instantiate() as MapRuntime
	add_child(map)
	move_child(map, 0)
	world = SimWorld.load_map(id)
	effects.world = world
	player = LocalPlayer.new()
	player.name = "LocalPlayer"
	player.online = true
	player.player_id = my_id
	add_child(player)
	player.setup(self, world, Vector3(0, 0, 0), 0.0)
	player.shot_fired.connect(_on_local_shot)
	hud.player = player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func server_tick_now() -> float:
	return _last_snapshot_tick + (Time.get_ticks_msec() / 1000.0 - _last_snapshot_time) * 64.0


# ------------------------------------------------------------------ network in

func _on_message(msg: Dictionary) -> void:
	match str(msg["type"]):
		"MatchState":
			round_seed = int(msg["seed"])
			for r: Dictionary in msg["roster"]:
				roster[int(r["playerId"])] = {"name": r["name"], "team": int(r["team"]), "agent": r["agent"]}
			if roster.has(my_id):
				my_team = int(roster[my_id]["team"])
			_load_map(msg["map"])
			scoreboard.roster = roster
		"Snapshot":
			_on_snapshot(msg)
		"Spawn":
			if int(msg["playerId"]) == my_id and player != null:
				player.teleport(msg["pos"], float(msg["yaw"]))
				my_team = int(msg["team"])
				_recap.clear()
		"RoundPhase":
			round_num = int(msg["round"])
			phase = int(msg["phase"])
			phase_ends_tick = int(msg["endsAtTick"])
			scores = [int(msg["scoreAttack"]), int(msg["scoreDefense"])]
			if phase == 0:
				hud.message("ROUND %d  ·  BUY PHASE" % round_num, 2.5)
				Sfx.play_2d("music", "buy_sting", -8.0, "Music")
				if charge_node != null:
					charge_node.queue_free()
					charge_node = null
			elif phase == 1:
				buy_menu.close()
		"RoundEnd":
			var won := int(msg["winnerTeam"]) == my_team
			if msg["reason"] == "match":
				hud.message("VICTORY" if won else "DEFEAT", 8.0)
				Sfx.play_2d("music", "win" if won else "loss", -4.0, "Music")
			else:
				hud.message("ROUND WON" if won else "ROUND LOST", 4.0)
		"HitConfirm":
			hud.hit("head" if int(msg["hitZone"]) == 0 else "body")
		"Damage":
			if int(msg["victimId"]) == my_id and player != null:
				var from: Vector3 = msg["fromPos"]
				hud.damage_from((from - player.global_position).normalized())
				_recap[int(msg["attackerId"])] = int(_recap.get(int(msg["attackerId"]), 0)) + int(msg["amount"])
				Sfx.play_2d("ui", "damage_taken", -6.0)
		"Kill":
			var killer := int(msg["killerId"])
			var victim := int(msg["victimId"])
			if killer == my_id:
				hud.hit("kill")
			hud.killfeed(_name(killer), _name(victim), str(Data.get_weapon(msg["weapon"]).get("name", msg["weapon"])), bool(msg["headshot"]), bool(msg["wallbang"]), _team(killer) == my_team, str(msg["weapon"]) if not Data.get_weapon(msg["weapon"]).is_empty() else "")
			if victim == my_id and player != null:
				player.alive = false
				player.health = 0
				_show_recap(killer)
		"ShotEvent":
			_on_remote_shot(msg)
		"AbilityEvent":
			ability_fx.handle(msg)
		"SoundEvent":
			if int(msg["kind"]) == 1:
				Sfx.play_3d("footsteps", str(msg["param"]), msg["pos"], -6.0, "Footsteps", 40.0)
		"PlayerStatus":
			_on_status(msg)
		"ChargeState":
			_on_charge(msg)
		"PlantStart":
			Sfx.play_3d("charge", "plant_loop", msg["pos"], 0.0, "SFX", 60.0)
		"DefuseStart":
			if bool(msg["resumeFromCheckpoint"]):
				Sfx.play_2d("charge", "defuse_half", -4.0)
		"Scoreboard":
			scoreboard.entries = msg["entries"]
		"BuyResult":
			if not bool(msg["ok"]):
				hud.message(str(msg["reason"]).replace("_", " "), 1.2)
			else:
				Sfx.play_2d("ui", "click", -4.0)


func _on_snapshot(msg: Dictionary) -> void:
	var tick := int(msg["tick"])
	var now := Time.get_ticks_msec() / 1000.0
	if _last_snapshot_tick > 0:
		var expected := float(tick - _last_snapshot_tick) / 64.0
		var actual := now - _last_snapshot_time
		_jitter = lerpf(_jitter, absf(actual - expected) * 64.0, 0.05)  # adaptive jitter buffer (ticks)
	_last_snapshot_tick = tick
	_last_snapshot_time = now
	var seen := {}
	for st: Dictionary in msg["players"]:
		var id := int(st["playerId"])
		seen[id] = true
		if id == my_id:
			if player != null:
				player.health = float(st["health"])
				player.shield = float(st["shield"])
				player.alive = (int(st["flags"]) & 2) != 0
				player.reconcile(int(msg["lastProcessedSeq"]), st)
			continue
		var rp: RemotePlayer = remotes.get(id)
		if rp == null:
			rp = RemotePlayer.new()
			var info: Dictionary = roster.get(id, {"name": "Player %d" % id, "team": 1 - my_team, "agent": "kestrel"})
			add_child(rp)
			rp.setup(id, int(info["team"]), str(info["agent"]), str(info["name"]), int(info["team"]) == my_team)
			remotes[id] = rp
		rp.push(tick, st)
	# Enemies culled by the server's fog of war disappear (no stale ghosts).
	for id: int in remotes:
		var r: RemotePlayer = remotes[id]
		if not seen.has(id) and not r.ally:
			r.visible = false
			r.buffer.clear()


func _on_status(msg: Dictionary) -> void:
	if int(msg["playerId"]) != my_id or player == null:
		return
	player.credits = int(msg["credits"])
	buy_menu.credits = player.credits
	for pair: Array in [["primary", str(msg["primary"])], ["secondary", str(msg["secondary"])]]:
		var slot_name: String = pair[0]
		var wid: String = pair[1]
		var have: String = player.loadout.get(slot_name, {}).get("def", {}).get("id", "")
		if wid == "":
			player.loadout.erase(slot_name)
		elif wid != have:
			player.give_weapon(slot_name, wid)
			if (slot_name == "primary" and int(msg["slot"]) == 0) or (slot_name == "secondary" and int(msg["slot"]) == 1):
				player.equip(slot_name)
	var cur: Dictionary = player.current()
	if not cur.is_empty():
		var st: SimWeapons.State = cur["st"]
		st.ammo = int(msg["ammo"])
		st.reserve = int(msg["reserve"])
	player.shield = float(msg["shield"])
	hud.set_abilities(str(msg["agent"]), msg["charges"], int(msg["ultPoints"]))
	buy_menu.set_agent(str(msg["agent"]))


func _on_charge(msg: Dictionary) -> void:
	charge_state = int(msg["state"])
	if charge_node != null:
		charge_node.queue_free()
		charge_node = null
	match charge_state:
		2:
			charge_node = ChargeModel.build(false)
			charge_node.position = msg["pos"]
			add_child(charge_node)
			hud.message("BREACH CHARGE DROPPED", 1.5)
		3:
			charge_node = ChargeModel.build(true)
			charge_node.position = msg["pos"]
			add_child(charge_node)
			charge_planted_tick = int(msg["plantedTick"])
			hud.message("BREACH CHARGE PLANTED", 2.5)
			Sfx.play_2d("charge", "beep", 0.0)
		4:
			hud.message("CHARGE DEFUSED", 2.5)
		5:
			Sfx.play_3d("charge", "detonate", msg["pos"], 6.0, "SFX", 300.0)
			effects.impact(msg["pos"], Vector3.UP, "concrete")


# ------------------------------------------------------------------ shots

func _on_local_shot(origin: Vector3, dirs: Array, weapon_id: String, _shot_number: int) -> void:
	# Instant local feedback (tracer + predicted impact against the map only). Damage and
	# hitmarkers wait for the server's HitConfirm (spec §13.4: no false hits).
	var def: Dictionary = Data.get_weapon(weapon_id)
	if def["class"] == "melee":
		return
	var muzzle := player.viewmodel.weapon.get_node_or_null("muzzle") as Node3D
	var from := muzzle.global_position if muzzle != null else origin
	for d: Vector3 in dirs:
		var hit := world.raycast(origin.x, origin.y, origin.z, d.x, d.y, d.z, 400.0)
		var to := origin + d * (float(hit["t"]) if not hit.is_empty() else 400.0)
		effects.tracer(from, to)
		if not hit.is_empty():
			var tags: Array = SimHitscan.tags()
			var tag: Dictionary = tags[int(hit["tag"])]
			effects.impact(to, Vector3(hit["nx"], hit["ny"], hit["nz"]), tag["impact"])


func _on_remote_shot(msg: Dictionary) -> void:
	var shooter := int(msg["playerId"])
	var origin: Vector3 = msg["origin"]
	var hit_pos: Vector3 = msg["hit"]
	var rp: RemotePlayer = remotes.get(shooter)
	var from := rp.muzzle_position() if rp != null and rp.visible else origin
	var tracer_color := Color(1.0, 0.82, 0.5)
	if not player.alive:
		tracer_color = Settings.team_colors()["ally" if _team(shooter) == my_team else "enemy"]
	effects.tracer(from, hit_pos, tracer_color)
	var impact_idx := int(msg["impact"])
	var tags: Array = SimHitscan.tags()
	var kind: String = "flesh" if impact_idx == 99 else (str(tags[impact_idx]["impact"]) if impact_idx < tags.size() else "concrete")
	if kind != "flesh":
		effects.impact(hit_pos, (origin - hit_pos).normalized(), kind)
	Sfx.gunshot(str(msg["weapon"]), origin, false)
	if rp != null and rp.visible:
		effects.muzzle_flash(Transform3D(Basis(), from), 1.2)
		if rp.anim != null:
			rp.anim.firing_kick = 1.0


# ------------------------------------------------------------------ per frame

func _physics_process(_delta: float) -> void:
	if player == null or not Net.state == Net.State.ONLINE:
		return
	# Clock sync: commands target the tick the server will process them on (RTT/2 lead + 1).
	var lead := (Net.rtt_ms / 1000.0 * 0.5) * 64.0 + 1.0
	player.server_tick_estimate = server_tick_now() + lead
	player.render_tick = server_tick_now() - INTERP_TICKS - clampf(_jitter, 0.0, 4.0)
	var cmds: Array = []
	var n := player.input_history.size()
	for i: int in range(maxi(0, n - SEND_REDUNDANCY), n):
		var e: Dictionary = player.input_history[i]
		cmds.append({"seq": int(e["seq"]), "tick": int(e["tick"]), "buttons": int(e["buttons"]), "yaw": float(e["yaw"]), "pitch": float(e["pitch"]), "weaponSlot": int(e["slot"]), "interpMs": int(clampf((float(e["tick"]) - player.render_tick) * 15.625, 0.0, 400.0))})
	if not cmds.is_empty():
		Net.send({"type": "Input", "ackSnapshot": _last_snapshot_tick, "cmds": cmds})


func _process(delta: float) -> void:
	var rt := server_tick_now() - INTERP_TICKS - clampf(_jitter, 0.0, 4.0)
	for id: int in remotes:
		var r: RemotePlayer = remotes[id]
		if not r.buffer.is_empty():
			r.render_at(rt, weapon_ids)
	if hud != null:
		hud.abilities.modulate.a = 0.15 if ability_fx.blackout_t > 0.0 else 1.0
		var secs := maxf(0.0, (phase_ends_tick - server_tick_now()) / 64.0)
		var timer_text := "%d:%02d" % [int(secs) / 60, int(secs) % 60] if phase != 2 else "◆"
		hud.set_round_info(timer_text, "%d  ·  ROUND %d  ·  %d" % [scores[0] if my_team == 0 else scores[1], round_num, scores[1] if my_team == 0 else scores[0]])
	# Planted charge: beeping speeds up toward detonation (no exact number shown, spec §15.2).
	if charge_state == 3 and charge_node != null:
		var left := 45.0 - (server_tick_now() - charge_planted_tick) / 64.0
		var interval := clampf(left / 45.0, 0.08, 1.0) * 1.0
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = interval
			Sfx.play_3d("charge", "beep", charge_node.global_position, 0.0, "SFX", 80.0)
	# Spectate teammates while dead (spec §10.3).
	if player != null and not player.alive:
		_spectate()


func _spectate() -> void:
	var mates: Array = []
	for id: int in remotes:
		var r: RemotePlayer = remotes[id]
		if r.ally and r.alive and r.visible:
			mates.append(r)
	if mates.is_empty():
		return
	var target: RemotePlayer = mates[_spectate_idx % mates.size()]
	player.camera.global_position = target.global_position + Vector3(0, 1.62, 0)
	player.camera.global_rotation = Vector3(target.pitch, target.yaw, 0)
	player.viewmodel.visible = false


func _show_recap(killer: int) -> void:
	var lines := PackedStringArray()
	for id: int in _recap:
		lines.append("%s  %d" % [_name(id), int(_recap[id])])
	hud.message("KILLED BY %s\n%s" % [_name(killer).to_upper(), "\n".join(lines)], 4.0)


func _name(id: int) -> String:
	if id == my_id:
		return "You"
	return str(roster.get(id, {}).get("name", "Player %d" % id))


func _team(id: int) -> int:
	if id == my_id:
		return my_team
	return int(roster.get(id, {}).get("team", -1))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu") and phase == 0:
		buy_menu.toggle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if buy_menu.visible else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("scoreboard"):
		scoreboard.visible = true
	elif event.is_action_released("scoreboard"):
		scoreboard.visible = false
	elif event.is_action_pressed("fire") and player != null and not player.alive:
		_spectate_idx += 1
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_F10:
		Net.disconnect_from_server()
		Game.goto("menu")
