## Renderer-parity probe (open problem: Compatibility "cool lift" under a shadowed sun). Loads the
## lightmap test courtyard and toggles one thing at a time from the command line, for captures:
##   -- --capture=res://scenes/dev/parity_probe.tscn --shadows=on|off --ambient=<energy>
##      --sky_contrib=<0..1> --lm=on|off --glow=on|off --sun=<energy multiplier>
extends Node3D


func _ready() -> void:
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var scene := (load("res://scenes/dev/lightmap_test.tscn") as PackedScene).instantiate()
	add_child(scene)
	var env: Environment = (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = scene.get_node("Sun")
	sun.shadow_enabled = str(args.get("shadows", "on")) == "on"
	if str(args.get("refl", "on")) == "off":
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if args.has("spec"):
		sun.light_specular = float(args["spec"])
	if args.has("sun"):
		sun.light_energy *= float(args["sun"])
	if args.has("ambient"):
		env.ambient_light_energy = float(args["ambient"])
	if args.has("sky_contrib"):
		env.ambient_light_sky_contribution = float(args["sky_contrib"])
	if str(args.get("glow", "on")) == "off":
		env.glow_enabled = false
	if str(args.get("lm", "on")) == "off":
		(scene.get_node("LightmapGI") as LightmapGI).light_data = null
	for c: Node in scene.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
