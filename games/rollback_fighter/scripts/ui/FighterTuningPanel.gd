extends Control
class_name RollbackFighterTuningPanel


const LoaderScript = preload(
	"res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd"
)
const DraftScript = preload(
	"res://games/rollback_fighter/scripts/config/FighterTuningDraft.gd"
)

signal reload_requested

const FIELD_SPECS := [
	{"title": "HEALTH", "label": "Max HP", "doc": "character", "section": "health", "key": "max_hp", "min": 1},
	{"title": "MOVEMENT", "label": "Move Speed", "doc": "character", "section": "movement", "key": "move_speed", "min": 0},
	{"title": "MOVEMENT", "label": "Acceleration", "doc": "character", "section": "movement", "key": "acceleration", "min": 0},
	{"title": "MOVEMENT", "label": "Braking", "doc": "character", "section": "movement", "key": "braking", "min": 0},
	{"title": "MOVEMENT", "label": "Reversal Acceleration", "doc": "character", "section": "movement", "key": "reversal_acceleration", "min": 0},
	{"title": "MOVEMENT", "label": "Knockback Friction", "doc": "character", "section": "movement", "key": "knockback_friction", "min": 0},
	{"title": "MOVEMENT", "label": "Max Knockback Speed", "doc": "character", "section": "movement", "key": "max_knockback_speed", "min": 0},
	{"title": "GUARD", "label": "Max", "doc": "character", "section": "guard", "key": "max_units", "min": 0},
	{"title": "GUARD", "label": "Held Drain / Frame", "doc": "character", "section": "guard", "key": "held_drain_per_frame", "min": 0},
	{"title": "GUARD", "label": "Regen / Frame", "doc": "character", "section": "guard", "key": "regen_per_frame", "min": 0},
	{"title": "GUARD", "label": "Break Refill", "doc": "character", "section": "guard", "key": "break_refill_units", "min": 0},
	{"title": "GUARD", "label": "Break Stun Frames", "doc": "character", "section": "guard", "key": "break_stun_frames", "min": 0},
	{"title": "DODGE", "label": "Total Frames", "doc": "character", "section": "dodge", "key": "total_frames", "min": 1},
	{"title": "DODGE", "label": "Invulnerability Start", "doc": "character", "section": "dodge", "key": "invuln_start", "min": 0},
	{"title": "DODGE", "label": "Invulnerability End", "doc": "character", "section": "dodge", "key": "invuln_end", "min": 0},
	{"title": "DODGE", "label": "Cooldown Frames", "doc": "character", "section": "dodge", "key": "cooldown_frames", "min": 0},
	{"title": "LIGHT / JAB", "label": "Startup", "doc": "jab", "section": "", "key": "startup", "min": 0},
	{"title": "LIGHT / JAB", "label": "Active", "doc": "jab", "section": "", "key": "active", "min": 1},
	{"title": "LIGHT / JAB", "label": "Recovery", "doc": "jab", "section": "", "key": "recovery", "min": 0},
	{"title": "LIGHT / JAB", "label": "Damage", "doc": "jab", "section": "", "key": "damage", "min": 0},
	{"title": "LIGHT / JAB", "label": "Hitstun", "doc": "jab", "section": "", "key": "hitstun", "min": 0},
	{"title": "LIGHT / JAB", "label": "Knockback X", "doc": "jab", "section": "", "key": "knockback_x", "min": 0},
	{"title": "LIGHT / JAB", "label": "Hitstop", "doc": "jab", "section": "", "key": "hitstop", "min": 0},
	{"title": "LIGHT / JAB", "label": "Contact Cooldown", "doc": "jab", "section": "", "key": "contact_cooldown", "min": 0},
	{"title": "LIGHT / JAB", "label": "Guard Damage", "doc": "jab", "section": "", "key": "guard_damage", "min": 0},
	{"title": "HEAVY", "label": "Startup", "doc": "heavy", "section": "", "key": "startup", "min": 0},
	{"title": "HEAVY", "label": "Active", "doc": "heavy", "section": "", "key": "active", "min": 1},
	{"title": "HEAVY", "label": "Recovery", "doc": "heavy", "section": "", "key": "recovery", "min": 0},
	{"title": "HEAVY", "label": "Damage", "doc": "heavy", "section": "", "key": "damage", "min": 0},
	{"title": "HEAVY", "label": "Hitstun", "doc": "heavy", "section": "", "key": "hitstun", "min": 0},
	{"title": "HEAVY", "label": "Knockback X", "doc": "heavy", "section": "", "key": "knockback_x", "min": 0},
	{"title": "HEAVY", "label": "Hitstop", "doc": "heavy", "section": "", "key": "hitstop", "min": 0},
	{"title": "HEAVY", "label": "Contact Cooldown", "doc": "heavy", "section": "", "key": "contact_cooldown", "min": 0},
	{"title": "HEAVY", "label": "Guard Damage", "doc": "heavy", "section": "", "key": "guard_damage", "min": 0},
]

