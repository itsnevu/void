extends ChatCommand
## Shortcut for /emote cry. See EmoteRegistry.


func _init() -> void:
	command_name = "cry"
	command_priority = 0
	command_usage = "/cry"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	EmoteRegistry.broadcast(server_instance, peer_id, EmoteRegistry.CRY)
	return ""
