extends SceneTree

const AttemptScript = preload("res://games/rollback_fighter/scripts/net/NatTraversalAttempt.gd")


func _initialize() -> void:
	var success = AttemptScript.new()
	success.begin(1000, 5000, 3)
	assert(success.state == AttemptScript.STATE_REGISTERING)
	success.wait_for_peer()
	assert(success.state == AttemptScript.STATE_WAITING_PEER)
	success.begin_punching(1500)
	assert(success.record_probe_sent())
	assert(success.record_probe_sent())
	assert(success.record_probe_sent())
	assert(not success.record_probe_sent())
	success.record_valid_ack()
	assert(success.state == AttemptScript.STATE_PUNCHING)
	success.record_valid_probe()
	assert(success.state == AttemptScript.STATE_DIRECT)
	assert(not success.update_timeout(10000))

	var timeout = AttemptScript.new()
	timeout.begin(2000, 3000, 40)
	timeout.wait_for_peer()
	assert(not timeout.update_timeout(4999))
	assert(timeout.update_timeout(5000))
	assert(timeout.state == AttemptScript.STATE_RELAY_REQUIRED)

	print("[NatTraversalAttemptTests] PASS")
	quit(0)
