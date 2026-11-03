extends Node
class_name RollbackFighterProjectPresentationRuntime


const AssetImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAssetImporter.gd")
const AudioImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAudioImporter.gd")

var _config: Dictionary = {}
var _audio_slots: Dictionary = {}
var _sfx_player: AudioStreamPlayer
var _bgm_player: AudioStreamPlayer
var _round_started := false
var _round_ended := false
var _last_p1_attack_id := 0
var _last_p2_attack_id := 0
var _last_p1_state := PlayerState.MoveState.IDLE
var _last_p2_state := PlayerState.MoveState.IDLE
var _last_p1_hp := -1
var _last_p2_hp := -1


func configure(arena: Node, config: Dictionary) -> void:
	_config = config.duplicate(true)
	_audio_slots = Dictionary(config.get("audio_slots", {})).duplicate()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "ProjectSfx"
	arena.add_child(_sfx_player)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "ProjectBgm"
	arena.add_child(_bgm_player)
	_create_background(arena)
	_create_branding(arena)


func observe(p1: PlayerState, p2: PlayerState, match_active: bool, match_over: bool) -> void:
	if _last_p1_hp < 0:
		_last_p1_hp = p1.hp
		_last_p2_hp = p2.hp
	if match_active and not _round_started:
		_round_started = true
		play_slot("round_start")
		play_slot("bgm")
	if match_active:
		_observe_attack(p1, true)
		_observe_attack(p2, false)
		_observe_dodge(p1, true)
		_observe_dodge(p2, false)
		_observe_damage(p1, p2, true)
		_observe_damage(p2, p1, false)
	if match_over and not _round_ended:
		_round_ended = true
		play_slot("ko")
		play_slot("round_end")
	_last_p1_state = p1.state
	_last_p2_state = p2.state
	_last_p1_hp = p1.hp
	_last_p2_hp = p2.hp


func play_slot(slot_id: String) -> bool:
	var path := str(_audio_slots.get(slot_id, ""))
	var stream: AudioStream = AudioImporterScript.new().load_stream(path)
	if stream == null:
		return false
	if slot_id == "bgm":
		_bgm_player.stream = stream
		_bgm_player.play()
	else:
		_sfx_player.stream = stream
		_sfx_player.play()
	return true


func _observe_attack(state: PlayerState, is_p1: bool) -> void:
	var last_id := _last_p1_attack_id if is_p1 else _last_p2_attack_id
	if state.attack_id > last_id and state.attack_kind != PlayerState.AttackKind.NONE:
		play_slot("heavy_swing" if state.attack_kind == PlayerState.AttackKind.HEAVY else "jab_swing")
		if is_p1:
			_last_p1_attack_id = state.attack_id
		else:
			_last_p2_attack_id = state.attack_id


func _observe_dodge(state: PlayerState, is_p1: bool) -> void:
	var previous := _last_p1_state if is_p1 else _last_p2_state
	if state.state == PlayerState.MoveState.DODGE and previous != PlayerState.MoveState.DODGE:
		play_slot("dodge")


func _observe_damage(defender: PlayerState, attacker: PlayerState, is_p1: bool) -> void:
	var previous_hp := _last_p1_hp if is_p1 else _last_p2_hp
	if defender.hp >= previous_hp:
		return
	if defender.blocking or defender.state == PlayerState.MoveState.BLOCK:
		play_slot("block")
	else:
		play_slot("hit_heavy" if attacker.attack_kind == PlayerState.AttackKind.HEAVY else "hit_light")


func _create_background(arena: Node) -> void:
	var texture: Texture2D = AssetImporterScript.new().load_texture(str(_config.get("background_image", "")))
	if texture == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "ProjectBackgroundLayer"
	layer.layer = -100
	arena.add_child(layer)
	var image := TextureRect.new()
	image.name = "ProjectBackground"
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(image)


func _create_branding(arena: Node) -> void:
	if not bool(_config.get("project", false)):
		return
	var layer := CanvasLayer.new()
	layer.name = "ProjectBrandingLayer"
	layer.layer = 5
	arena.add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.position = Vector2(-230.0, 8.0)
	margin.size = Vector2(220.0, 70.0)
	layer.add_child(margin)
	var texture: Texture2D = AssetImporterScript.new().load_texture(str(_config.get("logo_image", "")))
	if texture != null:
		var logo := TextureRect.new()
		logo.texture = texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		margin.add_child(logo)
	else:
		var title := Label.new()
		title.text = str(_config.get("display_name", ""))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		margin.add_child(title)
