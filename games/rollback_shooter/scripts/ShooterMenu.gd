extends Control

const ARENA_SCENE: String = "res://games/rollback_shooter/scenes/ShooterArena.tscn"

var address_edit: LineEdit
var port_spin: SpinBox
var status_label: Label


func _ready() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var center: CenterContainer = CenterContainer.new()
	margin.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title: Label = Label.new()
	title.text = "ROLLBACK SHOOTER — T1"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	_add_button(column, "Local Two-Player Test", func() -> void: _launch("local"))
	_add_button(column, "Host Game", func() -> void: _launch("host"))
	var address_label: Label = Label.new()
	address_label.text = "Host address"
	column.add_child(address_label)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "127.0.0.1 or hostname"
	address_edit.text = "127.0.0.1"
	column.add_child(address_edit)
	var port_label: Label = Label.new()
	port_label.text = "Port"
	column.add_child(port_label)
	port_spin = SpinBox.new()
	port_spin.min_value = 1
	port_spin.max_value = 65535
	port_spin.value = 7778
	port_spin.rounded = true
	column.add_child(port_spin)
	_add_button(column, "Join Game", func() -> void: _launch("client"))
	status_label = Label.new()
	status_label.text = "60 Hz deterministic proof template"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	_add_button(column, "Back to Main Menu", _back_to_main)


func _add_button(parent: VBoxContainer, label: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 54)
	button.pressed.connect(callback)
	parent.add_child(button)


func _launch(mode: String) -> void:
	var address: String = address_edit.text.strip_edges() if address_edit != null else ""
	var port: int = int(port_spin.value) if port_spin != null else 7778
	if mode == "client" and address.is_empty():
		status_label.text = "Enter a host address."
		return
	get_tree().set_meta("rollback_shooter_launch", {"mode": mode, "address": address, "port": port})
	var error: Error = get_tree().change_scene_to_file(ARENA_SCENE)
	if error != OK:
		status_label.text = "Could not open shooter arena."


func _back_to_main() -> void:
	get_tree().change_scene_to_file("res://games/rollback_fighter/scenes/MainMenu.tscn")
