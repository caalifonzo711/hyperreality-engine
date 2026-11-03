extends Control


const MAIN_MENU_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const PROJECT_DETAIL_PATH := "res://games/rollback_fighter/scenes/ProjectDetail.tscn"
const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const ArtImporter = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const AlignmentDraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const BuilderScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterBuilder.gd")
const AlignerScene = preload("res://games/rollback_fighter/scenes/CreatorSpriteAligner.tscn")
const ANIMATION_ORDER := ["idle", "jab", "heavy", "block", "dodge", "hit", "dead"]
const PHASE_ORDER := ["startup", "active", "recovery"]

var _draft: RollbackFighterCreatorDraft
var _alignment_draft: RollbackFighterCreatorPresentationDraft
var _aligner: RollbackFighterCreatorSpriteAligner
var _page: int = 0
var _id_is_manual: bool = false
var _updating_generated_id: bool = false
var _page_title: Label
var _page_container: VBoxContainer
var _status_label: Label
var _back_button: Button
var _next_button: Button
var _create_button: Button
var _build_button: Button
var _display_name_input: LineEdit
var _fighter_id_input: LineEdit
var _art_progress_label: Label
var _file_dialog: FileDialog
var _pending_slot_id: String = ""
var _preset_selector: OptionButton
var _feel_slider: HSlider
var _feel_value_label: Label


func _ready() -> void:
	_draft = DraftScript.new()
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context != null:
		_draft.set_project_context(str(context.call("get_project_id")))
		var presentation_config: Dictionary = context.call("get_presentation_config")
		_draft.set_presentation_policy(
			str(presentation_config.get("style_preset", "platform_fighter")),
			str(presentation_config.get("presentation_policy_reference", ""))
		)
	_alignment_draft = AlignmentDraftScript.new()
	_build_ui()
	_render_page()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 32.0, 280.0, 600.0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var heading: Label = Label.new()
	heading.text = "CREATE A FIGHTER"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	_page_title = Label.new()
	_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_title.add_theme_font_size_override("font_size", 21)
	column.add_child(_page_title)
	_page_container = VBoxContainer.new()
	_page_container.add_theme_constant_override("separation", 10)
	column.add_child(_page_container)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 48.0
	column.add_child(_status_label)
	var actions: GridContainer = GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	_back_button = _make_button("Back")
	_back_button.pressed.connect(_on_back_pressed)
	actions.add_child(_back_button)
	var cancel_button: Button = _make_button("Cancel")
	cancel_button.pressed.connect(_on_cancel_pressed)
	actions.add_child(cancel_button)
	_next_button = _make_button("Next")
	_next_button.pressed.connect(_on_next_pressed)
	actions.add_child(_next_button)
	_create_button = _make_button("Finish / Create Draft")
	_create_button.pressed.connect(_on_create_pressed)
	actions.add_child(_create_button)
	_build_button = _make_button("Build Fighter")
	_build_button.pressed.connect(_on_build_pressed)
	actions.add_child(_build_button)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.png", "PNG image")
	_file_dialog.file_selected.connect(_on_art_file_selected)
	add_child(_file_dialog)


func _make_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _render_page() -> void:
	for child in _page_container.get_children():
		child.queue_free()
	var titles: PackedStringArray = PackedStringArray(["STEP 1 — IDENTITY", "STEP 2 — FIGHTER FEEL", "STEP 3 — REQUIRED ART", "STEP 4 — SPRITE ALIGNMENT", "STEP 5 — REVIEW"])
	_page_title.text = "%s  (%d/5)" % [titles[_page], _page + 1]
	_back_button.disabled = _page == 0
	_next_button.visible = _page < 4
	_next_button.text = "Review" if _page == 3 else "Next"
	_create_button.visible = _page == 4
	_create_button.disabled = false
	_build_button.visible = _page == 4
	_build_button.disabled = true
	_status_label.text = ""
	match _page:
		0:
			_render_identity_page()
		1:
			_render_feel_page()
		2:
			_render_art_page()
		3:
			_render_alignment_page()
		4:
			_render_review_page()


