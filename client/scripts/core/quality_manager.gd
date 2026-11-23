## Autoload: detects platform + renderer, picks a fidelity tier from shared/config/quality.json
## (spec 9.3) and applies it to viewports, environments, lights and particles.
## No scene may assume Forward+ features exist: scenes call apply_environment()/apply_sun()
## and convert_particles() instead of setting those features directly.
extends Node

signal tier_changed(tier: Dictionary)

const RENDERER_FORWARD := QualityTiers.RENDERER_FORWARD

var tier: Dictionary = {}
var renderer: String = ""
var is_web: bool = false


func _ready() -> void:
	is_web = OS.has_feature("web")
	renderer = RenderingServer.get_current_rendering_method()
	var tiers: Array = Data.quality.get("tiers", [])
	var default_tier: String = Data.quality.get("defaultDesktopTier", "medium")
	var requested: String = Settings.get_value("video", "tier")
	set_tier(QualityTiers.select(tiers, renderer, requested, default_tier))
	Settings.changed.connect(_on_setting_changed)


func set_tier(new_tier: Dictionary) -> void:
	if new_tier.is_empty():
		push_error("QualityManager: no quality tiers loaded")
		return
	tier = new_tier
	RenderingServer.global_shader_parameter_set("quality_tier", int(tier["index"]))
	_apply_viewport(get_viewport())
	var size: int = int(tier["shadowSize"])
	RenderingServer.directional_shadow_atlas_set_size(size, true)
	get_viewport().positional_shadow_atlas_size = size
	if renderer == RENDERER_FORWARD:
		var soft: bool = tier["softShadows"]
		var q := RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if soft else RenderingServer.SHADOW_QUALITY_HARD
		RenderingServer.directional_soft_shadow_filter_set_quality(q)
		RenderingServer.positional_soft_shadow_filter_set_quality(q)
	tier_changed.emit(tier)


func tier_id() -> String:
	return tier.get("id", "")


## Human-readable anti-aliasing actually in effect on this renderer.
func effective_aa() -> String:
	var parts := PackedStringArray()
	if int(tier.get("msaa", 0)) > 0:
		parts.append("MSAA %dx" % int(tier["msaa"]))
	if renderer == RENDERER_FORWARD:
		if tier.get("fxaa", false):
			parts.append("FXAA")
		if tier.get("taa", false):
			parts.append("TAA")
		if tier.get("fsr2", false):
			parts.append("FSR2")
	return " + ".join(parts) if not parts.is_empty() else "off"


func _apply_viewport(vp: Viewport) -> void:
	var msaa: int = int(tier["msaa"])
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(msaa, Viewport.MSAA_DISABLED)
	if renderer == RENDERER_FORWARD:
		# Godot 4.7's Compatibility renderer has no screen-space AA, so the web tier's FXAA is a
		# no-op there (DECISIONS.md); MSAA 2x carries web anti-aliasing.
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if tier["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = tier["taa"]
		if tier["fsr2"]:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 1.0
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.use_debanding = true
	# Sharpening after TAA (spec 9.2) is applied through the scaling pipeline's FSR sharpness.
	vp.fsr_sharpness = 2.0 - clampf(float(tier["sharpen"]) * 2.0, 0.0, 2.0)


## Applies tier-dependent post effects to a map's Environment. Base grading (tonemap, LUT,
## exposure, glow) is authored per map and left untouched so every tier shares the same look.
func apply_environment(env: Environment) -> void:
	var forward := renderer == RENDERER_FORWARD
	env.ssao_enabled = forward and tier["ssao"]
	env.ssil_enabled = forward and tier["ssil"]
	env.ssr_enabled = forward and tier["ssr"]
	env.sdfgi_enabled = false  # Baked LightmapGI is the GI solution on every tier.
	env.volumetric_fog_enabled = forward and tier["volumetricFog"]


## Applies shadow cascades to a map's sun.
func apply_sun(sun: DirectionalLight3D) -> void:
	var cascades: int = int(tier["shadowCascades"])
	sun.directional_shadow_mode = {
		1: DirectionalLight3D.SHADOW_ORTHOGONAL,
		2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
	}.get(cascades, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	sun.shadow_blur = 1.5 if tier["softShadows"] else 1.0


## Replaces GPUParticles3D with CPUParticles3D where the tier asks for it (web), and scales
## particle amounts. Call on a map or effect root after it enters the tree.
func convert_particles(root: Node) -> void:
	var scale: float = float(tier.get("particleScale", 1.0))
	for node: Node in root.find_children("*", "GPUParticles3D", true, false):
		var gpu: GPUParticles3D = node
		if tier.get("gpuParticles", true):
			gpu.amount_ratio = scale
			continue
		var cpu := CPUParticles3D.new()
		cpu.convert_from_particles(gpu)
		cpu.name = gpu.name
		cpu.amount = maxi(1, int(round(cpu.amount * scale)))
		cpu.transform = gpu.transform
		cpu.emitting = gpu.emitting
		gpu.replace_by(cpu)
		gpu.queue_free()


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "video" and key == "tier":
		var tiers: Array = Data.quality.get("tiers", [])
		set_tier(QualityTiers.select(tiers, renderer, str(value), Data.quality.get("defaultDesktopTier", "medium")))
