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
	})
	assert(config.consume().is_empty())

	assert(config.set_client("  fighter.example  ", 12345))
	assert(config.consume() == {
		"mode": "client",
		"address": "fighter.example",
		"port": 12345,
		"p1_fighter_id": "example_fighter",
		"p2_fighter_id": "example_fighter_alt",
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
	config.free()
	print("[NetworkLaunchConfigTests] PASS")
	quit(0)
