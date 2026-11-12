extends Control

const BackgroundPlayerScript = preload("res://games/rollback_fighter/scripts/ui/MainMenuBackgroundPlayer.gd")
const CrestPlayerScript = preload("res://games/rollback_fighter/scripts/ui/MainMenuCrestPlayer.gd")
const SignalingClientScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingClient.gd")
const SignalingRoomStoreScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingRoomStore.gd")
const MatchConfigHandshakeScript = preload("res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd")
const ConnectionMethodRegistryScript = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionMethodRegistry.gd")
const CHARACTER_SELECT_SCENE_PATH := "res://games/rollback_fighter/scenes/CharacterSelect.tscn"
const CREATOR_WIZARD_SCENE_PATH := "res://games/rollback_fighter/scenes/CreatorWizard.tscn"
const CREATE_GAME_SCENE_PATH := "res://games/rollback_fighter/scenes/CreateGameWizard.tscn"
const MY_GAMES_SCENE_PATH := "res://games/rollback_fighter/scenes/MyGames.tscn"
const AI_SETTINGS_SCENE_PATH := "res://games/rollback_fighter/scenes/AISettings.tscn"
const NETWORK_SETTINGS_PATH := "user://network_settings.cfg"
const DEFAULT_PORT := 7777
const DEFAULT_SIGNALING_URL := "http://127.0.0.1:8787"
const LANGUAGE_ORDER := ["en", "es", "ko"]
const MENU_LABELS := {
	"play": {"en": "PLAY", "es": "JUGAR", "ko": "플레이"},
	"single_player": {"en": "SINGLE PLAYER", "es": "UN JUGADOR", "ko": "싱글 플레이"},
	"host": {"en": "HOST", "es": "ANFITRIÓN", "ko": "방 만들기"},
	"join": {"en": "JOIN", "es": "UNIRSE", "ko": "참가"},
	"create_fighter": {"en": "CREATE FIGHTER", "es": "CREAR LUCHADOR", "ko": "파이터 만들기"},
	"create_game": {"en": "CREATE GAME", "es": "CREAR JUEGO", "ko": "게임 만들기"},
	"my_games": {"en": "MY GAMES", "es": "MIS JUEGOS", "ko": "내 게임"},
	"ai_settings": {"en": "AI SETTINGS", "es": "AJUSTES IA", "ko": "AI 설정"},
	"quit": {"en": "QUIT", "es": "SALIR", "ko": "종료"},
	"address": {"en": "ADDRESS", "es": "DIRECCIÓN", "ko": "주소"},
	"port": {"en": "PORT", "es": "PUERTO", "ko": "포트"},
	"ready": {"en": "READY", "es": "LISTO", "ko": "준비 완료"},
}
const SIGNALING_LABELS := {
	"host_online": {"en": "HOST ONLINE", "es": "ANFITRION EN LINEA", "ko": "온라인 방 만들기"},
	"join_online": {"en": "JOIN ONLINE", "es": "UNIRSE EN LINEA", "ko": "온라인 참가"},
	"direct_ip": {"en": "DEVELOPER / DIRECT IP", "es": "DESARROLLO / IP DIRECTA", "ko": "개발자 / 직접 IP"},
	"room_code": {"en": "ROOM CODE", "es": "CODIGO DE SALA", "ko": "방 코드"},
	"signaling_server": {"en": "SIGNALING SERVER", "es": "SERVIDOR DE SENALIZACION", "ko": "시그널링 서버"},
}

var _address_input: LineEdit
var _port_input: SpinBox
var _room_code_input: LineEdit
var _signaling_url_input: LineEdit
var _status_label: Label
var _signaling_request_active := false


