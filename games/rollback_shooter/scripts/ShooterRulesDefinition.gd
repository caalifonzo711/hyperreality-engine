extends RefCounted
class_name RollbackShooterRulesDefinition

const CONFIG_VERSION: int = 1
const REQUIRED_FIELDS := [
	"simulation_hz", "arena_width", "arena_height", "player_hp",
	"move_speed_px_per_second", "player_half_extent", "projectile_half_extent",
	"projectile_speed_px_per_frame", "projectile_damage", "fire_cooldown_frames",
	"projectile_lifetime_frames", "spawn_p1_x", "spawn_p1_y", "spawn_p2_x", "spawn_p2_y",
]

var _values: Dictionary = {}


func load_from_resource(path: String = "res://games/rollback_shooter/config/shooter_rules.json") -> Dictionary:
	_values.clear()
	if not path.begins_with("res://") or path.contains("..") or path.contains("\\"):
		return {"ok": false, "error": "Rules path must be a safe res:// resource."}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Shooter rules resource is missing."}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Shooter rules resource could not be opened."}
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not (parser.data is Dictionary):
		return {"ok": false, "error": "Shooter rules JSON is invalid."}
	var source: Dictionary = parser.data
	if source.size() != REQUIRED_FIELDS.size() + 1 or source.get("config_version", -1) != 1:
		return {"ok": false, "error": "Shooter rules schema version or fields are invalid."}
	for field in REQUIRED_FIELDS:
		if not source.has(field) or not _is_exact_integer(source[field]):
			return {"ok": false, "error": "Shooter rule must be an exact integer: %s" % field}
		_values[field] = int(source[field])
	if int(_values["simulation_hz"]) != 60:
		return {"ok": false, "error": "T1 requires simulation_hz=60."}
	for field in REQUIRED_FIELDS:
		if field not in ["spawn_p1_x", "spawn_p1_y", "spawn_p2_x", "spawn_p2_y"] and int(_values[field]) <= 0:
			return {"ok": false, "error": "Shooter rule must be positive: %s" % field}
	if int(_values["spawn_p1_x"]) >= int(_values["arena_width"]) or int(_values["spawn_p2_x"]) >= int(_values["arena_width"]):
		return {"ok": false, "error": "Shooter spawn positions must be inside the arena."}
	return {"ok": true, "definition": self}


func get_int(field: String) -> int:
	return int(_values.get(field, 0))


func get_ordered_values() -> Array[int]:
	var values: Array[int] = [CONFIG_VERSION]
	for field in REQUIRED_FIELDS:
		values.append(int(_values[field]))
	return values


func _is_exact_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		return is_finite(number) and floorf(number) == number
	return false
