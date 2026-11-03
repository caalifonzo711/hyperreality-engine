extends Control

const MAIN_MENU_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const CREATOR_WIZARD_PATH := "res://games/rollback_fighter/scenes/CreatorWizard.tscn"
const PROJECT_DETAIL_PATH := "res://games/rollback_fighter/scenes/ProjectDetail.tscn"
const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const PresentationDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationDefinition.gd")
const PresentationStoreScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationStore.gd")
const AssetImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAssetImporter.gd")
const AudioImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAudioImporter.gd")
const STYLE_IDS := ["platform_fighter", "footsies", "anime_fighter", "custom"]
const STYLE_LABELS := ["Platform Fighter", "Footsies", "Anime Fighter", "Custom"]
const STEP_TITLES := ["IDENTITY", "STYLE", "BACKGROUND", "AUDIO / BRANDING", "REVIEW"]

var _step := 0
var _content: VBoxContainer
var _step_label: Label
var _status_label: Label
var _back_button: Button
var _next_button: Button
var _name_input: LineEdit
var _id_input: LineEdit
var _style_selector: OptionButton
var _id_is_manual := false
var _updating_id := false
var _created_project_id := ""
var _presentation: RollbackFighterProjectPresentationDefinition
var _image_dialog: FileDialog
var _audio_dialog: FileDialog
var _pending_image_kind := ""
var _pending_audio_slot := ""
var _audio_preview: AudioStreamPlayer
var _selected_style := "platform_fighter"
var _editing_existing := false

func _ready() -> void:
	_load_edit_context()
	_build_shell()
	_show_step()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 32.0, 300.0, 700.0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var heading := Label.new()
	heading.text = "CREATE A GAME"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", 21)
	column.add_child(_step_label)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	column.add_child(_content)
	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 42.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	_back_button = _make_button("Back")
	_back_button.pressed.connect(_on_back_pressed)
	actions.add_child(_back_button)
	var cancel := _make_button("Cancel")
	cancel.pressed.connect(_on_cancel_pressed)
	actions.add_child(cancel)
	_next_button = _make_button("Next")
	_next_button.pressed.connect(_on_next_pressed)
	actions.add_child(_next_button)
	_image_dialog = FileDialog.new()
	_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_image_dialog.file_selected.connect(_on_image_selected)
	add_child(_image_dialog)
	_audio_dialog = FileDialog.new()
	_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.filters = PackedStringArray(["*.wav, *.ogg ; Audio"])
	_audio_dialog.file_selected.connect(_on_audio_selected)
	add_child(_audio_dialog)
	_audio_preview = AudioStreamPlayer.new()
	add_child(_audio_preview)

func _show_step() -> void:
	for child in _content.get_children():
		child.queue_free()
	_status_label.text = ""
	_step_label.text = "STEP %d — %s" % [_step + 1, STEP_TITLES[_step]]
	_back_button.disabled = _step == 0
	_next_button.text = ("Return to Project" if _editing_existing else "Add Fighter") if _step == 4 else "Next"
	match _step:
		0: _build_identity_step()
		1: _build_style_step()
		2: _build_background_step()
		3: _build_audio_branding_step()
		4: _build_review_step()

func _build_identity_step() -> void:
	_add_label("Game Name")
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "My Fighting Game"
	_name_input.text_changed.connect(_on_name_changed)
	_name_input.editable = _created_project_id.is_empty()
	_content.add_child(_name_input)
	_add_label("Project ID  (a-z, 0-9, underscore)")
	_id_input = LineEdit.new()
	_id_input.placeholder_text = "my_fighting_game"
	_id_input.text_changed.connect(_on_id_changed)
	_id_input.editable = _created_project_id.is_empty()
	_content.add_child(_id_input)
	if _presentation != null:
		_name_input.text = _presentation.display_name
		_id_input.text = _presentation.project_id

