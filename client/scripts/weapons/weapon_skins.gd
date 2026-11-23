## Weapon skins (spec §7.4): skins are data (shared/config/skins.json) mapped onto M_Weapon's mask
## channels. A skin never changes the silhouette, so weapons stay identifiable.
class_name WeaponSkins
extends RefCounted


static func get_skin(skin_id: String, _weapon_id: String = "") -> Dictionary:
	var data: Dictionary = SharedConfig.read_json("res://data/config/skins.json")
	for s: Dictionary in data.get("skins", []):
		if s["id"] == skin_id:
			var out := s.duplicate()
			if out["accent"] == "class":
				out.erase("accent")  # WeaponBuilder falls back to the class accent
			if out.get("stripes", false):
				out["pattern"] = "res://assets/vfx/T_HazardStripes.png"
			return out
	return {}
