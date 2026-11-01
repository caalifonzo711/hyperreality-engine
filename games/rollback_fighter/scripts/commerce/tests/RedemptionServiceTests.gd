extends SceneTree

const CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const CODE_REGISTRY_PATH := (
	"res://games/rollback_fighter/config/development_redemption_codes.json"
)
const TEST_PRODUCT_ID := "skin.example_fighter_alt.001"
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)
const EntitlementServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/EntitlementService.gd"
)
const RedemptionServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/RedemptionService.gd"
)


class FailingEntitlementService:
	extends Node

	func grant_entitlement(_product_id: String) -> bool:
		return false


func _initialize() -> void:
	var catalog = ProductCatalogScript.new()
	assert(catalog.load_catalog(CATALOG_PATH))
	var entitlements = EntitlementServiceScript.new()
	var redemption = RedemptionServiceScript.new()
	redemption.configure(catalog, entitlements)
	assert(redemption.load_code_registry(CODE_REGISTRY_PATH))

	assert(redemption.normalize_input("  hyper-alt-001  ") == "HYPER-ALT-001")
	assert(
		redemption.normalize_input(
			"hyperreality://redeem?code=hyper-alt-002"
		) == "HYPER-ALT-002"
	)
	assert(redemption.redeem("   ").status == "EMPTY_CODE")
	assert(redemption.redeem("NOT-A-CODE").status == "INVALID_CODE")

	var raw_result: Dictionary = redemption.redeem("HYPER-ALT-001")
	assert(raw_result.success)
	assert(raw_result.status == "SUCCESS")
	assert(raw_result.product_id == TEST_PRODUCT_ID)
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))
	var repeated_result: Dictionary = redemption.redeem("hyper-alt-001")
	assert(not repeated_result.success)
	assert(repeated_result.status == "ALREADY_REDEEMED")

	var uri_result: Dictionary = redemption.redeem(
		"hyperreality://redeem?code=HYPER-ALT-002"
	)
	assert(uri_result.success)
	assert(uri_result.product_id == TEST_PRODUCT_ID)
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))

	var third_code_result: Dictionary = redemption.redeem("hyper-alt-003")
	assert(third_code_result.success)
	assert(entitlements.has_entitlement(TEST_PRODUCT_ID))
	var unknown_product_result: Dictionary = redemption.redeem("HYPER-UNKNOWN-001")
	assert(not unknown_product_result.success)
	assert(unknown_product_result.status == "UNKNOWN_PRODUCT")
	assert(not entitlements.has_entitlement("skin.prototype_missing.001"))

	var failing_entitlements: Node = FailingEntitlementService.new()
	var retryable_redemption = RedemptionServiceScript.new()
	retryable_redemption.configure(catalog, failing_entitlements)
	assert(retryable_redemption.load_code_registry(CODE_REGISTRY_PATH))
	var failed_grant: Dictionary = retryable_redemption.redeem("HYPER-ALT-001")
	assert(not failed_grant.success)
	assert(failed_grant.status == "ENTITLEMENT_GRANT_FAILED")
	var retry_entitlements = EntitlementServiceScript.new()
	retryable_redemption.configure(catalog, retry_entitlements)
	var retried_grant: Dictionary = retryable_redemption.redeem("HYPER-ALT-001")
	assert(retried_grant.success)
	assert(retry_entitlements.has_entitlement(TEST_PRODUCT_ID))

	redemption.free()
	entitlements.free()
	retryable_redemption.free()
	failing_entitlements.free()
	retry_entitlements.free()
	print("[RedemptionServiceTests] PASS")
	quit(0)
