# ZoneTile.gd
extends Area3D

signal clicked(tile: Area3D)

@export var claimed_by: int = -1  # leave here, each tile remembers who claimed it

func _ready() -> void:
	# Ray Pickable is already on in the Inspector
	pass

func _on_input_event(viewport, event, position, normal, shape_idx) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("clicked", self)
