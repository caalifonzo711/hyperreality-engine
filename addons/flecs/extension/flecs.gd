@tool
extends EditorPlugin

func _enter_tree():
	print("Godot Flecs Plugin Loaded")

func _exit_tree():
	print("Godot Flecs Plugin Unloaded")
