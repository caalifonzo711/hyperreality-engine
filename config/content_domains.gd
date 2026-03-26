extends Node
class_name ContentDomains

# Central registry for where each content domain stores its configs
# and which schemas are valid in that domain.
const DOMAINS: Dictionary = {
	"rollback_fighter": {
		"root": "res://games/rollback_fighter/",
		"schemas": [
			"fighter_move",
			"hitbox_rects",
		],
		"description": "Rollback fighter demo configs",
	},
	"meme_wars": {
		"root": "res://games/meme_wars/",
		"schemas": [
			"tile_ability",
		],
		"description": "Spreadsheet Meme Wars demo configs",
	},
	"ar_overlay": {
		"root": "res://games/ar_overlay/",
		"schemas": [
			"fps_weapon",  # extend later if needed
		],
		"description": "AR overlay / FPS-style demo configs",
	},
}


static func has_domain(domain_id: String) -> bool:
	return DOMAINS.has(domain_id)


static func get_domain(domain_id: String) -> Dictionary:
	return DOMAINS.get(domain_id, {})


static func get_root(domain_id: String) -> String:
	var d := get_domain(domain_id)
	if d.is_empty():
		return ""
	return str(d.get("root", ""))


static func get_schemas(domain_id: String) -> Array:
	var d := get_domain(domain_id)
	if d.is_empty():
		return []
	return d.get("schemas", [])
