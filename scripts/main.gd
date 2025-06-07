extends Node

var page_turner: Node

func _ready():
	page_turner = $PageTurnTest/PageTurner  # update this if your path differs

	# Simulate 3 inputs
	print("--- Simulating Page Turns ---")
	for i in range(3):
		var fake_input := InputEventAction.new()
		fake_input.action = "ui_accept"
		fake_input.pressed = true
		page_turner._apply_input(fake_input, i)

	# Now simulate a rollback to tick 1
	print("--- Simulating Rollback ---")
	page_turner.rollback_tick(1)
