extends Control
class_name RollbackFighterCreatorSpriteAligner

const PresentationDraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const SCALE_FINE_STEP: int = 10
const SCALE_COARSE_STEP: int = 100

signal draft_changed


class SpritePreview:
	extends Control
	var preview_texture: Texture2D
	var image_size: Vector2 = Vector2.ZERO
	var anchor: Vector2 = Vector2.ZERO
	var scale_milli: int = 1000

	func set_preview(image: Image, feet_anchor: Vector2, scale_value: int) -> void:
		preview_texture = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
		image_size = Vector2(image.get_width(), image.get_height()) if image != null and not image.is_empty() else Vector2.ZERO
		anchor = feet_anchor
		scale_milli = scale_value
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("20232a"), true)
		var tile: int = 16
		for y in range(0, int(size.y), tile):
			for x in range(0, int(size.x), tile):
				if ((x / tile) + (y / tile)) % 2 == 0:
					draw_rect(Rect2(x, y, tile, tile), Color("292d35"), true)
		var origin: Vector2 = Vector2(size.x * 0.5, size.y * 0.78)
		draw_line(Vector2(0.0, origin.y), Vector2(size.x, origin.y), Color("72d69a"), 2.0)
		draw_line(Vector2(origin.x, 0.0), Vector2(origin.x, size.y), Color(0.7, 0.78, 0.9, 0.48), 1.0)
		if preview_texture != null and image_size.x > 0.0 and image_size.y > 0.0:
			var base_scale: float = float(scale_milli) / 1000.0
			var fit: float = minf((size.x - 24.0) / (image_size.x * base_scale), (origin.y - 16.0) / (image_size.y * base_scale))
			fit = clampf(fit, 0.01, 4.0)
			var render_scale: float = base_scale * fit
			var drawn_size: Vector2 = image_size * render_scale
			var top_left: Vector2 = origin - anchor * render_scale
			draw_texture_rect(preview_texture, Rect2(top_left, drawn_size), false)
		draw_circle(origin, 6.0, Color("ffcf52"))
		draw_line(origin + Vector2(-14.0, 0.0), origin + Vector2(14.0, 0.0), Color("ffcf52"), 2.0)
		draw_line(origin + Vector2(0.0, -14.0), origin + Vector2(0.0, 14.0), Color("ffcf52"), 2.0)


const PHASE_ORDER := ["startup", "active", "recovery"]

var _alignment: RollbackFighterCreatorPresentationDraft
var _slot_manifest: Dictionary = {}
var _slot_ids: PackedStringArray = PackedStringArray()
var _current_index: int = 0
var _current_slot_id: String = ""
var _current_image: Image
var _anchor_x: int = 0
var _anchor_y: int = 0
var _scale_milli: int = 1000
var _dirty: bool = false
var _preview_ids: PackedStringArray = PackedStringArray()
var _preview_index: int = 0
var _preview_active: bool = false
var _canvas: SpritePreview
var _slot_label: Label
var _metadata_label: Label
var _status_label: Label
var _scale_label: Label
var _scale_slider: HSlider
var _previous_button: Button
var _next_button: Button
var _save_button: Button
var _preview_button: Button
var _timer: Timer


func configure(alignment: RollbackFighterCreatorPresentationDraft, slot_manifest: Dictionary) -> void:
	_alignment = alignment
	_slot_manifest = slot_manifest.duplicate(true)
	if is_node_ready():
		_refresh_slot_list()


func has_unsaved_changes() -> bool:
	return _dirty


func save_pending_changes() -> bool:
	return not _dirty or _save_current()


func _ready() -> void:
	custom_minimum_size.y = 900.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	if _alignment != null:
		_refresh_slot_list()


