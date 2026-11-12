extends RefCounted
class_name RollbackFighterConnectionMethodDefinition

const AVAILABLE := "AVAILABLE"
const EXPERIMENTAL := "EXPERIMENTAL"
const COMING_SOON := "COMING_SOON"

var id: String = ""
var display_name: String = ""
var description: String = ""
var availability: String = COMING_SOON
var experimental: bool = false
var connection_provider_id: String = ""
var recommended_topologies: Array[String] = []
var max_supported_players_hint: int = 0
var sort_order: int = 0


func configure(
	method_id: String,
	method_display_name: String,
	method_description: String,
	method_availability: String,
	provider_id: String,
	topologies: Array[String],
	max_players_hint: int,
	order: int
) -> RollbackFighterConnectionMethodDefinition:
	id = method_id
	display_name = method_display_name
	description = method_description
	availability = method_availability
	experimental = availability == EXPERIMENTAL
	connection_provider_id = provider_id
	recommended_topologies = topologies.duplicate()
	max_supported_players_hint = max_players_hint
	sort_order = order
	return self


func is_launchable() -> bool:
	return availability in [AVAILABLE, EXPERIMENTAL] and not connection_provider_id.is_empty()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("id is required")
	if display_name.is_empty():
		errors.append("display_name is required")
	if availability not in [AVAILABLE, EXPERIMENTAL, COMING_SOON]:
		errors.append("availability is invalid")
	if max_supported_players_hint < 2:
		errors.append("max_supported_players_hint must be at least 2")
	for topology_id: String in recommended_topologies:
		if not RollbackFighterNetworkTopology.is_valid(topology_id):
			errors.append("unknown topology: %s" % topology_id)
	return errors