func _render_identity_page() -> void:
	var instructions: Label = Label.new()
	instructions.text = "Choose a display name and a safe fighter ID. The ID is generated from the name and can be edited."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(instructions)
	_add_field_label("Fighter Name")
	_display_name_input = LineEdit.new()
	_display_name_input.placeholder_text = "Red Girl"
	_display_name_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_display_name_input.custom_minimum_size.y = 50.0
	_display_name_input.text = _draft.fighter_name
	_display_name_input.text_changed.connect(_on_name_changed)
	_page_container.add_child(_display_name_input)
	_add_field_label("Fighter ID  (a-z, 0-9, underscore)")
	_fighter_id_input = LineEdit.new()
	_fighter_id_input.placeholder_text = "red_girl"
	_fighter_id_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_fighter_id_input.custom_minimum_size.y = 50.0
	_fighter_id_input.text = _draft.fighter_id
	_fighter_id_input.text_changed.connect(_on_id_changed)
	_page_container.add_child(_fighter_id_input)
	var note: Label = Label.new()
	note.text = "A draft folder is created when the first image is imported or Create Draft is selected. Existing built-in or draft IDs cannot be reused."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(note)


func _render_feel_page() -> void:
	_add_field_label("Style preset")
	_preset_selector = OptionButton.new()
	_preset_selector.custom_minimum_size.y = 50.0
	var ids: PackedStringArray = _draft.get_preset_ids()
	var labels: PackedStringArray = _draft.get_preset_labels()
	for index in ids.size():
		_preset_selector.add_item(labels[index])
		_preset_selector.set_item_metadata(index, ids[index])
	var selected: int = ids.find(_draft.preset_id)
	_preset_selector.select(maxi(selected, 0))
	_preset_selector.item_selected.connect(_on_preset_selected)
	_page_container.add_child(_preset_selector)
	var help: Label = Label.new()
	help.text = "Preset changes are curated starting points for movement, guard, dodge, jab, and heavy. They do not add mechanics."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(help)
	_add_field_label("FAST / MOBILE  ←→  HEAVY / COMMITTED")
	_feel_slider = HSlider.new()
	_feel_slider.min_value = 0
	_feel_slider.max_value = 100
	_feel_slider.step = 1
	_feel_slider.value = _draft.feel_percent
	_feel_slider.custom_minimum_size.y = 44.0
	_feel_slider.value_changed.connect(_on_feel_changed)
	_page_container.add_child(_feel_slider)
	_feel_value_label = Label.new()
	_page_container.add_child(_feel_value_label)
	_refresh_feel_preview()
	var safe_note: Label = Label.new()
	safe_note.text = "The slider uses integer interpolation between validated preset endpoints. The editable draft is separate from fighters in the current match."
	safe_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(safe_note)


func _render_art_page() -> void:
	var intro: Label = Label.new()
	intro.text = "%s\nSimulation frames are not PNG counts; an 8-frame startup can use one drawing." % str(_draft.slot_manifest.get("help_text", "Add the required fighter drawings."))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(intro)
	_art_progress_label = Label.new()
	_art_progress_label.add_theme_font_size_override("font_size", 18)
	_page_container.add_child(_art_progress_label)
	var animations: Dictionary = _draft.slot_manifest.get("animations", {})
	var group_metadata: Dictionary = _draft.slot_manifest.get("group_metadata", {})
	var group_order: Array = Array(_draft.slot_manifest.get("group_order", ANIMATION_ORDER))
	for animation_id_value in group_order:
		var animation_id: String = str(animation_id_value)
		if not animations.has(animation_id):
			continue
		var metadata: Dictionary = group_metadata.get(animation_id, {})
		var heading: Label = Label.new()
		heading.text = str(metadata.get("display_name", _animation_title(animation_id))).to_upper()
		heading.add_theme_font_size_override("font_size", 18)
		_page_container.add_child(heading)
		var group_help: String = str(metadata.get("help_text", ""))
		if not group_help.is_empty():
			var help_label: Label = Label.new()
			help_label.text = "%s  Recommended drawings: %d." % [group_help, int(metadata.get("recommended_drawing_count", 0))]
			help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_page_container.add_child(help_label)
		var value: Variant = animations[animation_id]
		if value is Array:
			_add_slot_cards(animation_id, "pose", value)
		else:
			var phases: Dictionary = value
			for phase in PHASE_ORDER:
				if not phases.has(phase):
					continue
				var phase_data: Dictionary = phases[phase]
				var phase_label: Label = Label.new()
				phase_label.text = "%s: %d simulation frames → %d recommended drawing(s)" % [phase.capitalize(), int(phase_data.get("simulation_frames", 0)), int(phase_data.get("recommended_drawings", 0))]
				phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_page_container.add_child(phase_label)
				_add_slot_cards(animation_id, phase, phase_data.get("slots", []))
	var count_label: Label = Label.new()
	count_label.text = "Required: %d images  |  Optional: %d images. PNG transparency is preserved." % [_draft.get_required_art_slot_total(), _draft.get_optional_art_slot_total()]
	_page_container.add_child(count_label)
	_refresh_art_progress()


