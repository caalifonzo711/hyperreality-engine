extends SceneTree


func _initialize() -> void:
	call_deferred("_run_runtime_test")


func _run_runtime_test() -> void:
	var runtime: Node = root.get_node("CommerceRuntime")
	assert(bool(runtime.call("is_initialized")))
	var catalog = runtime.call("get_catalog")
	var entitlements: Node = runtime.call("get_entitlement_service")
	var redemption: Node = runtime.call("get_redemption_service")
	var commerce: Node = runtime.call("get_commerce_service")
	var provider = runtime.call("get_provider")
	assert(catalog != null)
	assert(catalog.get_product("skin.example_fighter_alt.001") != null)
	assert(entitlements == root.get_node("EntitlementService"))
	assert(redemption._catalog == catalog)
	assert(commerce._catalog == catalog)
	assert(redemption._entitlement_service == entitlements)
	assert(commerce._entitlement_service == entitlements)
	assert(commerce._provider == provider)
	print("[CommerceRuntimeTests] PASS")
	quit(0)
