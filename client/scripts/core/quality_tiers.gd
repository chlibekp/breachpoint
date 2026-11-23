## Pure fidelity-tier selection (spec 9.3). No autoload access, so tests and tools can use it.
class_name QualityTiers
extends RefCounted

const RENDERER_COMPAT := "gl_compatibility"
const RENDERER_FORWARD := "forward_plus"


## The Compatibility renderer always gets the web tier (it cannot run Forward+ features);
## Forward+ never gets the web tier. `requested` is the player setting ("auto" or a tier id).
static func select(tiers: Array, current_renderer: String, requested: String, default_tier: String) -> Dictionary:
	var by_id: Dictionary = {}
	for t: Variant in tiers:
		var d: Dictionary = t
		by_id[d["id"]] = d
	if by_id.is_empty():
		return {}
	if current_renderer != RENDERER_FORWARD:
		return by_id.get("web", tiers[0])
	if requested != "auto" and requested != "web" and by_id.has(requested):
		return by_id[requested]
	return by_id.get(default_tier, tiers[tiers.size() - 1])
