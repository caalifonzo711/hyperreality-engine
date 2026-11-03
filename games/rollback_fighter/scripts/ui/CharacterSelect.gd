extends Control

const MAIN_MENU_SCENE_PATH := "res://games/rollback_fighter/scenes/MainMenu.tscn"
const FIGHTER_ARENA_SCENE_PATH := "res://games/rollback_fighter/scenes/FighterArena.tscn"
const PROJECT_DETAIL_SCENE_PATH := "res://games/rollback_fighter/scenes/ProjectDetail.tscn"
const CHARACTER_REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const TEST_PRODUCT_ID := "skin.example_fighter_alt.001"
const FighterProviderScript = preload(
	"res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd"
)

var _launch_config: Node
var _mode: String = ""
var _fighters: Dictionary = {}
var _fighter_ids: Array[String] = []
var _p1_selector: OptionButton
var _p2_selector: OptionButton
var _p1_stats: Label
var _p2_stats: Label
var _mode_label: Label
var _status_label: Label
var _start_button: Button
var _entitlement_status_label: Label
var _grant_entitlement_button: Button
var _revoke_entitlement_button: Button
var _redemption_input: LineEdit
var _store_product_label: Label
var _store_provider_label: Label
var _provider_mode_selector: OptionButton
var _commerce_result_label: Label
var _transaction_label: Label
var _catalog
var _commerce_runtime: Node
var _entitlement_service: Node
var _redemption_service: Node
var _commerce_service: Node
var _leaving: bool = false


func _ready() -> void:
	_build_ui()
	_launch_config = get_node_or_null("/root/NetworkLaunchConfig")
	if _launch_config == null:
		_set_error("Match launch settings are unavailable.")
		return
	_commerce_runtime = get_node_or_null("/root/CommerceRuntime")
	if _commerce_runtime == null or not bool(_commerce_runtime.call("is_initialized")):
		_set_error("Commerce runtime is unavailable.")
		return
	_catalog = _commerce_runtime.call("get_catalog")
	_entitlement_service = _commerce_runtime.call("get_entitlement_service")
	_redemption_service = _commerce_runtime.call("get_redemption_service")
	_commerce_service = _commerce_runtime.call("get_commerce_service")
	if (
		_catalog == null
		or _entitlement_service == null
		or _redemption_service == null
		or _commerce_service == null
	):
		_set_error("Commerce services are unavailable.")
		return
	var launch: Dictionary = _launch_config.call("get_pending_launch")
	_mode = str(launch.get("mode", ""))
	if _mode not in ["single_player", "host", "client"]:
		_set_error("Return to the Main Menu and choose a match mode.")
		return
	if not _load_registered_fighters():
		return
	_populate_selectors(launch)
	_refresh_selection_details()
	_refresh_entitlement_debug_status()
	_refresh_store_debug_status()
	if _mode == "client":
		_mode_label.text = "Join Match — the host selects both fighters."
		_p1_selector.disabled = true
		_p2_selector.disabled = true
		_start_button.text = "Join Match"
	else:
		_mode_label.text = "Single Player" if _mode == "single_player" else "Host Multiplayer"
		_start_button.text = "Start Match"
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null and bool(project_context.call("is_project_match")):
		var project_launch: Dictionary = project_context.call("get_context")
		_mode_label.text = "%s — %s" % [str(project_launch.get("display_name", "Custom Game")), _mode.replace("_", " ").capitalize()]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(
		clampf(get_viewport_rect().size.x - 36.0, 240.0, 560.0), 0.0
	)
	panel.add_theme_constant_override("separation", 12)
	center.add_child(panel)
	var title: Label = Label.new()
	title.text = "CHARACTER SELECT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)
	_mode_label = Label.new()
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_mode_label)
	panel.add_child(_make_heading("P1 Fighter"))
	_p1_selector = _make_selector()
	_p1_selector.item_selected.connect(_on_selection_changed)
	panel.add_child(_p1_selector)
	_p1_stats = _make_stats_label()
	panel.add_child(_p1_stats)
	panel.add_child(_make_heading("P2 / CPU Fighter"))
	_p2_selector = _make_selector()
	_p2_selector.item_selected.connect(_on_selection_changed)
	panel.add_child(_p2_selector)
	_p2_stats = _make_stats_label()
	panel.add_child(_p2_stats)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_status_label)
	if OS.is_debug_build():
		_build_entitlement_debug_controls(panel)
	_start_button = _make_button("Start Match")
	_start_button.pressed.connect(_on_start_pressed)
	panel.add_child(_start_button)
	var back_button: Button = _make_button("Back")
	back_button.pressed.connect(_on_back_pressed)
	panel.add_child(back_button)


