extends Node2D

const RULES_SCRIPT = preload("res://games/rollback_shooter/scripts/ShooterRulesDefinition.gd")
const ADAPTER_SCRIPT = preload("res://games/rollback_shooter/scripts/ShooterRollbackAdapter.gd")
const CONFIG_SCRIPT = preload("res://games/rollback_shooter/scripts/ShooterCanonicalConfig.gd")
const HANDSHAKE_SCRIPT = preload("res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd")
const SESSION_SCRIPT = preload("res://games/rollback_fighter/scripts/net/RollbackNetworkSession.gd")
const TRANSPORT_SCRIPT = preload("res://games/rollback_fighter/scripts/net/ENetTransport.gd")
const MENU_SCENE: String = "res://games/rollback_shooter/scenes/ShooterMenu.tscn"
const FIXED_DT: float = 1.0 / 60.0

var mode: String = "local"
var network_player_id: int = 1
var rules: RollbackShooterRulesDefinition
var adapter: RollbackShooterAdapter
var session: RollbackNetworkSession
var transport: ENetTransport
var handshake: RollbackFighterMatchConfigHandshake
var local_identity: Dictionary = {}
var config_verified: bool = false
var accumulator: float = 0.0
var status_label: Label
var hp_label: Label
var result_label: Label
var start_button: Button
var rematch_button: Button
var menu_button: Button
var match_started: bool = false


func _ready() -> void:
	var launch: Dictionary = {}
	if get_tree().has_meta("rollback_shooter_launch"):
		launch = get_tree().get_meta("rollback_shooter_launch")
		get_tree().remove_meta("rollback_shooter_launch")
	mode = str(launch.get("mode", "local"))
	network_player_id = 2 if mode == "client" else 1
	_build_hud()
	rules = RULES_SCRIPT.new()
	var loaded: Dictionary = rules.load_from_resource()
	if not bool(loaded.get("ok", false)):
		status_label.text = "Shooter config error: %s" % str(loaded.get("error", "unknown"))
		return
	adapter = ADAPTER_SCRIPT.new()
	adapter.name = "ShooterRollbackAdapter"
	adapter.configure(rules)
	add_child(adapter)
	var canonical: RollbackShooterCanonicalConfig = CONFIG_SCRIPT.new()
	local_identity = HANDSHAKE_SCRIPT.new().build_identity(
		RollbackShooterCanonicalConfig.GAME_ID,
		RollbackShooterRulesDefinition.CONFIG_VERSION,
		"shooter_p1", 1, "shooter_p2", 1,
		canonical.canonical_bytes(rules), canonical.digest_hex(rules)
	)
	print("[ShooterConfig] game=rollback_shooter canonical_byte_length=%d digest=%s" % [int(local_identity["canonical_byte_length"]), str(local_identity["digest"])])
	if mode in ["host", "client"]:
		_setup_network(launch)
	else:
		status_label.text = "Local two-player test — WASD + Space vs arrows + Enter"
		match_started = true
		start_button.visible = false
	queue_redraw()


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(12, 10)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "Loading shooter rules..."
	panel.add_child(status_label)
	hp_label = Label.new()
	panel.add_child(hp_label)
	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 24)
	panel.add_child(result_label)
	start_button = Button.new()
	start_button.text = "Start Match"
	start_button.custom_minimum_size = Vector2(200, 48)
	start_button.visible = false
	start_button.pressed.connect(_start_network_match)
	panel.add_child(start_button)
	rematch_button = Button.new()
	rematch_button.text = "Rematch"
	rematch_button.custom_minimum_size = Vector2(200, 48)
	rematch_button.visible = false
	rematch_button.pressed.connect(_rematch)
	panel.add_child(rematch_button)
	menu_button = Button.new()
	menu_button.text = "Shooter Menu"
	menu_button.custom_minimum_size = Vector2(200, 48)
	menu_button.pressed.connect(_return_to_menu)
	panel.add_child(menu_button)


func _setup_network(launch: Dictionary) -> void:
	transport = TRANSPORT_SCRIPT.new()
	transport.name = "ShooterENetTransport"
	add_child(transport)
	transport.connected.connect(_on_transport_connected)
	transport.connection_failed.connect(_on_connection_failed)
	transport.disconnected.connect(_on_disconnected)
	transport.match_config_received.connect(_on_remote_config)
	transport.start_match_received.connect(_on_start_match_received)
	session = SESSION_SCRIPT.new()
	session.name = "ShooterRollbackSession"
	add_child(session)
	session.setup(adapter, transport, network_player_id)
	var port: int = int(launch.get("port", 7778))
	if mode == "host":
		status_label.text = "Hosting on port %d — waiting for peer" % port
		transport.host(port)
	else:
		var address: String = str(launch.get("address", "")).strip_edges()
		status_label.text = "Connecting to %s:%d" % [address, port]
		transport.join(address, port)


func _on_transport_connected() -> void:
	if transport == null or (transport.is_host and transport.remote_peer_id <= 0):
		return
	status_label.text = "Peer connected — verifying game configuration..."
	transport.send_match_config(local_identity)


