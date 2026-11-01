extends SceneTree

const CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const TEST_PRODUCT_ID := "skin.example_fighter_alt.001"
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)
const EntitlementServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/EntitlementService.gd"
)
const PrototypeProviderScript = preload(
	"res://games/rollback_fighter/scripts/commerce/PrototypeCommerceProvider.gd"
)
const CommerceServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/CommerceService.gd"
)


func _initialize() -> void:
	var catalog = ProductCatalogScript.new()
	assert(catalog.load_catalog(CATALOG_PATH))
	var entitlements = EntitlementServiceScript.new()
	var provider = PrototypeProviderScript.new()
	var commerce = CommerceServiceScript.new()
	commerce.configure(catalog, entitlements, provider)

	var unknown: Dictionary = commerce.purchase("unknown.product")
	assert(not unknown.success)
	assert(unknown.status == "PRODUCT_NOT_FOUND")
	assert(not entitlements.has_entitlement("unknown.product"))

	var direct_provider_result: Dictionary = provider.purchase(TEST_PRODUCT_ID)
	assert(direct_provider_result.success)
	assert(direct_provider_result.provider_id == "prototype")
	assert(str(direct_provider_result.transaction_id).begins_with("prototype-"))
	assert(not entitlements.has_entitlement(TEST_PRODUCT_ID))

	var success: Dictionary = commerce.purchase(TEST_PRODUCT_ID)
	assert(success.success)
	assert(success.status == "SUCCESS")
	assert(success.provider_id == "prototype")
	assert(str(success.transaction_id).begins_with("prototype-"))
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))
	assert(commerce.get_transaction_history().size() == 1)

	var already_owned: Dictionary = commerce.purchase(TEST_PRODUCT_ID)
	assert(not already_owned.success)
	assert(already_owned.status == "ALREADY_OWNED")
	assert(commerce.get_transaction_history().size() == 1)

	for outcome: Array in [
		["failure", "PURCHASE_FAILED"],
		["cancelled", "PURCHASE_CANCELLED"],
		["unavailable", "PROVIDER_UNAVAILABLE"],
	]:
		assert(entitlements.revoke_entitlement(TEST_PRODUCT_ID))
		assert(provider.set_mode(str(outcome[0])))
		var result: Dictionary = commerce.purchase(TEST_PRODUCT_ID)
		assert(not result.success)
		assert(result.status == str(outcome[1]))
		assert(result.provider_id == "prototype")
		assert(result.transaction_id == "")
		assert(not entitlements.has_entitlement(TEST_PRODUCT_ID))

	assert(provider.set_mode("success"))
	var second_success: Dictionary = commerce.purchase(TEST_PRODUCT_ID)
	assert(second_success.success)
	assert(second_success.transaction_id != success.transaction_id)
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))

	var restore_entitlements = EntitlementServiceScript.new()
	var restore_provider = PrototypeProviderScript.new()
	var restore_commerce = CommerceServiceScript.new()
	restore_commerce.configure(catalog, restore_entitlements, restore_provider)
	restore_provider.set_simulated_restore_results([
		restore_provider.make_result(
			false,
			"PURCHASE_FAILED",
			TEST_PRODUCT_ID,
			"prototype",
			"restore-failed-001"
		),
		restore_provider.make_result(
			false,
			"PURCHASE_CANCELLED",
			TEST_PRODUCT_ID,
			"prototype",
			"restore-cancelled-001"
		),
		restore_provider.make_result(
			true,
			"SUCCESS",
			"unknown.product",
			"prototype",
			"restore-unknown-001"
		),
	])
	var invalid_restore: Dictionary = restore_commerce.reconcile_purchases()
	assert(invalid_restore.success)
	assert(invalid_restore.restored_product_ids.is_empty())
	assert(invalid_restore.ignored_count == 3)
	assert(not restore_entitlements.has_entitlement(TEST_PRODUCT_ID))

	restore_provider.set_simulated_restore_results([
		restore_provider.make_result(
			true,
			"SUCCESS",
			TEST_PRODUCT_ID,
			"prototype",
			"restore-valid-001"
		),
	])
	var valid_restore: Dictionary = restore_commerce.reconcile_purchases()
	assert(valid_restore.success)
	assert(valid_restore.restored_product_ids == [TEST_PRODUCT_ID])
	assert(restore_entitlements.has_entitlement(TEST_PRODUCT_ID))
	var duplicate_restore: Dictionary = restore_commerce.reconcile_purchases()
	assert(duplicate_restore.success)
	assert(duplicate_restore.restored_product_ids.is_empty())
	assert(duplicate_restore.duplicate_count == 1)
	assert(restore_entitlements.has_entitlement(TEST_PRODUCT_ID))

	commerce.free()
	entitlements.free()
	restore_commerce.free()
	restore_entitlements.free()
	print("[CommerceServiceTests] PASS")
	quit(0)
