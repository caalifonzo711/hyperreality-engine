@tool
extends EditorPlugin

# ✅ This preloads the LogInspector scene so it can be instantiated later.
# ❌ FIX: The original path was "res://addons/godot-rollback-netcode/..."
#    but the correct path in your project is "res://addons/rollback_netcode/..."
const LogInspector = preload("res://addons/rollback_netcode/log_inspector/LogInspector.tscn")


var log_inspector  # Placeholder for the Log Inspector instance.

func _enter_tree() -> void:
	# ✅ Load and apply project settings required for rollback netcode.
	# ❌ FIX: Verify the correct path of `ProjectSettings.gd`
	var project_settings_node = load("res://addons/godot-rollback-netcode/ProjectSettings.gd").new()
	project_settings_node.add_project_settings()
	project_settings_node.free()

	# ✅ Registers "SyncManager" as an autoload singleton, making it globally accessible.
	# ❌ FIX: Ensure "SyncManager.gd" exists at the specified path.
	add_autoload_singleton("SyncManager", "res://addons/godot-rollback-netcode/SyncManager.gd")

	# ✅ Instantiates the Log Inspector scene and adds it to the editor UI.
	log_inspector = LogInspector.instantiate()
	get_editor_interface().get_base_control().add_child(log_inspector)
	log_inspector.set_editor_interface(get_editor_interface())

	# ✅ Adds "Log Inspector..." to the Godot Editor's tool menu.
	add_tool_menu_item("Log Inspector...", self.open_log_inspector)

	# ✅ Adds a custom input action "sync_debug" if it doesn’t exist.
	#    This binds it to F11 for debugging rollback netcode.
	if not ProjectSettings.has_setting("input/sync_debug"):
		var sync_debug = InputEventKey.new()
		sync_debug.keycode = KEY_F11  # Assign F11 as the debug key.

		ProjectSettings.set_setting("input/sync_debug", {
			deadzone = 0.5,
			events = [
				sync_debug,
			],
		})

		# ✅ Forces the editor to refresh ProjectSettings so the new input mapping takes effect.
		get_tree().root.get_child(0).propagate_notification(EditorSettings.NOTIFICATION_EDITOR_SETTINGS_CHANGED)


# ✅ Opens the Log Inspector window when selected from the tool menu.
func open_log_inspector() -> void:
	log_inspector.popup_centered_ratio()


func _exit_tree() -> void:
	# ✅ Removes "Log Inspector..." from the Godot Editor tool menu on plugin disable/unload.
	remove_tool_menu_item("Log Inspector...")

	# ✅ Properly frees the Log Inspector instance when the plugin is removed.
	if log_inspector:
		log_inspector.free()
		log_inspector = null
