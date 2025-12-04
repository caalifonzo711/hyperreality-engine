extends Node

# Because this script is on the “PageTurner” child, we go up one level to find TickLabel.
@onready var tick_label = get_node("../TickLabel")

var current_page := 1
var current_tick := 0

func _ready():
	if tick_label:
		tick_label.text = "Tick: 0"
	else:
		push_warning("⚠️ PageTurnTest: TickLabel not found")

# Godot 4’s InputEventKey uses `keycode`. Compare against KEY_SPACE / KEY_ENTER.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_page_turn()

func _on_page_turn() -> void:
	current_page += 1
	current_tick += 1

	# Print to the debugger console:
	print("Page Turned ➜ Page %d at Tick %d" % [current_page, current_tick])

	# Update the on-screen label:
	if tick_label:
		tick_label.text = "Tick: %d" % current_tick

func _on_rollback_tick(tick_number: int) -> void:
	# If you ever call this for a rollback pass:
	print("Resimulating Tick %d ↪ Current Page: %d" % [tick_number, current_page])
	if tick_label:
		tick_label.text = "⟳ Tick: %d" % tick_number
		# Example: to color-highlight on rollback, uncomment:
		# tick_label.add_theme_color_override("font_color", Color.RED)
