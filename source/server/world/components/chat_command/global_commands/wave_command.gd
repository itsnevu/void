extends ChatCommand
## Shortcut for /emote wave. See EmoteRegistry.


func _init() -> void:
	command_name = "wave"
	command_priority = 0
	command_usage = "/wave"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.WAVE)
	return ""
