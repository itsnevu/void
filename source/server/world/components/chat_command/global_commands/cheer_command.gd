extends ChatCommand
## Shortcut for /emote cheer. See EmoteRegistry.


func _init() -> void:
	command_name = "cheer"
	command_priority = 0
	command_usage = "/cheer"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.CHEER)
	return ""
