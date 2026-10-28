extends RefCounted
class_name RollbackShooterCanonicalConfig

const GAME_ID: String = "rollback_shooter"
const MAGIC: String = "HR-SHOOTER-AUTH-V1"


func canonical_bytes(rules: RollbackShooterRulesDefinition) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	_append_string(bytes, MAGIC)
	_append_string(bytes, GAME_ID)
	for value in rules.get_ordered_values():
		_append_i64_be(bytes, value)
	return bytes


func digest_hex(rules: RollbackShooterRulesDefinition) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(canonical_bytes(rules))
	return context.finish().hex_encode()


func _append_string(bytes: PackedByteArray, value: String) -> void:
	var encoded: PackedByteArray = value.to_utf8_buffer()
	_append_u32_be(bytes, encoded.size())
	bytes.append_array(encoded)


func _append_u32_be(bytes: PackedByteArray, value: int) -> void:
	for shift in [24, 16, 8, 0]:
		bytes.append((value >> shift) & 0xff)


func _append_i64_be(bytes: PackedByteArray, value: int) -> void:
	for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
		bytes.append((value >> shift) & 0xff)
