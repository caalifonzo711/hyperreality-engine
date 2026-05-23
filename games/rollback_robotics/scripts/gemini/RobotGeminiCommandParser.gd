extends Node
class_name RobotGeminiCommandParser

signal command_parsed(command: Dictionary)

var allowed_actions := ["idle", "jab", "heavy", "block", "grab", "wave"]
var allowed_profiles := ["snappy", "heavy", "defensive", "dramatic"]

func parse_text_command(text: String, frame: int = 0, player_id: int = 1) -> Dictionary:
	var lower := text.to_lower()

	var action := _extract_action(lower)
	var profile := _extract_profile(lower)

	var command := {
		"frame": frame,
		"player_id": player_id,
		"action": action,
		"profile": profile,
		"intensity": _extract_intensity(lower),
		"source": "gemini_parser_fallback",
		"raw_text": text
	}

	command_parsed.emit(command)
	return command

func parse_gemini_response(response_text: String, frame: int = 0, player_id: int = 1) -> Dictionary:
	var parsed := _try_parse_json(response_text)

	if parsed.is_empty():
		return parse_text_command(response_text, frame, player_id)

	var action := str(parsed.get("action", "wave")).to_lower()
	var profile := str(parsed.get("profile", "snappy")).to_lower()

	if not allowed_actions.has(action):
		action = "wave"

	if not allowed_profiles.has(profile):
		profile = "snappy"

	var command := {
		"frame": frame,
		"player_id": player_id,
		"action": action,
		"profile": profile,
		"intensity": clamp(float(parsed.get("intensity", 1.0)), 0.1, 1.0),
		"source": "gemini",
		"raw_text": response_text
	}

	command_parsed.emit(command)
	return command

func build_gemini_prompt(user_text: String) -> String:
	return """
You are controlling a safe robotics interaction demo.

Convert the user's request into JSON only.

Allowed actions:
- idle
- jab
- heavy
- block
- grab
- wave

Allowed profiles:
- snappy
- heavy
- defensive
- dramatic

Rules:
- Do not invent new actions.
- Do not output motor values.
- Do not output joint angles.
- Do not output explanations.
- Return JSON only.

Schema:
{
  "action": "jab",
  "profile": "snappy",
  "intensity": 1.0
}

User request:
%s
""" % user_text

func _try_parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)

	if err != OK:
		return {}

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		return {}

	return data

func _extract_action(lower: String) -> String:
	if "jab" in lower or "punch" in lower or "strike" in lower or "light" in lower:
		return "jab"

	if "heavy" in lower or "strong" in lower or "slam" in lower:
		return "heavy"

	if "block" in lower or "guard" in lower or "defend" in lower or "shield" in lower:
		return "block"

	if "grab" in lower or "clamp" in lower or "hold" in lower:
		return "grab"

	if "wave" in lower or "hello" in lower or "greet" in lower:
		return "wave"

	if "idle" in lower or "stop" in lower or "rest" in lower:
		return "idle"

	return "wave"

func _extract_profile(lower: String) -> String:
	if "dramatic" in lower or "theatrical" in lower or "expressive" in lower:
		return "dramatic"

	if "defensive" in lower or "safe" in lower or "careful" in lower or "cautious" in lower:
		return "defensive"

	if "heavy" in lower or "strong" in lower or "powerful" in lower:
		return "heavy"

	if "snappy" in lower or "fast" in lower or "quick" in lower or "instant" in lower:
		return "snappy"

	return "snappy"

func _extract_intensity(lower: String) -> float:
	if "gentle" in lower or "soft" in lower:
		return 0.4

	if "medium" in lower or "normal" in lower:
		return 0.7

	if "hard" in lower or "full" in lower or "max" in lower:
		return 1.0

	return 1.0
