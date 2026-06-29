extends DataRequestHandler
## Send a friend request. This records a PENDING request the target must accept
## (friend.accept) - it does NOT make you friends yet. If the target already
## requested YOU, this auto-accepts into a mutual friendship. Block-aware and
## rate-limited. Friendship itself is written to both sides by FriendService.

const MAX_FRIENDS: int = 200


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

	if not RateLimiter.check(peer_id, &"friend.request", 10, 60_000):
		return {"error": 1, "ok": false, "msg": "Slow down."}

	var target_id: int = int(args.get("id", 0))
	if target_id <= 0 or target_id == from_player.player_id:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	if store.get_player_profile_row(target_id).is_empty():
		return {"error": 1, "ok": false, "name": "Unknown"}

	if from_player.friends.has(target_id):
		return {"error": 1, "ok": false, "msg": "Already friend."}

	if from_player.friends.size() >= MAX_FRIENDS:
		return {"error": 1, "ok": false, "msg": "Friend list full."}

	# If the target blocked us, silently report success so the block isn't
	# disclosed (blocks are meant to be a ghost - see BlockList). Check the live
	# cache (online target) AND the persisted row (offline target).
	if BlockList.is_blocked(target_id, from_player.player_id) \
			or store.get_blocked_ids(target_id).has(from_player.player_id):
		return {"error": 0, "ok": true, "msg": "Request sent."}

	# Mutual: they already requested us - turn it straight into a friendship.
	if store.has_friend_request(target_id, from_player.player_id):
		FriendService.make_friends(world_server, from_player, target_id)
		store.remove_friend_request(target_id, from_player.player_id)
		store.remove_friend_request(from_player.player_id, target_id)
		FriendService.notify(world_server, target_id, "friend.accepted", from_player)
		return {"error": 0, "ok": true, "msg": "Friend added."}

	if store.has_friend_request(from_player.player_id, target_id):
		return {"error": 0, "ok": true, "msg": "Request already sent."}

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	store.add_friend_request(from_player.player_id, target_id, now_ms)
	FriendService.notify(world_server, target_id, "friend.request", from_player)

	return {"error": 0, "ok": true, "msg": "Request sent."}
