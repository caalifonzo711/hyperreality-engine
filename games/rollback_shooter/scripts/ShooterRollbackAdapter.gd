extends RollbackSimulationAdapter
class_name RollbackShooterAdapter

const RULES_SCRIPT = preload("res://games/rollback_shooter/scripts/ShooterRulesDefinition.gd")
const MAX_PROJECTILES: int = 256

var rules: RollbackShooterRulesDefinition
var players: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var next_projectile_id: int = 1
var simulation_frame: int = 0
var match_over: bool = false
var winner_id: int = 0

const DIR_X := [1, 1, 0, -1, -1, -1, 0, 1]
const DIR_Y := [0, 1, 1, 1, 0, -1, -1, -1]


func configure(loaded_rules: RollbackShooterRulesDefinition) -> void:
	rules = loaded_rules
	reset_match()


func reset_match() -> void:
	players = [
		_new_player(1, rules.get_int("spawn_p1_x"), rules.get_int("spawn_p1_y")),
		_new_player(2, rules.get_int("spawn_p2_x"), rules.get_int("spawn_p2_y")),
	]
	projectiles.clear()
	next_projectile_id = 1
	simulation_frame = 0
	match_over = false
	winner_id = 0


func neutral_input() -> Dictionary:
	return {"move_x": 0, "move_y": 0, "aim_dir": 0, "shoot": false}


func validate_input_data(input_data: Dictionary) -> bool:
	if input_data.size() != 4:
		return false
	for field in ["move_x", "move_y", "aim_dir"]:
		if not input_data.has(field) or typeof(input_data[field]) != TYPE_INT:
			return false
	if int(input_data["move_x"]) < -1 or int(input_data["move_x"]) > 1:
		return false
	if int(input_data["move_y"]) < -1 or int(input_data["move_y"]) > 1:
		return false
	if int(input_data["aim_dir"]) < 0 or int(input_data["aim_dir"]) > 7:
		return false
	return typeof(input_data.get("shoot")) == TYPE_BOOL


func inputs_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("move_x", 0)) == int(b.get("move_x", 0))
		and int(a.get("move_y", 0)) == int(b.get("move_y", 0))
		and int(a.get("aim_dir", 0)) == int(b.get("aim_dir", 0))
		and bool(a.get("shoot", false)) == bool(b.get("shoot", false))
	)


func simulate(local: Dictionary, remote: Dictionary, _dt: float) -> void:
	if rules == null or match_over:
		return
	var inputs: Array[Dictionary] = [local, remote]
	for index in range(2):
		var player: Dictionary = players[index]
		if not bool(player["alive"]):
			continue
		player["aim_dir"] = int(inputs[index].get("aim_dir", player["aim_dir"]))
		player["fire_cd"] = maxi(0, int(player["fire_cd"]) - 1)
		var move_x: int = int(inputs[index].get("move_x", 0))
		var move_y: int = int(inputs[index].get("move_y", 0))
		var step: int = 3 if move_x != 0 and move_y != 0 else 4
		player["x"] = clampi(int(player["x"]) + move_x * step, rules.get_int("player_half_extent"), rules.get_int("arena_width") - rules.get_int("player_half_extent"))
		player["y"] = clampi(int(player["y"]) + move_y * step, rules.get_int("player_half_extent"), rules.get_int("arena_height") - rules.get_int("player_half_extent"))
		players[index] = player
	_update_projectiles()
	for index in range(2):
		if match_over:
			break
		var player: Dictionary = players[index]
		if bool(player["alive"]) and bool(inputs[index].get("shoot", false)) and int(player["fire_cd"]) == 0:
			_spawn_projectile(player)
	simulation_frame += 1


