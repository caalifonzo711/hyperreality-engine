extends RefCounted
class_name RollbackFighterProjectAudioImporter


const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const PresentationDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationDefinition.gd")
const AUDIO_EXTENSIONS := ["wav", "ogg"]
const MAX_AUDIO_BYTES := 32 * 1024 * 1024


func import_audio(project_id: String, slot_id: String, source_path: String) -> Dictionary:
	if not ProjectDefinitionScript.is_safe_id(project_id):
		return _failure("PROJECT_AUDIO_PROJECT_INVALID", project_id, "project_id must match [a-z0-9_]+")
	if not FileAccess.file_exists("user://games/%s/project.json" % project_id):
		return _failure("PROJECT_AUDIO_PROJECT_NOT_FOUND", project_id, "project must exist before importing audio")
	if slot_id not in PresentationDefinitionScript.AUDIO_SLOT_IDS:
		return _failure("PROJECT_AUDIO_SLOT_INVALID", slot_id, "audio slot must be known")
	var extension := source_path.get_extension().to_lower()
	if extension not in AUDIO_EXTENSIONS:
		return _failure("PROJECT_AUDIO_TYPE_UNSUPPORTED", extension, "supported audio types are WAV and OGG")
	if not FileAccess.file_exists(source_path):
		return _failure("PROJECT_AUDIO_NOT_FOUND", source_path, "source audio must exist")
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return _failure("PROJECT_AUDIO_READ_FAILED", source_path, "source audio must be readable")
	var source_length := source.get_length()
	if source_length <= 0 or source_length > MAX_AUDIO_BYTES:
		source.close()
		return _failure("PROJECT_AUDIO_SIZE_INVALID", source_path, "audio must be non-empty and no larger than 32 MiB")
	var bytes := source.get_buffer(source_length)
	source.close()
	var load_result := load_stream_result(source_path)
	if not bool(load_result.get("ok", false)):
		return _failure(
			str(load_result.get("code", "PROJECT_AUDIO_DECODE_FAILED")),
			source_path,
			str(load_result.get("message", "audio must decode as supported WAV or OGG"))
		)
	var stream: AudioStream = load_result["stream"]
	var destination_folder := "user://games/%s/assets/audio" % project_id
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_folder))
	if mkdir_error != OK:
		return _failure("PROJECT_AUDIO_DIRECTORY_FAILED", destination_folder, "asset directory must be writable")
	remove_audio(project_id, slot_id)
	var destination := "%s/%s.%s" % [destination_folder, slot_id, extension]
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return _failure("PROJECT_AUDIO_COPY_FAILED", destination, "destination must be writable under user://games")
	output.store_buffer(bytes)
	output.close()
	return {"ok": true, "path": destination, "stream": stream, "errors": []}


func remove_audio(project_id: String, slot_id: String) -> bool:
	if not ProjectDefinitionScript.is_safe_id(project_id) or slot_id not in PresentationDefinitionScript.AUDIO_SLOT_IDS:
		return false
	for extension in AUDIO_EXTENSIONS:
		var path := "user://games/%s/assets/audio/%s.%s" % [project_id, slot_id, extension]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func load_stream(path: String) -> AudioStream:
	var result := load_stream_result(path)
	if not bool(result.get("ok", false)):
		return null
	var stream: AudioStream = result["stream"]
	return stream


