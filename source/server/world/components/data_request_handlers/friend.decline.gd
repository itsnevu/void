extends DataRequestHandler
## Decline (or cancel receiving) a pending friend request. [param player_id] is the
## REQUESTER whose request to us we're dropping. Idempotent.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "msg": "Not connected."}

	var requester_id: int = int(args.get("player_id", 0))
	if requester_id <= 0:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	store.remove_friend_request(requester_id, from_player.player_id)
	return {"error": 0, "ok": true, "msg": "Request declined."}
