extends RefCounted
class_name RollbackFighterAIFighterTuningAssistant

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const StructuredRequestScript = preload("res://games/rollback_fighter/scripts/ai_services/AIStructuredRequest.gd")
const Catalog = preload("res://games/rollback_fighter/scripts/config/CreatorTuningCatalog.gd")
const ProposalScript = preload("res://games/rollback_fighter/scripts/config/AIFighterTuningProposal.gd")


func request_proposal(ai_service: Node, draft, description: String, style_preset: String) -> Dictionary:
	if ai_service == null:
		return _failure(Contracts.ERROR_NOT_CONFIGURED, "AI assistance is unavailable.")
	if not bool(ai_service.call("supports", Contracts.CAPABILITY_STRUCTURED_OUTPUT)):
		return _failure(Contracts.ERROR_UNSUPPORTED_CAPABILITY, "This AI provider does not support structured fighter tuning.")
	var clean_description: String = description.strip_edges()
	if clean_description.is_empty():
		return _failure("INVALID_REQUEST", "Describe how you want the fighter to feel first.")
	var request = build_request(draft, clean_description, style_preset)
	var result_value: Variant = await ai_service.call("generate_structured", request)
	if not result_value is Dictionary:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned an invalid response.")
	var result: Dictionary = result_value
	if not bool(result.get("success", false)):
		return result
	var parsed: Dictionary = ProposalScript.from_dictionary(result.get("json_output", null), draft)
	if not bool(parsed.get("ok", false)):
		return {
			"success": false,
			"error_code": Contracts.ERROR_INVALID_RESPONSE,
			"user_message": str(parsed.get("message", "The AI tuning response was invalid.")),
		}
	return {
		"success": true,
		"error_code": "",
		"user_message": "Tuning proposal ready.",
		"proposal": parsed.proposal,
	}


func build_request(draft, description: String, style_preset: String):
	var request = StructuredRequestScript.new()
	request.instruction = "You are a fighting-game creator tuning assistant. Use only the supplied integer fields. Do not invent mechanics, scripts, moves, files, or project changes. Stay within every supplied range. Translate subjective feel into supported values, briefly explain the intent, and return only schema-compliant structured data. If the request mentions unsupported mechanics, approximate the feel with supported values and set unsupported_note."
	var context := {
		"fighter_display_name": draft.fighter_name,
		"fighter_visual_description": draft.visual_description,
		"style_preset": style_preset,
		"requested_feel": description,
		"current_values": Catalog.get_current_values(draft),
		"supported_fields_and_ranges": Catalog.prompt_ranges(draft),
	}
	request.prompt = "Propose fighter tuning from this creator context:\n%s" % JSON.stringify(context)
	request.schema = Catalog.schema_for(draft)
	request.temperature = 0.2
	request.max_output_tokens = 2048
	return request


func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "user_message": message}
