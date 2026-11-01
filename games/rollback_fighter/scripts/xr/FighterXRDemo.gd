extends Node3D
class_name RollbackFighterXRDemo

const XR_PRESENTATION_SETTINGS_SCRIPT := preload("res://games/rollback_fighter/scripts/xr/XRPresentationSettings.gd")
const DISTANCE_STEP_M := 0.25
const HEIGHT_STEP_M := 0.10
const SCALE_STEP := 0.10
const DEFAULT_FIGHTER_ID := "example_fighter"

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var desktop_camera: Camera3D = $DesktopCamera3D
@onready var fighter_stage: Node3D = $FighterStage
@onready var match_viewport: SubViewport = $FighterStage/MatchViewport
@onready var match_display: MeshInstance3D = $FighterStage/MatchDisplay
@onready var presentation_label: Label = $DebugOverlay/PresentationLabel

var _presentation_settings = XR_PRESENTATION_SETTINGS_SCRIPT.new()
var _xr_interface
var _openxr_available: bool = false
var _xr_active: bool = false
var _initialized_xr_here: bool = false
var _passthrough_supported: bool = false
var _passthrough_enabled: bool = false
var _previous_environment_blend_mode: int = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
var _stage_placed: bool = false
var _stage_placement_count: int = 0


func _enter_tree() -> void:
	# FighterArena consumes this one-shot launch config during its own _ready().
	# Both fighters use the existing built-in definition; P2 remains the existing CPU.
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config != null:
		launch_config.call("set_single_player")
		launch_config.call(
			"set_fighter_selection", DEFAULT_FIGHTER_ID, DEFAULT_FIGHTER_ID
		)


func _ready() -> void:
	_configure_match_surface()
	_xr_active = _initialize_xr()
	xr_camera.current = _xr_active
	desktop_camera.current = not _xr_active
	_configure_xr_background()
	_detect_passthrough_capability()
	# Wait one frame so OpenXR can provide its initial tracked camera pose. Placement
	# occurs once only; later headset transforms affect the camera, never the stage.
	await get_tree().process_frame
	_place_stage_once()
	_update_debug_overlay()


func _initialize_xr() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	_xr_interface = XRServer.find_interface("OpenXR")
	_openxr_available = _xr_interface != null
	if _xr_interface == null:
		push_warning("[FighterXRDemo] OpenXR is unavailable; using desktop camera fallback.")
		return false
	if not bool(_xr_interface.call("is_initialized")):
		if not bool(_xr_interface.call("initialize")):
			push_warning("[FighterXRDemo] OpenXR initialization failed; using desktop camera fallback.")
			return false
		_initialized_xr_here = true
	get_viewport().use_xr = true
	return true


func _configure_xr_background() -> void:
	# Transparent output is isolated to this explicit XR scene. Desktop fallback
	# keeps the neutral environment, and _exit_tree restores the root viewport.
	get_viewport().transparent_bg = _xr_active


func _detect_passthrough_capability() -> void:
	var supported_modes: Array = []
	_passthrough_supported = (
		_xr_active
		and _xr_interface != null
		and _xr_interface.has_method("get_supported_environment_blend_modes")
		and _xr_interface.has_method("get_environment_blend_mode")
		and _xr_interface.has_method("set_environment_blend_mode")
	)
	if _passthrough_supported:
		supported_modes = _xr_interface.call(
			"get_supported_environment_blend_modes"
		)
		_passthrough_supported = (
			XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in supported_modes
		)
	_passthrough_enabled = false
	if _passthrough_supported:
		var active_mode := int(
			_xr_interface.call("get_environment_blend_mode")
		)
		_previous_environment_blend_mode = active_mode
		if active_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
			if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in supported_modes:
				_previous_environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in supported_modes:
				_previous_environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		set_passthrough_enabled(true)


