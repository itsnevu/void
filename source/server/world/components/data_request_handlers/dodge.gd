extends DataRequestHandler
## Client -> server: the player dodge-rolled (Space). The dash itself is client-side
## (position is client-authoritative); the server's job is to spend the stamina and
## grant the brief i-frame window that makes a roll actually dodge attacks.

## Must match LocalPlayer.DODGE_STAMINA - the client predicts the same gate.
const DODGE_STAMINA: int = 25
## How long incoming damage is ignored after a roll (ms). Slightly longer than the
## dash so a well-timed roll cleanly avoids a hit.
const INVULN_MS: int = 300


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if not RateLimiter.check(peer_id, &"dodge", 6, 1_000):
		return {}
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead:
		return {}
	var energy: float = player.stats_component.get_stat(Stat.ENERGY)
	if energy < float(DODGE_STAMINA):
		return {}  # not enough stamina - no roll
	player.stats_component.set_stat(Stat.ENERGY, maxf(0.0, energy - DODGE_STAMINA))
	player.dodge_invuln_until_ms = Time.get_ticks_msec() + INVULN_MS
	return {}
