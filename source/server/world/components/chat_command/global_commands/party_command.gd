extends ChatCommand
## Open-world party management (social grouping). Party members show as allies
## (blue health bars) and share the Team chat channel (/p). Server-authoritative
## via GroupService. Anyone can use it.


func _init() -> void:
	command_name = "party"
	command_priority = 0
	command_alias = PackedStringArray(["group"])
	command_usage = "/party <invite <name>|accept|leave|list>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var ws: WorldServer = server_instance.world_server
	var sub: String = (args[0] if args.size() > 0 else "list").to_lower()
	match sub:
		"invite", "inv", "add":
			if args.size() < 2:
				return "Usage: /party invite <name|#id>"
			var target_peer: int = _resolve_peer(args[1], peer_id, server_instance)
			if target_peer <= 0:
				return "Player '%s' not found online." % args[1]
			var gid: int = GroupService.invite(peer_id, target_peer)
			if gid == -3:
				return "You can't invite yourself."
			if gid == -1:
				return "That player is already in a party."
			if gid == -2:
				return "Your party is full (max %d)." % GroupService.MAX_PARTY
			var inviter: PlayerResource = ws.connected_players.get(peer_id)
			var inviter_name: String = inviter.display_name if inviter else "A player"
			var invitee: PlayerResource = ws.connected_players.get(target_peer)
			if invitee != null and ws.chat_service != null:
				ws.chat_service.push_system_to_player(
					server_instance, invitee.player_id,
					"%s invited you to a party. Type /party accept to join." % inviter_name
				)
			return "Party invite sent to %s." % (invitee.display_name if invitee else args[1])
		"accept", "join":
			var gid: int = GroupService.accept(peer_id)
			if gid == 0:
				return "You have no pending party invite."
			if gid < 0:
				return "Couldn't join - the party is full or no longer exists."
			var me: PlayerResource = ws.connected_players.get(peer_id)
			var my_name: String = me.display_name if me else "A player"
			if ws.chat_service != null:
				for member_peer: int in GroupService.members_of(gid):
					if member_peer == peer_id:
						continue
					var m: PlayerResource = ws.connected_players.get(member_peer)
					if m != null:
						ws.chat_service.push_system_to_player(server_instance, m.player_id, "%s joined the party." % my_name)
			return "You joined the party. Use /p <message> for party chat."
		"leave", "quit":
			if GroupService.group_of(peer_id) == 0:
				return "You're not in a party."
			GroupService.leave(peer_id)
			return "You left the party."
		_:
			var gid: int = GroupService.group_of(peer_id)
			if gid == 0:
				return "You're not in a party. Use /party invite <name> to start one."
			var names: PackedStringArray = PackedStringArray()
			var leader: int = GroupService.leader_of(gid)
			for member_peer: int in GroupService.members_of(gid):
				var p: PlayerResource = ws.connected_players.get(member_peer)
				if p == null:
					continue
				names.append(p.display_name + (" (leader)" if member_peer == leader else ""))
			return "Party (%d/%d): %s" % [names.size(), GroupService.MAX_PARTY, ", ".join(names)]


## Resolve a target token to an online peer id: #id / @account via CommandTarget,
## else a case-insensitive display-name match among connected players. 0 if none.
func _resolve_peer(token: String, caller_peer_id: int, instance: ServerInstance) -> int:
	var r: CommandTarget.Result = CommandTarget.resolve(token, caller_peer_id, instance)
	if r.ok and r.online and r.peer_id > 0:
		return r.peer_id
	var needle: String = token.strip_edges().to_lower()
	for pid: int in instance.world_server.connected_players:
		var p: PlayerResource = instance.world_server.connected_players[pid]
		if p != null and p.display_name.to_lower() == needle:
			return pid
	return 0
