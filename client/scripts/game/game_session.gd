## Offline game session (spec milestone 3): map + local player + bots + effects + HUD, with shots
## resolved locally by the same hitscan the server uses. The online session (milestone 4) reuses
## this structure but takes authority from the server.
class_name GameSession
extends Node3D

@export var map_id: String = "range"

var map: MapRuntime
var world: SimWorld
var effects: Effects
var player: LocalPlayer
var hud: Hud
var bots: Array[TrainingBot] = []
var round_seed: int = 1
var kills := 0
var shots_fired := 0
var shots_hit := 0
var headshots := 0


func _ready() -> void:
	round_seed = randi()
	map = (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate() as MapRuntime
	add_child(map)
	world = SimWorld.load_map(map_id)
	effects = Effects.new()
	effects.world = world
	add_child(effects)
	var spawns: Array = map.meta.get("spawns", {}).get("attack", [])
	var spawn := MapRuntime.vec(spawns[0]["pos"]) if not spawns.is_empty() else Vector3.ZERO
	var spawn_yaw := float(spawns[0]["yaw"]) if not spawns.is_empty() else 0.0
	player = LocalPlayer.new()
	player.name = "LocalPlayer"
	add_child(player)
	player.setup(self, world, spawn, spawn_yaw)
	player.shot_fired.connect(_on_shot)
	if map_id == "range":
		_spawn_range_bots()
		player.give_weapon("primary", "saber")
		player.equip("primary")
		player.credits = 9000
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	hud.message("THE RANGE  ·  click to play" if map_id == "range" else map_id.to_upper(), 3.0)
	print("[session] map=%s bots=%d first=%s" % [map_id, bots.size(), str(bots[0].position) if not bots.is_empty() else "-"])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_range_bots() -> void:
	var id := 100
	for t: Dictionary in map.meta.get("targets", []):
		var pos := MapRuntime.vec(t["pos"])
		for x: float in [-3.0, 0.0, 3.0]:
			_add_bot(id, pos + Vector3(x, 0, 0), 0.0, "static")
			id += 1
	var track: Dictionary = map.meta.get("strafeTrack", {})
	if not track.is_empty():
		var bot := _add_bot(id, MapRuntime.vec(track["a"]), 0.0, "strafe")
		bot.track_a = MapRuntime.vec(track["a"])
		bot.track_b = MapRuntime.vec(track["b"])
		id += 1
	var movers: Array = map.meta.get("movingBots", [])
	for i: int in movers.size():
		var a := MapRuntime.vec(movers[i])
		var bot2 := _add_bot(id, a, 0.0, "patrol")
		bot2.track_a = a
		bot2.track_b = a + Vector3(-8.0 if a.x > 0 else 8.0, 0, 0)
		id += 1


func _add_bot(id: int, pos: Vector3, yaw: float, mode: String) -> TrainingBot:
	var bot := TrainingBot.new()
	bot.name = "Bot%d" % id
	add_child(bot)
	bot.setup(world, id, pos, yaw, mode)
	bots.append(bot)
	return bot


func targets() -> Array:
	var out: Array = []
	for b: TrainingBot in bots:
		if b.alive:
			out.append(b.target_info())
	return out


## Resolves a local shot (offline authority). Online, the server does this and sends HitConfirm.
func _on_shot(origin: Vector3, dirs: Array, weapon_id: String, _shot_number: int) -> void:
	var def: Dictionary = Data.get_weapon(weapon_id)
	var tier: String = def["penetration"]
	var range_m := float(def.get("meleeRange", 400.0)) if def["class"] == "melee" else 400.0
	var tgts := targets()
	shots_fired += 1
	var best_kind := ""
	var muzzle := player.viewmodel.weapon.get_node_or_null("muzzle") as Node3D
	var tracer_from := muzzle.global_position if muzzle != null else origin
	for d: Vector3 in dirs:
		var hit := SimHitscan.trace(world, tgts, player.player_id, tier, origin, d, range_m)
		if def["class"] != "melee":
			effects.tracer(tracer_from, hit["pos"])
		if hit["kind"] == "world":
			effects.impact(hit["pos"], hit["normal"], hit["impact"])
		elif hit["kind"] == "player":
			effects.impact(hit["pos"], hit["normal"], "flesh")
			var bot := _bot(int(hit["player"]))
			if bot == null:
				continue
			var dmg := SimWeapons.damage_at(def, float(hit["t"]), hit["zone"]) * float(hit["scale"])
			var killed := bot.take_hit(dmg, hit["zone"])
			shots_hit += 1
			if hit["zone"] == "head":
				headshots += 1
			var kind: String = "kill" if killed else ("head" if hit["zone"] == "head" else "body")
			if kind == "kill" or best_kind == "" or (kind == "head" and best_kind == "body"):
				best_kind = kind
			if killed:
				kills += 1
				hud.killfeed("You", "Bot %d" % bot.bot_id, def["name"], hit["zone"] == "head", bool(hit["wallbang"]), true, str(def["id"]))
	if best_kind != "":
		hud.hit(best_kind)


func _bot(id: int) -> TrainingBot:
	for b: TrainingBot in bots:
		if b.bot_id == id:
			return b
	return null


func _process(_delta: float) -> void:
	if hud != null and map_id == "range":
		var acc := 100.0 * shots_hit / maxf(1.0, shots_fired)
		hud.set_round_info("THE RANGE", "KILLS %d  ·  ACC %d%%  ·  HS %d" % [kills, int(acc), headshots])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_F10:
		Game.goto("menu")
