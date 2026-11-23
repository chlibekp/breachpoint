extends TestCase


func test_all_configs_validate() -> void:
	var result: Dictionary = SharedConfig.load_all()
	var errors: PackedStringArray = result["errors"]
	check(errors.is_empty(), "schema errors: %s" % "; ".join(errors))
	var data: Dictionary = result["data"]
	check_eq(data.size(), SharedConfig.NAMES.size(), "configs loaded")


func test_roster_sizes() -> void:
	var data: Dictionary = SharedConfig.load_all()["data"]
	check_eq((data["weapons"]["weapons"] as Array).size(), 16, "weapons")
	check_eq((data["agents"]["agents"] as Array).size(), 8, "agents")


func test_movement_tick_matches_physics() -> void:
	var data: Dictionary = SharedConfig.load_all()["data"]
	check_eq(int(data["movement"]["tickRate"]), int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), "tick rate")
