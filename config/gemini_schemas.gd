extends Node
class_name GeminiSchemas

const SCHEMAS := {
	"fighter_move": {
		"description": "Rollback-safe fighting game move config",
		"required_fields": [
			"name",
			"startup",
			"active",
			"recovery",
			"on_hit",
			"on_block"
		]
	},
	"hitbox_rects": {
		"description": "Rectangular hitboxes per animation frame",
		"required_fields": [
			"animation",
			"frames"
		]
	},
	"fps_weapon": {
		"description": "Weapon config for FPS demo",
		"required_fields": [
			"name",
			"damage",
			"fire_rate",
			"spread",
			"clip_size"
		]
	},
	"tile_ability": {
		"description": "Ability config for grid / Meme Wars style game",
		"required_fields": [
			"name",
			"cooldown",
			"area_type",
			"effect"
		]
	}
}

static func has_schema(schema_id: String) -> bool:
	return SCHEMAS.has(schema_id)

static func get_schema(schema_id: String) -> Dictionary:
	return SCHEMAS.get(schema_id, {})
