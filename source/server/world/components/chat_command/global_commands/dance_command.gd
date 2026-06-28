extends ChatCommand
## Shortcut for /emote dance. See EmoteRegistry.


func _init() -> void:
	command_name = "dance"
	command_priority = 0
	command_usage = "/dance"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.DANCE)
	return ""
