extends Node2D

@onready var attack_button = $AttackButton
@onready var dodge_button = $DodgeButton
@onready var tick_label = $FighterTickLabel

var current_tick := 0

func _ready():
	# Connect each button’s “pressed” signal to its handler
	attack_button.pressed.connect(_on_attack)
	dodge_button.pressed.connect(_on_dodge)

	# Initialize the label on start
	if tick_label:
		tick_label.text = "Tick: 0"
	else:
		push_warning("⚠️ FighterArena: FighterTickLabel not found")

func _on_attack():
	current_tick += 1
	print("Attack pressed at Tick %d" % current_tick)
	if tick_label:
		tick_label.text = "Tick: %d" % current_tick

func _on_dodge():
	current_tick += 1
	print("Dodge pressed at Tick %d" % current_tick)
	if tick_label:
		tick_label.text = "Tick: %d" % current_tick
