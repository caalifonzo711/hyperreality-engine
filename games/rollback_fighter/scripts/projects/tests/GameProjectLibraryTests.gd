extends SceneTree

const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ProviderScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectProvider.gd")
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")
const BuilderScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectBuilder.gd")
const LaunchConfigScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectLaunchConfig.gd")
const PresentationResolverScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationResolver.gd")
const NetworkConfigScript = preload("res://games/rollback_fighter/scripts/net/NetworkLaunchConfig.gd")
const FighterProviderScript = preload("res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd")

const VALID_ID := "c9_library_valid"
const INCOMPLETE_ID := "c9_library_incomplete"
const CORRUPT_ID := "c9_library_corrupt"

func _initialize() -> void:
	var failures := PackedStringArray()
	for project_id in [VALID_ID, INCOMPLETE_ID, CORRUPT_ID]:
		_cleanup_tree("user://games/%s" % project_id)
	var store := ProjectStoreScript.new()
	var valid := _project("C9 Valid", VALID_ID, ["example_fighter", "example_fighter_alt"])
	_expect(bool(store.create(valid).get("ok", false)), "valid project fixture saves", failures)
	var incomplete := _project("C9 Incomplete", INCOMPLETE_ID, ["missing_c9_fighter"])
	_expect(bool(store.create(incomplete).get("ok", false)), "incomplete project fixture saves", failures)
	var corrupt_root := "user://games/%s" % CORRUPT_ID
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(corrupt_root))
	_write_text(corrupt_root + "/project.json", "{broken")

	var projects := ProviderScript.new().list_projects()
	var listed_ids: Array[String] = []
	for entry in projects:
		listed_ids.append(str(entry.get("project_id", "")))
	_expect(listed_ids.has(VALID_ID), "provider enumerates a valid project", failures)
	_expect(not listed_ids.has(CORRUPT_ID), "provider skips corrupt projects safely", failures)
	var sorted_ids := listed_ids.duplicate()
	sorted_ids.sort()
	_expect(listed_ids == sorted_ids, "provider ordering is deterministic", failures)

	var readiness_service := ReadinessScript.new()
	var valid_readiness := readiness_service.evaluate(VALID_ID)
	_expect(str(valid_readiness.get("status", "")) == "ready_to_build", "readiness derives READY TO BUILD from actual valid data", failures)
	var incomplete_readiness := readiness_service.evaluate(INCOMPLETE_ID)
	_expect(str(incomplete_readiness.get("status", "")) == "incomplete", "missing required fighter blocks build", failures)
	_expect(not bool(incomplete_readiness.get("can_build", true)), "incomplete project cannot build", failures)
	_expect(bool(valid_readiness.get("can_build", false)), "unassigned optional project assets do not block build", failures)

	var build := BuilderScript.new().build(VALID_ID)
	_expect(bool(build.get("ok", false)), "valid project builds successfully", failures)
	_expect(str(build.get("path", "")).begins_with("user://games/") and not str(build.get("path", "")).begins_with("res://"), "build writes only beneath user://games", failures)
	var manifest: Dictionary = build.get("manifest", {})
	_expect(str(manifest.get("project_id", "")) == VALID_ID, "built manifest contains project identity", failures)
	_expect(Array(manifest.get("fighter_ids", [])) == valid.fighter_ids, "built manifest contains roster references", failures)
	_expect(str(manifest.get("presentation_reference", "")) == "presentation.json", "built manifest contains presentation reference", failures)
	var restarted_readiness := ReadinessScript.new().evaluate(VALID_ID)
	_expect(str(restarted_readiness.get("status", "")) == "built" and bool(restarted_readiness.get("can_play", false)), "built project survives service restart", failures)

	var launch := LaunchConfigScript.new()
	_expect(launch.begin_local(VALID_ID), "built project enters local launch context", failures)
	_expect(launch.get_fighter_ids() == valid.fighter_ids, "custom Character Select receives only project roster", failures)
	var project_entries := FighterProviderScript.new().list_fighters_for_ids(launch.get_fighter_ids())
	var project_entry_ids: Array[String] = []
	for entry in project_entries:
		project_entry_ids.append(str(entry.get("id", "")))
	_expect(project_entry_ids == valid.fighter_ids, "custom Character Select provider returns only project roster", failures)
	_expect(not launch.set_fighter_selection("example_fighter", "outside_roster"), "project launch rejects fighters outside roster", failures)
	_expect(launch.set_fighter_selection("example_fighter", "example_fighter_alt"), "project launch accepts roster fighters", failures)
	var pending := launch.get_context()
	_expect(str(pending.get("project_id", "")) == VALID_ID and str(pending.get("mode", "")) == "single_player", "launch context survives project to match setup", failures)
	_expect(str(pending.get("presentation_reference", "")) == "presentation.json", "launch context carries presentation identity", failures)
	var presentation := PresentationResolverScript.new().resolve(launch.get_project_id())
	_expect(bool(presentation.get("project", false)), "custom match resolves project presentation", failures)
	var network := NetworkConfigScript.new()
	network.set_single_player()
	network.set_fighter_selection("example_fighter", "example_fighter_alt")
	network.consume()
	_expect(launch.has_project() and launch.get_context().get("p1_fighter_id", "") == "example_fighter", "match consume and rematch preserve project context", failures)
	launch.clear()
	_expect(launch.get_fighter_ids().is_empty(), "default Character Select has no project roster filter", failures)

	for project_id in [VALID_ID, INCOMPLETE_ID, CORRUPT_ID]:
		_cleanup_tree("user://games/%s" % project_id)
	_finish(failures)

func _project(display_name: String, project_id: String, fighter_ids: Array[String]) -> RollbackFighterGameProjectDefinition:
	var project := ProjectDefinitionScript.new()
	project.configure(display_name, project_id, "platform_fighter")
	for fighter_id in fighter_ids:
		project.add_fighter(fighter_id)
	return project

func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func _cleanup_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path + "/" + name
		if dir.current_is_dir():
			_cleanup_tree(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)

func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)

func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[GameProjectLibraryTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[GameProjectLibraryTests] FAIL: %s" % failure)
	quit(1)
