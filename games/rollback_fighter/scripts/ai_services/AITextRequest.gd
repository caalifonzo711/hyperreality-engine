extends RefCounted
class_name RollbackFighterAITextRequest

var instruction: String = ""
var prompt: String = ""
var temperature: float = 0.2
var max_output_tokens: int = 1024


func to_dictionary() -> Dictionary:
	return {
		"instruction": instruction,
		"prompt": prompt,
		"temperature": clampf(temperature, 0.0, 2.0),
		"max_output_tokens": maxi(max_output_tokens, 1),
	}
