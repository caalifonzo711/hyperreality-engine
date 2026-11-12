extends RefCounted
class_name RollbackFighterNatTraversalProbe

const MAGIC := "HRNP"
const VERSION := 1
const TYPE_REGISTER := 1
const TYPE_REGISTER_ACK := 2
const TYPE_PROBE := 3
const TYPE_ACK := 4
const SESSION_HEX_LENGTH := 48
const PEER_HEX_LENGTH := 32
const TOKEN_HEX_LENGTH := 64
const NONCE_HEX_LENGTH := 16
const PACKET_SIZE := 86


static func encode(packet_type: int, session_id: String, peer_id: String, token: String, nonce: String) -> PackedByteArray:
	if packet_type not in [TYPE_REGISTER, TYPE_REGISTER_ACK, TYPE_PROBE, TYPE_ACK]:
		return PackedByteArray()
	if not _valid_hex(session_id, SESSION_HEX_LENGTH):
		return PackedByteArray()
	if not _valid_hex(peer_id, PEER_HEX_LENGTH):
		return PackedByteArray()
	if not _valid_hex(token, TOKEN_HEX_LENGTH):
		return PackedByteArray()
	if not _valid_hex(nonce, NONCE_HEX_LENGTH):
		return PackedByteArray()
	var packet := PackedByteArray()
	packet.append_array(MAGIC.to_ascii_buffer())
	packet.append(VERSION)
	packet.append(packet_type)
	packet.append_array(session_id.hex_decode())
	packet.append_array(peer_id.hex_decode())
	packet.append_array(token.hex_decode())
	packet.append_array(nonce.hex_decode())
	return packet


static func decode(packet: PackedByteArray, expected_session: String = "", expected_token: String = "") -> Dictionary:
	if packet.size() != PACKET_SIZE:
		return _error("MALFORMED_PACKET")
	if packet.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _error("WRONG_MAGIC")
	if int(packet[4]) != VERSION:
		return _error("WRONG_VERSION")
	var packet_type := int(packet[5])
	if packet_type not in [TYPE_REGISTER, TYPE_REGISTER_ACK, TYPE_PROBE, TYPE_ACK]:
		return _error("WRONG_TYPE")
	var session_id := packet.slice(6, 30).hex_encode()
	var peer_id := packet.slice(30, 46).hex_encode()
	var token := packet.slice(46, 78).hex_encode()
	var nonce := packet.slice(78, 86).hex_encode()
	if not expected_session.is_empty() and session_id != expected_session:
		return _error("WRONG_SESSION")
	if not expected_token.is_empty() and token != expected_token:
		return _error("WRONG_TOKEN")
	return {
		"ok": true,
		"type": packet_type,
		"session_id": session_id,
		"peer_id": peer_id,
		"token": token,
		"nonce": nonce,
	}


static func _valid_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error_code": code}