func _ready() -> void:
	_build_ui()
	_load_settings()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = BackgroundPlayerScript.new()
	add_child(background)
	var crest = CrestPlayerScript.new()
	add_child(crest)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 18)
	outer_margin.add_theme_constant_override("margin_top", 18)
	outer_margin.add_theme_constant_override("margin_right", 196 if get_viewport_rect().size.x >= 760.0 else 136)
	outer_margin.add_theme_constant_override("margin_bottom", 18)
	add_child(outer_margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_margin.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var menu_stack: VBoxContainer = VBoxContainer.new()
	var crest_gutter: float = 196.0 if get_viewport_rect().size.x >= 760.0 else 136.0
	menu_stack.custom_minimum_size.x = clampf(get_viewport_rect().size.x - crest_gutter - 42.0, 280.0, 820.0)
	menu_stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_stack.add_theme_constant_override("separation", 6)
	center.add_child(menu_stack)

	menu_stack.add_child(_make_title_bar("hypermundo presenta:", 16, Color(0.86, 0.86, 0.82)))
	menu_stack.add_child(_make_title_bar("¡¡¡ Ocean Fight !!!", 42, Color.WHITE))
	_add_action_row(menu_stack, "play", _on_single_player_pressed)
	_add_action_row(menu_stack, "single_player", _on_single_player_pressed)
	_add_connection_method_catalog(menu_stack)
	menu_stack.add_child(_make_field_label("room_code"))
	_room_code_input = LineEdit.new()
	_room_code_input.placeholder_text = "BEACH7"
	_room_code_input.max_length = 8
	_room_code_input.custom_minimum_size = Vector2(180.0, 38.0)
	_apply_field_style(_room_code_input)
	menu_stack.add_child(_room_code_input)
	_add_action_row(menu_stack, "host_online", _on_host_online_pressed)
	_add_action_row(menu_stack, "join_online", _on_join_online_pressed)
	menu_stack.add_child(_make_field_label("signaling_server"))
	_signaling_url_input = LineEdit.new()
	_signaling_url_input.placeholder_text = DEFAULT_SIGNALING_URL
	_signaling_url_input.custom_minimum_size = Vector2(300.0, 38.0)
	_apply_field_style(_signaling_url_input)
	menu_stack.add_child(_signaling_url_input)
	menu_stack.add_child(_make_title_bar(_trilingual_text("direct_ip"), 12, Color(0.78, 0.78, 0.72)))
	_add_action_row(menu_stack, "host", _on_host_pressed)

	var address_label: Label = _make_field_label("address")
	menu_stack.add_child(address_label)
	_address_input = LineEdit.new()
	_address_input.placeholder_text = "IP address / dirección IP / IP 주소"
	_address_input.clear_button_enabled = true
	_address_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_address_input.custom_minimum_size = Vector2(300.0, 38.0)
	_apply_field_style(_address_input)
	menu_stack.add_child(_address_input)

	var port_label: Label = _make_field_label("port")
	menu_stack.add_child(port_label)
	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.step = 1
	_port_input.value = DEFAULT_PORT
	_port_input.custom_minimum_size = Vector2(150.0, 38.0)
	_apply_field_style(_port_input.get_line_edit())
	menu_stack.add_child(_port_input)
	_add_action_row(menu_stack, "join", _on_join_pressed)
	_add_action_row(menu_stack, "create_fighter", _on_creator_pressed)
	_add_action_row(menu_stack, "create_game", _on_create_game_pressed)
	_add_action_row(menu_stack, "my_games", _on_my_games_pressed)
	_add_action_row(menu_stack, "ai_settings", _on_ai_settings_pressed)
	_add_action_row(menu_stack, "quit", _on_quit_pressed)

	_status_label = Label.new()
	_status_label.text = _trilingual_text("ready")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	menu_stack.add_child(_status_label)


func _add_connection_method_catalog(parent: VBoxContainer) -> void:
	parent.add_child(_make_title_bar("MULTIPLAYER CONNECTION METHODS", 16, Color(0.92, 0.92, 0.86)))
	var registry = ConnectionMethodRegistryScript.create_default()
	for definition in registry.get_definitions():
		var button: Button = _make_censor_button(
			"%s\n%s\n%s" % [definition.display_name, definition.availability, definition.description]
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(300.0, 66.0)
		button.disabled = not definition.is_launchable()
		button.tooltip_text = definition.description
		if not button.disabled:
			button.pressed.connect(_on_connection_method_metadata_pressed.bind(definition.id))
		parent.add_child(button)


func _on_connection_method_metadata_pressed(method_id: String) -> void:
	match method_id:
		"room_code_p2p":
			_status_label.text = "ROOM CODE is experimental. Use Host Online or Join Online below."
		"lan":
			_status_label.text = "For the same WiFi/LAN, use the existing Host and Join controls below."
		"direct_ip_vpn":
			_status_label.text = "For direct IP, Tailscale, or ZeroTier, use Host and Join below."


func _add_action_row(parent: VBoxContainer, text_key: String, callback: Callable) -> void:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)
	var translations: Dictionary = _translations_for(text_key)
	for language: String in LANGUAGE_ORDER:
		var button: Button = _make_censor_button(str(translations.get(language, text_key)))
		button.pressed.connect(callback)
		row.add_child(button)


func _make_censor_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.94, 0.94, 0.9))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.78))
	button.add_theme_stylebox_override("normal", _make_censor_style(Color(0.005, 0.005, 0.005, 0.96)))
	button.add_theme_stylebox_override("hover", _make_censor_style(Color(0.12, 0.12, 0.1, 0.98)))
	button.add_theme_stylebox_override("pressed", _make_censor_style(Color(0.03, 0.03, 0.025, 1.0)))
	button.add_theme_stylebox_override("focus", _make_censor_style(Color(0.08, 0.08, 0.07, 1.0)))
	return button