func _build_ui() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var intro: Label = Label.new()
	intro.text = "Each source pixel is positioned so feet_anchor lands on the floor reference. Gameplay timing frames and recommended art drawings remain separate."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_slot_label)
	_canvas = SpritePreview.new()
	_canvas.custom_minimum_size.y = 330.0
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_canvas)
	_metadata_label = Label.new()
	metadata_label_setup()
	column.add_child(_metadata_label)
	_add_section_label(column, "FEET ANCHOR (SOURCE PIXELS)")
	var small_grid: GridContainer = GridContainer.new()
	small_grid.columns = 3
	small_grid.add_theme_constant_override("h_separation", 6)
	small_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(small_grid)
	_add_grid_spacer(small_grid)
	_add_anchor_button(small_grid, "↑ 1", 0, -1)
	_add_grid_spacer(small_grid)
	_add_anchor_button(small_grid, "← 1", -1, 0)
	_add_anchor_button(small_grid, "Bottom Center", 999, 999)
	_add_anchor_button(small_grid, "→ 1", 1, 0)
	_add_grid_spacer(small_grid)
	_add_anchor_button(small_grid, "↓ 1", 0, 1)
	_add_grid_spacer(small_grid)
	var large_grid: GridContainer = GridContainer.new()
	large_grid.columns = 4
	large_grid.add_theme_constant_override("h_separation", 6)
	column.add_child(large_grid)
	_add_anchor_button(large_grid, "← 10", -10, 0)
	_add_anchor_button(large_grid, "→ 10", 10, 0)
	_add_anchor_button(large_grid, "↑ 10", 0, -10)
	_add_anchor_button(large_grid, "↓ 10", 0, 10)
	_add_section_label(column, "UNIFORM SCALE")
	_scale_slider = HSlider.new()
	_scale_slider.min_value = PresentationDraftScript.SCALE_MIN
	_scale_slider.max_value = PresentationDraftScript.SCALE_MAX
	_scale_slider.step = 1
	_scale_slider.exp_edit = true
	_scale_slider.custom_minimum_size.y = 48.0
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.value_changed.connect(_on_scale_changed)
	column.add_child(_scale_slider)
	var scale_steps: HBoxContainer = HBoxContainer.new()
	column.add_child(scale_steps)
	for step in [-SCALE_COARSE_STEP, -SCALE_FINE_STEP, SCALE_FINE_STEP, SCALE_COARSE_STEP]:
		var step_button: Button = _make_button("%+d" % step)
		step_button.pressed.connect(_adjust_scale.bind(step))
		scale_steps.add_child(step_button)
	_scale_label = Label.new()
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_scale_label)
	var apply_row: HBoxContainer = HBoxContainer.new()
	column.add_child(apply_row)
	var apply_group: Button = _make_button("Apply to Animation")
	apply_group.pressed.connect(_apply_to_group)
	apply_row.add_child(apply_group)
	var apply_scale: Button = _make_button("Apply Scale to All")
	apply_scale.pressed.connect(_apply_scale_to_all)
	apply_row.add_child(apply_scale)
	var auto_fit: Button = _make_button("Auto Fit")
	auto_fit.pressed.connect(_auto_fit)
	apply_row.add_child(auto_fit)
	var preview_row: HBoxContainer = HBoxContainer.new()
	column.add_child(preview_row)
	_preview_button = _make_button("Play Preview")
	_preview_button.pressed.connect(_toggle_preview)
	preview_row.add_child(_preview_button)
	var preview_note: Label = Label.new()
	preview_note.text = "Preview cycles drawings, not simulation frames."
	preview_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_row.add_child(preview_note)
	var nav_row: HBoxContainer = HBoxContainer.new()
	column.add_child(nav_row)
	_previous_button = _make_button("‹ Previous")
	_previous_button.pressed.connect(_navigate.bind(-1))
	nav_row.add_child(_previous_button)
	_save_button = _make_button("Save")
	_save_button.pressed.connect(_save_current)
	nav_row.add_child(_save_button)
	_next_button = _make_button("Next ›")
	_next_button.pressed.connect(_navigate.bind(1))
	nav_row.add_child(_next_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 44.0
	column.add_child(_status_label)
	_timer = Timer.new()
	_timer.wait_time = 0.18
	_timer.timeout.connect(_advance_preview)
	add_child(_timer)


func _refresh_slot_list() -> void:
	if _alignment == null:
		return
	_alignment.synchronize_slots(_slot_manifest)
	_slot_ids = _alignment.get_assigned_slot_ids(_slot_manifest)
	_current_index = clampi(_current_index, 0, maxi(_slot_ids.size() - 1, 0))
	if _slot_ids.is_empty():
		_current_slot_id = ""
		_current_image = null
		var manifest_assigned: int = _alignment.get_manifest_assigned_count(_slot_manifest)
		_slot_label.text = "Assigned image unavailable" if manifest_assigned > 0 else "No assigned images"
		_metadata_label.text = "A marked image is missing or corrupt; re-import it in Required Art." if manifest_assigned > 0 else "Import PNG art in the Required Art step first."
		_canvas.set_preview(null, Vector2.ZERO, 1000)
		_set_controls_enabled(false)
		return
	_set_controls_enabled(true)
	_select_current_slot()


func _select_current_slot() -> void:
	_stop_preview()
	_current_slot_id = _slot_ids[_current_index]
	var image_result: Dictionary = _alignment.load_slot_image(_current_slot_id)
	if not bool(image_result.get("ok", false)):
		_current_image = null
		_slot_label.text = "%s — image unavailable" % _friendly_slot_name(_current_slot_id)
		_metadata_label.text = "Missing or corrupt image. Re-import it from Required Art."
		_status_label.text = _format_errors(image_result.get("errors", []))
		return
	_current_image = image_result["image"]
	var entry: Dictionary = _alignment.get_slot(_current_slot_id)
	var anchor: Array = entry.get("feet_anchor", [int(_current_image.get_width() / 2), _current_image.get_height()])
	_anchor_x = int(anchor[0])
	_anchor_y = int(anchor[1])
	_scale_milli = int(entry.get("scale_milli", 1000))
	_dirty = false
	var group: String = _group_title(_current_slot_id)
	_slot_label.text = "%s   %d / %d" % [group, _current_index + 1, _slot_ids.size()]
	_update_metadata_label()
	_canvas.set_preview(_current_image, Vector2(_anchor_x, _anchor_y), _scale_milli)
	_scale_slider.set_value_no_signal(_scale_milli)
	_update_scale_label()
	_previous_button.disabled = _current_index <= 0
	_next_button.disabled = _current_index >= _slot_ids.size() - 1
	_save_button.disabled = false
	_status_label.text = "Needs alignment" if str(entry.get("status", "")) != "aligned" else "Saved alignment"


func _update_metadata_label() -> void:
	if _current_image == null:
		return
	_metadata_label.text = "Image: %d×%d  |  Anchor: (%d, %d)  |  Runtime offset: size/2 − anchor" % [_current_image.get_width(), _current_image.get_height(), _anchor_x, _anchor_y]


func _update_preview() -> void:
	if _current_image != null:
		_canvas.set_preview(_current_image, Vector2(_anchor_x, _anchor_y), _scale_milli)
		_update_metadata_label()
		_update_scale_label()
		_dirty = true
		_status_label.text = "Unsaved alignment changes"


func _update_scale_label() -> void:
	_scale_label.text = "Scale: %d%%  (scale_milli=%d)" % [int(round(float(_scale_milli) / 10.0)), _scale_milli]


func _adjust_anchor(dx: int, dy: int) -> void:
	if _current_image == null:
		return
	if dx == 999 and dy == 999:
		_anchor_x = int(_current_image.get_width() / 2)
		_anchor_y = _current_image.get_height()
	else:
		_anchor_x += dx
		_anchor_y += dy
	_update_preview()


func _adjust_scale(delta: int) -> void:
	_scale_milli = clampi(
		_scale_milli + delta,
		PresentationDraftScript.SCALE_MIN,
		PresentationDraftScript.SCALE_MAX
	)
	_scale_slider.set_value_no_signal(_scale_milli)
	_update_preview()


func _on_scale_changed(value: float) -> void:
	_scale_milli = clampi(
		int(round(value / float(SCALE_FINE_STEP))) * SCALE_FINE_STEP,
		PresentationDraftScript.SCALE_MIN,
		PresentationDraftScript.SCALE_MAX
	)
	_update_preview()


func _save_current() -> bool:
	if _current_slot_id.is_empty() or _current_image == null:
		return false
	var result: Dictionary = _alignment.save_alignment(_current_slot_id, _anchor_x, _anchor_y, _scale_milli)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return false
	var save_result: Dictionary = _alignment.save()
	if not bool(save_result.get("ok", false)):
		_status_label.text = _format_errors(save_result.get("errors", []))
		return false
	_dirty = false
	_status_label.text = "Saved — feet anchor and uniform scale are aligned."
	draft_changed.emit()
	return true


func _navigate(direction: int) -> void:
	if _dirty:
		_status_label.text = "Save this sprite before navigating."
		return
	var next_index: int = _current_index + direction
	if next_index < 0 or next_index >= _slot_ids.size():
		return
	_current_index = next_index
	_select_current_slot()


func _apply_to_group() -> void:
	if _dirty and not _save_current():
		return
	var result: Dictionary = _alignment.apply_to_animation(_slot_manifest, _current_slot_id)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	var saved: Dictionary = _alignment.save()
	if not bool(saved.get("ok", false)):
		_status_label.text = _format_errors(saved.get("errors", []))
		return
	_status_label.text = "Applied anchor + scale to %d assigned sibling(s) in %s." % [int(result.get("count", 0)), _group_title(_current_slot_id)]
	draft_changed.emit()


func _apply_scale_to_all() -> void:
	if _dirty and not _save_current():
		return
	var result: Dictionary = _alignment.apply_scale_to_all(_slot_manifest, _current_slot_id)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	var saved: Dictionary = _alignment.save()
	if not bool(saved.get("ok", false)):
		_status_label.text = _format_errors(saved.get("errors", []))
		return
	_status_label.text = "Applied only scale_milli to %d assigned sprite(s)." % int(result.get("count", 0))
	draft_changed.emit()
	_select_current_slot()


func _auto_fit() -> void:
	if _dirty and not _save_current():
		return
	var result: Dictionary = _alignment.auto_fit(_slot_manifest)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	var saved: Dictionary = _alignment.save()
	if not bool(saved.get("ok", false)):
		_status_label.text = _format_errors(saved.get("errors", []))
		return
	_select_current_slot()
	_status_label.text = "Auto Fit matched %s visible height to the built-in fighter: scale_milli=%d across %d assigned sprite(s). Feet anchors unchanged." % [
		str(result.get("source_slot", "idle_0")),
		int(result.get("scale_milli", 1000)),
		int(result.get("count", 0)),
	]
	draft_changed.emit()


func _toggle_preview() -> void:
	if _preview_active:
		_stop_preview()
		return
	_preview_ids = _preview_sequence(_current_slot_id)
	if _preview_ids.size() < 2:
		_status_label.text = "This animation group needs at least two valid assigned drawings."
		return
	_preview_active = true
	_preview_index = 0
	_preview_button.text = "Stop Preview"
	_timer.start()
	_advance_preview()


func _advance_preview() -> void:
	if not _preview_active or _preview_ids.is_empty():
		return
	var preview_slot_id: String = _preview_ids[_preview_index]
	_preview_index = (_preview_index + 1) % _preview_ids.size()
	var result: Dictionary = _alignment.load_slot_image(preview_slot_id)
	if bool(result.get("ok", false)):
		var image: Image = result["image"]
		var entry: Dictionary = _alignment.get_slot(preview_slot_id)
		var anchor: Array = entry.get("feet_anchor", [int(image.get_width() / 2), image.get_height()])
		_canvas.set_preview(image, Vector2(int(anchor[0]), int(anchor[1])), int(entry.get("scale_milli", 1000)))
		_status_label.text = "Visual preview: %s" % _friendly_slot_name(preview_slot_id)


func _stop_preview() -> void:
	if _timer != null:
		_timer.stop()
	_preview_active = false
	if _preview_button != null:
		_preview_button.text = "Play Preview"
	if _current_image != null and _canvas != null:
		_canvas.set_preview(_current_image, Vector2(_anchor_x, _anchor_y), _scale_milli)


func _preview_sequence(slot_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var animation_id: String = slot_id.get_slice("_", 0)
	if animation_id == "jab" or animation_id == "heavy":
		for phase in PHASE_ORDER:
			var prefix: String = "%s_%s_" % [animation_id, phase]
			for candidate in _slot_ids:
				if candidate.begins_with(prefix):
					result.append(candidate)
	else:
		var prefix: String = animation_id + "_"
		for candidate in _slot_ids:
			if candidate.begins_with(prefix):
				result.append(candidate)
	return result


func _set_controls_enabled(enabled: bool) -> void:
	if _previous_button != null:
		_previous_button.disabled = not enabled
		_next_button.disabled = not enabled
		_save_button.disabled = not enabled
		_scale_slider.editable = enabled
		_preview_button.disabled = not enabled


func _add_anchor_button(parent: GridContainer, text: String, dx: int, dy: int) -> void:
	var button: Button = _make_button(text)
	button.pressed.connect(_adjust_anchor.bind(dx, dy))
	parent.add_child(button)


func _add_grid_spacer(parent: GridContainer) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 52.0
	parent.add_child(spacer)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)


func _make_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _friendly_slot_name(slot_id: String) -> String:
	return slot_id.replace("_", " ").capitalize()


func _group_title(slot_id: String) -> String:
	var phase: String = ""
	for candidate in PHASE_ORDER:
		if slot_id.contains("_%s_" % candidate):
			phase = " / %s" % candidate.capitalize()
	return "%s%s" % [_friendly_slot_name(slot_id.get_slice("_", 0)), phase]


func _format_errors(errors: Array) -> String:
	if errors.is_empty():
		return "Alignment could not be saved."
	var lines: PackedStringArray = PackedStringArray()
	for value in errors:
		if value is Dictionary:
			lines.append("%s (%s)" % [str(value.get("expected_rule", "invalid")), str(value.get("invalid_value", ""))])
	return "Cannot continue:\n%s" % "\n".join(lines)


func metadata_label_setup() -> void:
	_metadata_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_metadata_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

