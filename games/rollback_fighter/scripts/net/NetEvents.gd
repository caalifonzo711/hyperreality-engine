# res://games/rollback_fighter/scripts/net/NetEvents.gd
extends Node

signal request_host(room_id: String)
signal request_join(room_id: String)
signal net_connected(peer_count: int)
signal net_error(msg: String)
