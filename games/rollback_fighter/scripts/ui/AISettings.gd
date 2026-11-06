extends Control

const MAIN_MENU_SCENE_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const AIServiceScript = preload("res://games/rollback_fighter/scripts/ai_services/AIService.gd")

var _service: Node
var _enabled_toggle: CheckButton
var _provider_selector: OptionButton
var _credential_input: LineEdit
var _text_model_input: LineEdit
var _image_model_input: LineEdit
var _endpoint_input: LineEdit
var _capability_label: Label
var _status_label: Label


func _ready() -> void:
	_service = AIServiceScript.new()
	add_child(_service)
	_build_ui()
	_load_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(clampf(get_viewport_rect().size.x - 40.0, 260.0, 560.0), 0.0)
	panel.add_theme_constant_override("separation", 10)
	center.add_child(panel)

	var title := Label.new()
	title.text = "AI SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)
	var note := Label.new()
	note.text = "Optional creator assistance. Settings and credentials stay on this device."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(note)

	_enabled_toggle = CheckButton.new()
	_enabled_toggle.text = "Enable AI assistance"
	panel.add_child(_enabled_toggle)
	_add_label(panel, "Provider")
	_provider_selector = OptionButton.new()
	_provider_selector.item_selected.connect(_on_provider_selected)
	panel.add_child(_provider_selector)
	_add_label(panel, "Credential / API key")
	_credential_input = LineEdit.new()
	_credential_input.secret = true
	_credential_input.secret_character = "•"
	_credential_input.placeholder_text = "Stored locally under user://settings"
	_credential_input.clear_button_enabled = true
	panel.add_child(_credential_input)
	_add_label(panel, "Text model")
	_text_model_input = LineEdit.new()
	panel.add_child(_text_model_input)
	_add_label(panel, "Image model (optional; not enabled in AI1)")
	_image_model_input = LineEdit.new()
	panel.add_child(_image_model_input)
	_add_label(panel, "Endpoint override (optional HTTPS URL; use {model})")
	_endpoint_input = LineEdit.new()
	panel.add_child(_endpoint_input)
	_capability_label = Label.new()
	_capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_capability_label)

	var test_button := _make_button("Test Connection")
	test_button.pressed.connect(_on_test_connection_pressed)
	panel.add_child(test_button)
	var save_button := _make_button("Save")
	save_button.pressed.connect(_on_save_pressed)
	panel.add_child(save_button)
	var clear_button := _make_button("Clear Credentials")
	clear_button.pressed.connect(_on_clear_credentials_pressed)
	panel.add_child(clear_button)
	var back_button := _make_button("Back")
	back_button.pressed.connect(_on_back_pressed)
	panel.add_child(back_button)
	_status_label = Label.new()
	_status_label.text = "AI assistance is optional."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)


func _load_ui() -> void:
	_enabled_toggle.button_pressed = bool(_service.enabled)
	var selected_id: String = str(_service.get_selected_provider_id())
	for provider: Dictionary in _service.list_providers():
		_provider_selector.add_item(str(provider.display_name))
		var index: int = _provider_selector.item_count - 1
		_provider_selector.set_item_metadata(index, str(provider.provider_id))
		if str(provider.provider_id) == selected_id:
			_provider_selector.select(index)
	_show_selected_config()


func _show_selected_config() -> void:
	var provider_id: String = _selected_provider_id()
	if provider_id.is_empty() or not _service.select_provider(provider_id):
		return
	var config: Variant = _service.get_provider_config(provider_id)
	if config == null:
		return
	_credential_input.text = str(config.api_key)
	_text_model_input.text = str(config.text_model)
	_image_model_input.text = str(config.image_model)
	_endpoint_input.text = str(config.endpoint_override)
	var capabilities: Array[String] = []
	for capability: String in ["TEXT", "STRUCTURED_OUTPUT", "IMAGE_GENERATION"]:
		if _service.supports(capability):
			capabilities.append(capability)
	_capability_label.text = "Capabilities: %s" % ", ".join(capabilities)


func _capture_ui() -> bool:
	var provider_id: String = _selected_provider_id()
	var config: Variant = _service.get_provider_config(provider_id)
	if config == null:
		return false
	config.api_key = _credential_input.text.strip_edges()
	config.text_model = _text_model_input.text.strip_edges()
	config.image_model = _image_model_input.text.strip_edges()
	config.endpoint_override = _endpoint_input.text.strip_edges()
	config.enabled = true
	_service.enabled = _enabled_toggle.button_pressed
	return bool(_service.set_provider_config(config))


func _selected_provider_id() -> String:
	if _provider_selector.item_count == 0 or _provider_selector.selected < 0:
		return ""
	return str(_provider_selector.get_item_metadata(_provider_selector.selected))


func _on_provider_selected(_index: int) -> void:
	_show_selected_config()


func _on_test_connection_pressed() -> void:
	if not _capture_ui():
		_status_label.text = "Could not read the selected provider configuration."
		return
	_status_label.text = "Testing connection..."
	var result: Dictionary = await _service.test_connection()
	_status_label.text = str(result.user_message)


func _on_save_pressed() -> void:
	if not _capture_ui():
		_status_label.text = "Could not save the selected provider configuration."
		return
	var error: Error = _service.save_settings()
	_status_label.text = "AI settings saved locally." if error == OK else "Could not save AI settings."


func _on_clear_credentials_pressed() -> void:
	var provider_id: String = _selected_provider_id()
	var error: Error = _service.clear_credentials(provider_id)
	_credential_input.clear()
	_status_label.text = "Credentials cleared." if error == OK else "Could not clear credentials."


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _add_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	return button
