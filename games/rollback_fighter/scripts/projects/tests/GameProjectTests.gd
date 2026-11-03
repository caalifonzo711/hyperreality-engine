extends SceneTree


const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const LaunchContextScript = preload("res://games/rollback_fighter/scripts/projects/CreatorLaunchContext.gd")
const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const TEST_ID := "c6_project_test"
const CORRUPT_ID := "c6_corrupt_test"


func _initialize() -> void:
	var failures := PackedStringArray()
	_cleanup_project(TEST_ID)
	_cleanup_project(CORRUPT_ID)
	var store: RollbackFighterGameProjectStore = ProjectStoreScript.new()
	var project: RollbackFighterGameProjectDefinition = ProjectDefinitionScript.new()
	project.configure("C6 Test Game", TEST_ID, "anime_fighter")
	_expect(project.validate().is_empty(), "valid GameProjectDefinition is accepted", failures)
	_expect(project.status == "draft" and project.version == 1, "new projects carry draft status and a version", failures)
	_expect(store.get_project_root(TEST_ID) == "user://games/%s" % TEST_ID, "project root is a safe user:// path", failures)
	_expect(not store.get_project_root("../escape").begins_with("user://"), "unsafe IDs cannot produce storage paths", failures)

	for invalid_id in ["", "Upper", "bad-id", "bad/id", "../escape"]:
		var invalid: RollbackFighterGameProjectDefinition = ProjectDefinitionScript.new()
		invalid.configure("Invalid", invalid_id, "platform_fighter")
		_expect(not invalid.validate().is_empty(), "invalid project ID rejected: %s" % invalid_id, failures)

	var created: Dictionary = store.create(project)
	_expect(bool(created.get("ok", false)), "valid project saves", failures)
	_expect(str(created.get("path", "")).begins_with("user://games/") and not str(created.get("path", "")).begins_with("res://"), "project save never targets res://", failures)
	_expect(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://games/%s/fighters" % TEST_ID)), "fighters folder is created", failures)
	_expect(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://games/%s/drafts" % TEST_ID)), "drafts folder is created", failures)
	var loaded: Dictionary = store.load_project(TEST_ID)
	_expect(bool(loaded.get("ok", false)), "saved project loads", failures)
	if bool(loaded.get("ok", false)):
		var loaded_project: RollbackFighterGameProjectDefinition = loaded["project"]
		_expect(loaded_project.to_dictionary() == project.to_dictionary(), "save/load round trip preserves fields", failures)
		_expect(loaded_project.style_preset == "anime_fighter", "style preset persists", failures)
	_expect(not bool(store.create(project).get("ok", false)), "duplicate project ID is rejected cleanly", failures)

	var corrupt_root := "user://games/%s" % CORRUPT_ID
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(corrupt_root))
	var corrupt_file := FileAccess.open(corrupt_root + "/project.json", FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{not valid json")
		corrupt_file.close()
	_expect(not bool(store.load_project(CORRUPT_ID).get("ok", false)), "corrupt project.json fails safely", failures)

	var context: RollbackFighterCreatorLaunchContext = LaunchContextScript.new()
	_expect(context.launch_for_project(TEST_ID) and context.get_project_id() == TEST_ID, "Create Fighter retains project launch context", failures)
	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	_expect(draft.set_project_context(context.get_project_id()) and draft.project_id == TEST_ID, "fighter draft records its project association", failures)
	_expect(str(draft._build_creator_manifest().get("project_id", "")) == TEST_ID, "fighter creator metadata persists project association", failures)
	var roster_result: Dictionary = context.record_successful_build("c6_fighter_test")
	_expect(bool(roster_result.get("ok", false)), "successful-build hook updates project roster", failures)
	var roster_load: Dictionary = store.load_project(TEST_ID)
	if bool(roster_load.get("ok", false)):
		var roster_project: RollbackFighterGameProjectDefinition = roster_load["project"]
		_expect(roster_project.fighter_ids == ["c6_fighter_test"], "project roster contains built fighter once", failures)
	else:
		_expect(false, "project reloads after roster update", failures)
	context.launch_global()
	_expect(not context.has_project(), "legacy Create Fighter clears project context", failures)
	var legacy_draft: RollbackFighterCreatorDraft = DraftScript.new()
	_expect(str(legacy_draft._build_creator_manifest().get("project_id", "not-empty")).is_empty(), "legacy fighter draft has no project association", failures)
	_expect(bool(context.record_successful_build("legacy_fighter").get("legacy", false)), "legacy successful build remains a no-op for projects", failures)

	_cleanup_project(TEST_ID)
	_cleanup_project(CORRUPT_ID)
	_finish(failures)


func _cleanup_project(project_id: String) -> void:
	if not ProjectDefinitionScript.is_safe_id(project_id):
		return
	var root: String = "user://games/%s" % project_id
	var absolute_root: String = ProjectSettings.globalize_path(root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return
	_remove_contents(root)
	DirAccess.remove_absolute(absolute_root)


func _remove_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path + "/" + name
		if dir.current_is_dir():
			_remove_contents(child)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[GameProjectTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[GameProjectTests] FAIL: %s" % failure)
	quit(1)
