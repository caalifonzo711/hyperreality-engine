extends SceneTree

const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const PresentationDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationDefinition.gd")
const PresentationStoreScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationStore.gd")
const AssetImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAssetImporter.gd")
const AudioImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAudioImporter.gd")
const ResolverScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationResolver.gd")
const LaunchContextScript = preload("res://games/rollback_fighter/scripts/projects/CreatorLaunchContext.gd")
const WriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const PROJECT_ID := "c8_presentation_test"
const OLD_PROJECT_ID := "c8_old_project_test"

func _initialize() -> void:
	var failures := PackedStringArray()
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	_cleanup_tree("user://games/%s" % OLD_PROJECT_ID)
	var project := ProjectDefinitionScript.new()
	project.configure("C8 Test Game", PROJECT_ID, "platform_fighter")
	var project_store := ProjectStoreScript.new()
	_expect(bool(project_store.create(project).get("ok", false)), "project fixture saves", failures)
	for folder in ["backgrounds", "branding", "audio"]:
		_expect(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://games/%s/assets/%s" % [PROJECT_ID, folder])), "asset folder exists: %s" % folder, failures)

	var presentation := PresentationDefinitionScript.new()
	presentation.configure(PROJECT_ID, project.display_name)
	presentation.floor_y_normalized = 0.77
	var presentation_store := PresentationStoreScript.new()
	_expect(bool(presentation_store.save(presentation).get("ok", false)), "ProjectPresentationDefinition saves", failures)
	var loaded := presentation_store.load_presentation(PROJECT_ID)
	_expect(bool(loaded.get("ok", false)), "ProjectPresentationDefinition loads", failures)
	if bool(loaded.get("ok", false)):
		_expect(loaded["presentation"].to_dictionary() == presentation.to_dictionary(), "presentation save/load round trip preserves fields", failures)

	var source_png := "user://c8_source.png"
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.3, 0.6, 1.0))
	image.save_png(source_png)
	var image_result := AssetImporterScript.new().import_image(PROJECT_ID, "background", source_png)
	_expect(bool(image_result.get("ok", false)), "project background imports", failures)
	if bool(image_result.get("ok", false)):
		presentation.background_image = str(image_result["path"])
		_expect(presentation.background_image == "user://games/%s/assets/backgrounds/background.png" % PROJECT_ID, "background uses deterministic project path", failures)
	var bad_image := "user://c8_bad.png"
	_write_text(bad_image, "not an image")
	_expect(not bool(AssetImporterScript.new().import_image(PROJECT_ID, "logo", bad_image).get("ok", false)), "invalid image is rejected safely", failures)

	var wav_path := "user://c8_source.wav"
	_write_test_wav(wav_path)
	var audio_result := AudioImporterScript.new().import_audio(PROJECT_ID, "jab_swing", wav_path)
	_expect(bool(audio_result.get("ok", false)), "WAV audio imports and decodes", failures)
	if bool(audio_result.get("ok", false)):
		var wav_stream: AudioStreamWAV = audio_result["stream"]
		_expect(wav_stream.format == AudioStreamWAV.FORMAT_8_BITS, "PCM8 WAV selects the Godot 4.3 8-bit format", failures)
		_expect(wav_stream.mix_rate == 8000 and not wav_stream.stereo, "PCM8 WAV preserves sample rate and mono layout", failures)
		_expect(wav_stream.data.size() == 2 and wav_stream.data[0] == 0, "unsigned RIFF PCM8 is converted to signed Godot PCM8", failures)
		_expect(presentation.set_audio_slot("jab_swing", str(audio_result["path"])), "audio slot mapping accepts imported asset", failures)
	var stereo_wav_path := "user://c8_source_stereo16.wav"
	_write_test_wav_stereo16(stereo_wav_path)
	var stereo_stream := AudioImporterScript.new().load_stream(stereo_wav_path)
	_expect(stereo_stream is AudioStreamWAV, "PCM16 WAV decodes on Godot 4.3", failures)
	if stereo_stream is AudioStreamWAV:
		_expect(stereo_stream.format == AudioStreamWAV.FORMAT_16_BITS and stereo_stream.stereo, "PCM16 stereo metadata is preserved", failures)
	var bad_audio := "user://c8_bad.wav"
	_write_text(bad_audio, "not audio")
	_expect(not bool(AudioImporterScript.new().import_audio(PROJECT_ID, "ko", bad_audio).get("ok", false)), "invalid audio is rejected safely", failures)
	var unsupported_wav := "user://c8_unsupported.wav"
	_write_test_wav(unsupported_wav)
	var unsupported_bytes := FileAccess.get_file_as_bytes(unsupported_wav)
	unsupported_bytes.encode_u16(20, 3)
	var unsupported_file := FileAccess.open(unsupported_wav, FileAccess.WRITE)
	if unsupported_file != null:
		unsupported_file.store_buffer(unsupported_bytes)
		unsupported_file.close()
	var unsupported_result := AudioImporterScript.new().import_audio(PROJECT_ID, "ko", unsupported_wav)
	_expect(not bool(unsupported_result.get("ok", false)), "compressed or floating-point WAV rejects cleanly", failures)
	if not bool(unsupported_result.get("ok", false)):
		var unsupported_errors: Array = unsupported_result.get("errors", [])
		_expect(not unsupported_errors.is_empty() and str(unsupported_errors[0].get("code", "")) == "PROJECT_AUDIO_WAV_CODEC_UNSUPPORTED", "unsupported WAV reports an actionable codec error", failures)
	_expect(bool(presentation_store.save(presentation).get("ok", false)), "presentation with imported mappings saves", failures)

	var resolved := ResolverScript.new().resolve(PROJECT_ID)
	_expect(str(resolved.get("background_image", "")) == presentation.background_image, "project context resolves its background", failures)
	_expect(str(Dictionary(resolved.get("audio_slots", {})).get("jab_swing", "")) == str(presentation.audio_slots.get("jab_swing", "")), "project context resolves its audio mapping", failures)
	_expect(not bool(resolved.get("fallback_background", true)), "valid custom background suppresses fallback", failures)
	_expect(ResolverScript.new().resolve("").get("audio_slots", {}) == {}, "missing legacy audio falls back to silence", failures)
	_expect(bool(ResolverScript.new().resolve("").get("fallback_background", false)), "legacy flow uses built-in background fallback", failures)

	var old_project := ProjectDefinitionScript.new()
	old_project.configure("Old Project", OLD_PROJECT_ID, "platform_fighter")
	_expect(bool(project_store.create(old_project).get("ok", false)), "old project fixture saves without presentation.json", failures)
	var old_resolved := ResolverScript.new().resolve(OLD_PROJECT_ID)
	_expect(bool(old_resolved.get("project", false)) and bool(old_resolved.get("fallback_background", false)), "C6/C7 project without presentation file loads defaults", failures)
	_write_text("user://games/%s/presentation.json" % OLD_PROJECT_ID, "{not valid json")
	var corrupt_resolved := ResolverScript.new().resolve(OLD_PROJECT_ID)
	_expect(bool(corrupt_resolved.get("project", false)) and bool(corrupt_resolved.get("fallback_background", false)), "corrupt presentation file degrades to defaults", failures)
	var context := LaunchContextScript.new()
	_expect(context.launch_for_project(PROJECT_ID), "project launch context accepts C8 project", failures)
	_expect(str(context.get_runtime_presentation().get("background_image", "")) == presentation.background_image, "launch context resolves project presentation", failures)
	context.launch_global()
	_expect(bool(context.get_runtime_presentation().get("legacy", false)), "direct legacy flow resolves built-in presentation", failures)

	var loader := LoaderScript.new()
	var rules := loader.load_game_rules("res://games/rollback_fighter/config/game_rules.json")
	var fighter := loader.load_builtin_fighter("res://games/rollback_fighter/config/builtin_fighters.json", "example_fighter")
	if bool(rules.get("ok", false)) and bool(fighter.get("ok", false)):
		var writer := WriterScript.new()
		var digest_before := writer.sha256_hex(writer.character_bytes(rules["definition"], fighter["definition"]))
		presentation.floor_y_normalized = 0.88
		presentation_store.save(presentation)
		var digest_after := writer.sha256_hex(writer.character_bytes(rules["definition"], fighter["definition"]))
		_expect(digest_before == digest_after and not digest_before.is_empty(), "project presentation does not alter authoritative digest", failures)
	else:
		_expect(false, "authoritative digest fixtures load", failures)
	_expect(not str(presentation_store.save(presentation).get("path", "")).begins_with("res://"), "presentation never writes to res://", failures)

	for path in [source_png, bad_image, wav_path, stereo_wav_path, bad_audio, unsupported_wav]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	_cleanup_tree("user://games/%s" % OLD_PROJECT_ID)
	_finish(failures)

