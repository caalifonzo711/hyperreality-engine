extends Node
class_name HapticsAdapter

signal haptic_triggered(event_name: String, strength: float, duration_ms: int)

@export var enabled: bool = true

var last_event: String = ""
var last_strength: float = 0.0

func trigger_event(event_name: String, strength: float = 0.6, duration_ms: int = 120) -> void:
	if not enabled:
		return

	strength = clamp(strength, 0.0, 1.0)

	last_event = event_name
	last_strength = strength

	print("HAPTIC:", event_name, " strength=", strength, " duration_ms=", duration_ms)

	haptic_triggered.emit(event_name, strength, duration_ms)

func on_action_started(action_data: Dictionary) -> void:
	var action := str(action_data.get("name", "idle"))

	match action:
		"jab":
			trigger_event("jab_start", 0.35, 80)
		"heavy":
			trigger_event("heavy_windup", 0.55, 140)
		"block":
			trigger_event("block_guard", 0.25, 100)
		"grab":
			trigger_event("grab_start", 0.45, 120)
		"wave":
			trigger_event("wave_motion", 0.2, 80)
		_:
			trigger_event("idle", 0.05, 40)

func on_phase_changed(action_name: String, phase: String) -> void:
	match phase:
		"startup":
			trigger_event("%s_startup" % action_name, 0.25, 60)
		"active":
			trigger_event("%s_active" % action_name, 0.75, 120)
		"recovery":
			trigger_event("%s_recovery" % action_name, 0.15, 60)

func on_action_finished(action_data: Dictionary) -> void:
	var action := str(action_data.get("name", "idle"))
	trigger_event("%s_finished" % action, 0.1, 50)

func on_remote_prediction() -> void:
	trigger_event("remote_prediction", 0.2, 50)

func on_rollback_correction() -> void:
	trigger_event("rollback_correction", 0.9, 160)

func on_clash() -> void:
	trigger_event("robot_clash", 1.0, 200)

func stop_all() -> void:
	print("HAPTIC STOP ALL")
	last_event = ""
	last_strength = 0.0
