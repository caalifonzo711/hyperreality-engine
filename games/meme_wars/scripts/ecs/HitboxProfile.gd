extends RefCounted
class_name HitboxProfile

var animation: String = ""
var frames: Dictionary = {}


func load_from_file(path: String) -> bool:
	frames.clear()
	animation = ""

	if not FileAccess.file_exists(path):
		push_warning("[HitboxProfile] File not found: " + path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[HitboxProfile] Could not open: " + path)
		return false

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)

	if parsed == null or not (parsed is Dictionary):
		push_warning("[HitboxProfile] Invalid JSON: " + path)
		return false

	var data: Dictionary = parsed

	# -------------------------------------------------
	# NEW FORMAT
	#
	# {
	#   "animation": "jab",
	#   "frames": [
	#     {
	#       "index": 0,
	#       "hitboxes": [...],
	#       "hurtboxes": [...]
	#     }
	#   ]
	# }
	# -------------------------------------------------

	if data.has("frames") and data["frames"] is Array:
		animation = str(
			data.get(
				"animation",
				data.get("move_id", path.get_file().get_basename())
			)
		)

		for frame_variant in data["frames"]:
			if not (frame_variant is Dictionary):
				continue

			var frame_data: Dictionary = frame_variant

			var frame_index := int(
				frame_data.get(
					"index",
					frame_data.get("frame", 0)
				)
			)

			_ensure_frame(frame_index)

			if frame_data.has("hitboxes") and frame_data["hitboxes"] is Array:
				for box_variant in frame_data["hitboxes"]:
					if box_variant is Dictionary:
						frames[frame_index]["hitboxes"].append(
							_normalize_box(box_variant)
						)

			if frame_data.has("hurtboxes") and frame_data["hurtboxes"] is Array:
				for box_variant in frame_data["hurtboxes"]:
					if box_variant is Dictionary:
						frames[frame_index]["hurtboxes"].append(
							_normalize_box(box_variant)
						)

		print(
			"[HitboxProfile] Loaded ",
			animation,
			" | frames=",
			frames.size()
		)

		return true

	# -------------------------------------------------
	# OLD FORMAT SUPPORT
	#
	# {
	#   "move_id": "jab",
	#   "boxes": [
	#     {
	#       "frame": 1,
	#       "type": "hit",
	#       "x": 30,
	#       "y": -40,
	#       "w": 40,
	#       "h": 20
	#     }
	#   ]
	# }
	#
	# We support this so you DO NOT need to redo your
	# existing jab.json before testing.
	# -------------------------------------------------

	if data.has("boxes") and data["boxes"] is Array:
		animation = str(
			data.get(
				"move_id",
				path.get_file().get_basename()
			)
		)

		for box_variant in data["boxes"]:
			if not (box_variant is Dictionary):
				continue

			var box_data: Dictionary = box_variant

			var frame_index := int(
				box_data.get("frame", 0)
			)

			var box_type := str(
				box_data.get("type", "hit")
			).to_lower()

			_ensure_frame(frame_index)

			var normalized := _normalize_box(box_data)

			if box_type == "hurt" or box_type == "hurtbox":
				frames[frame_index]["hurtboxes"].append(normalized)
			else:
				frames[frame_index]["hitboxes"].append(normalized)

		print(
			"[HitboxProfile] Loaded OLD FORMAT ",
			animation,
			" | frames=",
			frames.size()
		)

		return true

	push_warning(
		"[HitboxProfile] No recognized frame/box data in: " + path
	)

	return false


func get_hitboxes(frame_index: int) -> Array:
	if not frames.has(frame_index):
		return []

	return frames[frame_index]["hitboxes"]


func get_hurtboxes(frame_index: int) -> Array:
	if not frames.has(frame_index):
		return []

	return frames[frame_index]["hurtboxes"]


func has_hitboxes(frame_index: int) -> bool:
	return (
		frames.has(frame_index)
		and not frames[frame_index]["hitboxes"].is_empty()
	)


func _ensure_frame(frame_index: int) -> void:
	if frames.has(frame_index):
		return

	frames[frame_index] = {
		"hitboxes": [],
		"hurtboxes": []
	}


func _normalize_box(data: Dictionary) -> Dictionary:
	# Convert editor floats to integer simulation-space values.
	#
	# This gives the runtime predictable, cheap geometry even if
	# the editor itself uses Rect2 / mouse coordinates.

	return {
		"x": roundi(float(data.get("x", 0))),
		"y": roundi(float(data.get("y", 0))),
		"w": maxi(
			1,
			roundi(float(data.get("w", 1)))
		),
		"h": maxi(
			1,
			roundi(float(data.get("h", 1)))
		)
	}
