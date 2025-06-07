extends Node3D

@onready var ar_shape = $MeshInstance3D

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		print("⟳ Space pressed, calling show_shape()")
		ar_shape.show_shape()
