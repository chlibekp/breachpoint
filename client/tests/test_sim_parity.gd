extends TestCase
## Spec §13.3: the GDScript sim must reproduce the server's golden vectors within 1 mm.


func _cfg() -> Dictionary:
	return SharedConfig.read_json("res://data/config/movement.json")


func test_movement_vectors_match_server() -> void:
	var data: Dictionary = SharedConfig.read_json("res://tests/data/movement/vectors.json")
	var w := SimWorld.new()
	for b: Array in data["boxes"]:
		w.add_box(b[0], b[1], b[2], b[3], b[4], b[5], b[6], int(b[7]))
	var cfg := _cfg()
	var worst := 0.0
	for sc: Dictionary in data["scenarios"]:
		var start: Array = sc["start"]
		var s := SimMovement.new_state(start[0], start[1], start[2])
		var cps: Array = sc["checkpoints"]
		var cp := 0
		var inputs: Array = sc["inputs"]
		for i: int in inputs.size():
			var inp: Array = inputs[i]
			SimMovement.step(cfg, w, s, int(inp[0]), float(inp[1]), float(inp[2]))
			if cp < cps.size() and int(cps[cp]["tick"]) == i + 1:
				var want: Dictionary = cps[cp]
				var err := maxf(absf(s.x - float(want["x"])), maxf(absf(s.y - float(want["y"])), absf(s.z - float(want["z"]))))
				worst = maxf(worst, err)
				check(err < 0.001, "%s tick %d off by %.6f m" % [sc["name"], i + 1, err])
				check(s.grounded == bool(want["grounded"]), "%s tick %d grounded" % [sc["name"], i + 1])
				cp += 1
	print("    movement parity worst error: %.9f m" % worst)


func test_rng_matches_server() -> void:
	var data: Dictionary = SharedConfig.read_json("res://tests/data/weapons/vectors.json")
	var r: Dictionary = data["rng"]
	check_eq(SimRng.hash_seed(int(r["seedA"]), int(r["seedB"])), int(r["hash"]), "hash_seed")
	var rng := SimRng.new(int(r["hash"]))
	for v: Variant in r["sequence"]:
		check_near(rng.next(), float(v), 1e-12, "mulberry32")


func test_weapon_vectors_match_server() -> void:
	var data: Dictionary = SharedConfig.read_json("res://tests/data/weapons/vectors.json")
	var weapons: Dictionary = {}
	for w: Dictionary in SharedConfig.read_json("res://data/config/weapons.json")["weapons"]:
		weapons[w["id"]] = w
	var setups := {"saber_spray": ["saber", true, 0.0], "wasp_taps": ["wasp", false, 0.6], "breaker": ["breaker", false, 0.0], "lancer_burst": ["lancer", true, 0.0]}
	for case_name: String in setups:
		var spec: Array = setups[case_name]
		var def: Dictionary = weapons[spec[0]]
		var held: bool = spec[1]
		var want: Array = data["cases"][case_name]["shots"]
		var st := SimWeapons.new_state(def, 0.0)
		var now := float(def["equipTime"])
		var n := 0
		for t: int in want.size() * 20:
			if n >= want.size():
				break
			var pressed := t == 0 if held else t % 16 == 0
			var hold := held or pressed
			SimWeapons.update(def, st, now, 1.0 / 64.0, hold)
			var shot := SimWeapons.try_fire(def, st, now, float(spec[2]), 0.2, false, false, false, 777, 3, pressed, hold)
			if not shot.is_empty():
				var w: Dictionary = want[n]
				check_near(now, float(w["t"]), 1e-9, "%s shot %d time" % [case_name, n])
				var pel: Array = shot["pellets"]
				var wpel: Array = w["pellets"]
				check_eq(pel.size(), wpel.size(), "%s pellets" % case_name)
				for k: int in mini(pel.size(), wpel.size()):
					check_near(float(pel[k][0]), float(wpel[k]["yaw"]), 1e-9, "%s shot %d pellet %d yaw" % [case_name, n, k])
					check_near(float(pel[k][1]), float(wpel[k]["pitch"]), 1e-9, "%s shot %d pellet %d pitch" % [case_name, n, k])
				check_eq(st.ammo, int(w["ammo"]), "%s ammo" % case_name)
				n += 1
			now += 1.0 / 64.0
		check_eq(n, want.size(), "%s shot count" % case_name)


func test_solstice_collision_loads() -> void:
	var w := SimWorld.load_map("solstice")
	check(w.count() > 50, "solstice has collision boxes (%d)" % w.count())
	# Standing in the plaza centre-ish: ground under the feet is the plaza floor (y = 0).
	check_near(SimMovement.ground_height(w, 22.0, 0.4, -20.0, 0.3), 0.0, 0.001, "plaza floor height")
