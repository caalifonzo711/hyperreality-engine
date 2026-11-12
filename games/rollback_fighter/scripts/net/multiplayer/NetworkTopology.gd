extends RefCounted
class_name RollbackFighterNetworkTopology

const P2P := "P2P"
const P2P_MESH := "P2P_MESH"
const HOST_AUTHORITY := "HOST_AUTHORITY"
const RELAY := "RELAY"
const DEDICATED_SERVER := "DEDICATED_SERVER"

const ALL: Array[String] = [
	P2P,
	P2P_MESH,
	HOST_AUTHORITY,
	RELAY,
	DEDICATED_SERVER,
]


static func is_valid(topology_id: String) -> bool:
	return topology_id in ALL
