# N1 signaling service

The N1 service exchanges connection metadata only. It does not relay rollback,
gameplay, fighter, or project data.

Development launch (Godot 4.3):

```text
godot --headless --path . --script res://games/rollback_fighter/scripts/signaling/SignalingBackend.gd -- --bind=127.0.0.1 --port=8787 --udp-port=8788
```

For LAN/container deployment, set `--bind=0.0.0.0`, expose TCP port 8787,
and expose UDP port 8788.
Production deployments should terminate HTTPS in front of this service and set
the in-game signaling URL to that HTTPS origin.

Rooms expire after 10 minutes. Codes contain six characters from
`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Session and peer IDs are random opaque
tokens. Request bodies are capped at 4 KiB and only the fixed room identity and
ENet endpoint schema is accepted.

The server-observed remote address replaces the client-supplied endpoint
address. N1 performs no STUN, hole punching, or relay, so public-NAT peers may
still require Tailscale until N2.

Routes are `POST /rooms`, `POST /rooms/<code>/join`, authenticated
`GET /rooms/<code>`, `POST /rooms/<code>/peer`,
`POST /rooms/<code>/candidates`, and host-only
`DELETE /rooms/<code>`. The client sends only protocol/game identity and an
ENet UDP endpoint. Session and peer IDs travel in bounded headers for room
polling; gameplay/configuration still uses the existing ENet handshakes.

N2 uses UDP 8788 only to observe each room member's real UDP source endpoint.
The fixed-size registration datagram is authenticated with the opaque room
session, peer ID, and traversal token. Peers then exchange probes directly;
the signaling service never relays gameplay or peer-to-peer traversal packets.

The 86-byte traversal packet is: `HRNP` magic (4), version (1), type (1),
session (24), peer/probe ID (16), traversal token (32), and nonce (8). The
backend processes at most 64 UDP registration packets per frame. Clients probe
every 200 ms for at most 8 seconds and 128 total candidate packets, then report
`RELAY_REQUIRED` without entering gameplay.