func _on_remote_config(identity: Dictionary) -> void:
	var checker: RollbackFighterMatchConfigHandshake = HANDSHAKE_SCRIPT.new()
	checker.local_identity = local_identity.duplicate(true)
	var result: Dictionary = checker.accept_remote_identity(identity)
	if not bool(result.get("ok", false)):
		status_label.text = "Game/config mismatch. Both peers need the same shooter build."
		push_warning("[ShooterHandshake] %s" % str(result.get("message", "mismatch")))
		return
	config_verified = true
	print("[ShooterHandshake] MATCH CONFIG VERIFIED game=rollback_shooter")
	if transport.is_host:
		status_label.text = "Configuration verified — press Start Match"
		start_button.visible = true
	else:
		status_label.text = "Configuration verified — waiting for host"


func _start_network_match() -> void:
	if mode != "host" or not config_verified or transport == null:
		return
	transport.send_start_match()


func _on_start_match_received() -> void:
	if not config_verified or session == null:
		return
	adapter.reset_match()
	session.start_session()
	match_started = true
	start_button.visible = false
	status_label.text = "Rollback Shooter — network match"


func _on_connection_failed(reason: String) -> void:
	status_label.text = reason


func _on_disconnected() -> void:
	if is_instance_valid(status_label):
		status_label.text = "Disconnected"


func _physics_process(delta: float) -> void:
	if not match_started or adapter == null:
		return
	accumulator += delta
	while accumulator >= FIXED_DT:
		accumulator -= FIXED_DT
		if mode in ["host", "client"]:
			if session != null and session.match_started:
				session.tick(_read_local_input(network_player_id))
		else:
			adapter.simulate(_read_local_input(1), _read_local_input(2), FIXED_DT)
		_refresh_hud()
		queue_redraw()


func _read_local_input(player_id: int) -> Dictionary:
	var move_x: int = 0
	var move_y: int = 0
	if player_id == 1:
		move_x = int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
		move_y = int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	else:
		move_x = int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT))
		move_y = int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP))
	var player: Dictionary = adapter.players[player_id - 1]
	var mouse: Vector2 = get_global_mouse_position()
	var aim_dir: int = _quantize_aim(int(mouse.x) - int(player["x"]), int(mouse.y) - int(player["y"]))
	var shoot: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if player_id == 1:
		shoot = shoot or Input.is_key_pressed(KEY_SPACE)
	else:
		shoot = shoot or Input.is_key_pressed(KEY_ENTER)
	return {"move_x": move_x, "move_y": move_y, "aim_dir": aim_dir, "shoot": shoot}


func _quantize_aim(dx: int, dy: int) -> int:
	if dx == 0 and dy == 0:
		return 0
	var ax: int = absi(dx)
	var ay: int = absi(dy)
	var horizontal: bool = ax * 1000 >= ay * 2414
	var vertical: bool = ay * 1000 >= ax * 2414
	if horizontal:
		return 0 if dx > 0 else 4
	if vertical:
		return 2 if dy > 0 else 6
	if dx > 0:
		return 1 if dy > 0 else 7
	return 3 if dy > 0 else 5


func _refresh_hud() -> void:
	if adapter == null or adapter.players.size() != 2:
		return
	hp_label.text = "P1 HP %d     P2 HP %d" % [int(adapter.players[0]["hp"]), int(adapter.players[1]["hp"])]
	if adapter.match_over:
		match_started = false
		result_label.text = "PLAYER %d WINS" % adapter.winner_id
		rematch_button.visible = mode == "local"
		status_label.text = "Match complete"


func _rematch() -> void:
	if mode != "local" or adapter == null:
		return
	adapter.reset_match()
	result_label.text = ""
	rematch_button.visible = false
	match_started = true
	accumulator = 0.0


func _return_to_menu() -> void:
	if session != null:
		session.reset_session()
	if transport != null:
		transport.shutdown()
	get_tree().change_scene_to_file(MENU_SCENE)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(800, 600)), Color("202431"), true)
	draw_rect(Rect2(Vector2(8, 8), Vector2(784, 584)), Color("b6c4d5"), false, 3.0)
	if adapter == null or adapter.players.size() != 2:
		return
	for index in range(2):
		var player: Dictionary = adapter.players[index]
		var half: int = rules.get_int("player_half_extent")
		var color: Color = Color("42a5ff") if index == 0 else Color("ff765e")
		if not bool(player["alive"]):
			color = Color("555966")
		draw_rect(Rect2(int(player["x"]) - half, int(player["y"]) - half, half * 2, half * 2), color, true)
	for projectile_value in adapter.projectiles:
		var projectile: Dictionary = projectile_value
		var extent: int = rules.get_int("projectile_half_extent")
		draw_rect(Rect2(int(projectile["x"]) - extent, int(projectile["y"]) - extent, extent * 2, extent * 2), Color("ffe680"), true)


func _exit_tree() -> void:
	if transport != null and is_instance_valid(transport):
		transport.shutdown()
