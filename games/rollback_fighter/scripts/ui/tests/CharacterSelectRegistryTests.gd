extends SceneTree

const REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const LoaderScript = preload(
	"res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd"
)


func _initialize() -> void:
	var registry_file: FileAccess = FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	assert(registry_file != null)
	var parsed: Variant = JSON.parse_string(registry_file.get_as_text())
	assert(typeof(parsed) == TYPE_DICTIONARY)
	var registry: Dictionary = parsed
	var fighter_roots: Dictionary = registry["fighters"]
	var fighter_ids: Array[String] = []
	for fighter_id: Variant in fighter_roots.keys():
		fighter_ids.append(str(fighter_id))
	fighter_ids.sort()
	assert(fighter_ids == ["example_fighter", "example_fighter_alt"])
	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	for fighter_id: String in fighter_ids:
		var result: Dictionary = loader.load_builtin_fighter(REGISTRY_PATH, fighter_id)
		assert(bool(result.get("ok", false)))
		var definition: RollbackFighterCharacterDefinition = result["definition"]
		assert(definition.get_id() == fighter_id)
	print("[CharacterSelectRegistryTests] PASS | options=%s" % ",".join(fighter_ids))
	quit(0)