func _build_style_step() -> void:
	_add_label("Choose the fighter presentation style. This does not change authoritative gameplay.")
	_style_selector = OptionButton.new()
	for index in STYLE_IDS.size():
		_style_selector.add_item(STYLE_LABELS[index])
		_style_selector.set_item_metadata(index, STYLE_IDS[index])
	_style_selector.selected = maxi(0, STYLE_IDS.find(_selected_style))
	_style_selector.item_selected.connect(_on_style_selected)
	if not _created_project_id.is_empty():
		var loaded := ProjectStoreScript.new().load_project(_created_project_id)
		if bool(loaded.get("ok", false)):
			var selected_style: String = loaded["project"].style_preset
			_selected_style = selected_style
			_style_selector.selected = maxi(0, STYLE_IDS.find(selected_style))
	_style_selector.disabled = not _created_project_id.is_empty()
	_content.add_child(_style_selector)

func _build_background_step() -> void:
	_add_label("Stage background (optional; PNG, JPG, or WebP)")
	_add_image_editor("background", _presentation.background_image)
	_add_label("Floor / fighting line preview")
	var floor_slider := HSlider.new()
	floor_slider.min_value = 0.50
	floor_slider.max_value = 0.95
	floor_slider.step = 0.01
	floor_slider.value = _presentation.floor_y_normalized
	floor_slider.value_changed.connect(_on_floor_changed)
	_content.add_child(floor_slider)
	_add_label("The floor marker is presentation metadata only; it does not change collision or world rules.")

func _build_audio_branding_step() -> void:
	_add_label("Logo / title image (optional)")
	_add_image_editor("logo", _presentation.logo_image)
	_add_label("Project audio (optional; WAV or OGG)")
	for slot_id in PresentationDefinitionScript.AUDIO_SLOT_IDS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(slot_id).replace("_", " ").capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var assigned := not str(_presentation.audio_slots.get(slot_id, "")).is_empty()
		var add := _make_button("Replace" if assigned else "Add")
		add.pressed.connect(_choose_audio.bind(slot_id))
		row.add_child(add)
		var preview := _make_button("Test")
		preview.disabled = not assigned
		preview.pressed.connect(_preview_audio.bind(slot_id))
		row.add_child(preview)
		var remove := _make_button("Remove")
		remove.disabled = not assigned
		remove.pressed.connect(_remove_audio.bind(slot_id))
		row.add_child(remove)
		_content.add_child(row)

func _build_review_step() -> void:
	_add_label(_presentation.display_name)
	_add_label("Project ID: %s" % _presentation.project_id)
	var project_result := ProjectStoreScript.new().load_project(_presentation.project_id)
	var style := "platform_fighter"
	if bool(project_result.get("ok", false)):
		style = project_result["project"].style_preset
	_add_label("Style: %s" % style.replace("_", " ").capitalize())
	_add_label("Background: %s" % ("custom" if not _presentation.background_image.is_empty() else "built-in default"))
	_add_label("Logo: %s" % ("custom" if not _presentation.logo_image.is_empty() else "text title"))
	_add_label("Audio overrides: %d / %d" % [_presentation.audio_slots.size(), PresentationDefinitionScript.AUDIO_SLOT_IDS.size()])
	_add_label("Project saved as a draft. Add Fighter opens the existing project-aware fighter creator.")

