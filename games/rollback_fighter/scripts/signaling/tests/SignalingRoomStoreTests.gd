extends SceneTree

const RoomStoreScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingRoomStore.gd")


func _initialize() -> void:
	var gameplay_sentinel := {"frame": 42, "checksum": "unchanged"}
	var store = RoomStoreScript.new()
	store.room_ttl_seconds = 10
	var host_payload := _payload(7777)
	var created: Dictionary = store.create_room(host_payload, "100.64.0.10", 100)
	assert(created.get("ok") == true)
	var room: Dictionary = created["data"]
	var room_code := str(room["room_code"])
	assert(RoomStoreScript.is_valid_room_code(room_code))
	assert(room_code.length() == 6)
	assert(room["host_endpoint"] == {"transport": "enet_udp", "address": "100.64.0.10", "port": 7777})

	var second_created: Dictionary = store.create_room(host_payload, "100.64.0.11", 100)
	assert(second_created.get("ok") == true)
	assert(str(second_created["data"]["room_code"]) != room_code)

	var joined: Dictionary = store.join_room(room_code, _payload(0), "100.64.0.20", 101)
	assert(joined.get("ok") == true)
	assert(joined["data"]["opponent_connected"] == true)
	assert(joined["data"]["guest_endpoint"]["address"] == "100.64.0.20")
	assert(str(joined["data"]["session_id"]) == str(room["session_id"]))
	var token := str(room["traversal_token"])
	assert(store.register_udp_endpoint(str(room["session_id"]), str(room["peer_id"]), token, "203.0.113.10", 42000, 101).get("ok") == true)
	assert(store.register_udp_endpoint(str(room["session_id"]), str(joined["data"]["peer_id"]), token, "198.51.100.20", 43000, 101).get("ok") == true)
	assert(store.register_udp_endpoint(str(room["session_id"]), str(room["peer_id"]), "bad-token", "203.0.113.10", 42000, 101).get("error_code") == "NOT_AUTHORIZED")
	assert(store.set_local_candidates(room_code, str(room["session_id"]), str(room["peer_id"]), [{"address": "192.168.1.10", "port": 7777}], 101).get("ok") == true)
	assert(store.set_local_candidates(room_code, str(room["session_id"]), str(joined["data"]["peer_id"]), [{"address": "192.168.1.20", "port": 43000}], 101).get("ok") == true)
	assert(store.set_local_candidates(room_code, str(room["session_id"]), str(room["peer_id"]), [{"address": "../secret", "port": 7777}], 101).get("error_code") == "INVALID_PAYLOAD")

	var host_view: Dictionary = store.get_room(room_code, str(room["session_id"]), str(room["peer_id"]), 102)
	assert(host_view.get("ok") == true)
	assert(host_view["data"]["opponent_connected"] == true)
	assert(host_view["data"]["host_endpoint"] == {"transport": "enet_udp", "address": "203.0.113.10", "port": 42000})
	assert(host_view["data"]["guest_endpoint"] == {"transport": "enet_udp", "address": "198.51.100.20", "port": 43000})
	assert(host_view["data"]["host_udp_registered"] == true)
	assert(host_view["data"]["guest_udp_registered"] == true)
	assert(str(host_view["data"]["opponent_probe_id"]) == str(joined["data"]["probe_id"]))
	assert(host_view["data"]["host_local_candidates"] == [{"address": "192.168.1.10", "port": 7777}])
	assert(host_view["data"]["guest_local_candidates"] == [{"address": "192.168.1.20", "port": 43000}])

	var second_guest: Dictionary = store.join_room(room_code, _payload(0), "100.64.0.21", 102)
	assert(second_guest.get("error_code") == "ROOM_FULL")
	assert(store.join_room("BAD", _payload(0), "100.64.0.21", 102).get("error_code") == "INVALID_ROOM_CODE")
	assert(store.join_room("ZZZZZZ", _payload(0), "100.64.0.21", 102).get("error_code") == "ROOM_NOT_FOUND")

	var incompatible := _payload(0)
	incompatible["protocol_version"] = 999
	var other_room: Dictionary = second_created["data"]
	assert(store.join_room(str(other_room["room_code"]), incompatible, "100.64.0.22", 102).get("error_code") == "INCOMPATIBLE_PROTOCOL")

	assert(store.create_room({"protocol_version": 2, "game_id": "../bad", "endpoint": host_payload["endpoint"]}, "100.64.0.10", 100).get("error_code") == "INVALID_PAYLOAD")
	assert(store.create_room({"protocol_version": 2, "game_id": "rollback_fighter", "endpoint": {"transport": "file", "address": "C:/secret", "port": 7777}}, "", 100).get("error_code") == "INVALID_PAYLOAD")

	var expiring = RoomStoreScript.new()
	expiring.room_ttl_seconds = 10
	var expiring_room: Dictionary = expiring.create_room(host_payload, "127.0.0.1", 200)["data"]
	assert(expiring.get_room(str(expiring_room["room_code"]), str(expiring_room["session_id"]), str(expiring_room["peer_id"]), 211).get("error_code") == "ROOM_EXPIRED")
	assert(gameplay_sentinel == {"frame": 42, "checksum": "unchanged"})

	print("[SignalingRoomStoreTests] PASS")
	quit(0)


func _payload(port: int) -> Dictionary:
	return {
		"protocol_version": 2,
		"game_id": "rollback_fighter",
		"endpoint": {"transport": "enet_udp", "address": "127.0.0.1", "port": port},
	}
