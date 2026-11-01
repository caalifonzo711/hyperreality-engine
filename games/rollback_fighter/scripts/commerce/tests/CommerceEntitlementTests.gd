extends SceneTree

const CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const TEST_PRODUCT_ID := "skin.example_fighter_alt.001"
const TEST_CONTENT_ID := "example_fighter_alt"
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)
const EntitlementServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/EntitlementService.gd"
)
const CharacterSelectScript = preload(
	"res://games/rollback_fighter/scripts/ui/CharacterSelect.gd"
)


func _initialize() -> void:
	var catalog = ProductCatalogScript.new()
	assert(catalog.load_catalog(CATALOG_PATH))
	var product = catalog.get_product(TEST_PRODUCT_ID)
	assert(product != null)
	assert(product.product_id == TEST_PRODUCT_ID)
	assert(product.display_name == "Example Fighter Alt Skin")
	assert(product.product_type == "skin")
	assert(product.content_id == TEST_CONTENT_ID)
	assert(product.display_price == "$1.00")
	assert(catalog.get_product("unknown.product") == null)

	var entitlements = EntitlementServiceScript.new()
	assert(not entitlements.has_entitlement(TEST_PRODUCT_ID))
	assert(entitlements.grant_entitlement(TEST_PRODUCT_ID))
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))
	assert(entitlements.grant_entitlement(TEST_PRODUCT_ID))
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))
	assert(entitlements.revoke_entitlement(TEST_PRODUCT_ID))
	assert(not entitlements.has_entitlement(TEST_PRODUCT_ID))

	var character_select: Control = CharacterSelectScript.new()
	character_select._catalog = catalog
	character_select._entitlement_service = entitlements
	assert(character_select._is_fighter_selectable("example_fighter"))
	assert(not character_select._is_fighter_selectable(TEST_CONTENT_ID))
	assert(not character_select._can_apply_fighter_selection("example_fighter", TEST_CONTENT_ID))
	entitlements.grant_entitlement(TEST_PRODUCT_ID)
	assert(character_select._is_fighter_selectable(TEST_CONTENT_ID))
	assert(character_select._can_apply_fighter_selection("example_fighter", TEST_CONTENT_ID))
	entitlements.revoke_entitlement(TEST_PRODUCT_ID)
	assert(not character_select._can_apply_fighter_selection(TEST_CONTENT_ID, "example_fighter"))

	character_select.free()
	entitlements.free()
	call_deferred("_run_character_select_ui_test")


func _run_character_select_ui_test() -> void:

	var launch_config: Node = root.get_node("NetworkLaunchConfig")
	var live_entitlements: Node = root.get_node("EntitlementService")
	launch_config.call("set_single_player")
	live_entitlements.call("revoke_entitlement", TEST_PRODUCT_ID)
	var character_select_ui: Control = CharacterSelectScript.new()
	root.add_child(character_select_ui)
	var locked_index: int = _find_selector_item(
		character_select_ui._p1_selector,
		TEST_CONTENT_ID
	)
	assert(locked_index >= 0)
	assert(character_select_ui._p1_selector.is_item_disabled(locked_index))
	var commerce_runtime: Node = root.get_node("CommerceRuntime")
	var live_commerce: Node = commerce_runtime.call("get_commerce_service")
	live_commerce.call("set_provider_test_mode", "failure")
	character_select_ui._on_buy_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(character_select_ui._p1_selector.is_item_disabled(locked_index))
	assert(character_select_ui._commerce_result_label.text == "Purchase failed.")
	live_commerce.call("set_provider_test_mode", "success")
	character_select_ui._on_buy_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(not character_select_ui._p1_selector.is_item_disabled(locked_index))
	assert(character_select_ui._store_product_label.text.contains("Owned: Yes"))
	assert(character_select_ui._transaction_label.text.contains("prototype-"))
	character_select_ui._on_buy_pressed()
	assert(character_select_ui._commerce_result_label.text == "Product already owned.")
	character_select_ui._on_revoke_entitlement_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(character_select_ui._p1_selector.is_item_disabled(locked_index))
	character_select_ui._redemption_input.text = "HYPER-ALT-001"
	character_select_ui._on_redeem_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(not character_select_ui._p1_selector.is_item_disabled(locked_index))
	assert(character_select_ui._commerce_result_label.text.begins_with("Redeemed successfully"))
	character_select_ui._on_redeem_pressed()
	assert(character_select_ui._commerce_result_label.text.begins_with("Code already redeemed"))
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(not character_select_ui._p1_selector.is_item_disabled(locked_index))
	character_select_ui._on_revoke_entitlement_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(character_select_ui._p1_selector.is_item_disabled(locked_index))
	character_select_ui._on_grant_entitlement_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(not character_select_ui._p1_selector.is_item_disabled(locked_index))
	character_select_ui._on_revoke_entitlement_pressed()
	locked_index = _find_selector_item(character_select_ui._p1_selector, TEST_CONTENT_ID)
	assert(character_select_ui._p1_selector.is_item_disabled(locked_index))
	character_select_ui.free()
	launch_config.call("clear")
	print("[CommerceEntitlementTests] PASS")
	quit(0)


func _find_selector_item(selector: OptionButton, fighter_id: String) -> int:
	for index: int in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == fighter_id:
			return index
	return -1
