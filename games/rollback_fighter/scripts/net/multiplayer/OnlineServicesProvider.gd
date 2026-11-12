extends RefCounted
class_name RollbackFighterOnlineServicesProvider

# Online services are deliberately separate from connection transports/providers.
const AUTHENTICATION := "authentication"
const LOBBIES := "lobbies"
const MATCHMAKING := "matchmaking"
const LEADERBOARDS := "leaderboards"
const PERSISTENCE := "persistence"
const SERVER_ALLOCATION := "server_allocation"

const CUSTOM_ONLINE_SERVICES := "custom_online_services"
const NAKAMA_ONLINE_SERVICES := "nakama_online_services"
const STEAM_ONLINE_SERVICES := "steam_online_services"
const HYPERWORLD_ONLINE_SERVICES := "hyperworld_online_services"


func get_provider_id() -> String:
	return ""


func get_capabilities() -> Array[String]:
	return []


func supports(capability: String) -> bool:
	return capability in get_capabilities()
