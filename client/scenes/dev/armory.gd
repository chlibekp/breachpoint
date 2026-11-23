## Armory review (milestone 9): every weapon side by side for silhouette checks (spec §7.1).
extends Node3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5C6B78")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9AA8B8")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var skin := str(args.get("skin", "standard"))
	var ids: Array = Data.weapons.keys()
	for i: int in ids.size():
		var w := WeaponBuilder.build(ids[i], WeaponSkins.get_skin(skin))
		w.position = Vector3(-1.2 + (i % 4) * 0.85, 1.35 - floorf(i / 4.0) * 0.38, 0)
		w.rotation_degrees.y = 90
		add_child(w)
		var l := Label3D.new()
		l.text = str(Data.get_weapon(ids[i])["name"]).to_upper()
		l.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
		l.font_size = 32
		l.pixel_size = 0.0012
		l.position = w.position + Vector3(0, -0.16, 0)
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0.1, 0.8, 2.1)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0.1, 0.8, 0))