func _make_heading(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 19)
	return label


func _make_selector() -> OptionButton:
	var selector: OptionButton = OptionButton.new()
	selector.custom_minimum_size.y = 54.0
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return selector


func _make_stats_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 56.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _build_entitlement_debug_controls(panel: VBoxContainer) -> void:
	panel.add_child(_make_heading("Commerce Prototype"))
	panel.add_child(_make_heading("Product"))
	_store_product_label = Label.new()
	_store_product_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_store_product_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_store_product_label)
	panel.add_child(_make_heading("Provider"))
	_store_provider_label = Label.new()
	_store_provider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_store_provider_label)
	_provider_mode_selector = _make_selector()
	for mode: String in ["success", "cancelled", "failure", "unavailable"]:
		_provider_mode_selector.add_item(mode.capitalize())
		_provider_mode_selector.set_item_metadata(
			_provider_mode_selector.item_count - 1, mode
		)
	_provider_mode_selector.item_selected.connect(_on_provider_mode_selected)
	panel.add_child(_provider_mode_selector)
	var buy_button: Button = _make_button("Buy Test Skin")
	buy_button.pressed.connect(_on_buy_pressed)
	panel.add_child(buy_button)
	panel.add_child(_make_heading("Redemption"))
	_redemption_input = LineEdit.new()
	_redemption_input.placeholder_text = "HYPER-ALT-001 or redemption URI"
	_redemption_input.clear_button_enabled = true
	_redemption_input.custom_minimum_size.y = 48.0
	panel.add_child(_redemption_input)
	var redeem_button: Button = _make_button("Redeem Code")
	redeem_button.pressed.connect(_on_redeem_pressed)
	panel.add_child(redeem_button)
	panel.add_child(_make_heading("Entitlement Debug"))
	_entitlement_status_label = Label.new()
	_entitlement_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_entitlement_status_label)
	var controls: HBoxContainer = HBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(controls)
	_grant_entitlement_button = _make_button("Grant Test Skin")
	_grant_entitlement_button.pressed.connect(_on_grant_entitlement_pressed)
	controls.add_child(_grant_entitlement_button)
	_revoke_entitlement_button = _make_button("Revoke Test Skin")
	_revoke_entitlement_button.pressed.connect(_on_revoke_entitlement_pressed)
	controls.add_child(_revoke_entitlement_button)
	panel.add_child(_make_heading("Latest Result"))
	_commerce_result_label = Label.new()
	_commerce_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commerce_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_commerce_result_label)
	_transaction_label = Label.new()
	_transaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_transaction_label)


func _load_registered_fighters() -> bool:
	var provider: RollbackFighterImportedFighterProvider = FighterProviderScript.new()
	_fighter_ids.clear()
	_fighters.clear()
	var entries: Array[Dictionary] = []
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null and bool(project_context.call("is_project_match")):
		var project_ids: Array[String] = project_context.call("get_fighter_ids")
		entries = provider.list_fighters_for_ids(project_ids)
	else:
		entries = provider.list_fighters()
	for fighter_entry: Dictionary in entries:
		var fighter_id: String = str(fighter_entry.get("id", ""))
		var definition_value: Variant = fighter_entry.get("definition")
		if fighter_id.is_empty() or not definition_value is RollbackFighterCharacterDefinition:
			continue
		_fighter_ids.append(fighter_id)
		_fighters[fighter_id] = definition_value
	if _fighter_ids.is_empty():
		_set_error("No registered fighters are available.")
		return false
	return true


