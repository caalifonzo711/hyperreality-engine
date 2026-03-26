extends Node

func _ready() -> void:
	print("== GEMINI TEST START ==")

	var result: Dictionary = await Gemini.generate_json_for_schema(
		"fighter_move",
		"Create a basic jab move.",
		{}
	)

	print("Gemini result:", result)