func _configure_match_surface() -> void:
	if DisplayServer.get_name() == "headless":
		match_display.visible = false
		match_display.mesh = null
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = match_viewport.get_texture()
	match_display.material_override = material


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			recenter_stage()
		KEY_BRACKETLEFT:
			set_distance_m(_presentation_settings.distance_m - DISTANCE_STEP_M)
		KEY_BRACKETRIGHT:
			set_distance_m(_presentation_settings.distance_m + DISTANCE_STEP_M)
		KEY_PAGEUP:
			set_vertical_offset_m(_presentation_settings.vertical_offset_m + HEIGHT_STEP_M)
		KEY_PAGEDOWN:
			set_vertical_offset_m(_presentation_settings.vertical_offset_m - HEIGHT_STEP_M)
		KEY_EQUAL, KEY_KP_ADD:
			set_display_scale(_presentation_settings.display_scale + SCALE_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_display_scale(_presentation_settings.display_scale - SCALE_STEP)
		KEY_0, KEY_KP_0:
			reset_presentation_settings()
		KEY_P:
			set_passthrough_enabled(not _passthrough_enabled)
		_:
			return
	get_viewport().set_input_as_handled()


func _place_stage_once() -> void:
	if _stage_placed:
		return
	recenter_stage()


func recenter_stage() -> void:
	var view_camera: Camera3D = get_active_view_camera()
	var camera_transform: Transform3D = view_camera.global_transform
	var forward: Vector3 = -camera_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var stage_position: Vector3 = (
		camera_transform.origin
		+ forward * _presentation_settings.distance_m
		+ Vector3.UP * _presentation_settings.vertical_offset_m
	)
	fighter_stage.global_position = stage_position
	var horizontal_camera_position := Vector3(
		camera_transform.origin.x,
		stage_position.y,
		camera_transform.origin.z
	)
	fighter_stage.look_at(horizontal_camera_position, Vector3.UP, true)
	fighter_stage.scale = Vector3.ONE * _presentation_settings.display_scale
	_stage_placed = true
	_stage_placement_count += 1
	_update_debug_overlay()


func reset_presentation_settings() -> void:
	_presentation_settings.reset_to_defaults()
	recenter_stage()


func set_distance_m(value: float) -> void:
	_presentation_settings.distance_m = value
	recenter_stage()


func set_vertical_offset_m(value: float) -> void:
	_presentation_settings.vertical_offset_m = value
	recenter_stage()


func set_display_scale(value: float) -> void:
	_presentation_settings.display_scale = value
	recenter_stage()


func get_presentation_settings():
	return _presentation_settings


func get_active_view_camera() -> Camera3D:
	return xr_camera if _xr_active else desktop_camera


func set_passthrough_enabled(enabled: bool) -> bool:
	if not _passthrough_supported or _xr_interface == null:
		_passthrough_enabled = false
		_update_debug_overlay()
		return false
	var requested_mode := (
		XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		if enabled
		else _previous_environment_blend_mode
	)
	var mode_changed := bool(_xr_interface.call(
		"set_environment_blend_mode", requested_mode
	))
	var active_mode := int(_xr_interface.call("get_environment_blend_mode"))
	_passthrough_enabled = (
		active_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	)
	_update_debug_overlay()
	return mode_changed and _passthrough_enabled == enabled


func is_openxr_available() -> bool:
	return _openxr_available


func is_passthrough_supported() -> bool:
	return _passthrough_supported


func is_passthrough_enabled() -> bool:
	return _passthrough_enabled


func _passthrough_status_text() -> String:
	if not _xr_active:
		return "N/A"
	if not _passthrough_supported:
		return "Unsupported"
	return "Enabled" if _passthrough_enabled else "Supported (disabled)"


func _xr_mode_status_text() -> String:
	if _xr_active:
		return "OpenXR"
	if _openxr_available:
		return "Desktop fallback (OpenXR inactive)"
	return "Desktop fallback (OpenXR unavailable)"


func _update_debug_overlay() -> void:
	if not is_instance_valid(presentation_label):
		return
	presentation_label.visible = OS.is_debug_build()
	presentation_label.text = (
		"XR Presentation\n"
		+ "XR Mode: %s\n" % _xr_mode_status_text()
		+ "Passthrough: %s\n" % _passthrough_status_text()
		+ "Stage: World anchored\n"
		+ "Distance: %.2fm\n" % _presentation_settings.distance_m
		+ "Height: %.2fm\n" % _presentation_settings.vertical_offset_m
		+ "Scale: %.2fx\n" % _presentation_settings.display_scale
		+ "R Recenter | [ ] Distance | PgUp/PgDn Height | -/+ Scale | 0 Reset | P Passthrough"
	)


func is_xr_active() -> bool:
	return _xr_active


func is_stage_placed() -> bool:
	return _stage_placed


func get_stage_placement_count() -> int:
	return _stage_placement_count


func _exit_tree() -> void:
	if _passthrough_enabled:
		set_passthrough_enabled(false)
	if get_viewport() != null:
		get_viewport().transparent_bg = false
	if get_viewport() != null and _xr_active:
		get_viewport().use_xr = false
	if _initialized_xr_here and _xr_interface != null:
		_xr_interface.call("uninitialize")
