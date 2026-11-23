extends TestCase

func _tiers() -> Array:
	return SharedConfig.load_all()["data"]["quality"]["tiers"]


func test_compatibility_always_gets_web_tier() -> void:
	for requested: String in ["auto", "ultra", "low"]:
		check_eq(QualityTiers.select(_tiers(), "gl_compatibility", requested, "medium")["id"], "web", requested)


func test_forward_plus_auto_uses_default() -> void:
	check_eq(QualityTiers.select(_tiers(), "forward_plus", "auto", "medium")["id"], "medium")


func test_forward_plus_respects_override_but_never_web() -> void:
	check_eq(QualityTiers.select(_tiers(), "forward_plus", "high", "medium")["id"], "high")
	check_eq(QualityTiers.select(_tiers(), "forward_plus", "web", "medium")["id"], "medium")


func test_web_tier_matches_spec_table() -> void:
	var web: Dictionary = QualityTiers.select(_tiers(), "gl_compatibility", "auto", "medium")
	check_eq(int(web["msaa"]), 2, "MSAA 2x")
	check(web["fxaa"], "FXAA on")
	check(not web["ssao"] and not web["ssil"] and not web["ssr"] and not web["volumetricFog"], "no screen-space effects")
	check_eq(int(web["shadowCascades"]), 1, "1 cascade")
	check(not web["gpuParticles"], "CPU particles on web")
