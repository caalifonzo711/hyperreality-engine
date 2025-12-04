extends Node
# Lightweight HUD binder: keeps the two HP bars in sync with PlayerState nodes.

@export var p1_state: PlayerState
@export var p2_state: PlayerState

@onready var p1bar: Range = $HBoxContainer/P1Bar
@onready var p2bar: Range = $HBoxContainer/P2Bar

func _ready() -> void:
	_sync_once()

func _process(_dt: float) -> void:
	_sync_bars()

func _sync_once() -> void:
	if p1_state and p1bar:
		p1bar.max_value = float(p1_state.max_hp)
		p1bar.value     = float(p1_state.hp)
	if p2_state and p2bar:
		p2bar.max_value = float(p2_state.max_hp)
		p2bar.value     = float(p2_state.hp)

func _sync_bars() -> void:
	if p1_state and p1bar:
		p1bar.value = float(p1_state.hp)
	if p2_state and p2bar:
		p2bar.value = float(p2_state.hp)
