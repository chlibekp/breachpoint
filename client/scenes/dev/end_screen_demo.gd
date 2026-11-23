## QA: renders the end-of-match screen with sample data (`--capture=res://scenes/dev/end_screen_demo.tscn`).
extends Node


func _ready() -> void:
	var es := EndScreen.new()
	add_child(es)
	var roster: Dictionary = {}
	var entries: Array = []
	var agents := ["kestrel", "vesper", "haldor", "orin", "imani", "mamba", "sable", "tomas", "kestrel", "vesper"]
	for i: int in 10:
		roster[i + 1] = {"name": "Player%d" % (i + 1), "team": 0 if i < 5 else 1, "agent": agents[i]}
		entries.append({"playerId": i + 1, "kills": 20 - i, "deaths": 8 + i % 4, "assists": i % 6, "score": 5200 - i * 300, "credits": 0, "pingMs": 30})
	var rounds: Array = []
	var reasons := ["elimination", "time", "detonated", "defused"]
	for r: int in 23:
		rounds.append({"round": r + 1, "winnerTeam": 0 if (r * 7) % 5 < 3 else 1, "reason": reasons[r % 4]})
	es.show_result(true, 0, rounds, entries, roster)