func _add_slot_cards(animation_id: String, phase: String, slots: Array) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_page_container.add_child(grid)
	for slot_value in slots:
		var slot: Dictionary = slot_value
		var slot_id: String = str(slot.get("slot", "%s_%s" % [animation_id, phase]))
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(132.0, 180.0)
		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 5)
		card.add_child(content)
		var title: Label = Label.new()
		title.text = str(slot.get("display_name", _slot_title(slot_id)))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(title)
		var required: bool = bool(slot.get("required", false))
		var assigned: bool = bool(slot.get("assigned", false))
		var requirement: Label = Label.new()
		requirement.text = "Required" if required else "Optional"
		requirement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(requirement)
		if assigned:
			var preview: TextureRect = TextureRect.new()
			preview.custom_minimum_size = Vector2(112.0, 100.0)
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.texture = ArtImporter.load_thumbnail(_draft.get_user_draft_path(), slot_id)
			content.add_child(preview)
			var file_label: Label = Label.new()
			file_label.text = "%s  %dx%d" % [str(slot.get("display_filename", slot.get("path", ""))), int(slot.get("width", 0)), int(slot.get("height", 0))]
			file_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			content.add_child(file_label)
			var controls: HBoxContainer = HBoxContainer.new()
			var replace_button: Button = _make_button("Replace")
			replace_button.pressed.connect(_open_art_picker.bind(slot_id))
			controls.add_child(replace_button)
			var remove_button: Button = _make_button("Remove")
			remove_button.pressed.connect(_remove_art_slot.bind(slot_id))
			controls.add_child(remove_button)
			content.add_child(controls)
		else:
			var add_button: Button = _make_button("+ Add Image")
			add_button.custom_minimum_size.y = 72.0
			add_button.pressed.connect(_open_art_picker.bind(slot_id))
			content.add_child(add_button)
		grid.add_child(card)


func _render_review_page() -> void:
	_sync_alignment_progress()
	var summary: Dictionary = _draft.get_review_summary()
	var lines: PackedStringArray = PackedStringArray([
		str(summary.get("name", "")),
		"ID: %s" % str(summary.get("id", "")),
		"Preset: %s  |  Feel: %d%%" % [str(summary.get("preset", "")), _draft.feel_percent],
		"HP: %d" % int(summary.get("hp", 0)),
		"Move Speed: %d" % int(summary.get("move_speed", 0)),
		"Jab: %s frames  |  Damage %d" % [str(summary.get("jab_timing", "")), int(summary.get("jab_damage", 0))],
		"Heavy: %s frames  |  Damage %d" % [str(summary.get("heavy_timing", "")), int(summary.get("heavy_damage", 0))],
		"Required art: %d / %d complete" % [int(summary.get("completed_required_art_slots", 0)), int(summary.get("required_art_slots", 0))],
		"Optional art: %d / %d added" % [int(summary.get("completed_optional_art_slots", 0)), int(summary.get("optional_art_slots", 0))],
		"Aligned art: %d / %d assigned" % [int(summary.get("aligned_art_slots", 0)), int(summary.get("assigned_art_slots", 0))],
	])
	var missing_value: Variant = summary.get("missing_required_art_slots", PackedStringArray())
	var missing_slots: PackedStringArray = PackedStringArray()
	for slot_value in missing_value:
		missing_slots.append(_slot_title(str(slot_value)))
	if not missing_slots.is_empty():
		lines.append("Missing: %s" % ", ".join(missing_slots))
	var missing_alignment: PackedStringArray = _alignment_draft.get_missing_alignment_ids(_draft.slot_manifest)
	if not missing_alignment.is_empty():
		var alignment_labels: PackedStringArray = PackedStringArray()
		for slot_id in missing_alignment:
			alignment_labels.append(_slot_title(slot_id))
		lines.append("Missing alignment: %s" % ", ".join(alignment_labels))
	var summary_label: Label = Label.new()
	summary_label.text = "\n".join(lines)
	summary_label.add_theme_font_size_override("font_size", 18)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(summary_label)
	var note: Label = Label.new()
	note.text = "Draft incomplete — add remaining art before the fighter can be built."
	if _draft.get_missing_required_art_slots().is_empty() and not missing_alignment.is_empty():
		note.text = "Alignment incomplete — fighter cannot be built yet."
	elif _draft.get_missing_required_art_slots().is_empty() and missing_alignment.is_empty():
		note.text = "Minimum art and alignment are complete. Optional art can be added later; the fighter is ready to build."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_container.add_child(note)
	var ready_to_build: bool = (
		_is_valid_build_identity()
		and _draft.validate_documents().is_empty()
		and _draft.get_missing_required_art_slots().is_empty()
		and missing_alignment.is_empty()
	)
	_build_button.disabled = not ready_to_build
	if not ready_to_build:
		var requirements: PackedStringArray = PackedStringArray()
		if not _draft.get_missing_required_art_slots().is_empty():
			requirements.append("add all required art")
		if not missing_alignment.is_empty():
			requirements.append("align every assigned required or optional image")
		if not _is_valid_build_identity():
			requirements.append("fix fighter identity")
		if not _draft.validate_documents().is_empty():
			requirements.append("fix fighter configuration")
		var requirement_label: Label = Label.new()
		requirement_label.text = "Build requirements: " + "; ".join(requirements)
		requirement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_page_container.add_child(requirement_label)


