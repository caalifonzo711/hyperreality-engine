extends Control

const MAIN_MENU_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const DETAIL_PATH := "res://games/rollback_fighter/scenes/ProjectDetail.tscn"
const ProviderScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectProvider.gd")

var _status: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 32.0, 300.0, 720.0)
	list.add_theme_constant_override("separation", 12)
	center.add_child(list)
	var title := Label.new()
	title.text = "MY GAMES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	list.add_child(title)
	var projects := ProviderScript.new().list_projects()
	if projects.is_empty():
		var empty := Label.new()
		empty.text = "No valid projects found. Use Create Game to start one."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	for entry in projects:
		list.add_child(_project_card(entry))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(_status)
	var back := _button("Back")
	back.pressed.connect(_on_back_pressed)
	list.add_child(back)

func _project_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var project: RollbackFighterGameProjectDefinition = entry["project"]
	var readiness: Dictionary = entry["readiness"]
	var name := Label.new()
	name.text = project.display_name
	name.add_theme_font_size_override("font_size", 21)
	content.add_child(name)
	var metadata := Label.new()
	metadata.text = "%s  •  %s  •  v%d  •  %d fighters" % [project.project_id, project.style_preset.replace("_", " ").capitalize(), project.version, project.fighter_ids.size()]
	metadata.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(metadata)
	var status := Label.new()
	status.text = "Project: %s  •  Build: %s" % [project.status.to_upper(), str(readiness.get("status", "invalid")).replace("_", " ").to_upper()]
	content.add_child(status)
	var open := _button("Open")
	open.pressed.connect(_open_project.bind(project.project_id))
	content.add_child(open)
	return panel

func _open_project(project_id: String) -> void:
	var context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if context == null or not bool(context.call("open_project", project_id)):
		_status.text = "Could not open this project."
		return
	get_tree().change_scene_to_file(DETAIL_PATH)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button
