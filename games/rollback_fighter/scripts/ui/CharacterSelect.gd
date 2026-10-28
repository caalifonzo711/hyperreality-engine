extends Control

const MAIN_MENU_SCENE_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const FIGHTER_ARENA_SCENE_PATH := "res://games/rollback_fighter/scenes/FighterArena.tscn"
const CHARACTER_REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const FighterProviderScript = preload(
	"res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd"
)

var _launch_config: Node
var _mode: String = ""
var _fighters: Dictionary = {}
var _fighter_ids: Array[String] = []
var _p1_selector: OptionButton
var _p2_selector: OptionButton
var _p1_stats: Label
var _p2_stats: Label
var _mode_label: Label
var _status_label: Label
var _start_button: Button
var _leaving: bool = false


func _ready() -> void:
	_build_ui()
	_launch_config = get_node_or_null("/root/NetworkLaunchConfig")
	if _launch_config == null:
		_set_error("Match launch settings are unavailable.")
		return
	var launch: Dictionary = _launch_config.call("get_pending_launch")
	_mode = str(launch.get("mode", ""))
	if _mode not in ["single_player", "host", "client"]:
		_set_error("Return to the Main Menu and choose a match mode.")
		return
	if not _load_registered_fighters():
		return
	_populate_selectors(launch)
	_refresh_selection_details()
	if _mode == "client":
		_mode_label.text = "Join Match — the host selects both fighters."
		_p1_selector.disabled = true
		_p2_selector.disabled = true
		_start_button.text = "Join Match"
	else:
		_mode_label.text = "Single Player" if _mode == "single_player" else "Host Multiplayer"
		_start_button.text = "Start Match"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(
		clampf(get_viewport_rect().size.x - 36.0, 240.0, 560.0), 0.0
	)
	panel.add_theme_constant_override("separation", 12)
	center.add_child(panel)
	var title: Label = Label.new()
	title.text = "CHARACTER SELECT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)
	_mode_label = Label.new()
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_mode_label)
	panel.add_child(_make_heading("P1 Fighter"))
	_p1_selector = _make_selector()
	_p1_selector.item_selected.connect(_on_selection_changed)
	panel.add_child(_p1_selector)
	_p1_stats = _make_stats_label()
	panel.add_child(_p1_stats)
	panel.add_child(_make_heading("P2 / CPU Fighter"))
	_p2_selector = _make_selector()
	_p2_selector.item_selected.connect(_on_selection_changed)
	panel.add_child(_p2_selector)
	_p2_stats = _make_stats_label()
	panel.add_child(_p2_stats)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_status_label)
	_start_button = _make_button("Start Match")
	_start_button.pressed.connect(_on_start_pressed)
	panel.add_child(_start_button)
	var back_button: Button = _make_button("Back")
	back_button.pressed.connect(_on_back_pressed)
	panel.add_child(back_button)


func _make_heading(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 19)
	return label


func _make_selector() -> OptionButton:
	var selector: OptionButton = OptionButton.new()
	selector.custom_minimum_size.y = 54.0
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return selector


func _make_stats_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 56.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _load_registered_fighters() -> bool:
	var provider: RollbackFighterImportedFighterProvider = FighterProviderScript.new()
	_fighter_ids.clear()
	_fighters.clear()
	for fighter_entry: Dictionary in provider.list_fighters():
		var fighter_id: String = str(fighter_entry.get("id", ""))
		var definition_value: Variant = fighter_entry.get("definition")
		if fighter_id.is_empty() or not definition_value is RollbackFighterCharacterDefinition:
			continue
		_fighter_ids.append(fighter_id)
		_fighters[fighter_id] = definition_value
	if _fighter_ids.is_empty():
		_set_error("No registered fighters are available.")
		return false
	return true


func _populate_selectors(launch: Dictionary) -> void:
	for fighter_id: String in _fighter_ids:
		var definition: RollbackFighterCharacterDefinition = _fighters[fighter_id]
		_p1_selector.add_item(definition.get_display_name())
		_p1_selector.set_item_metadata(
			_p1_selector.item_count - 1, fighter_id
		)
		_p2_selector.add_item(definition.get_display_name())
		_p2_selector.set_item_metadata(
			_p2_selector.item_count - 1, fighter_id
		)
	_select_id(_p1_selector, str(launch.get("p1_fighter_id", "example_fighter")))
	_select_id(_p2_selector, str(launch.get("p2_fighter_id", "example_fighter_alt")))


func _select_id(selector: OptionButton, fighter_id: String) -> void:
	for index: int in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == fighter_id:
			selector.select(index)
			return
	if selector.item_count > 0:
		selector.select(0)


func _selected_id(selector: OptionButton) -> String:
	if selector.item_count <= 0 or selector.selected < 0:
		return ""
	return str(selector.get_item_metadata(selector.selected))


func _on_selection_changed(_index: int) -> void:
	_refresh_selection_details()


func _refresh_selection_details() -> void:
	if _p1_selector == null or _p2_selector == null:
		return
	_p1_stats.text = _format_stats(_selected_id(_p1_selector))
	_p2_stats.text = _format_stats(_selected_id(_p2_selector))


func _format_stats(fighter_id: String) -> String:
	if not _fighters.has(fighter_id):
		return ""
	var definition: RollbackFighterCharacterDefinition = _fighters[fighter_id]
	return "HP %d   Speed %d   Jab %d   Heavy %d" % [
		definition.get_int("max_hp"),
		definition.get_int("move_speed"),
		definition.get_move_for_slot("light").get_int("damage"),
		definition.get_move_for_slot("heavy").get_int("damage"),
	]


func _on_start_pressed() -> void:
	if _launch_config == null:
		_set_error("Match launch settings are unavailable.")
		return
	var p1_id: String = _selected_id(_p1_selector)
	var p2_id: String = _selected_id(_p2_selector)
	if not bool(_launch_config.call("set_fighter_selection", p1_id, p2_id)):
		_set_error("Select two valid registered fighters.")
		return
	var error: Error = get_tree().change_scene_to_file(FIGHTER_ARENA_SCENE_PATH)
	if error != OK:
		_set_error("Could not open FighterArena.")


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	if _launch_config != null:
		_launch_config.call("clear")
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _set_error(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	if _start_button != null:
		_start_button.disabled = true
	push_warning("[CharacterSelect] %s" % message)
