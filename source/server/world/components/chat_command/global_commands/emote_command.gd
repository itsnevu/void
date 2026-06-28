extends ChatCommand
## Player emote: pops a one-shot social bubble above your head that everyone in the
## instance sees. Works everywhere (desktop/web/mobile) since it's a chat command.
## Favourites also have their own shortcut commands (/wave, /dance, ...).


func _init() -> void:
	command_name = "emote"
	command_priority = 0  # anyone
	command_alias = PackedStringArray(["e"])
	command_usage = "/emote <%s>" % EmoteRegistry.key_list()


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.is_empty():
		return "Emotes: %s\nUse /emote <name> — or shortcuts like /wave, /dance, /cheer." % EmoteRegistry.key_list()
	var id: int = EmoteRegistry.id_of(args[0])
	if id < 0:
		return "Unknown emote '%s'. Available: %s" % [args[0], EmoteRegistry.key_list()]
	EmoteRegistry.broadcast(server_instance, peer_id, id)
	return ""  # the bubble is the feedback — no chat echo
