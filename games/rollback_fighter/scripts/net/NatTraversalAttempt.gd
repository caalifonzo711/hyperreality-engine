extends RefCounted
class_name RollbackFighterNatTraversalAttempt

const STATE_IDLE := "IDLE"
const STATE_REGISTERING := "REGISTERING"
const STATE_WAITING_PEER := "WAITING_PEER"
const STATE_PUNCHING := "PUNCHING"
const STATE_DIRECT := "DIRECT"
const STATE_RELAY_REQUIRED := "RELAY_REQUIRED"

var state := STATE_IDLE
var started_msec := 0
var timeout_msec := 8000
var max_probe_count := 40
var probe_count := 0
var received_probe := false
var received_ack := false


func begin(now_msec: int, timeout_value_msec: int = 8000, max_probes: int = 40) -> void:
	state = STATE_REGISTERING
	started_msec = now_msec
	timeout_msec = maxi(timeout_value_msec, 1000)
	max_probe_count = clampi(max_probes, 1, 128)
	probe_count = 0
	received_probe = false
	received_ack = false


func wait_for_peer() -> void:
	if state == STATE_REGISTERING:
		state = STATE_WAITING_PEER


func begin_punching(now_msec: int = -1) -> void:
	if state in [STATE_REGISTERING, STATE_WAITING_PEER]:
		state = STATE_PUNCHING
		if now_msec >= 0:
			started_msec = now_msec


func record_probe_sent() -> bool:
	if state != STATE_PUNCHING or probe_count >= max_probe_count:
		return false
	probe_count += 1
	return true


func record_valid_probe() -> void:
	if state == STATE_PUNCHING:
		received_probe = true
		_update_success()


func record_valid_ack() -> void:
	if state == STATE_PUNCHING:
		received_ack = true
		_update_success()


func update_timeout(now_msec: int) -> bool:
	if state in [STATE_DIRECT, STATE_RELAY_REQUIRED, STATE_IDLE]:
		return false
	if now_msec - started_msec < timeout_msec:
		return false
	state = STATE_RELAY_REQUIRED
	return true


func fail() -> void:
	if state != STATE_DIRECT:
		state = STATE_RELAY_REQUIRED


func _update_success() -> void:
	if received_probe and received_ack:
		state = STATE_DIRECT
