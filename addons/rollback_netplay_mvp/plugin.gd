# res://addons/rollback_netplay_mvp/plugin.gd
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "RollbackNetplay"
const AUTOLOAD_PATH := "res://addons/rollback_netplay_mvp/src/RollbackNetplay.gd"

func _enter_tree() -> void:
	if not get_tree().has_autoload_singleton(AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	# Optional: warn if rollback_netcode isn’t present/enabled
	if not DirAccess.dir_exists_absolute("res://addons/rollback_netcode"):
		push_warning("[RollbackNetplayMVP] 'rollback_netcode' addon not found; functionality will be limited.")

func _exit_tree() -> void:
	if get_tree().has_autoload_singleton(AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
