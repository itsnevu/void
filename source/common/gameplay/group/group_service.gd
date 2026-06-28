class_name GroupService
## Runtime-only, session-scoped co-op GROUPS — the third allegiance context after
## guild (open world) and spar teams. A group exists ONLY for a co-op instance (a
## dungeon run): formed at the entrance, dissolved on exit, never persisted.
## Groupmates are allies (CombatHit.are_allied) regardless of guild — the whole
## point of cross-guild co-op, and what keeps the open world cleanly guild-only.
##
## This layer is just membership + the allegiance query + the client tint sync.
## Dungeon lifecycle (private instance, modes, scaling, rewards, lockouts) rides
## ON TOP of it later — see docs/dungeons.md. Server-authoritative state; clients
## mirror only the roster (for health-bar tint) via the group.roster push.

# group_id -> { "members": Array[int] (peer ids), "leader": int }
static var _groups: Dictionary[int, Dictionary] = {}
# peer_id -> group_id (absent = ungrouped)
static var _peer_to_group: Dictionary[int, int] = {}
static var _next_group_id: int = 1

## Open-world parties (social grouping, distinct from dungeon co-op lobbies) share
## the same membership store. Cap + pending invites live here.
const MAX_PARTY: int = 5
# invitee_peer -> group_id they were invited to (cleared on accept/decline).
static var _pending_invites: Dictionary[int, int] = {}


## THE co-op allegiance check (used by CombatHit.are_allied): true only when both
## peers sit in the SAME group. Server-side — on a client _peer_to_group is empty,
## so this is false there (the client uses the synced roster for tint instead).
static func are_grouped(peer_a: int, peer_b: int) -> bool:
	if peer_a <= 0 or peer_b <= 0:
		return false
	var g: int = _peer_to_group.get(peer_a, 0)
	return g != 0 and g == _peer_to_group.get(peer_b, 0)


static func group_of(peer_id: int) -> int:
	return _peer_to_group.get(peer_id, 0)


static func members_of(group_id: int) -> Array:
	return _groups.get(group_id, {}).get("members", [])


## Form a group from [param peers] (the lobby's ready players). Returns the new
## group id; any peer already grouped is moved into this one. Server-only.
static func create_group(peers: Array, leader: int) -> int:
	var group_id: int = _next_group_id
	_next_group_id += 1
	var members: Array[int] = []
	for peer: int in peers:
		if peer <= 0:
			continue
		_detach(peer) # keep _peer_to_group single-valued
		members.append(peer)
		_peer_to_group[peer] = group_id
	_groups[group_id] = {"members": members, "leader": leader}
	_broadcast_roster(group_id)
	return group_id


static func leader_of(group_id: int) -> int:
	return int(_groups.get(group_id, {}).get("leader", 0))


## Invite [param invitee_peer] to [param inviter_peer]'s party, creating a solo
## party for the inviter if they have none. Returns the group id, or a negative
## code: -1 invitee already grouped, -2 party full, -3 can't invite yourself.
static func invite(inviter_peer: int, invitee_peer: int) -> int:
	if inviter_peer == invitee_peer:
		return -3
	if group_of(invitee_peer) != 0:
		return -1
	var group_id: int = group_of(inviter_peer)
	if group_id == 0:
		group_id = create_group([inviter_peer], inviter_peer)
	if members_of(group_id).size() >= MAX_PARTY:
		return -2
	_pending_invites[invitee_peer] = group_id
	return group_id


## Accept a pending invite. Returns the joined group id, or: 0 no pending invite,
## -1 already grouped, -2 party full or gone.
static func accept(invitee_peer: int) -> int:
	var group_id: int = _pending_invites.get(invitee_peer, 0)
	_pending_invites.erase(invitee_peer)
	if group_id == 0 or not _groups.has(group_id):
		return 0
	if group_of(invitee_peer) != 0:
		return -1
	if members_of(group_id).size() >= MAX_PARTY:
		return -2
	var members: Array = members_of(group_id)
	members.append(invitee_peer)
	_peer_to_group[invitee_peer] = group_id
	_broadcast_roster(group_id)
	return group_id


## Remove one peer (left the run for good). Dissolves the group when the last
## member goes. A crash/disconnect that intends to rejoin should NOT call this —
## the seat stays so they can re-enter the live instance. Server-only.
static func leave(peer_id: int) -> void:
	var group_id: int = _peer_to_group.get(peer_id, 0)
	if group_id == 0:
		return
	_detach(peer_id)
	_push_roster_to(peer_id, []) # clear the leaver's ally tint
	if members_of(group_id).is_empty():
		_groups.erase(group_id)
	else:
		_broadcast_roster(group_id)


## Tear down a whole group (the run ended). Server-only.
static func dissolve(group_id: int) -> void:
	for peer: int in members_of(group_id):
		_peer_to_group.erase(peer)
		_push_roster_to(peer, [])
	_groups.erase(group_id)


static func _detach(peer_id: int) -> void:
	var group_id: int = _peer_to_group.get(peer_id, 0)
	if group_id == 0:
		return
	_peer_to_group.erase(peer_id)
	var members: Array = members_of(group_id) # the stored ref — mutate in place
	var idx: int = members.find(peer_id)
	if idx != -1:
		members.remove_at(idx)


## Push every member their groupmate peer list for the ally health-bar tint
## (client mirror) — per-peer, the same data_push the rest of the game uses.
static func _broadcast_roster(group_id: int) -> void:
	var members: Array = members_of(group_id)
	for peer: int in members:
		_push_roster_to(peer, members)


static func _push_roster_to(peer_id: int, members: Array) -> void:
	if WorldServer.curr == null:
		return
	# Skip a peer that's already gone from the network table — a disconnecting
	# player triggers leave()→here, but they've left get_peers() by the time the
	# peer_disconnected signal fires, so the RPC would throw "unknown peer ID".
	var mp: MultiplayerAPI = WorldServer.curr.multiplayer
	if mp == null or not mp.has_multiplayer_peer() or peer_id not in mp.get_peers():
		return
	WorldServer.curr.data_push.rpc_id(peer_id, &"group.roster", {"members": members})
