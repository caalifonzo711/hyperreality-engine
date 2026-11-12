extends RefCounted
class_name RollbackFighterSessionPlayer

const CONNECTION_PENDING := "PENDING"
const CONNECTION_CONNECTED := "CONNECTED"
const CONNECTION_DISCONNECTED := "DISCONNECTED"

var player_id: String = ""
var peer_id: Variant = null
var slot: int = -1
var display_name: String = ""
var ready: bool = false
var connection_state: String = CONNECTION_PENDING


func configure(
	requested_player_id: String,
	requested_peer_id: Variant,
	requested_slot: int,
	requested_display_name: String,
	is_ready: bool = false,
	requested_connection_state: String = CONNECTION_PENDING
) -> RollbackFighterSessionPlayer:
	player_id = requested_player_id
	peer_id = requested_peer_id
	slot = requested_slot
	display_name = requested_display_name
	ready = is_ready
	connection_state = requested_connection_state
	return self


func to_dictionary() -> Dictionary:
	return {
		"player_id": player_id,
		"peer_id": peer_id,
		"slot": slot,
		"display_name": display_name,
		"ready": ready,
		"connection_state": connection_state,
	}
