extends Node3D

@onready var DemoScene: PackedScene = preload("res://games/meme_wars/scenes/FinanceWarDemo.tscn")

func _ready() -> void:
	var old = get_node_or_null("FinanceWarDemo")
	if old:
		old.queue_free()

	var demo := DemoScene.instantiate()
	demo.name = "FinanceWarDemo"
	add_child(demo)
	print("Main loader: Finance War demo spawned.")
