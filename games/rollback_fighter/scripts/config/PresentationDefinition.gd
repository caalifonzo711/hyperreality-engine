extends RefCounted
class_name RollbackFighterPresentationDefinition


var _data: Dictionary
var _texture_cache: Dictionary = {}


func _init(data: Dictionary) -> void:
	_data = data.duplicate(true)


func get_source_art_faces() -> String:
	return str(_data["source_art_faces"])


func get_animation(animation_id: String) -> Dictionary:
	var animations: Dictionary = _data["animations"]
	if not animations.has(animation_id):
		return {}
	return Dictionary(animations[animation_id]).duplicate(true)


func get_animation_ids() -> PackedStringArray:
	var result := PackedStringArray()
	var animations: Dictionary = _data["animations"]
	var ids: Array = animations.keys()
	ids.sort()
	for animation_id in ids:
		result.append(str(animation_id))
	return result


func get_state_animation_id(state_id: String) -> String:
	var state_map: Dictionary = _data["state_to_animation"]
	return str(state_map.get(state_id, ""))


func get_attack_phase_frames(animation_id: String, phase: String) -> Array[int]:
	var result: Array[int] = []
	var phase_maps: Dictionary = _data["attack_phase_to_frames"]
	if not phase_maps.has(animation_id):
		return result
	var phase_map: Dictionary = phase_maps[animation_id]
	var values: Variant = phase_map.get(phase)
	if not values is Array:
		return result
	for value in values:
		result.append(int(value))
	return result


func get_data() -> Dictionary:
	return _data.duplicate(true)


func get_texture(sprite_path: String) -> Texture2D:
	if _texture_cache.has(sprite_path):
		return _texture_cache[sprite_path] as Texture2D
	var result: Texture2D = null
	if sprite_path.begins_with("user://"):
		var image: Image = Image.new()
		if FileAccess.file_exists(sprite_path) and image.load(sprite_path) == OK and not image.is_empty():
			result = ImageTexture.create_from_image(image)
	else:
		result = ResourceLoader.load(sprite_path) as Texture2D
	if result != null:
		_texture_cache[sprite_path] = result
	return result
