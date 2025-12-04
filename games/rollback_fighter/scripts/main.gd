extends Node2D

# Either hardcode the correct location:
@export var arena_scene : PackedScene = preload("res://games/rollback_fighter/scenes/FighterArena.tscn")

func _ready() -> void:
	print("Main loader: Arena spawned.")
	if not arena_scene:
		push_error("Arena scene not assigned or failed to load.")
		return
	var arena = arena_scene.instantiate()
	add_child(arena)
