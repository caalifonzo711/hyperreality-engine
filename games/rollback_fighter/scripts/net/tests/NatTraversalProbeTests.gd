extends SceneTree

const ProbeScript = preload("res://games/rollback_fighter/scripts/net/NatTraversalProbe.gd")


func _initialize() -> void:
	var session_id := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var peer_id := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	var token := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	var nonce := "dddddddddddddddd"
	var packet: PackedByteArray = ProbeScript.encode(
		ProbeScript.TYPE_PROBE, session_id, peer_id, token, nonce
	)
	assert(packet.size() == ProbeScript.PACKET_SIZE)
	var decoded: Dictionary = ProbeScript.decode(packet, session_id, token)
	assert(decoded.get("ok") == true)
	assert(decoded["type"] == ProbeScript.TYPE_PROBE)
	assert(decoded["peer_id"] == peer_id)
	assert(decoded["nonce"] == nonce)

	assert(ProbeScript.decode(packet.slice(0, packet.size() - 1)).get("error_code") == "MALFORMED_PACKET")
	var malformed := packet.duplicate()
	malformed[0] = 0
	assert(ProbeScript.decode(malformed).get("error_code") == "WRONG_MAGIC")
	assert(ProbeScript.decode(packet, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", token).get("error_code") == "WRONG_SESSION")
	assert(ProbeScript.decode(packet, session_id, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff").get("error_code") == "WRONG_TOKEN")
	assert(ProbeScript.encode(99, session_id, peer_id, token, nonce).is_empty())

	print("[NatTraversalProbeTests] PASS")
	quit(0)
