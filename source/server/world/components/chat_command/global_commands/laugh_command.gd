extends ChatCommand
## Shortcut for /emote laugh. See EmoteRegistry.


func _init() -> void:
	command_name = "laugh"
	command_priority = 0
	command_alias = PackedStringArray(["lol"])
	command_usage = "/laugh"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.LAUGH)
	return ""
