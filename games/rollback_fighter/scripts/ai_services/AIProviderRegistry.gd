extends RefCounted
class_name RollbackFighterAIProviderRegistry

var _providers: Dictionary = {}
var _selected_provider_id: String = ""


func register_provider(provider: Node) -> bool:
	if provider == null or not provider.has_method("get_provider_id") or not provider.has_method("get_capabilities"):
		return false
	var provider_id: String = str(provider.call("get_provider_id"))
	if not _is_safe_id(provider_id) or _providers.has(provider_id):
		return false
	_providers[provider_id] = provider
	if _selected_provider_id.is_empty():
		_selected_provider_id = provider_id
	return true


func select_provider(provider_id: String) -> bool:
	if not _providers.has(provider_id):
		return false
	_selected_provider_id = provider_id
	return true


func get_selected_provider():
	return _providers.get(_selected_provider_id)


func get_provider(provider_id: String):
	return _providers.get(provider_id)


func get_selected_provider_id() -> String:
	return _selected_provider_id


func list_provider_ids() -> Array[String]:
	var ids: Array[String] = []
	for value: Variant in _providers.keys():
		ids.append(str(value))
	ids.sort()
	return ids


func _is_safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true
