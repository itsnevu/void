extends DataRequestHandler
## Lists the caller's pending friend requests so the Friends menu can show an
## "Incoming" section (Accept / Decline) even for requests that arrived while the
## player was offline. Also returns outgoing ids so the UI can mark "Requested".
## Shape: {incoming: {id: {name, online}}, outgoing: [id, ...]}.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false}

	var incoming: Dictionary = {}
	for requester_id: int in store.list_incoming_requests(from_player.player_id):
		var name: String = store.get_player_display_name(requester_id)
		if name.is_empty():
			continue
		incoming[requester_id] = {
			"name": name,
			"online": int(world_server.player_id_to_peer_id.get(requester_id, 0)) > 0,
		}

	return {
		"error": 0,
		"ok": true,
		"incoming": incoming,
		"outgoing": Array(store.list_outgoing_requests(from_player.player_id)),
	}
