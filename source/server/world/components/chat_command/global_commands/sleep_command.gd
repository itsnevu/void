extends ChatCommand
## Shortcut for /emote sleep. See EmoteRegistry.


func _init() -> void:
	command_name = "sleep"
	command_priority = 0
	command_usage = "/sleep"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.SLEEP)
	return ""
