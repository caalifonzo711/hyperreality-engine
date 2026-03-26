extends Node
class_name ConfigFactory

const GeminiSchemas = preload("res://config/gemini_schemas.gd")

# Where different schema types live under a domain root
const SCHEMA_SUBFOLDERS := {
	"fighter_move": "moves",
	"hitbox_rects": "hitboxes",
	"fps_weapon": "weapons",
	"tile_ability": "abilities",
}

# Built-in per-schema defaults.
# These are merged FIRST, then any defaults in gemini_schemas.gd,
# then the raw AI output on top.
const SCHEMA_DEFAULTS := {
	"fighter_move": {
		"name": "unnamed_move",
		"startup": 0,
		"active": 0,
		"recovery": 0,
		"on_hit_adv": 0,
		"on_block_adv": -2,
		"damage": 0,
		"meter_gain": 0,
		"priority": 0,
		"cancel_window_start": 0,
		"cancel_window_end": 0,
		"pushback_x": 0.0,
		"pushback_y": 0.0,
		"tags": [], # e.g. ["jab", "anti_air"]
	},

	"hitbox_rects": {
		# Typically an array of {x, y, w, h, type}
		"frames": [], # each frame = array of rects
	},

	"fps_weapon": {
		"name": "unnamed_weapon",
		"damage": 0,
		"fire_rate": 0.0,   # shots per second
		"mag_size": 0,
		"reload_time": 0.0,
		"spread": 0.0,
		"recoil": 0.0,
		"projectile_speed": 0.0,
		"tags": [],
	},

	"tile_ability": {
		"name": "unnamed_ability",
		"cooldown_frames": 0,
		"range_tiles": 0,
		"aoe_radius": 0,
		"damage": 0,
		"status_effect": "", # e.g. "burn", "slow"
		"duration_frames": 0,
	}
}


static func normalize_config(schema_id: String, raw: Dictionary) -> Dictionary:
	# 1) Pull schema metadata
	var schema: Dictionary = GeminiSchemas.get_schema(schema_id)
	if schema.is_empty():
		return { "ok": false, "error": "unknown_schema", "schema_id": schema_id }

	var required: Array = schema.get("required_fields", [])
	var allowed: Array = schema.get("allowed_fields", [])  # optional, may be empty
	var schema_defaults: Dictionary = schema.get("defaults", {})
	var builtin_defaults: Dictionary = SCHEMA_DEFAULTS.get(schema_id, {})

	# 2) Merge defaults → schema defaults → raw data
	#    Later merges override earlier ones.
	var data: Dictionary = {}
	data.merge(builtin_defaults, true)
	data.merge(schema_defaults, true)
	data.merge(raw, true)

	# 3) Check required fields & fill any last-minute gaps with safe defaults
	var missing: Array = []
	for field in required:
		if not data.has(field):
			missing.append(field)
			# Use simple fallback – numeric 0, bool false, empty string/array
			# You can specialize this later if needed.
			data[field] = 0

	if not missing.is_empty():
		push_warning("ConfigFactory: missing fields %s for schema %s; filled defaults." % [missing, schema_id])

	# 4) If allowed_fields is defined, strip out any junk keys
	if not allowed.is_empty():
		var filtered: Dictionary = {}
		for key in data.keys():
			if key in allowed:
				filtered[key] = data[key]
		data = filtered

	return {
		"ok": true,
		"schema_id": schema_id,
		"data": data,
		"missing": missing,
	}


static func get_default_subfolder_for_schema(schema_id: String) -> String:
	# e.g. "moves" for fighter_move, "hitboxes" for hitbox_rects, etc.
	return SCHEMA_SUBFOLDERS.get(schema_id, "configs")


static func get_default_filename(schema_id: String, data: Dictionary) -> String:
	# Prefer the move/weapon/ability name, fall back to "fighter_move" etc.
	var base: String = str(data.get("name", schema_id))

	# Normalize: lowercase, underscores, strip weird characters
	base = base.to_lower()
	base = base.replace(" ", "_")
	base = base.replace("-", "_")

	# Optional: ensure it has some prefix per schema (helps keep folders tidy)
	# You can tweak or remove this if you prefer bare names.
	match schema_id:
		"fighter_move":
			if not base.begins_with("move_"):
				base = "move_%s" % base
		"fps_weapon":
			if not base.begins_with("wpn_"):
				base = "wpn_%s" % base
		"tile_ability":
			if not base.begins_with("ability_"):
				base = "ability_%s" % base
		_:
			pass

	return "%s.json" % base
