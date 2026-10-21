extends Node
# Lightweight HUD binder: keeps the two HP bars in sync with PlayerState nodes.

@export var p1_state: PlayerState
@export var p2_state: PlayerState

@onready var p1bar: Range = $HBoxContainer/P1Bar
@onready var p2bar: Range = $HBoxContainer/P2Bar
@onready var p1label: Label = $HBoxContainer/P1Label
@onready var p2label: Label = $HBoxContainer/P2Label

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
	if p1_state and p1label:
		p1label.text = "P1 HP: %d" % p1_state.hp
	if p2_state and p2bar:
		p2bar.value = float(p2_state.hp)
	if p2_state and p2label:
		p2label.text = "P2 HP: %d" % p2_state.hp