func _populate_selectors(launch: Dictionary) -> void:
	_p1_selector.clear()
	_p2_selector.clear()
	for fighter_id: String in _fighter_ids:
		var definition: RollbackFighterCharacterDefinition = _fighters[fighter_id]
		var available: bool = _is_fighter_selectable(fighter_id)
		var label: String = definition.get_display_name()
		if not available:
			label += " (Locked)"
		_p1_selector.add_item(label)
		_p1_selector.set_item_metadata(
			_p1_selector.item_count - 1, fighter_id
		)
		_p1_selector.set_item_disabled(_p1_selector.item_count - 1, not available)
		_p2_selector.add_item(label)
		_p2_selector.set_item_metadata(
			_p2_selector.item_count - 1, fighter_id
		)
		_p2_selector.set_item_disabled(_p2_selector.item_count - 1, not available)
	_select_id(_p1_selector, str(launch.get("p1_fighter_id", "example_fighter")))
	_select_id(_p2_selector, str(launch.get("p2_fighter_id", "example_fighter_alt")))


func _select_id(selector: OptionButton, fighter_id: String) -> void:
	for index: int in range(selector.item_count):
		if (
			str(selector.get_item_metadata(index)) == fighter_id
			and _is_fighter_selectable(fighter_id)
		):
			selector.select(index)
			return
	for index: int in range(selector.item_count):
		if _is_fighter_selectable(str(selector.get_item_metadata(index))):
			selector.select(index)
			return


func _selected_id(selector: OptionButton) -> String:
	if selector.item_count <= 0 or selector.selected < 0:
		return ""
	return str(selector.get_item_metadata(selector.selected))


func _on_selection_changed(_index: int) -> void:
	_refresh_selection_details()


func _refresh_selection_details() -> void:
	if _p1_selector == null or _p2_selector == null:
		return
	_p1_stats.text = _format_stats(_selected_id(_p1_selector))
	_p2_stats.text = _format_stats(_selected_id(_p2_selector))


func _format_stats(fighter_id: String) -> String:
	if not _fighters.has(fighter_id):
		return ""
	var definition: RollbackFighterCharacterDefinition = _fighters[fighter_id]
	return "HP %d   Speed %d   Jab %d   Heavy %d" % [
		definition.get_int("max_hp"),
		definition.get_int("move_speed"),
		definition.get_move_for_slot("light").get_int("damage"),
		definition.get_move_for_slot("heavy").get_int("damage"),
	]


func _is_fighter_selectable(fighter_id: String) -> bool:
	if _catalog == null:
		return false
	var product = _catalog.get_product_for_content(fighter_id)
	if product == null:
		return true
	return (
		_entitlement_service != null
		and bool(_entitlement_service.call("has_entitlement", product.product_id))
	)


func _can_apply_fighter_selection(p1_id: String, p2_id: String) -> bool:
	return _is_fighter_selectable(p1_id) and _is_fighter_selectable(p2_id)


func _on_start_pressed() -> void:
	if _launch_config == null:
		_set_error("Match launch settings are unavailable.")
		return
	var p1_id: String = _selected_id(_p1_selector)
	var p2_id: String = _selected_id(_p2_selector)
	if not _can_apply_fighter_selection(p1_id, p2_id):
		_status_label.text = "Unlock the selected content before starting the match."
		return
	if not bool(_launch_config.call("set_fighter_selection", p1_id, p2_id)):
		_set_error("Select two valid registered fighters.")
		return
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null and bool(project_context.call("is_project_match")):
		if not bool(project_context.call("set_fighter_selection", p1_id, p2_id)):
			_set_error("Selected fighters are outside this project's roster.")
			return
	var error: Error = get_tree().change_scene_to_file(FIGHTER_ARENA_SCENE_PATH)
	if error != OK:
		_set_error("Could not open FighterArena.")


func _on_grant_entitlement_pressed() -> void:
	if _entitlement_service == null:
		return
	_entitlement_service.call("grant_entitlement", TEST_PRODUCT_ID)
	_refresh_after_entitlement_change()


func _on_revoke_entitlement_pressed() -> void:
	if _entitlement_service == null:
		return
	_entitlement_service.call("revoke_entitlement", TEST_PRODUCT_ID)
	_refresh_after_entitlement_change()