func _is_valid_build_identity() -> bool:
	if _draft.fighter_name.strip_edges().is_empty():
		return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(_draft.fighter_id) != null


func _on_build_pressed() -> void:
	if _page != 4 or _build_button.disabled:
		return
	var draft_result: Dictionary = _draft.create_user_draft()
	if not bool(draft_result.get("ok", false)):
		_status_label.text = _format_errors(draft_result.get("errors", []))
		return
	var alignment_result: Dictionary = _alignment_draft.save()
	if not bool(alignment_result.get("ok", false)):
		_status_label.text = _format_errors(alignment_result.get("errors", []))
		return
	var manifest_result: Dictionary = _draft.save_art_manifests()
	if not bool(manifest_result.get("ok", false)):
		_status_label.text = _format_errors(manifest_result.get("errors", []))
		return
	var builder: RollbackFighterCreatorBuilder = BuilderScript.new()
	var result: Dictionary = builder.build(_draft.fighter_id)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("message", "Could not build fighter."))
		if OS.is_debug_build():
			for detail in result.get("errors", []):
				push_warning("[CreatorBuild] %s" % str(detail))
		return
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context != null:
		var project_result: Dictionary = context.call("record_successful_build", _draft.fighter_id)
		if not bool(project_result.get("ok", false)):
			_status_label.text = "Fighter built, but its project roster could not be updated."
			return
	_status_label.text = "%s built and ready to play." % _draft.fighter_name
	_create_button.disabled = true
	_build_button.disabled = true
	var play_button: Button = _make_button("Play Fighter")
	play_button.pressed.connect(_on_play_built_fighter_pressed)
	_page_container.add_child(play_button)
	var project_context: Node = get_node_or_null("/root/CreatorLaunchContext")
	var menu_button: Button = _make_button("Return to Project" if project_context != null and bool(project_context.call("has_project")) else "Return to Main Menu")
	menu_button.pressed.connect(_on_cancel_pressed)
	_page_container.add_child(menu_button)
	print("[CreatorBuild] playable fighter built id=%s" % _draft.fighter_id)


func _on_play_built_fighter_pressed() -> void:
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null:
		_status_label.text = "Match launch settings are unavailable."
		return
	launch_config.call("set_single_player")
	if not bool(launch_config.call("set_fighter_selection", _draft.fighter_id, "example_fighter_alt")):
		_status_label.text = "Could not select the newly built fighter."
		return
	get_tree().change_scene_to_file("res://games/rollback_fighter/scenes/CharacterSelect.tscn")


func _add_field_label(value: String) -> void:
	var label: Label = Label.new()
	label.text = value
	_page_container.add_child(label)