const MAX_INT_VALUE: float = 2147483647.0

var _draft: RollbackFighterTuningDraft
var _fighter_selector: OptionButton
var _display_name_label: Label
var _dirty_label: Label
var _status_label: Label
var _validate_button: Button
var _save_button: Button
var _revert_button: Button
var _reload_button: Button
var _field_controls: Array[Dictionary] = []
var _networked_match: bool = true
var _building_controls: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()


func configure(registry_path: String, networked_match: bool) -> void:
	_networked_match = networked_match
	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	_draft = DraftScript.new()
	_draft.configure(loader, registry_path)
	_populate_fighter_selector()
	if _networked_match:
		_reload_button.disabled = true
		_status_label.text = "Network match: saved config applies after both peers restart."


func set_panel_open(open: bool) -> void:
	visible = open
	if open and _fighter_selector != null:
		_fighter_selector.grab_focus()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "TuningPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.02
	panel.anchor_bottom = 0.98
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var heading := Label.new()
	heading.text = "FIGHTER TUNING  (F4 closes)"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(heading)

	var select_row := HBoxContainer.new()
	outer.add_child(select_row)
	var select_label := Label.new()
	select_label.text = "Fighter"
	select_row.add_child(select_label)
	_fighter_selector = OptionButton.new()
	_fighter_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fighter_selector.item_selected.connect(_on_fighter_selected)
	select_row.add_child(_fighter_selector)
	_display_name_label = Label.new()
	outer.add_child(_display_name_label)

	_dirty_label = Label.new()
	outer.add_child(_dirty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	var active_title: String = ""
	for spec in FIELD_SPECS:
		var section_title: String = str(spec["title"])
		if section_title != active_title:
			active_title = section_title
			var section_label := Label.new()
			section_label.text = active_title
			content.add_child(section_label)
		var row := HBoxContainer.new()
		content.add_child(row)
		var field_label := Label.new()
		field_label.text = str(spec["label"])
		field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(field_label)
		var spin := SpinBox.new()
		spin.min_value = float(spec["min"])
		spin.max_value = MAX_INT_VALUE
		spin.step = 1.0
		spin.rounded = true
		spin.allow_greater = false
		spin.allow_lesser = false
		spin.custom_minimum_size.x = 150.0
		spin.value_changed.connect(_on_field_changed.bind(spec))
		row.add_child(spin)
		_field_controls.append({"spec": spec, "control": spin})

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 42.0
	outer.add_child(_status_label)

	var actions := HBoxContainer.new()
	outer.add_child(actions)
	_validate_button = Button.new()
	_validate_button.text = "Validate"
	_validate_button.pressed.connect(_validate_draft)
	actions.add_child(_validate_button)
	_save_button = Button.new()
	_save_button.text = "Save Changes"
	_save_button.pressed.connect(_save_changes)
	actions.add_child(_save_button)
	_revert_button = Button.new()
	_revert_button.text = "Revert Changes"
	_revert_button.pressed.connect(_revert_changes)
	actions.add_child(_revert_button)
	_reload_button = Button.new()
	_reload_button.text = "Reload Match"
	_reload_button.pressed.connect(_reload_match)
	actions.add_child(_reload_button)


func _populate_fighter_selector() -> void:
	_fighter_selector.clear()
	if _draft == null:
		return
	var ids: PackedStringArray = _draft.get_registered_fighter_ids()
	for fighter_id in ids:
		_fighter_selector.add_item(fighter_id)
		_fighter_selector.set_item_metadata(
			_fighter_selector.item_count - 1,
			fighter_id
		)
	var initial_index: int = ids.find("example_fighter")
	if initial_index < 0 and not ids.is_empty():
		initial_index = 0
	if initial_index >= 0:
		_fighter_selector.select(initial_index)
		_load_selected_fighter(initial_index)


func _on_fighter_selected(index: int) -> void:
	if _draft != null and _draft.is_dirty():
		_status_label.text = "Save or revert the current draft before changing fighters."
		var old_index: int = 0
		for item_index in _fighter_selector.item_count:
			if str(_fighter_selector.get_item_metadata(item_index)) == _draft.fighter_id:
				old_index = item_index
				break
		_fighter_selector.select(old_index)
		return
	_load_selected_fighter(index)


func _load_selected_fighter(index: int) -> void:
	var selected_id: String = str(_fighter_selector.get_item_metadata(index))
	if not _draft.load_fighter(selected_id):
		_status_label.text = _format_errors(_draft.last_errors)
		return
	_display_name_label.text = "%s — %s" % [selected_id, _draft.get_display_name()]
	_status_label.text = "Edits stay in a separate draft until validated and saved."
	_refresh_fields()
	_refresh_dirty_state()


func _refresh_fields() -> void:
	_building_controls = true
	for binding in _field_controls:
		var spec: Dictionary = binding["spec"]
		var spin: SpinBox = binding["control"]
		spin.set_value_no_signal(_draft.get_integer(
			str(spec["doc"]),
			str(spec["section"]),
			str(spec["key"])
		))
	_building_controls = false


func _on_field_changed(value: float, spec: Dictionary) -> void:
	if _building_controls or _draft == null:
		return
	_draft.set_integer(
		str(spec["doc"]),
		str(spec["section"]),
		str(spec["key"]),
		int(round(value))
	)
	_status_label.text = "Draft changed. Save validates before writing; active match is unchanged."
	_refresh_dirty_state()


func _refresh_dirty_state() -> void:
	var dirty: bool = _draft != null and _draft.is_dirty()
	_dirty_label.text = "Unsaved Changes" if dirty else "No Unsaved Changes"
	_save_button.disabled = not dirty
	_revert_button.disabled = not dirty


func _save_changes() -> void:
	if _draft == null:
		return
	var errors: Array[Dictionary] = _draft.validate()
	if not errors.is_empty():
		_status_label.text = _format_errors(errors)
		return
	var result: Dictionary = _draft.save()
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	print("[TuningUI] saved fighter=%s" % _draft.fighter_id)
	print("character.json updated")
	print("jab.json updated")
	print("heavy.json updated")
	_refresh_dirty_state()
	if _networked_match:
		_status_label.text = "Saved. Config changed; restart both peers to use new settings."
	else:
		_status_label.text = "Saved. Use Reload Match to apply the new config."


func _validate_draft() -> void:
	if _draft == null:
		return
	var errors: Array[Dictionary] = _draft.validate()
	if not errors.is_empty():
		_status_label.text = _format_errors(errors)
		return
	_status_label.text = "Draft valid. Save Changes to write JSON files."


func _revert_changes() -> void:
	if _draft == null or not _draft.revert():
		_status_label.text = _format_errors(_draft.last_errors if _draft != null else [])
		return
	_refresh_fields()
	_refresh_dirty_state()
	_status_label.text = "Draft reverted from current on-disk config."


func _reload_match() -> void:
	if _networked_match:
		_status_label.text = "Restart both peers to use saved settings."
		return
	if _draft != null and _draft.is_dirty():
		_status_label.text = "Save or revert draft changes before reloading."
		return
	reload_requested.emit()


func _format_errors(errors: Array) -> String:
	if errors.is_empty():
		return "Configuration operation failed."
	var lines := PackedStringArray(["Cannot save:"])
	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	for error_variant in errors:
		if error_variant is Dictionary:
			lines.append(loader.format_error(error_variant))
	return "\n".join(lines)
