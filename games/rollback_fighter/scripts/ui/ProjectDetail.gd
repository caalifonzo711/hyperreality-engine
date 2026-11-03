extends Control

const MY_GAMES_PATH := "res://games/rollback_fighter/scenes/MyGames.tscn"
const CREATOR_PATH := "res://games/rollback_fighter/scenes/CreatorWizard.tscn"
const PRESENTATION_PATH := "res://games/rollback_fighter/scenes/CreateGameWizard.tscn"
const CHARACTER_SELECT_PATH := "res://games/rollback_fighter/scenes/CharacterSelect.tscn"
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")
const BuilderScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectBuilder.gd")

var _content: VBoxContainer
var _status: Label
var _project_id := ""
var _host_port: SpinBox

func _ready() -> void:
	var context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if context == null or not bool(context.call("has_project")):
		get_tree().change_scene_to_file(MY_GAMES_PATH)
		return
	_project_id = str(context.call("get_project_id"))
	context.call("open_project", _project_id)
	_build_shell()
	_refresh()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 32.0, 300.0, 700.0)
	_content.add_theme_constant_override("separation", 10)
	center.add_child(_content)

func _refresh() -> void:
	for child in _content.get_children():
		child.queue_free()
	var readiness := ReadinessScript.new().evaluate(_project_id)
	var project: RollbackFighterGameProjectDefinition = readiness.get("project")
	if project == null:
		_add_label("INVALID PROJECT", 26)
		_add_label("Project definition could not be loaded.")
		_add_back_button()
		return
	_add_label(project.display_name, 28)
	_add_label("Project ID: %s" % project.project_id)
	_add_label("Style: %s" % project.style_preset.replace("_", " ").capitalize())
	_add_label("Version: %d" % project.version)
	_add_label("Roster (%d): %s" % [project.fighter_ids.size(), ", ".join(PackedStringArray(project.fighter_ids))])
	var presentation = readiness.get("presentation")
	if presentation != null:
		_add_label("Background: %s" % ("Custom" if not presentation.background_image.is_empty() else "Built-in default"))
		_add_label("Branding: %s" % ("Logo" if not presentation.logo_image.is_empty() else "Text title"))
		_add_label("Audio overrides: %d" % presentation.audio_slots.size())
	_add_label("Build status: %s" % str(readiness.get("status", "invalid")).replace("_", " ").to_upper(), 20)
	for message in readiness.get("messages", []):
		_add_label(str(message))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_status)
	var add_fighter := _button("Add Fighter")
	add_fighter.pressed.connect(_on_add_fighter)
	_content.add_child(add_fighter)
	var edit_presentation := _button("Edit Presentation")
	edit_presentation.pressed.connect(_on_edit_presentation)
	_content.add_child(edit_presentation)
	var build := _button("Build Game")
	build.disabled = not bool(readiness.get("can_build", false)) or str(readiness.get("status", "")) == "built"
	build.pressed.connect(_on_build)
	_content.add_child(build)
	var play := _button("Play / Test")
	play.disabled = not bool(readiness.get("can_play", false))
	play.pressed.connect(_on_play)
	_content.add_child(play)
	var host_label := Label.new()
	host_label.text = "Host port"
	_content.add_child(host_label)
	_host_port = SpinBox.new()
	_host_port.min_value = 1
	_host_port.max_value = 65535
	_host_port.value = 7777
	_content.add_child(_host_port)
	var host_project := _button("Host Project")
	host_project.disabled = not bool(readiness.get("can_play", false))
	host_project.pressed.connect(_on_host_project)
	_content.add_child(host_project)
	_add_back_button()

func _on_add_fighter() -> void:
	var creator: Node = get_node_or_null("/root/CreatorLaunchContext")
	if creator == null or not bool(creator.call("launch_for_project", _project_id)):
		_status.text = "Could not open the fighter creator."
		return
	get_tree().change_scene_to_file(CREATOR_PATH)

func _on_edit_presentation() -> void:
	var creator: Node = get_node_or_null("/root/CreatorLaunchContext")
	if creator == null or not bool(creator.call("launch_for_project", _project_id)):
		_status.text = "Could not open project presentation."
		return
	get_tree().change_scene_to_file(PRESENTATION_PATH)

func _on_build() -> void:
	var result := BuilderScript.new().build(_project_id)
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("errors", ["Build failed."])[0])
		return
	_refresh()

func _on_play() -> void:
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	var creator_context: Node = get_node_or_null("/root/CreatorLaunchContext")
	var launch: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if project_context == null or creator_context == null or launch == null:
		_status.text = "Project launch services are unavailable."
		return
	if not bool(project_context.call("begin_local", _project_id)) or not bool(creator_context.call("launch_for_project", _project_id)):
		_status.text = "Build this project before playing."
		return
	launch.call("set_single_player")
	get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)

func _on_host_project() -> void:
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	var creator_context: Node = get_node_or_null("/root/CreatorLaunchContext")
	var launch: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if project_context == null or creator_context == null or launch == null:
		_status.text = "Project launch services are unavailable."
		return
	if not bool(project_context.call("begin_network", _project_id, true)):
		_status.text = "Project changed — rebuild before hosting."
		return
	if not bool(creator_context.call("launch_for_project", _project_id)):
		_status.text = "Could not load project context."
		return
	if not bool(launch.call("set_host", int(_host_port.value))):
		_status.text = "Choose a valid host port."
		return
	get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)

func _add_back_button() -> void:
	var back := _button("Back")
	back.pressed.connect(_on_back)
	_content.add_child(back)

func _on_back() -> void:
	get_tree().change_scene_to_file(MY_GAMES_PATH)

func _add_label(text: String, size: int = 0) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	_content.add_child(label)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button
