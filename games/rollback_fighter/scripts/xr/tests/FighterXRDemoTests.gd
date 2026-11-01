extends SceneTree

const XR_DEMO_PATH := "res://games/rollback_fighter/scenes/FighterXRDemo.tscn"
const XR_PRESENTATION_SETTINGS_SCRIPT := preload("res://games/rollback_fighter/scripts/xr/XRPresentationSettings.gd")


class FakePassthroughInterface:
	extends RefCounted

	var blend_mode := XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	var start_count := 0
	var stop_count := 0

	func get_supported_environment_blend_modes() -> Array:
		return [
			XRInterface.XR_ENV_BLEND_MODE_OPAQUE,
			XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND,
		]

	func get_environment_blend_mode() -> int:
		return blend_mode

	func set_environment_blend_mode(mode: int) -> bool:
		blend_mode = mode
		if mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
			start_count += 1
		else:
			stop_count += 1
		return true


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_test_presentation_settings()

	var packed: PackedScene = load(XR_DEMO_PATH)
	assert(packed != null)
	var demo: Node3D = packed.instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame

	var origin: XROrigin3D = demo.get_node("XROrigin3D")
	var tracked_camera: XRCamera3D = demo.get_node("XROrigin3D/XRCamera3D")
	var desktop_camera: Camera3D = demo.get_node("DesktopCamera3D")
	var stage: Node3D = demo.get_node("FighterStage")
	var arena: Node = demo.get_node("FighterStage/MatchViewport/FighterArena")
	var settings = demo.call("get_presentation_settings")
	assert(origin != null)
	assert(tracked_camera != null)
	assert(stage.get_parent() == demo)
	assert(not tracked_camera.is_ancestor_of(stage))
	assert(not origin.is_ancestor_of(stage))
	assert(not bool(demo.call("is_xr_active")))
	assert(not bool(demo.call("is_openxr_available")))
	assert(not bool(demo.call("is_passthrough_supported")))
	assert(not bool(demo.call("is_passthrough_enabled")))
	assert(not bool(demo.call("set_passthrough_enabled", true)))
	assert(not root.transparent_bg)
	assert(desktop_camera.current)
	assert(demo.call("get_active_view_camera") == desktop_camera)
	assert(bool(demo.call("is_stage_placed")))
	assert(int(demo.call("get_stage_placement_count")) == 1)
	assert(stage.global_position.is_equal_approx(Vector3(0.0, 1.15, -2.0)))
	assert(stage.scale.is_equal_approx(Vector3.ONE))
	assert(arena != null)
	assert(bool(arena.get("_single_player_mode")))
	assert(arena.get("_single_player_cpu") != null)
	assert(arena.get("p1_placeholder") != null)
	assert(arena.get("p2_placeholder") != null)
	assert(str(demo.get_node("DebugOverlay/PresentationLabel").text).contains(
		"XR Mode: Desktop fallback"
	))
	assert(str(demo.get_node("DebugOverlay/PresentationLabel").text).contains(
		"Passthrough: N/A"
	))
	assert(ProjectSettings.get_setting("application/run/main_scene") == (
		"res://games/rollback_fighter/scenes/MainMenu.tscn"
	))

	var initial_stage_transform: Transform3D = stage.global_transform
	tracked_camera.transform = Transform3D(
		Basis(Vector3.UP, PI * 0.5),
		Vector3(0.35, 0.1, -0.15)
	)
	desktop_camera.transform = Transform3D(
		Basis(Vector3.UP, -PI * 0.5),
		Vector3(-0.4, 1.7, 0.2)
	)
	await process_frame
	assert(stage.global_transform.is_equal_approx(initial_stage_transform))
	assert(int(demo.call("get_stage_placement_count")) == 1)

	demo.call("recenter_stage")
	assert(int(demo.call("get_stage_placement_count")) == 2)
	assert(stage.global_position.is_equal_approx(
		_expected_stage_position(desktop_camera, settings.distance_m, settings.vertical_offset_m)
	))
	assert(not stage.global_transform.is_equal_approx(initial_stage_transform))

	demo.call("set_distance_m", 99.0)
	assert(is_equal_approx(settings.distance_m, 5.0))
	assert(is_equal_approx(
		_horizontal_distance(stage.global_position, desktop_camera.global_position),
		5.0
	))
	demo.call("set_vertical_offset_m", 99.0)
	assert(is_equal_approx(settings.vertical_offset_m, 2.0))
	assert(is_equal_approx(
		stage.global_position.y,
		desktop_camera.global_position.y + 2.0
	))
	demo.call("set_display_scale", 0.01)
	assert(is_equal_approx(settings.display_scale, 0.25))
	assert(stage.scale.is_equal_approx(Vector3.ONE * 0.25))

	var adjusted_stage_transform: Transform3D = stage.global_transform
	desktop_camera.position += Vector3(0.3, -0.2, 0.5)
	desktop_camera.rotation.y += deg_to_rad(30.0)
	await process_frame
	assert(stage.global_transform.is_equal_approx(adjusted_stage_transform))

	demo.set("_xr_active", true)
	assert(demo.call("get_active_view_camera") == tracked_camera)
	tracked_camera.position = Vector3(0.5, 1.8, -0.25)
	tracked_camera.rotation.y = deg_to_rad(35.0)
	demo.call("recenter_stage")
	assert(stage.global_position.is_equal_approx(
		_expected_stage_position(tracked_camera, settings.distance_m, settings.vertical_offset_m)
	))
	demo.set("_xr_active", false)

	demo.call("reset_presentation_settings")
	assert(is_equal_approx(settings.distance_m, 2.0))
	assert(is_equal_approx(settings.vertical_offset_m, -0.45))
	assert(is_equal_approx(settings.display_scale, 1.0))
	assert(stage.global_position.is_equal_approx(
		_expected_stage_position(desktop_camera, settings.distance_m, settings.vertical_offset_m)
	))
	assert(stage.scale.is_equal_approx(Vector3.ONE))

	var state_before_passthrough: Transform3D = stage.global_transform
	var placement_count_before_passthrough: int = int(
		demo.call("get_stage_placement_count")
	)
	var fake_passthrough := FakePassthroughInterface.new()
	demo.set("_xr_interface", fake_passthrough)
	demo.set("_xr_active", true)
	demo.call("_configure_xr_background")
	demo.call("_detect_passthrough_capability")
	assert(bool(demo.call("is_passthrough_supported")))
	assert(bool(demo.call("is_passthrough_enabled")))
	assert(fake_passthrough.start_count == 1)
	assert(root.transparent_bg)
	assert(bool(demo.call("set_passthrough_enabled", false)))
	assert(not bool(demo.call("is_passthrough_enabled")))
	assert(fake_passthrough.stop_count == 1)
	assert(stage.global_transform.is_equal_approx(state_before_passthrough))
	assert(int(demo.call("get_stage_placement_count")) == placement_count_before_passthrough)
	assert(bool(arena.get("_single_player_mode")))
	demo.set("_xr_active", false)
	demo.call("_configure_xr_background")
	demo.call("_detect_passthrough_capability")
	assert(not root.transparent_bg)
	assert(not bool(demo.call("is_passthrough_supported")))

	var placement_count: int = int(demo.call("get_stage_placement_count"))
	var reset_stage_transform: Transform3D = stage.global_transform
	demo.call("_place_stage_once")
	assert(int(demo.call("get_stage_placement_count")) == placement_count)
	assert(stage.global_transform.is_equal_approx(reset_stage_transform))

	demo.set("_xr_active", true)
	demo.call("_configure_xr_background")
	demo.call("_detect_passthrough_capability")
	assert(root.transparent_bg)
	assert(bool(demo.call("is_passthrough_enabled")))
	demo.free()
	await process_frame
	assert(not root.transparent_bg)
	assert(fake_passthrough.stop_count == 2)
	print("[FighterXRDemoTests] PASS")
	quit(0)


