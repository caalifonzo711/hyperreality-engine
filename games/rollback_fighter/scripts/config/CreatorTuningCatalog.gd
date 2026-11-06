extends RefCounted
class_name RollbackFighterCreatorTuningCatalog

# This is the single AI2 whitelist and range source. The same specifications
# drive the creator's manual advanced controls, prompt schema, validation, and
# proposal application.
const FIELD_SPECS := [
	{"id": "max_hp", "label": "Max HP", "doc": "character", "section": "health", "key": "max_hp", "min": 1, "max": 500},
	{"id": "move_speed", "label": "Move Speed", "doc": "character", "section": "movement", "key": "move_speed", "min": 0, "max": 1000},
	{"id": "acceleration", "label": "Acceleration", "doc": "character", "section": "movement", "key": "acceleration", "min": 0, "max": 100000},
	{"id": "braking", "label": "Braking", "doc": "character", "section": "movement", "key": "braking", "min": 0, "max": 100000},
	{"id": "guard_max", "label": "Guard Max", "doc": "character", "section": "guard", "key": "max_units", "min": 0, "max": 2000},
	{"id": "guard_drain", "label": "Guard Drain / Frame", "doc": "character", "section": "guard", "key": "held_drain_per_frame", "min": 0, "max": 50},
	{"id": "guard_regen", "label": "Guard Recovery / Frame", "doc": "character", "section": "guard", "key": "regen_per_frame", "min": 0, "max": 50},
	{"id": "guard_break_stun", "label": "Guard Break Stun", "doc": "character", "section": "guard", "key": "break_stun_frames", "min": 0, "max": 300},
	{"id": "dodge_total", "label": "Dodge Total Frames", "doc": "character", "section": "dodge", "key": "total_frames", "min": 1, "max": 120},
	{"id": "dodge_cooldown", "label": "Dodge Cooldown", "doc": "character", "section": "dodge", "key": "cooldown_frames", "min": 0, "max": 300},
	{"id": "jab_startup", "label": "Jab Startup", "doc": "light", "section": "", "key": "startup", "min": 0, "max": 120},
	{"id": "jab_active", "label": "Jab Active", "doc": "light", "section": "", "key": "active", "min": 2, "max": 120},
	{"id": "jab_recovery", "label": "Jab Recovery", "doc": "light", "section": "", "key": "recovery", "min": 0, "max": 180},
	{"id": "jab_damage", "label": "Jab Damage", "doc": "light", "section": "", "key": "damage", "min": 0, "max": 500},
	{"id": "jab_hitstun", "label": "Jab Hitstun", "doc": "light", "section": "", "key": "hitstun", "min": 0, "max": 300},
	{"id": "jab_knockback", "label": "Jab Knockback", "doc": "light", "section": "", "key": "knockback_x", "min": 0, "max": 5000},
	{"id": "jab_cooldown", "label": "Jab Contact Cooldown", "doc": "light", "section": "", "key": "contact_cooldown", "min": 0, "max": 300},
	{"id": "heavy_startup", "label": "Heavy Startup", "doc": "heavy", "section": "", "key": "startup", "min": 0, "max": 120},
	{"id": "heavy_active", "label": "Heavy Active", "doc": "heavy", "section": "", "key": "active", "min": 1, "max": 120},
	{"id": "heavy_recovery", "label": "Heavy Recovery", "doc": "heavy", "section": "", "key": "recovery", "min": 0, "max": 180},
	{"id": "heavy_damage", "label": "Heavy Damage", "doc": "heavy", "section": "", "key": "damage", "min": 0, "max": 500},
	{"id": "heavy_hitstun", "label": "Heavy Hitstun", "doc": "heavy", "section": "", "key": "hitstun", "min": 0, "max": 300},
	{"id": "heavy_knockback", "label": "Heavy Knockback", "doc": "heavy", "section": "", "key": "knockback_x", "min": 0, "max": 5000},
	{"id": "heavy_cooldown", "label": "Heavy Contact Cooldown", "doc": "heavy", "section": "", "key": "contact_cooldown", "min": 0, "max": 300},
]


static func get_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in FIELD_SPECS:
		result.append(value.duplicate(true))
	return result


static func get_spec(field_id: String) -> Dictionary:
	for spec: Dictionary in FIELD_SPECS:
		if str(spec.id) == field_id:
			return spec.duplicate(true)
	return {}


static func get_spec_for_document(document_name: String, section: String, key: String) -> Dictionary:
	var normalized_document: String = "light" if document_name == "jab" else document_name
	for spec: Dictionary in FIELD_SPECS:
		if str(spec.doc) == normalized_document and str(spec.section) == section and str(spec.key) == key:
			return spec.duplicate(true)
	return {}


static func get_current_values(draft) -> Dictionary:
	var values: Dictionary = {}
	for spec: Dictionary in FIELD_SPECS:
		values[str(spec.id)] = get_value(draft, spec)
	return values


static func get_value(draft, spec: Dictionary) -> int:
	if str(spec.doc) == "character":
		return draft.get_character_value(str(spec.section), str(spec.key))
	return draft.get_move_value(str(spec.doc), str(spec.key))


static func get_range(draft, spec: Dictionary) -> Vector2i:
	var minimum: int = int(spec.min)
	var maximum: int = int(spec.max)
	if str(spec.id) == "guard_max":
		minimum = maxi(minimum, draft.get_character_value("guard", "break_refill_units"))
	elif str(spec.id) == "dodge_total":
		minimum = maxi(minimum, draft.get_character_value("dodge", "invuln_end") + 1)
	return Vector2i(minimum, maximum)


static func set_value(draft, field_id: String, value: int) -> bool:
	var spec: Dictionary = get_spec(field_id)
	if spec.is_empty():
		return false
	var allowed: Vector2i = get_range(draft, spec)
	var safe_value: int = clampi(value, allowed.x, allowed.y)
	if str(spec.doc) == "character":
		var section: Dictionary = draft.character_document.get(str(spec.section), {})
		section[str(spec.key)] = safe_value
		draft.character_document[str(spec.section)] = section
	else:
		var move: Dictionary = draft.move_documents.get(str(spec.doc), {})
		move[str(spec.key)] = safe_value
		draft.move_documents[str(spec.doc)] = move
	return true


static func schema_for(draft) -> Dictionary:
	var properties: Dictionary = {}
	for spec: Dictionary in FIELD_SPECS:
		var allowed: Vector2i = get_range(draft, spec)
		properties[str(spec.id)] = {
			"type": "integer",
			"minimum": allowed.x,
			"maximum": allowed.y,
			"description": str(spec.label),
		}
	return {
		"type": "object",
		"additionalProperties": false,
		"properties": {
			"reason": {"type": "string"},
			"unsupported_note": {"type": "string"},
			"values": {
				"type": "object",
				"additionalProperties": false,
				"properties": properties,
			},
		},
		"required": ["reason", "values"],
	}


static func prompt_ranges(draft) -> Dictionary:
	var ranges: Dictionary = {}
	for spec: Dictionary in FIELD_SPECS:
		var allowed: Vector2i = get_range(draft, spec)
		ranges[str(spec.id)] = {"label": str(spec.label), "min": allowed.x, "max": allowed.y}
	return ranges
