class_name LevelMilestoneService
## On level-up, fire styled chat messages for any quest whose min_level matches
## the player's new level. Quests author the message themselves
## (QuestResource.unlock_message) — usually as a personal note from the giving
## NPC, e.g. "[Duel Master] I've heard you've been honing your blade. Find me
## at the arena." Empty unlock_message = no notification (the quest just
## becomes available silently on the giver's offer list).
##
## Cached on first use so we don't walk the whole quests registry every kill.

static var _by_min_level: Dictionary = {} # int -> Array[QuestResource]
static var _loaded: bool

## Capstone vanity title awarded once for reaching PlayerResource.MAX_LEVEL — the
## game's top-line goal. Free-form string, granted the same way quests grant
## titles (see grant_capstone).
const CAPSTONE_TITLE: String = "Ascendant"


## Called whenever a player's level changed. Walks the open range (old, new]
## so multi-level pops still fire each milestone in order.
static func on_levels_gained(player_res: PlayerResource, old_level: int, new_level: int, instance: Node) -> void:
	if not _loaded:
		_load()
	if new_level <= old_level:
		return
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.chat_service == null:
		return
	for level: int in range(old_level + 1, new_level + 1):
		for quest: QuestResource in _by_min_level.get(level, []):
			if quest == null or quest.unlock_message.is_empty():
				continue
			# Don't re-notify on a quest the player has already touched.
			if player_res.quests.has(int(quest.get_meta(&"id", 0))):
				continue
			ws.chat_service.push_system_to_player(instance, player_res.player_id, quest.unlock_message)

	# Capstone: the one milestone every player chases. Fired here so it lands in
	# the same chat lane as the per-level quest unlocks, only when this level-up
	# is the one that crossed the cap.
	if old_level < PlayerResource.MAX_LEVEL and new_level >= PlayerResource.MAX_LEVEL:
		ws.chat_service.push_system_to_player(
			instance, player_res.player_id,
			"You have reached the pinnacle of Mythreach — %s." % CAPSTONE_TITLE
		)


## Grants the one-time capstone title, auto-equipping it only if the player has
## no banner shown (mirrors quest title grants). Returns true if it was newly
## granted (so the caller can append a "Title unlocked" feedback line), false if
## the player already had it. Server-side; safe to call from any xp source.
static func grant_capstone(player_res: PlayerResource) -> bool:
	if player_res == null or player_res.titles_unlocked.has(CAPSTONE_TITLE):
		return false
	player_res.titles_unlocked.append(CAPSTONE_TITLE)
	if player_res.display_title.is_empty():
		player_res.display_title = CAPSTONE_TITLE
	return true


# --- internals ---

static func _load() -> void:
	_loaded = true
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"quests")
	if registry == null:
		return
	# ContentRegistry doesn't expose iteration; reach into _id_to_path.
	for id: int in registry._id_to_path.keys():
		var quest: QuestResource = ContentRegistryHub.load_by_id(&"quests", id) as QuestResource
		if quest == null or quest.min_level <= 0:
			continue
		var bucket: Array = _by_min_level.get_or_add(quest.min_level, [])
		bucket.append(quest)