func _update_projectiles() -> void:
	var remaining: Array[Dictionary] = []
	for projectile_value in projectiles:
		var projectile: Dictionary = projectile_value.duplicate(true)
		var direction: int = int(projectile["direction"])
		var step: int = 7 if DIR_X[direction] != 0 and DIR_Y[direction] != 0 else rules.get_int("projectile_speed_px_per_frame")
		projectile["x"] = int(projectile["x"]) + DIR_X[direction] * step
		projectile["y"] = int(projectile["y"]) + DIR_Y[direction] * step
		projectile["lifetime"] = int(projectile["lifetime"]) - 1
		var hit: bool = false
		var target_index: int = 1 if int(projectile["owner"]) == 1 else 0
		var target: Dictionary = players[target_index]
		var extent: int = rules.get_int("player_half_extent") + rules.get_int("projectile_half_extent")
		if bool(target["alive"]) and absi(int(projectile["x"]) - int(target["x"])) <= extent and absi(int(projectile["y"]) - int(target["y"])) <= extent:
			target["hp"] = maxi(0, int(target["hp"]) - int(projectile["damage"]))
			if int(target["hp"]) == 0:
				target["alive"] = false
				match_over = true
				winner_id = int(projectile["owner"])
			players[target_index] = target
			hit = true
		var in_bounds: bool = int(projectile["x"]) >= 0 and int(projectile["x"]) <= rules.get_int("arena_width") and int(projectile["y"]) >= 0 and int(projectile["y"]) <= rules.get_int("arena_height")
		if not hit and in_bounds and int(projectile["lifetime"]) > 0:
			remaining.append(projectile)
	projectiles = remaining


func _spawn_projectile(player: Dictionary) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		return
	var direction: int = int(player["aim_dir"])
	var origin_step: int = rules.get_int("player_half_extent") + rules.get_int("projectile_half_extent") + 1
	var projectile: Dictionary = {
		"id": next_projectile_id,
		"owner": int(player["id"]),
		"x": int(player["x"]) + DIR_X[direction] * origin_step,
		"y": int(player["y"]) + DIR_Y[direction] * origin_step,
		"direction": direction,
		"lifetime": rules.get_int("projectile_lifetime_frames"),
		"damage": rules.get_int("projectile_damage"),
	}
	projectiles.append(projectile)
	next_projectile_id += 1
	player["fire_cd"] = rules.get_int("fire_cooldown_frames")
	players[int(player["id"]) - 1] = player


func _new_player(player_id: int, x: int, y: int) -> Dictionary:
	return {"id": player_id, "x": x, "y": y, "hp": rules.get_int("player_hp"), "aim_dir": 0, "fire_cd": 0, "alive": true}


func capture() -> Dictionary:
	return {
		"players": players.duplicate(true),
		"projectiles": projectiles.duplicate(true),
		"next_projectile_id": next_projectile_id,
		"simulation_frame": simulation_frame,
		"match_over": match_over,
		"winner_id": winner_id,
	}


func restore(snapshot: Dictionary) -> void:
	players = Array(snapshot.get("players", [])).duplicate(true)
	projectiles = Array(snapshot.get("projectiles", [])).duplicate(true)
	next_projectile_id = int(snapshot.get("next_projectile_id", 1))
	simulation_frame = int(snapshot.get("simulation_frame", 0))
	match_over = bool(snapshot.get("match_over", false))
	winner_id = int(snapshot.get("winner_id", 0))


func canonical_debug_values(snapshot: Dictionary) -> Array:
	var values: Array = [int(snapshot.get("simulation_frame", 0)), int(snapshot.get("match_over", false)), int(snapshot.get("winner_id", 0)), int(snapshot.get("next_projectile_id", 1))]
	for player_value in Array(snapshot.get("players", [])):
		var player: Dictionary = player_value
		for key in ["id", "x", "y", "hp", "aim_dir", "fire_cd", "alive"]:
			values.append(int(player.get(key, 0)))
	var shots: Array = Array(snapshot.get("projectiles", [])).duplicate(true)
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id", 0)) < int(b.get("id", 0)))
	values.append(shots.size())
	for projectile_value in shots:
		var projectile: Dictionary = projectile_value
		for key in ["id", "owner", "x", "y", "direction", "lifetime", "damage"]:
			values.append(int(projectile.get(key, 0)))
	return values


func canonical_checksum(snapshot: Dictionary) -> int:
	return canonical_debug_values(snapshot).hash()


func report_first_debug_difference(_frame: int, _local_snapshot: Dictionary, _remote_values: Array, _remote_checksum: int = 0) -> void:
	pass