func _on_redeem_pressed() -> void:
	if _redemption_service == null:
		return
	var result: Dictionary = _redemption_service.call("redeem", _redemption_input.text)
	_commerce_result_label.text = _format_redemption_result(result)
	_transaction_label.text = ""
	if bool(result.get("success", false)):
		_refresh_after_entitlement_change()


func _format_redemption_result(result: Dictionary) -> String:
	var status: String = str(result.get("status", ""))
	var product_id: String = str(result.get("product_id", ""))
	match status:
		"SUCCESS":
			return "Redeemed successfully: %s" % product_id
		"ALREADY_REDEEMED":
			return "Code already redeemed: %s" % product_id
		"EMPTY_CODE":
			return "Enter a redemption code."
		"INVALID_CODE":
			return "Invalid redemption code."
		"UNKNOWN_PRODUCT":
			return "Redemption product is unavailable."
		"ENTITLEMENT_GRANT_FAILED":
			return "Could not grant the entitlement."
		_:
			return "Redemption failed."


func _on_provider_mode_selected(index: int) -> void:
	if _commerce_service == null:
		return
	var mode: String = str(_provider_mode_selector.get_item_metadata(index))
	_commerce_service.call("set_provider_test_mode", mode)


func _on_buy_pressed() -> void:
	if _commerce_service == null:
		return
	var result: Dictionary = _commerce_service.call("purchase", TEST_PRODUCT_ID)
	_commerce_result_label.text = _format_purchase_result(result)
	var transaction_id: String = str(result.get("transaction_id", ""))
	_transaction_label.text = (
		"Transaction: %s" % transaction_id if not transaction_id.is_empty() else ""
	)
	if bool(result.get("success", false)):
		_refresh_after_entitlement_change()


func _format_purchase_result(result: Dictionary) -> String:
	var status: String = str(result.get("status", ""))
	match status:
		"SUCCESS":
			return "Purchase successful."
		"PRODUCT_NOT_FOUND":
			return "Product not found."
		"PURCHASE_CANCELLED":
			return "Purchase cancelled."
		"PURCHASE_FAILED":
			return "Purchase failed."
		"ALREADY_OWNED":
			return "Product already owned."
		"PROVIDER_UNAVAILABLE":
			return "Provider unavailable."
		_:
			return "Purchase failed."


func _refresh_after_entitlement_change() -> void:
	var p1_id: String = _selected_id(_p1_selector)
	var p2_id: String = _selected_id(_p2_selector)
	_populate_selectors({"p1_fighter_id": p1_id, "p2_fighter_id": p2_id})
	_refresh_selection_details()
	_refresh_entitlement_debug_status()
	_refresh_store_debug_status()


func _refresh_entitlement_debug_status() -> void:
	if _entitlement_status_label == null:
		return
	var owned: bool = (
		_entitlement_service != null
		and bool(_entitlement_service.call("has_entitlement", TEST_PRODUCT_ID))
	)
	_entitlement_status_label.text = "Test skin owned: %s" % ("Yes" if owned else "No")
	_grant_entitlement_button.disabled = owned
	_revoke_entitlement_button.disabled = not owned


func _refresh_store_debug_status() -> void:
	if _store_product_label == null:
		return
	var product = _catalog.get_product(TEST_PRODUCT_ID) if _catalog != null else null
	var owned: bool = (
		_entitlement_service != null
		and bool(_entitlement_service.call("has_entitlement", TEST_PRODUCT_ID))
	)
	if product == null:
		_store_product_label.text = "Test product unavailable"
	else:
		_store_product_label.text = "%s\n%s\n%s\nOwned: %s" % [
			product.display_name,
			product.product_id,
			product.display_price,
			"Yes" if owned else "No",
		]
	_store_provider_label.text = "Provider: %s" % str(
		_commerce_service.call("get_provider_id") if _commerce_service != null else ""
	)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	if _launch_config != null:
		_launch_config.call("clear")
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	var target := PROJECT_DETAIL_SCENE_PATH if project_context != null and bool(project_context.call("is_project_match")) else MAIN_MENU_SCENE_PATH
	get_tree().change_scene_to_file(target)


func _set_error(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	if _start_button != null:
		_start_button.disabled = true
	push_warning("[CharacterSelect] %s" % message)