func load_stream_result(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _load_failure("PROJECT_AUDIO_NOT_FOUND", "audio file does not exist")
	match path.get_extension().to_lower():
		"wav":
			var wav_file := FileAccess.open(path, FileAccess.READ)
			if wav_file == null:
				return _load_failure("PROJECT_AUDIO_READ_FAILED", "WAV file must be readable")
			var wav_length := wav_file.get_length()
			if wav_length <= 0 or wav_length > MAX_AUDIO_BYTES:
				wav_file.close()
				return _load_failure("PROJECT_AUDIO_SIZE_INVALID", "WAV must be non-empty and no larger than 32 MiB")
			var bytes := wav_file.get_buffer(wav_length)
			wav_file.close()
			return _decode_pcm_wav(bytes)
		"ogg":
			var ogg_file := FileAccess.open(path, FileAccess.READ)
			if ogg_file == null:
				return _load_failure("PROJECT_AUDIO_READ_FAILED", "OGG file must be readable")
			var ogg_length := ogg_file.get_length()
			ogg_file.close()
			if ogg_length <= 0 or ogg_length > MAX_AUDIO_BYTES:
				return _load_failure("PROJECT_AUDIO_SIZE_INVALID", "OGG must be non-empty and no larger than 32 MiB")
			var stream := AudioStreamOggVorbis.load_from_file(path)
			if stream == null:
				return _load_failure("PROJECT_AUDIO_OGG_DECODE_FAILED", "OGG must contain valid Ogg Vorbis audio")
			return {"ok": true, "stream": stream, "code": "", "message": ""}
	return _load_failure("PROJECT_AUDIO_TYPE_UNSUPPORTED", "supported audio types are PCM WAV and Ogg Vorbis")


func _decode_pcm_wav(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 12 or not _ascii_equals(bytes, 0, "RIFF") or not _ascii_equals(bytes, 8, "WAVE"):
		return _load_failure("PROJECT_AUDIO_WAV_INVALID", "WAV must use a valid RIFF/WAVE container")
	var riff_end := 8 + _read_u32_le(bytes, 4)
	if riff_end < 12 or riff_end > bytes.size():
		return _load_failure("PROJECT_AUDIO_WAV_INVALID", "WAV RIFF size is invalid or truncated")
	var audio_format := 0
	var channels := 0
	var sample_rate := 0
	var block_align := 0
	var bits_per_sample := 0
	var data_offset := -1
	var data_size := 0
	var cursor := 12
	while cursor + 8 <= riff_end:
		var chunk_size := _read_u32_le(bytes, cursor + 4)
		var payload_offset := cursor + 8
		var payload_end := payload_offset + chunk_size
		if payload_end > riff_end:
			return _load_failure("PROJECT_AUDIO_WAV_INVALID", "WAV contains a truncated chunk")
		if _ascii_equals(bytes, cursor, "fmt "):
			if chunk_size < 16:
				return _load_failure("PROJECT_AUDIO_WAV_INVALID", "WAV fmt chunk is too short")
			audio_format = _read_u16_le(bytes, payload_offset)
			channels = _read_u16_le(bytes, payload_offset + 2)
			sample_rate = _read_u32_le(bytes, payload_offset + 4)
			block_align = _read_u16_le(bytes, payload_offset + 12)
			bits_per_sample = _read_u16_le(bytes, payload_offset + 14)
		elif _ascii_equals(bytes, cursor, "data") and data_offset < 0:
			data_offset = payload_offset
			data_size = chunk_size
		cursor = payload_end + (chunk_size & 1)
	if audio_format != 1:
		return _load_failure("PROJECT_AUDIO_WAV_CODEC_UNSUPPORTED", "WAV must use uncompressed PCM encoding")
	if channels not in [1, 2]:
		return _load_failure("PROJECT_AUDIO_WAV_CHANNELS_UNSUPPORTED", "PCM WAV must be mono or stereo")
	if bits_per_sample not in [8, 16]:
		return _load_failure("PROJECT_AUDIO_WAV_BITS_UNSUPPORTED", "PCM WAV must use 8-bit or 16-bit samples")
	if sample_rate <= 0 or sample_rate > 384000:
		return _load_failure("PROJECT_AUDIO_WAV_RATE_INVALID", "PCM WAV sample rate must be between 1 and 384000 Hz")
	var expected_block_align := channels * (bits_per_sample >> 3)
	if block_align != expected_block_align:
		return _load_failure("PROJECT_AUDIO_WAV_INVALID", "PCM WAV block alignment does not match its channels and sample size")
	if data_offset < 0 or data_size <= 0 or data_size % block_align != 0:
		return _load_failure("PROJECT_AUDIO_WAV_INVALID", "PCM WAV audio data is missing or not sample-aligned")
	var pcm_data := bytes.slice(data_offset, data_offset + data_size)
	if bits_per_sample == 8:
		# RIFF PCM8 is unsigned; AudioStreamWAV expects signed PCM8 in Godot 4.3.
		for index in pcm_data.size():
			pcm_data[index] = (pcm_data[index] + 128) & 0xff
	var stream := AudioStreamWAV.new()
	stream.data = pcm_data
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits_per_sample == 8 else AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return {"ok": true, "stream": stream, "code": "", "message": ""}


func _ascii_equals(bytes: PackedByteArray, offset: int, expected: String) -> bool:
	var encoded := expected.to_ascii_buffer()
	if offset < 0 or offset + encoded.size() > bytes.size():
		return false
	for index in encoded.size():
		if bytes[offset + index] != encoded[index]:
			return false
	return true


func _read_u16_le(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)


func _read_u32_le(bytes: PackedByteArray, offset: int) -> int:
	return (
		bytes[offset]
		| (bytes[offset + 1] << 8)
		| (bytes[offset + 2] << 16)
		| (bytes[offset + 3] << 24)
	)


func _load_failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "stream": null, "code": code, "message": message}


func _failure(code: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "presentation.json", "field": "audio", "invalid_value": value, "expected_rule": rule}]}
