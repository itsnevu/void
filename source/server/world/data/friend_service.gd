class_name FriendService
extends RefCounted
## Server-side helpers for the friend graph. Friendship is SYMMETRIC: every
## mutation writes BOTH sides - the caller's row and the other player's row,
## loading the other from the DB via WorldServer.get_player_for_write() when they
## are offline. Pending requests live in the friend_requests table (see
## WorldSchema._migration_v8 / WorldStoreSqlite). Handlers call into here so the
## request/accept/remove paths can't drift out of sync (the old bug was each
## handler editing only its own row).


## Make [param a] (a live caller PlayerResource) and [param b_id] mutual friends
## and persist both sides. No-op per side if already friends.
static func make_friends(world_server: WorldServer, a: PlayerResource, b_id: int) -> void:
	if not a.friends.has(b_id):
		a.friends.append(b_id)
		world_server.database.save_player(a)
	var b: PlayerResource = world_server.get_player_for_write(b_id)
	if b != null and not b.friends.has(a.player_id):
		b.friends.append(a.player_id)
		world_server.database.save_player(b)


## Remove the friendship from BOTH sides and persist. Safe if not friends.
static func unfriend(world_server: WorldServer, a: PlayerResource, b_id: int) -> void:
	a.friends = _without(a.friends, b_id)
	world_server.database.save_player(a)
	var b: PlayerResource = world_server.get_player_for_write(b_id)
	if b != null:
		b.friends = _without(b.friends, a.player_id)
		world_server.database.save_player(b)


## Push a {topic, player_name, player_id} notification to [param player_id] if
## they are currently online; no-op otherwise (they'll see it in the menu).
static func notify(world_server: WorldServer, player_id: int, topic: String, from_player: PlayerResource) -> void:
	var peer: int = int(world_server.player_id_to_peer_id.get(player_id, 0))
	if peer > 0:
		world_server.data_push.rpc_id(peer, &"notification", {
			"topic": topic,
			"player_name": from_player.display_name,
			"player_id": from_player.player_id,
		})


static func _without(arr: PackedInt64Array, value: int) -> PackedInt64Array:
	var out: PackedInt64Array = arr.duplicate()
	var i: int = out.find(value)
	if i >= 0:
		out.remove_at(i)
	return out