func _test_presentation_settings() -> void:
	var settings = XR_PRESENTATION_SETTINGS_SCRIPT.new()
	assert(is_equal_approx(settings.distance_m, 2.0))
	assert(is_equal_approx(settings.vertical_offset_m, -0.45))
	assert(is_equal_approx(settings.display_scale, 1.0))

	settings.distance_m = -10.0
	assert(is_equal_approx(settings.distance_m, 0.75))
	settings.distance_m = 10.0
	assert(is_equal_approx(settings.distance_m, 5.0))
	settings.vertical_offset_m = -10.0
	assert(is_equal_approx(settings.vertical_offset_m, -2.0))
	settings.vertical_offset_m = 10.0
	assert(is_equal_approx(settings.vertical_offset_m, 2.0))
	settings.display_scale = 0.01
	assert(is_equal_approx(settings.display_scale, 0.25))
	settings.display_scale = 10.0
	assert(is_equal_approx(settings.display_scale, 3.0))
	settings.reset_to_defaults()
	assert(is_equal_approx(settings.distance_m, 2.0))
	assert(is_equal_approx(settings.vertical_offset_m, -0.45))
	assert(is_equal_approx(settings.display_scale, 1.0))


func _expected_stage_position(
	camera: Camera3D,
	distance_m: float,
	vertical_offset_m: float
) -> Vector3:
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return camera.global_position + forward * distance_m + Vector3.UP * vertical_offset_m


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
