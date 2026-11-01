extends RefCounted
class_name RollbackFighterXRPresentationSettings

const DEFAULT_DISTANCE_M := 2.0
const DEFAULT_VERTICAL_OFFSET_M := -0.45
const DEFAULT_DISPLAY_SCALE := 1.0

const MIN_DISTANCE_M := 0.75
const MAX_DISTANCE_M := 5.0
const MIN_VERTICAL_OFFSET_M := -2.0
const MAX_VERTICAL_OFFSET_M := 2.0
const MIN_DISPLAY_SCALE := 0.25
const MAX_DISPLAY_SCALE := 3.0

var distance_m: float = DEFAULT_DISTANCE_M:
	set(value):
		distance_m = clampf(value, MIN_DISTANCE_M, MAX_DISTANCE_M)

var vertical_offset_m: float = DEFAULT_VERTICAL_OFFSET_M:
	set(value):
		vertical_offset_m = clampf(value, MIN_VERTICAL_OFFSET_M, MAX_VERTICAL_OFFSET_M)

var display_scale: float = DEFAULT_DISPLAY_SCALE:
	set(value):
		display_scale = clampf(value, MIN_DISPLAY_SCALE, MAX_DISPLAY_SCALE)


func reset_to_defaults() -> void:
	distance_m = DEFAULT_DISTANCE_M
	vertical_offset_m = DEFAULT_VERTICAL_OFFSET_M
	display_scale = DEFAULT_DISPLAY_SCALE
