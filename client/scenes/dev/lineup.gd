## Agent line-up (milestone 7 review): all eight agents side by side on the Range with weapons,
## for silhouette and colour checks (spec §6.1: recognisable from silhouette at 30 m).
extends Node3D


func _ready() -> void:
	var map := (load("res://scenes/maps/range.tscn") as PackedScene).instantiate()
	add_child(map)
	var ids := ["kestrel", "mamba", "vesper", "haldor", "orin", "sable", "imani", "tomas"]
	for i: int in ids.size():
		var rig := AgentLooks.build(ids[i])
		rig.position = Vector3(-5.25 + i * 1.5, 0, -6)
		rig.rotation_degrees.y = 180.0 + (i - 3.5) * 6.0
		add_child(rig)
		var anim := AgentAnimator.new()
		anim.setup(rig)
		anim.attach_weapon(WeaponBuilder.build("saber"))
		rig.add_child(anim)
		var l := Label3D.new()
		l.text = ids[i].to_upper()
		l.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
		l.font_size = 48
		l.pixel_size = 0.004
		l.position = rig.position + Vector3(0, 2.15, 0)
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, -1.2)
	cam.fov = 55
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, -6))
