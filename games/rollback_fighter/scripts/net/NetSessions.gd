# res://games/rollback_fighter/scripts/net/NetSession.gd
extends Node

# --- CONFIG ---
const SIGNALING_URL := "ws://localhost:8910" # change to your signaling endpoint
const MAX_PLAYERS := 2

# --- STATE ---
var room_id: String = ""
var is_host: bool = false
var is_connected: bool = false

# --- REFS (lazy created) ---
var _signaling := null           # your SignalingServer wrapper
var _transport := null           # your WebRTCTransport wrapper
var _multiplayer := MultiplayerAPI.new()

func _ready() -> void:
	# wire event bus
	NetEvents.request_host.connect(_on_request_host)
	NetEvents.request_join.connect(_on_request_join)

func _ensure_signaling():
	if _signaling: return
	# TODO: if your signaling wrapper has a constructor signature, adapt here
	_signaling = preload("res://addons/rollback_netcode_mvp/src/SignalingServer.gd").new()
	_signaling.connect_to_url(SIGNALING_URL)
	_signaling.connection_opened.connect(_on_signaling_open)
	_signaling.connection_closed.connect(_on_signaling_closed)
	_signaling.message_received.connect(_on_signaling_message)

func _ensure_transport():
	if _transport: return
	_transport = preload("res://addons/rollback_netcode_mvp/src/WebRTCTransport.gd").new()
	_transport.connected.connect(_on_webrtc_connected)
	_transport.connection_failed.connect(_on_webrtc_failed)
	_transport.ice_candidate_generated.connect(_on_local_ice)

# =========================
# HOST / JOIN ENTRY POINTS
# =========================
func _on_request_host(id: String) -> void:
	room_id = id.strip_edges()
	is_host = true
	_ensure_signaling()
	_ensure_transport()
	_signaling.create_room(room_id)           # TODO: map to your API
	_transport.create_offer()                 # TODO: begin host offer
	print("[Net] Host: creating room %s" % room_id)

func _on_request_join(id: String) -> void:
	room_id = id.strip_edges()
	is_host = false
	_ensure_signaling()
	_ensure_transport()
	_signaling.join_room(room_id)             # TODO: map to your API
	_transport.prepare_for_answer()           # TODO: begin join flow
	print("[Net] Join: requesting room %s" % room_id)

# =========================
# SIGNALING CALLBACKS
# =========================
func _on_signaling_open() -> void:
	print("[Net] Signaling connected")

func _on_signaling_closed(code = 0, reason = "") -> void:
	print("[Net] Signaling closed: %s" % reason)
	if not is_connected:
		NetEvents.net_error.emit("Signaling closed")

func _on_signaling_message(payload: Dictionary) -> void:
	# Expect minimal JSON messages: { "type":"offer/answer/candidate", "sdp":..., "candidate":... }
	match payload.get("type",""):
		"offer":
			if not is_host:
				_transport.set_remote_offer(payload["sdp"])  # TODO: map
				var ans = _transport.create_answer()
				_signaling.send_answer(room_id, ans)         # TODO: map
		"answer":
			if is_host:
				_transport.set_remote_answer(payload["sdp"]) # TODO: map
		"candidate":
			_transport.add_remote_ice(payload["candidate"])  # TODO: map

# =========================
# WEBRTC CALLBACKS
# =========================
func _on_local_ice(candidate: Dictionary) -> void:
	_signaling.send_ice(room_id, candidate)                 # TODO: map

func _on_webrtc_connected() -> void:
	is_connected = true
	# Hand off to Godot Multiplayer (optional but convenient)
	var mp_peer := _transport.to_multiplayer_peer()         # TODO: expose from your wrapper
	_multiplayer.set_multiplayer_peer(mp_peer)
	get_tree().set_multiplayer(_multiplayer)
	print("Connected!")
	NetEvents.net_connected.emit(2)

func _on_webrtc_failed(reason := "unknown") -> void:
	NetEvents.net_error.emit("WebRTC failed: %s" % reason)
