extends Node
class_name FighterMoveImporter

var default_action_map := {
	"move_light_punch": "jab",
	"light_punch": "jab",
	"jab": "jab",

	"move_strong_punch": "heavy",
	"strong_punch": "heavy",
	"heavy": "heavy",

	"block": "block",
	"guard": "block",

	"grab": "grab",
	"throw": "grab",

	"wave": "wave"
}

func import_move_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("FighterMoveImporter: file not found: " + path)
		return _fallback_action("wave")

	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)

	if err != OK:
		push_warning("FighterMoveImporter: JSON parse failed: " + path)
		return _fallback_action("wave")

	if typeof(json.data) != TYPE_DICTIONARY:
		push_warning("FighterMoveImporter: JSON root was not dictionary: " + path)
		return _fallback_action("wave")

	return import_move_data(json.data, path)

func import_move_data(move_data: Dictionary, source_path: String = "") -> Dictionary:
	var source_name := _get_source_name(move_data, source_path)
	var robot_action := _map_to_robot_action(source_name)

	var startup := _extract_int(move_data, [
		"startup",
		"startup_frames",
		"startupFrames"
	], 4)

	var active := _extract_int(move_data, [
		"active",
		"active_frames",
		"activeFrames"
	], 3)

	var recovery := _extract_int(move_data, [
		"recovery",
		"recovery_frames",
		"recoveryFrames"
	], 10)

	var imported := {
		"name": robot_action,
		"source_name": source_name,
		"source_path": source_path,
		"startup_frames": clamp(startup, 1, 30),
		"active_frames": clamp(active, 1, 30),
		"recovery_frames": clamp(recovery, 1, 45),
		"motion_id": "%s_motion" % robot_action,
		"can_cancel_into": _extract_cancel_list(move_data),
		"imported_from_fighter": true
	}

	return imported

func import_many(paths: Array[String]) -> Dictionary:
	var actions := {}

	for path in paths:
		var action := import_move_file(path)
		actions[action["name"]] = action

	return actions

func build_default_robot_actions() -> Dictionary:
	return {
		"jab": {
			"name": "jab",
			"source_name": "default_jab",
			"startup_frames": 4,
			"active_frames": 3,
			"recovery_frames": 10,
			"motion_id": "jab_motion",
			"can_cancel_into": ["block"],
			"imported_from_fighter": false
		},
		"heavy": {
			"name": "heavy",
			"source_name": "default_heavy",
			"startup_frames": 10,
			"active_frames": 5,
			"recovery_frames": 20,
			"motion_id": "heavy_motion",
			"can_cancel_into": [],
			"imported_from_fighter": false
		},
		"block": {
			"name": "block",
			"source_name": "default_block",
			"startup_frames": 2,
			"active_frames": 12,
			"recovery_frames": 4,
			"motion_id": "block_motion",
			"can_cancel_into": ["jab"],
			"imported_from_fighter": false
		},
		"grab": {
			"name": "grab",
			"source_name": "default_grab",
			"startup_frames": 8,
			"active_frames": 6,
			"recovery_frames": 14,
			"motion_id": "grab_motion",
			"can_cancel_into": [],
			"imported_from_fighter": false
		},
		"wave": {
			"name": "wave",
			"source_name": "default_wave",
			"startup_frames": 6,
			"active_frames": 12,
			"recovery_frames": 8,
			"motion_id": "wave_motion",
			"can_cancel_into": [],
			"imported_from_fighter": false
		}
	}

func _get_source_name(move_data: Dictionary, source_path: String) -> String:
	if move_data.has("name"):
		return str(move_data["name"]).to_lower()

	if move_data.has("move_name"):
		return str(move_data["move_name"]).to_lower()

	if source_path != "":
		var file_name := source_path.get_file().get_basename()
		return file_name.to_lower()

	return "unknown_move"

func _map_to_robot_action(source_name: String) -> String:
	var normalized := source_name.to_lower()

	if default_action_map.has(normalized):
		return default_action_map[normalized]

	if "light" in normalized or "jab" in normalized:
		return "jab"

	if "strong" in normalized or "heavy" in normalized:
		return "heavy"

	if "block" in normalized or "guard" in normalized:
		return "block"

	if "grab" in normalized or "throw" in normalized:
		return "grab"

	return "wave"

func _extract_int(data: Dictionary, keys: Array[String], fallback: int) -> int:
	for key in keys:
		if data.has(key):
			return int(data[key])

	if data.has("timing") and typeof(data["timing"]) == TYPE_DICTIONARY:
		var timing: Dictionary = data["timing"]
		for key in keys:
			if timing.has(key):
				return int(timing[key])

	if data.has("frames") and typeof(data["frames"]) == TYPE_DICTIONARY:
		var frames: Dictionary = data["frames"]
		for key in keys:
			if frames.has(key):
				return int(frames[key])

	return fallback

func _extract_cancel_list(data: Dictionary) -> Array[String]:
	var result: Array[String] = []

	if data.has("can_cancel_into") and typeof(data["can_cancel_into"]) == TYPE_ARRAY:
		for item in data["can_cancel_into"]:
			result.append(_map_to_robot_action(str(item)))
		return result

	if data.has("cancels") and typeof(data["cancels"]) == TYPE_ARRAY:
		for item in data["cancels"]:
			result.append(_map_to_robot_action(str(item)))
		return result

	return result

func _fallback_action(action_name: String) -> Dictionary:
	return {
		"name": action_name,
		"source_name": "fallback_" + action_name,
		"source_path": "",
		"startup_frames": 6,
		"active_frames": 8,
		"recovery_frames": 8,
		"motion_id": "%s_motion" % action_name,
		"can_cancel_into": [],
		"imported_from_fighter": false
	}
