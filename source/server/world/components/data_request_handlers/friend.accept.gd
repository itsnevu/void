extends DataRequestHandler
## Accept a pending friend request. [param player_id] is the REQUESTER. We require
## a real pending request from them (you can't accept one that was never sent),
## then make the friendship mutual on BOTH sides and clear the request.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var requester_id: int = int(args.get("player_id", 0))
	if requester_id <= 0 or requester_id == from_player.player_id:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	if from_player.friends.has(requester_id):
		# Already friends - just clean up any stale request and succeed.
		store.remove_friend_request(requester_id, from_player.player_id)
		return {"error": 0, "ok": true, "msg": "Already friend."}

	# Must be a genuine pending request addressed to us.
	if not store.has_friend_request(requester_id, from_player.player_id):
		return {"error": 1, "ok": false, "msg": "No pending request."}

	FriendService.make_friends(world_server, from_player, requester_id)
	store.remove_friend_request(requester_id, from_player.player_id)
	store.remove_friend_request(from_player.player_id, requester_id)

	# Let the requester know so their list refreshes live.
	FriendService.notify(world_server, requester_id, "friend.accepted", from_player)

	return {"error": 0, "ok": true, "msg": "Friend added."}
