extends SceneTree

const RulesScript = preload("res://games/rollback_shooter/scripts/ShooterRulesDefinition.gd")
const AdapterScript = preload("res://games/rollback_shooter/scripts/ShooterRollbackAdapter.gd")
const CanonicalScript = preload("res://games/rollback_shooter/scripts/ShooterCanonicalConfig.gd")
const HandshakeScript = preload("res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd")
const SessionScript = preload("res://games/rollback_fighter/scripts/net/RollbackNetworkSession.gd")


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var rules: RollbackShooterRulesDefinition = RulesScript.new()
	var rules_result: Dictionary = rules.load_from_resource()
	_expect(bool(rules_result.get("ok", false)), "rules load and validate", failures)
	if not bool(rules_result.get("ok", false)):
		_finish(failures)
		return
	var first: RollbackShooterAdapter = AdapterScript.new()
	var second: RollbackShooterAdapter = AdapterScript.new()
	var replay: RollbackShooterAdapter = AdapterScript.new()
	first.configure(rules)
	second.configure(rules)
	replay.configure(rules)
	_expect(first.validate_input_data(_input(0)), "shooter InputFrame validates", failures)
	_expect(not first.validate_input_data({"move_x": 2, "move_y": 0, "aim_dir": 0, "shoot": false}), "invalid quantized movement is rejected", failures)
	var rollback_snapshot: Dictionary = {}
	for frame in range(300):
		var input_pair: Array[Dictionary] = _input_pair(frame)
		first.simulate(input_pair[0], input_pair[1], 1.0 / 60.0)
		second.simulate(input_pair[0], input_pair[1], 1.0 / 60.0)
		if frame == 119:
			rollback_snapshot = first.capture()
	_expect(first.canonical_checksum(first.capture()) == second.canonical_checksum(second.capture()), "same scripted inputs converge to identical checksum", failures)
	replay.restore(rollback_snapshot)
	for frame in range(120, 300):
		var replay_pair: Array[Dictionary] = _input_pair(frame)
		replay.simulate(replay_pair[0], replay_pair[1], 1.0 / 60.0)
	_expect(first.canonical_checksum(first.capture()) == replay.canonical_checksum(replay.capture()), "snapshot restore and replay converge to the same checksum", failures)
	_expect(first.capture().has("projectiles") and first.capture().has("next_projectile_id"), "snapshot includes projectiles and ID sequence", failures)
	_expect(first.canonical_debug_values(first.capture()).size() > 20, "canonical checksum includes ordered match/player/projectile state", failures)
	var session_adapter: RollbackShooterAdapter = AdapterScript.new()
	session_adapter.configure(rules)
	var session: RollbackNetworkSession = SessionScript.new()
	session.setup(session_adapter, null, 1)
	session.start_session()
	for frame in range(30):
		session.remote_inputs[frame] = session_adapter.neutral_input()
		session.last_remote_input_frame = frame
		session.remote_confirmed_through = frame
		session.tick(_input(frame))
	_expect(session.current_frame == 30, "shared RollbackNetworkSession advances shooter frames", failures)
	_expect(session.local_checksums.has(29), "shared session records shooter canonical checksums", failures)
	session.free()
	session_adapter.free()
	var late_adapter: RollbackShooterAdapter = AdapterScript.new()
	late_adapter.configure(rules)
	var late_session: RollbackNetworkSession = SessionScript.new()
	late_session.setup(late_adapter, null, 1)
	late_session.start_session()
	for frame in range(4):
		late_session.tick(_input(frame))
	var late_records: Array[Dictionary] = [{
		"frame": 1,
		"input": {"move_x": 1, "move_y": 0, "aim_dir": 4, "shoot": false},
		"redundant": false,
	}]
	late_session._merge_remote_input_records(late_records)
	_expect(late_session.rollback_count == 1, "shared session rolls back after late shooter input", failures)
	_expect(int(late_adapter.players[1]["x"]) > rules.get_int("spawn_p2_x"), "late remote input is replayed through shooter simulation", failures)
	late_session.free()
	late_adapter.free()

	var combat: RollbackShooterAdapter = AdapterScript.new()
	combat.configure(rules)
	combat.players[0]["x"] = 300
	combat.players[1]["x"] = 360
	for _frame in range(120):
		combat.simulate({"move_x": 0, "move_y": 0, "aim_dir": 0, "shoot": true}, combat.neutral_input(), 0.0)
		if combat.match_over:
			break
	_expect(combat.match_over and combat.winner_id == 1 and int(combat.players[1]["hp"]) == 0, "deterministic hit damage produces death and winner", failures)
	var writer: RollbackShooterCanonicalConfig = CanonicalScript.new()
	var digest: String = writer.digest_hex(rules)
	_expect(digest.length() == 64 and writer.canonical_bytes(rules).size() > 100, "canonical shooter config identity is stable and nonempty", failures)
	var identity: Dictionary = HandshakeScript.new().build_identity(
		"rollback_shooter", 1, "shooter_p1", 1, "shooter_p2", 1,
		writer.canonical_bytes(rules), digest
	)
	var same_peer: RollbackFighterMatchConfigHandshake = HandshakeScript.new()
	same_peer.local_identity = identity.duplicate(true)
	_expect(bool(same_peer.accept_remote_identity(identity).get("ok", false)), "same shooter identity verifies", failures)
	var wrong_game_peer: RollbackFighterMatchConfigHandshake = HandshakeScript.new()
	wrong_game_peer.local_identity = identity.duplicate(true)
	var fighter_identity: Dictionary = identity.duplicate(true)
	fighter_identity["game_id"] = "rollback_fighter"
	_expect(not bool(wrong_game_peer.accept_remote_identity(fighter_identity).get("ok", false)), "fighter/shooter cross-join is rejected", failures)
	first.free()
	second.free()
	replay.free()
	combat.free()
	_finish(failures)


func _input(frame: int) -> Dictionary:
	return {"move_x": 1 if frame % 80 < 40 else -1, "move_y": 1 if frame % 50 < 25 else 0, "aim_dir": frame % 8, "shoot": frame % 17 == 0}


func _input_pair(frame: int) -> Array[Dictionary]:
	var p1: Dictionary = _input(frame)
	var p2: Dictionary = {"move_x": -int(p1["move_x"]), "move_y": -int(p1["move_y"]), "aim_dir": (int(p1["aim_dir"]) + 4) % 8, "shoot": frame % 23 == 0}
	return [p1, p2]


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[ShooterDeterminismTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[ShooterDeterminismTests] FAIL: %s" % failure)
	quit(1)