func _make_censor_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.58, 0.58, 0.52, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _make_title_bar(text: String, font_size: int, color: Color) -> PanelContainer:
	var bar: PanelContainer = PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", _make_censor_style(Color(0.0, 0.0, 0.0, 0.9)))
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	bar.add_child(label)
	return bar


func _make_field_label(text_key: String) -> Label:
	var label: Label = Label.new()
	label.text = _trilingual_text(text_key)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _trilingual_text(text_key: String) -> String:
	var translations: Dictionary = _translations_for(text_key)
	var labels: PackedStringArray = PackedStringArray()
	for language: String in LANGUAGE_ORDER:
		labels.append(str(translations.get(language, text_key)))
	return " / ".join(labels)


func _translations_for(text_key: String) -> Dictionary:
	if SIGNALING_LABELS.has(text_key):
		return SIGNALING_LABELS[text_key]
	return MENU_LABELS.get(text_key, {})


func _apply_field_style(field: LineEdit) -> void:
	field.add_theme_font_size_override("font_size", 14)
	field.add_theme_color_override("font_color", Color.WHITE)
	field.add_theme_color_override("font_placeholder_color", Color(0.68, 0.68, 0.64))
	field.add_theme_stylebox_override("normal", _make_censor_style(Color(0.0, 0.0, 0.0, 0.9)))
	field.add_theme_stylebox_override("focus", _make_censor_style(Color(0.06, 0.06, 0.05, 0.96)))


func _on_host_pressed() -> void:
	_clear_project_context()
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null or not bool(launch_config.call("set_host", int(_port_input.value))):
		_status_label.text = "Enter a port from 1 to 65535."
		return
	_status_label.text = "Hosting on port %d\nWaiting for player..." % int(_port_input.value)
	_launch_arena()


func _on_host_online_pressed() -> void:
	if _signaling_request_active:
		return
	_clear_project_context()
	var client = _new_signaling_client()
	if client == null:
		return
	_signaling_request_active = true
	_status_label.text = "Creating room..."
	var result: Dictionary = await client.create_room(
		{"transport": "enet_udp", "address": "127.0.0.1", "port": int(_port_input.value)},
		_signaling_identity()
	)
	_signaling_request_active = false
	client.queue_free()
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("user_message", "Could not create a room."))
		return
	var room: Dictionary = result.get("data", {})
	var room_context := _signaling_context(room, true)
	var nat_coordinator: Node = get_node_or_null("/root/NatTraversalCoordinator")
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if (
		nat_coordinator == null
		or launch_config == null
		or not bool(nat_coordinator.call("start_traversal", room_context, int(_port_input.value), _signaling_udp_host(str(room_context["server_url"]))))
		or not bool(launch_config.call("set_online_host", int(_port_input.value), room_context))
	):
		if nat_coordinator != null:
			nat_coordinator.call("cancel")
		if launch_config != null:
			launch_config.call("clear")
		_status_label.text = "Could not configure the online room."
		return
	_save_settings(_address_input.text.strip_edges(), int(_port_input.value))
	_status_label.text = "Room Code: %s\nWaiting for opponent..." % str(room.get("room_code", ""))
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


