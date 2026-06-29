extends DataRequestHandler
## Removes [param id] from the caller's friend list AND removes the caller from the
## target's list (friendship is symmetric). Also clears any leftover pending
## requests both ways. Idempotent: still "ok" if they weren't friends.


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

	var target_id: int = int(args.get("id", 0))
	if target_id <= 0:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	# Drop any pending requests between the two regardless of friend state.
	store.remove_friend_request(from_player.player_id, target_id)
	store.remove_friend_request(target_id, from_player.player_id)

	if not from_player.friends.has(target_id):
		return {"error": 0, "ok": true, "msg": "Not a friend."}

	FriendService.unfriend(world_server, from_player, target_id)
	return {"error": 0, "ok": true, "msg": "Removed friend."}