func _add_image_editor(kind: String, path: String) -> void:
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(0.0, 180.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = AssetImporterScript.new().load_texture(path)
	_content.add_child(preview)
	var row := HBoxContainer.new()
	var add := _make_button("Replace" if not path.is_empty() else "Add")
	add.pressed.connect(_choose_image.bind(kind))
	row.add_child(add)
	var remove := _make_button("Remove")
	remove.disabled = path.is_empty()
	remove.pressed.connect(_remove_image.bind(kind))
	row.add_child(remove)
	_content.add_child(row)

func _on_next_pressed() -> void:
	if _step == 0:
		if _name_input.text.strip_edges().is_empty() or not ProjectDefinitionScript.is_safe_id(_id_input.text.strip_edges()):
			_status_label.text = "Enter a game name and a project ID matching [a-z0-9_]+."
			return
		var pending := PresentationDefinitionScript.new()
		pending.configure(_id_input.text.strip_edges(), _name_input.text)
		_presentation = pending
	elif _step == 1 and _created_project_id.is_empty():
		var project := ProjectDefinitionScript.new()
		project.configure(_presentation.display_name, _presentation.project_id, _selected_style)
		var created := ProjectStoreScript.new().create(project)
		if not bool(created.get("ok", false)):
			_status_label.text = _format_errors(created.get("errors", []))
			return
		_created_project_id = project.project_id
		var saved := PresentationStoreScript.new().save(_presentation)
		if not bool(saved.get("ok", false)):
			_status_label.text = _format_errors(saved.get("errors", []))
			return
	elif _step == 4:
		if _editing_existing:
			get_tree().change_scene_to_file(PROJECT_DETAIL_PATH)
			return
		_on_add_fighter_pressed()
		return
	_step += 1
	_show_step()

func _on_back_pressed() -> void:
	if _step > 0:
		_step -= 1
		_show_step()

func _choose_image(kind: String) -> void:
	_pending_image_kind = kind
	_image_dialog.popup_centered_ratio(0.8)

func _on_image_selected(path: String) -> void:
	var result := AssetImporterScript.new().import_image(_created_project_id, _pending_image_kind, path)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	if _pending_image_kind == "background":
		_presentation.background_image = str(result["path"])
	else:
		_presentation.logo_image = str(result["path"])
	_save_presentation()
	_show_step()

func _remove_image(kind: String) -> void:
	AssetImporterScript.new().remove_image(_created_project_id, kind)
	if kind == "background":
		_presentation.background_image = ""
	else:
		_presentation.logo_image = ""
	_save_presentation()
	_show_step()

func _choose_audio(slot_id: String) -> void:
	_pending_audio_slot = slot_id
	_audio_dialog.popup_centered_ratio(0.8)

func _on_audio_selected(path: String) -> void:
	var result := AudioImporterScript.new().import_audio(_created_project_id, _pending_audio_slot, path)
	if not bool(result.get("ok", false)):
		_status_label.text = _format_errors(result.get("errors", []))
		return
	_presentation.set_audio_slot(_pending_audio_slot, str(result["path"]))
	_save_presentation()
	_show_step()

func _preview_audio(slot_id: String) -> void:
	var stream: AudioStream = AudioImporterScript.new().load_stream(str(_presentation.audio_slots.get(slot_id, "")))
	if stream != null:
		_audio_preview.stream = stream
		_audio_preview.play()

func _remove_audio(slot_id: String) -> void:
	AudioImporterScript.new().remove_audio(_created_project_id, slot_id)
	_presentation.set_audio_slot(slot_id, "")
	_save_presentation()
	_show_step()

func _on_floor_changed(value: float) -> void:
	_presentation.floor_y_normalized = value
	_save_presentation()

func _save_presentation() -> void:
	var saved := PresentationStoreScript.new().save(_presentation)
	if not bool(saved.get("ok", false)):
		_status_label.text = _format_errors(saved.get("errors", []))

func _on_add_fighter_pressed() -> void:
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context == null or not bool(context.call("launch_for_project", _created_project_id)):
		_status_label.text = "Could not open the fighter creator for this project."
		return
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null:
		project_context.call("open_project", _created_project_id)
	if get_tree().change_scene_to_file(CREATOR_WIZARD_PATH) != OK:
		_status_label.text = "Could not open the fighter creator."

func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file(PROJECT_DETAIL_PATH if _editing_existing else MAIN_MENU_PATH)

func _load_edit_context() -> void:
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context == null or not bool(context.call("has_project")):
		return
	var project_id := str(context.call("get_project_id"))
	var loaded := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	_created_project_id = project.project_id
	_selected_style = project.style_preset
	_presentation = PresentationStoreScript.new().load_or_default(project.project_id, project.display_name)
	_editing_existing = true
	_step = 2

func _on_name_changed(value: String) -> void:
	if _id_is_manual:
		return
	_updating_id = true
	_id_input.text = _id_from_display_name(value)
	_updating_id = false

func _on_id_changed(_value: String) -> void:
	if not _updating_id:
		_id_is_manual = true

func _on_style_selected(index: int) -> void:
	_selected_style = str(_style_selector.get_item_metadata(index))

func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

func _format_errors(errors: Variant) -> String:
	if errors is Array and not errors.is_empty():
		var first: Dictionary = errors[0]
		return "%s: %s" % [str(first.get("field", "project")), str(first.get("expected_rule", "invalid project"))]
	return "Could not save the project."

func _id_from_display_name(value: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]+")
	return regex.sub(value.to_lower(), "_", true).trim_prefix("_").trim_suffix("_")
