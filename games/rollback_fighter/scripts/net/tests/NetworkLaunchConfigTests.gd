extends SceneTree

const NetworkLaunchConfigScript = preload(
	"res://games/rollback_fighter/scripts/net/NetworkLaunchConfig.gd"
)


func _initialize() -> void:
	var config: Variant = NetworkLaunchConfigScript.new()
	assert(config.set_host(7777))
	assert(config.consume() == {
		"mode": "host", "address": "", "port": 7777,
		"p1_fighter_id": "example_fighter",
		"p2_fighter_id": "example_fighter_alt",
		"local_port": 0,
		"connection_mode": "DIRECT_IP",
	})
	assert(config.consume().is_empty())

	assert(config.set_client("  fighter.example  ", 12345))
	assert(config.consume() == {
		"mode": "client",
		"address": "fighter.example",
		"port": 12345,
		"p1_fighter_id": "example_fighter",
		"p2_fighter_id": "example_fighter_alt",
		"local_port": 0,
		"connection_mode": "DIRECT_IP",
	})
	config.set_single_player()
	assert(config.consume() == {
		"mode": "single_player",
		"p1_fighter_id": "example_fighter",
		"p2_fighter_id": "example_fighter_alt",
	})
	config.set_single_player()
	assert(config.set_fighter_selection("example_fighter_alt", "example_fighter"))
	var selected_launch: Dictionary = config.consume()
	assert(selected_launch["p1_fighter_id"] == "example_fighter_alt")
	assert(selected_launch["p2_fighter_id"] == "example_fighter")
	assert(not config.set_fighter_selection("../fighter", "example_fighter"))

	assert(not config.set_client("", 7777))
	assert(config.consume().is_empty())
	assert(not config.set_host(0))
	assert(not config.set_host(65536))
	assert(not config.set_client("127.0.0.1", 0))
	assert(not config.set_client("127.0.0.1", 65536))

	assert(config.set_host(7777))
	var signaling_context := {
		"room_code": "ABC234",
		"session_id": "opaque-session",
		"peer_id": "opaque-peer",
		"server_url": "http://127.0.0.1:8787",
		"is_host": true,
	}
	assert(config.set_signaling_room(signaling_context))
	var signaled_launch: Dictionary = config.get_pending_launch()
	assert(signaled_launch["mode"] == "host")
	assert(signaled_launch["signaling"] == signaling_context)
	assert(config.set_fighter_selection("example_fighter", "example_fighter_alt"))
	assert(config.get_signaling_room() == signaling_context)
	assert(config.set_traversal_result({
		"connection_mode": "DIRECT",
		"local_port": 7777,
		"peer_address": "198.51.100.20",
		"peer_port": 41000,
	}))
	assert(config.get_pending_launch()["connection_mode"] == "DIRECT")
	assert(config.get_pending_launch()["local_port"] == 7777)
	assert(config.consume()["signaling"] == signaling_context)
	assert(config.get_signaling_room().is_empty())
	var client_context: Dictionary = signaling_context.duplicate(true)
	client_context["is_host"] = false
	assert(config.set_online_client(client_context))
	assert(config.get_pending_launch()["connection_mode"] == "TRAVERSING")
	assert(config.set_traversal_result({
		"connection_mode": "DIRECT",
		"local_port": 43000,
		"peer_address": "203.0.113.10",
		"peer_port": 42000,
	}))
	var client_handoff: Dictionary = config.consume()
	assert(client_handoff["address"] == "203.0.113.10")
	assert(client_handoff["port"] == 42000)
	assert(client_handoff["local_port"] == 43000)
	assert(client_handoff["connection_mode"] == "DIRECT")
	assert(not config.set_signaling_room({"room_code": "BAD"}))
	config.free()
	print("[NetworkLaunchConfigTests] PASS")
	quit(0)