func _on_ai_settings_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(AI_SETTINGS_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open AI Settings."


func _on_quit_pressed() -> void:
	get_tree().quit()


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


func _on_join_online_pressed() -> void:
	if _signaling_request_active:
		return
	_clear_project_context()
	var room_code := SignalingRoomStoreScript.normalize_room_code(_room_code_input.text)
	if not SignalingRoomStoreScript.is_valid_room_code(room_code):
		_status_label.text = "Enter a valid 6-character room code."
		return
	var client = _new_signaling_client()
	if client == null:
		return
	_signaling_request_active = true
	_status_label.text = "Joining room %s..." % room_code
	var result: Dictionary = await client.join_room(
		room_code,
		{"transport": "enet_udp", "address": "127.0.0.1", "port": 0},
		_signaling_identity()
	)
	_signaling_request_active = false
	client.queue_free()
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("user_message", "Could not join the room."))
		return
	var room: Dictionary = result.get("data", {})
	var room_context := _signaling_context(room, false)
	var nat_coordinator: Node = get_node_or_null("/root/NatTraversalCoordinator")
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if (
		nat_coordinator == null
		or launch_config == null
		or not bool(nat_coordinator.call("start_traversal", room_context, 0, _signaling_udp_host(str(room_context["server_url"]))))
		or not bool(launch_config.call("set_online_client", room_context))
	):
		if nat_coordinator != null:
			nat_coordinator.call("cancel")
		if launch_config != null:
			launch_config.call("clear")
		_status_label.text = "Could not start direct connection setup."
		return
	_save_settings(_address_input.text.strip_edges(), int(_port_input.value))
	_status_label.text = "Connecting directly..."
	_launch_arena()


func _new_signaling_client():
	var client = SignalingClientScript.new()
	add_child(client)
	var server_url := _signaling_url_input.text.strip_edges()
	if server_url.is_empty():
		server_url = DEFAULT_SIGNALING_URL
	if not client.configure(server_url):
		client.queue_free()
		_status_label.text = "Enter a valid HTTP or HTTPS signaling server URL."
		return null
	return client


func _signaling_identity() -> Dictionary:
	return {
		"protocol_version": MatchConfigHandshakeScript.PROTOCOL_VERSION,
		"game_id": "rollback_fighter",
	}


func _signaling_context(room: Dictionary, is_host: bool) -> Dictionary:
	var server_url := _signaling_url_input.text.strip_edges()
	if server_url.is_empty():
		server_url = DEFAULT_SIGNALING_URL
	return {
		"room_code": str(room.get("room_code", "")),
		"session_id": str(room.get("session_id", "")),
		"peer_id": str(room.get("peer_id", "")),
		"server_url": server_url,
		"is_host": is_host,
		"opponent_connected": bool(room.get("opponent_connected", false)),
		"host_endpoint": Dictionary(room.get("host_endpoint", {})).duplicate(true),
		"guest_endpoint": Dictionary(room.get("guest_endpoint", {})).duplicate(true),
		"probe_id": str(room.get("probe_id", "")),
		"opponent_probe_id": str(room.get("opponent_probe_id", "")),
		"traversal_token": str(room.get("traversal_token", "")),
		"signaling_udp_port": int(room.get("signaling_udp_port", 0)),
		"host_udp_registered": bool(room.get("host_udp_registered", false)),
		"guest_udp_registered": bool(room.get("guest_udp_registered", false)),
	}


func _signaling_udp_host(server_url: String) -> String:
	var authority := server_url.strip_edges().trim_suffix("/")
	var scheme_index := authority.find("://")
	if scheme_index >= 0:
		authority = authority.substr(scheme_index + 3)
	authority = authority.get_slice("/", 0)
	if authority.begins_with("["):
		var closing := authority.find("]")
		return authority.substr(1, closing - 1) if closing > 1 else ""
	return authority.get_slice(":", 0)


func _launch_arena() -> void:
	var error: Error = get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH)
	if error != OK:
		_status_label.text = "Could not open character select."
		var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
		if launch_config != null:
			launch_config.call("clear")


func _clear_project_context() -> void:
	var nat_coordinator: Node = get_node_or_null("/root/NatTraversalCoordinator")
	if nat_coordinator != null:
		nat_coordinator.call("cancel")
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context != null:
		context.call("launch_global")
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null:
		project_context.call("clear")


func _load_settings() -> void:
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(NETWORK_SETTINGS_PATH) != OK:
		_signaling_url_input.text = DEFAULT_SIGNALING_URL
		return
	_address_input.text = str(settings.get_value("join", "last_address", ""))
	_signaling_url_input.text = str(settings.get_value("signaling", "server_url", DEFAULT_SIGNALING_URL))
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
	var signaling_url := _signaling_url_input.text.strip_edges()
	settings.set_value("signaling", "server_url", signaling_url if not signaling_url.is_empty() else DEFAULT_SIGNALING_URL)
	var error: Error = settings.save(NETWORK_SETTINGS_PATH)
	if error != OK:
		push_warning("[MainMenu] Could not save network settings: %d" % error)
