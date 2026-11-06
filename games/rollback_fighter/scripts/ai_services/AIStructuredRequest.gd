extends RefCounted
class_name RollbackFighterAIStructuredRequest

var instruction: String = ""
var prompt: String = ""
var schema: Dictionary = {}
var temperature: float = 0.1
var max_output_tokens: int = 1024


func to_dictionary() -> Dictionary:
	return {
		"instruction": instruction,
		"prompt": prompt,
		"schema": schema.duplicate(true),
		"temperature": clampf(temperature, 0.0, 2.0),
		"max_output_tokens": maxi(max_output_tokens, 1),
	}