func _write_test_wav(path: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(46)
	_write_ascii(bytes, 0, "RIFF")
	bytes.encode_u32(4, 38)
	_write_ascii(bytes, 8, "WAVEfmt ")
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 1)
	bytes.encode_u32(24, 8000)
	bytes.encode_u32(28, 8000)
	bytes.encode_u16(32, 1)
	bytes.encode_u16(34, 8)
	_write_ascii(bytes, 36, "data")
	bytes.encode_u32(40, 2)
	bytes[44] = 128
	bytes[45] = 128
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _write_test_wav_stereo16(path: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(48)
	_write_ascii(bytes, 0, "RIFF")
	bytes.encode_u32(4, 40)
	_write_ascii(bytes, 8, "WAVEfmt ")
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 2)
	bytes.encode_u32(24, 8000)
	bytes.encode_u32(28, 32000)
	bytes.encode_u16(32, 4)
	bytes.encode_u16(34, 16)
	_write_ascii(bytes, 36, "data")
	bytes.encode_u32(40, 4)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _write_ascii(bytes: PackedByteArray, offset: int, value: String) -> void:
	var encoded := value.to_ascii_buffer()
	for index in encoded.size():
		bytes[offset + index] = encoded[index]

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
		print("[ProjectPresentationTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[ProjectPresentationTests] FAIL: %s" % failure)
	quit(1)
