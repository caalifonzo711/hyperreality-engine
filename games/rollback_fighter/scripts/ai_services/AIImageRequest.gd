extends RefCounted
class_name RollbackFighterAIImageRequest

var prompt: String = ""
var width: int = 1024
var height: int = 1024
var aspect_ratio: String = "1:1"
var transparent_background: bool = false
var output_count: int = 1
var reference_images: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	return {
		"prompt": prompt,
		"width": maxi(width, 1),
		"height": maxi(height, 1),
		"aspect_ratio": aspect_ratio,
		"transparent_background": transparent_background,
		"output_count": 1,
		"reference_images": reference_images.duplicate(true),
	}
