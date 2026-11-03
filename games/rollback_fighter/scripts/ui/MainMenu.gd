extends Control

const CHARACTER_SELECT_SCENE_PATH := "res://games/rollback_fighter/scenes/CharacterSelect.tscn"
const CREATOR_WIZARD_SCENE_PATH := "res://games/rollback_fighter/scenes/CreatorWizard.tscn"
const CREATE_GAME_SCENE_PATH := "res://games/rollback_fighter/scenes/CreateGameWizard.tscn"
const MY_GAMES_SCENE_PATH := "res://games/rollback_fighter/scenes/MyGames.tscn"
const NETWORK_SETTINGS_PATH := "user://network_settings.cfg"
const DEFAULT_PORT := 7777

var _address_input: LineEdit
var _port_input: SpinBox
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_load_settings()


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
		clampf(get_viewport_rect().size.x - 40.0, 220.0, 480.0),
		0.0
	)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_constant_override("separation", 12)
	center.add_child(panel)

	var title: Label = Label.new()
	title.text = "ROLLBACK FIGHTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	panel.add_child(title)

	var single_player_button: Button = _make_button("Single Player")
	single_player_button.pressed.connect(_on_single_player_pressed)
	panel.add_child(single_player_button)

	var creator_button: Button = _make_button("Create Fighter")
	creator_button.pressed.connect(_on_creator_pressed)
	panel.add_child(creator_button)

	var create_game_button: Button = _make_button("Create Game")
	create_game_button.pressed.connect(_on_create_game_pressed)
	panel.add_child(create_game_button)
	var my_games_button: Button = _make_button("My Games")
	my_games_button.pressed.connect(_on_my_games_pressed)
	panel.add_child(my_games_button)

	var host_button: Button = _make_button("Host Game")
	host_button.pressed.connect(_on_host_pressed)
	panel.add_child(host_button)

	var join_heading: Label = Label.new()
	join_heading.text = "Join Game"
	join_heading.add_theme_font_size_override("font_size", 20)
	panel.add_child(join_heading)

	var address_label: Label = Label.new()
	address_label.text = "Address"
	panel.add_child(address_label)
	_address_input = LineEdit.new()
	_address_input.placeholder_text = "IP address or hostname"
	_address_input.clear_button_enabled = true
	_address_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_address_input.custom_minimum_size.y = 48.0
	panel.add_child(_address_input)

	var port_label: Label = Label.new()
	port_label.text = "Port (host and join)"
	panel.add_child(port_label)
	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.step = 1
	_port_input.value = DEFAULT_PORT
	_port_input.custom_minimum_size.y = 48.0
	panel.add_child(_port_input)

	var join_button: Button = _make_button("Join Game")
	join_button.pressed.connect(_on_join_pressed)
	panel.add_child(join_button)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)

	var quit_button: Button = _make_button("Quit")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	panel.add_child(quit_button)


func _make_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _on_host_pressed() -> void:
	_clear_project_context()
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null or not bool(launch_config.call("set_host", int(_port_input.value))):
		_status_label.text = "Enter a port from 1 to 65535."
		return
	_status_label.text = "Hosting on port %d\nWaiting for player..." % int(_port_input.value)
	_launch_arena()


func _on_single_player_pressed() -> void:
	_clear_project_context()
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null:
		_status_label.text = "Could not configure Single Player."
		return
	launch_config.call("set_single_player")
	_launch_arena()


func _on_creator_pressed() -> void:
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context != null:
		context.call("launch_global")
	var error: Error = get_tree().change_scene_to_file(CREATOR_WIZARD_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open the Creator Wizard."


func _on_create_game_pressed() -> void:
	_clear_project_context()
	var error: Error = get_tree().change_scene_to_file(CREATE_GAME_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open the Create Game wizard."


func _on_my_games_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(MY_GAMES_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open My Games."


func _on_join_pressed() -> void:
	_clear_project_context()
	var address: String = _address_input.text.strip_edges()
	var port: int = int(_port_input.value)
	if address.is_empty():
		_status_label.text = "Enter an IP address or hostname."
		return
	if port < 1 or port > 65535:
		_status_label.text = "Enter a port from 1 to 65535."
		return
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null or not bool(launch_config.call("set_client", address, port)):
		_status_label.text = "The address or port is invalid."
		return
	_save_settings(address, port)
	_status_label.text = "Connecting to %s:%d..." % [address, port]
	_launch_arena()


func _launch_arena() -> void:
	var error: Error = get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open character select."
		var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
		if launch_config != null:
			launch_config.call("clear")


func _clear_project_context() -> void:
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context != null:
		context.call("launch_global")
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null:
		project_context.call("clear")


func _load_settings() -> void:
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(NETWORK_SETTINGS_PATH) != OK:
		return
	_address_input.text = str(settings.get_value("join", "last_address", ""))
	_port_input.value = clampi(
		int(settings.get_value("join", "last_port", DEFAULT_PORT)),
		1,
		65535
	)


func _save_settings(address: String, port: int) -> void:
	var settings: ConfigFile = ConfigFile.new()
	settings.load(NETWORK_SETTINGS_PATH)
	settings.set_value("join", "last_address", address)
	settings.set_value("join", "last_port", port)
	var error: Error = settings.save(NETWORK_SETTINGS_PATH)
	if error != OK:
		push_warning("[MainMenu] Could not save network settings: %d" % error)
