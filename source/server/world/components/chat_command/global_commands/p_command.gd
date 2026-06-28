extends ChatCommand
## /p <message> — quick party (Team) chat shortcut. Routes through the same TEAM
## channel handler the Team tab uses, so it reaches every party member.


func _init() -> void:
	command_name = "p"
	command_priority = 0
	command_usage = "/p <message>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.is_empty():
		return "Usage: /p <message>"
	var ws: WorldServer = server_instance.world_server
	var player: PlayerResource = ws.connected_players.get(peer_id)
	if player == null:
		return "You're not connected."
	if ws.chat_service == null:
		return "Chat unavailable."
	var result: Dictionary = ws.chat_service.handle_send_channel_message(
		server_instance, player, ChatConstants.CHANNEL_TEAM, " ".join(args)
	)
	# Surface "not in a party" etc.; success returns {} and the push is the feedback.
	if result.has("message"):
		return str(result["message"])
	return ""
