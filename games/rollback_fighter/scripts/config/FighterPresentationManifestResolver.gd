extends RefCounted
class_name RollbackFighterPresentationManifestResolver


const ManifestScript = preload("res://games/rollback_fighter/scripts/config/FighterPresentationManifest.gd")
const VERSION := 1
const STYLES := ["platform_fighter", "footsies", "anime_fighter", "custom"]


static func policy_reference(style_preset: String) -> String:
	if style_preset not in STYLES:
		return ""
	return "fighter_presentation:%s:v%d" % [style_preset, VERSION]


static func resolve(style_preset: String, reference: String = "") -> Dictionary:
	if style_preset not in STYLES:
		return {"ok": false, "manifest": null, "errors": [{"code": "PRESENTATION_STYLE_UNKNOWN", "file": "project.json", "field": "style_preset", "invalid_value": style_preset, "expected_rule": "must be a known presentation style"}]}
	var style: String = style_preset
	var expected: String = policy_reference(style)
	if not reference.is_empty() and reference != expected:
		return {"ok": false, "manifest": null, "errors": [{"code": "PRESENTATION_POLICY_UNKNOWN", "file": "project.json", "field": "presentation_policy_reference", "invalid_value": reference, "expected_rule": expected}]}
	var manifest: RollbackFighterPresentationManifest = ManifestScript.new()
	manifest.configure(_document(style))
	var errors: Array[Dictionary] = manifest.validate()
	return {"ok": errors.is_empty(), "manifest": manifest if errors.is_empty() else null, "errors": errors}


static func _document(style: String) -> Dictionary:
	var groups: Array[Dictionary] = []
	match style:
		"footsies":
			groups = [
				_simple_group("idle", "Idle", 2, 2, 0, "A compact, readable neutral stance."),
				_attack_group("jab", "Light / Jab", [2, 1, 2], [1, 1, 1], 1, "Show startup, contact, and recovery clearly."),
				_attack_group("heavy", "Heavy", [2, 1, 2], [1, 1, 1], 2, "Dedicated heavy phases are required for attack readability."),
				_simple_group("block", "Block", 1, 1, 3, "A clear defensive silhouette."),
				_simple_group("dodge", "Dodge", 2, 1, 4, "One required dodge pose plus an optional transition."),
				_simple_group("hit", "Hit", 1, 1, 5, "Readable hit reaction."),
				_simple_group("dead", "Defeated", 1, 1, 6, "Defeated pose."),
			]
		"anime_fighter":
			groups = [
				_simple_group("idle", "Idle", 3, 2, 0, "Extra idle drawing recommended for a livelier loop."),
				_attack_group("jab", "Light / Jab", [2, 2, 2], [1, 1, 1], 1, "Richer phase coverage without changing move timing."),
				_attack_group("heavy", "Heavy", [2, 2, 2], [1, 1, 1], 2, "Dedicated startup, active, and recovery presentation."),
				_simple_group("block", "Block", 2, 1, 3, "Optional secondary block drawing."),
				_simple_group("dodge", "Dodge", 4, 2, 4, "More drawings recommended for a fast dodge presentation."),
				_simple_group("hit", "Hit", 2, 1, 5, "Optional secondary hit reaction."),
				_simple_group("dead", "Defeated", 2, 1, 6, "Optional transition into the defeated pose."),
			]
		_:
			groups = [
				_simple_group("idle", "Idle", 3, 2, 0, "Two required idle drawings and one optional extra."),
				_attack_group("jab", "Light / Jab", [1, 1, 1], [1, 1, 0], 1, "Recovery may reuse the startup drawing."),
				_attack_group("heavy", "Heavy", [1, 1, 1], [0, 0, 0], 2, "Dedicated heavy art is optional; jab art is the fallback.", "jab"),
				_simple_group("block", "Block", 2, 1, 3, "One required block pose."),
				_simple_group("dodge", "Dodge", 3, 2, 4, "Two required dodge drawings and one optional extra."),
				_simple_group("hit", "Hit", 2, 1, 5, "One required hit reaction."),
				_simple_group("dead", "Defeated", 2, 1, 6, "One required defeated pose."),
			]
	var label: String = style.replace("_", " ").capitalize()
	return {
		"manifest_id": "%s_v%d" % [style, VERSION],
		"manifest_version": VERSION,
		"style_preset": style,
		"display_name": "%s Fighter Presentation" % label,
		"help_text": _help_text(style),
		"groups": groups,
	}


static func _simple_group(group_id: String, label: String, total: int, required: int, ordering: int, help: String) -> Dictionary:
	var slots: Array[Dictionary] = []
	for index in total:
		slots.append(_slot("%s_%d" % [group_id, index], group_id, "%s %d" % [label, index + 1], index < required, "", index, ""))
	return {"group_id": group_id, "display_name": label, "ordering": ordering, "recommended_drawing_count": total, "fallback_group": "", "help_text": help, "slots": slots}


static func _attack_group(group_id: String, label: String, totals: Array, requireds: Array, ordering: int, help: String, fallback_group: String = "") -> Dictionary:
	var slots: Array[Dictionary] = []
	var phases := ["startup", "active", "recovery"]
	for phase_index in phases.size():
		var phase: String = phases[phase_index]
		var phase_total: int = int(totals[phase_index])
		for index in phase_total:
			var fallback: String = ""
			if group_id == "jab" and phase == "recovery":
				fallback = "jab_startup_0"
			elif group_id == "heavy" and not fallback_group.is_empty():
				fallback = "jab_%s_0" % phase
			slots.append(_slot("%s_%s_%d" % [group_id, phase, index], group_id, "%s %s %d" % [label, phase.capitalize(), index + 1], index < int(requireds[phase_index]), phase, slots.size(), fallback))
	return {"group_id": group_id, "display_name": label, "ordering": ordering, "recommended_drawing_count": slots.size(), "fallback_group": fallback_group, "help_text": help, "slots": slots}


static func _slot(slot_id: String, group_id: String, label: String, required: bool, phase: String, ordering: int, fallback: String) -> Dictionary:
	return {"slot_id": slot_id, "group_id": group_id, "display_name": label, "required": required, "phase": phase, "recommended_drawing_count": 1, "fallback_slot": fallback, "ordering": ordering, "help_text": ""}


static func _help_text(style: String) -> String:
	match style:
		"footsies":
			return "Readable attack phases are emphasized. Art changes presentation only; simulation timing remains authoritative."
		"anime_fighter":
			return "A richer drawing plan is recommended while optional drawings remain non-blocking. Art does not add mechanics."
		"custom":
			return "Custom starts from the Platform Fighter presentation policy in C7. Manifest editing is deferred."
	return "The familiar nine-image minimum is preserved, with aggressive reuse of optional jab and heavy presentation."