func _refresh_feel_preview() -> void:
	if _feel_value_label == null:
		return
	_feel_value_label.text = "Feel: %d%%  |  Speed %d  |  Jab %d / %d / %d  |  Heavy %d / %d / %d" % [
		_draft.feel_percent,
		_draft.get_character_value("movement", "move_speed"),
		_draft.get_move_value("light", "startup"),
		_draft.get_move_value("light", "active"),
		_draft.get_move_value("light", "recovery"),
		_draft.get_move_value("heavy", "startup"),
		_draft.get_move_value("heavy", "active"),
		_draft.get_move_value("heavy", "recovery"),
	]


func _on_name_changed(value: String) -> void:
	if not _id_is_manual:
		var generated: String = DraftScript.id_from_display_name(value)
		_updating_generated_id = true
		_fighter_id_input.text = generated
		_updating_generated_id = false
		_draft.set_identity(value, generated)
	else:
		_draft.set_identity(value, _fighter_id_input.text)


func _on_id_changed(value: String) -> void:
	if _updating_generated_id:
		return
	_id_is_manual = true
	_draft.set_identity(_display_name_input.text, value)


func _on_preset_selected(index: int) -> void:
	var id: String = str(_preset_selector.get_item_metadata(index))
	_draft.set_preset(id)
	_draft.set_feel(int(round(_feel_slider.value)))
	_refresh_feel_preview()


func _on_feel_changed(value: float) -> void:
	_draft.set_feel(int(round(value)))
	_refresh_feel_preview()


func _on_back_pressed() -> void:
	if _page == 3 and _aligner != null and not _aligner.save_pending_changes():
		_status_label.text = "Save or correct the current sprite alignment before going back."
		return
	if _page > 0:
		_page -= 1
		_render_page()


func _on_next_pressed() -> void:
	if _page == 0:
		_draft.set_identity(_display_name_input.text, _fighter_id_input.text)
		var identity_errors: Array[Dictionary] = _draft.validate_identity()
		if not identity_errors.is_empty():
			_status_label.text = _format_errors(identity_errors)
			return
	elif _page == 1:
		var config_errors: Array[Dictionary] = _draft.validate()
		if not config_errors.is_empty():
			_status_label.text = _format_errors(config_errors)
			return
		if not _alignment_draft.configure(_draft.fighter_id):
			_status_label.text = _alignment_draft.last_error
			return
	elif _page == 3 and _aligner != null and not _aligner.save_pending_changes():
		_status_label.text = "Save or correct the current sprite alignment before continuing."
		return
	_page = mini(_page + 1, 4)
	_render_page()


func _on_create_pressed() -> void:
	_sync_alignment_progress()
	var result: Dictionary = _draft.create_user_draft()
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	var presentation_result: Dictionary = _alignment_draft.save()
	if not bool(presentation_result.get("ok", false)):
		_status_label.text = _format_errors(presentation_result.get("errors", []))
		return
	_draft.save_art_manifests()
	var completed: int = _draft.get_completed_required_art_slots()
	var required: int = _draft.get_required_art_slot_total()
	_status_label.text = "Draft saved at %s\nArt: %d / %d  |  Aligned: %d / %d  |  %s. Not playable yet." % [str(result.get("path", "user://characters/")), completed, required, _draft.aligned_art_slots, _draft.assigned_art_slots, _draft.get_creator_status()]
	_create_button.disabled = true
	print("[CreatorWizard] saved draft=%s art=%d/%d aligned=%d/%d status=%s" % [_draft.fighter_id, completed, required, _draft.aligned_art_slots, _draft.assigned_art_slots, _draft.get_creator_status()])


func _on_cancel_pressed() -> void:
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	get_tree().change_scene_to_file(PROJECT_DETAIL_PATH if context != null and bool(context.call("has_project")) else MAIN_MENU_PATH)


func _animation_title(animation_id: String) -> String:
	match animation_id:
		"idle":
			return "IDLE"
		"jab":
			return "LIGHT ATTACK / JAB"
		"heavy":
			return "HEAVY ATTACK"
		"block":
			return "BLOCK"
		"dodge":
			return "DODGE"
		"hit":
			return "HIT"
		"dead":
			return "DEAD"
	return animation_id.to_upper()


func _open_art_picker(slot_id: String) -> void:
	_pending_slot_id = slot_id
	_file_dialog.popup_centered_ratio(0.9)


