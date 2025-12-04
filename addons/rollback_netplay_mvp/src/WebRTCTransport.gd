extends Node
class_name WebRTCTransport

signal packet_received(payload:Dictionary)
signal state_changed(state:String)

var _pc := WebRTCPeerConnection.new()
var _dc : WebRTCDataChannel

func _ready() -> void:
	_pc.session_description_created.connect(_on_sdp)
	_pc.ice_candidate_created.connect(_on_ice)
	_pc.data_channel_received.connect(_on_data_channel)

func create_data_channel(label:String="roll") -> void:
	_dc = _pc.create_data_channel(label)
	_wire_dc()

func _wire_dc() -> void:
	if _dc:
		_dc.open_state_changed.connect(_on_dc_state)
		_dc.data_received.connect(_on_dc_data)

func send_packet(payload:Dictionary) -> void:
	if _dc and _dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_dc.put_packet(JSON.stringify(payload).to_utf8_buffer())

func _on_dc_state() -> void:
	state_changed.emit(str(_dc.get_ready_state()))

func _on_dc_data() -> void:
	var txt := _dc.get_packet().get_string_from_utf8()
	var obj := JSON.parse_string(txt)
	if typeof(obj) == TYPE_DICTIONARY:
		packet_received.emit(obj)

func _on_data_channel(ch:WebRTCDataChannel) -> void:
	_dc = ch
	_wire_dc()

func _on_sdp(_type:String, _sdp:String) -> void: pass
func _on_ice(_mid:String, _idx:int, _sdp:String) -> void: pass
