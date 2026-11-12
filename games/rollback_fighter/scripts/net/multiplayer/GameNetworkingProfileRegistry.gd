extends RefCounted
class_name RollbackFighterGameNetworkingProfileRegistry

const Profile = preload("res://games/rollback_fighter/scripts/net/multiplayer/GameNetworkingProfile.gd")

var _profiles: Dictionary = {}


static func create_default() -> RollbackFighterGameNetworkingProfileRegistry:
	var registry := RollbackFighterGameNetworkingProfileRegistry.new()
	registry.register_profile(Profile.ocean_fight())
	return registry


func register_profile(profile: RollbackFighterGameNetworkingProfile) -> bool:
	if profile == null or not profile.validate().is_empty() or _profiles.has(profile.game_id):
		return false
	_profiles[profile.game_id] = profile
	return true


func get_profile(game_id: String) -> RollbackFighterGameNetworkingProfile:
	return _profiles.get(game_id)