func _on_art_file_selected(source_path: String) -> void:
	if _pending_slot_id.is_empty():
		return
	var imported_slot_id: String = _pending_slot_id
	var create_result: Dictionary = _draft.create_user_draft()
	if not bool(create_result.get("ok", false)):
		_status_label.text = _format_errors(create_result.get("errors", []))
		return
	var result: Dictionary = ArtImporter.import_png(_draft.get_user_draft_path(), _draft.fighter_id, _draft.slot_manifest, _pending_slot_id, source_path)
	_pending_slot_id = ""
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	var relative_path: String = "sprites/%s.png" % imported_slot_id
	if not _alignment_draft.mark_replaced(imported_slot_id, relative_path, int(result.get("width", 0)), int(result.get("height", 0))):
		_status_label.text = _alignment_draft.last_error
		return
	var save_result: Dictionary = _draft.save_art_manifests()
	if not bool(save_result.get("ok", false)):
		_status_label.text = _format_errors(save_result.get("errors", []))
		return
	var alignment_save: Dictionary = _alignment_draft.save()
	if not bool(alignment_save.get("ok", false)):
		_status_label.text = _format_errors(alignment_save.get("errors", []))
		return
	_sync_alignment_progress()
	_draft.save_art_manifests()
	_render_page()
	_status_label.text = "Imported %s (%dx%d). Original file was not changed." % [_slot_title(imported_slot_id), int(result.get("width", 0)), int(result.get("height", 0))]


func _remove_art_slot(slot_id: String) -> void:
	var result: Dictionary = ArtImporter.remove_slot(_draft.get_user_draft_path(), _draft.fighter_id, _draft.slot_manifest, slot_id)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	_alignment_draft.remove_slot(slot_id)
	var alignment_save: Dictionary = _alignment_draft.save()
	if not bool(alignment_save.get("ok", false)):
		_status_label.text = _format_errors(alignment_save.get("errors", []))
		return
	_sync_alignment_progress()
	var save_result: Dictionary = _draft.save_art_manifests()
	if not bool(save_result.get("ok", false)):
		_status_label.text = _format_errors(save_result.get("errors", []))
		return
	_render_page()
	_status_label.text = "%s removed from this draft." % _slot_title(slot_id)


func _render_alignment_page() -> void:
	_alignment_draft.synchronize_slots(_draft.slot_manifest)
	_sync_alignment_progress()
	if _draft.draft_created:
		_alignment_draft.save()
		_draft.save_art_manifests()
	var aligner_node: Node = AlignerScene.instantiate()
	_aligner = aligner_node as RollbackFighterCreatorSpriteAligner
	_aligner.configure(_alignment_draft, _draft.slot_manifest)
	_aligner.draft_changed.connect(_on_alignment_changed)
	_aligner.custom_minimum_size.y = 900.0
	_page_container.add_child(_aligner)


func _on_alignment_changed() -> void:
	_sync_alignment_progress()
	if _draft.draft_created:
		_alignment_draft.save()
		_draft.save_art_manifests()


func _sync_alignment_progress() -> void:
	if _alignment_draft == null or _draft == null:
		return
	var assigned: int = _alignment_draft.get_manifest_assigned_count(_draft.slot_manifest)
	var aligned: int = _alignment_draft.get_aligned_count(_draft.slot_manifest)
	_draft.set_alignment_progress(assigned, aligned)


func _refresh_art_progress() -> void:
	if _art_progress_label != null:
		_art_progress_label.text = "Required art: %d / %d  |  Optional art: %d / %d" % [
			_draft.get_completed_required_art_slots(),
			_draft.get_required_art_slot_total(),
			_draft.get_completed_optional_art_slots(),
			_draft.get_optional_art_slot_total(),
		]


func _slot_title(slot_id: String) -> String:
	var words: PackedStringArray = slot_id.split("_")
	var label: String = ""
	for index in words.size():
		var word: String = words[index]
		if index == words.size() - 1 and word.is_valid_int():
			label += " %d" % (int(word) + 1)
		else:
			label += (" " if not label.is_empty() else "") + word.capitalize()
	return label


func _format_errors(errors: Array) -> String:
	if errors.is_empty():
		return "The draft could not be validated."
	var lines: PackedStringArray = PackedStringArray()
	for error_value in errors:
		if error_value is Dictionary:
			lines.append("%s: %s (%s)" % [str(error_value.get("field", "config")), str(error_value.get("expected_rule", "invalid")), str(error_value.get("invalid_value", ""))])
	return "Cannot continue:\n%s" % "\n".join(lines)
