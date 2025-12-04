extends Node
class_name SignalingServer

signal offer_received(sdp:String)
signal answer_received(sdp:String)

var _ws := WebSocketPeer.new()
var _connected := false

func connect_to(url:String) -> void:
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("Signaling connect failed: %s" % err)
		return
	_connected = true
	set_process(true)

func _process(_delta:float) -> void:
	if not _connected: return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet().get_string_from_utf8()
				# Super dumb demo parser:
				if pkt.begins_with("OFFER:"):
					offer_received.emit(pkt.substr(6))
				elif pkt.begins_with("ANSWER:"):
					answer_received.emit(pkt.substr(7))
		WebSocketPeer.STATE_CLOSED:
			_connected = false
			set_process(false)

func send_raw(msg:String) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(msg)
