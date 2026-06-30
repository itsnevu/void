class_name PlayerSkins
## Thin facade over the `sprites` ContentRegistry: every sprite is a wearable player skin.
## Character creation (gateway), the wardrobe, and the server's buy/equip validation all go
## through here so they agree on the roster + display names WITHOUT a hardcoded list - drop a
## SpriteFrames into the sprite_frames folder, reindex, and it's offered everywhere at once.


# TEMPORARY (next-patch): roster trimmed to 4 starters for this release. The full
# sprite set still ships in sprite_frames/ + the registry - we only hide the rest from
# the wardrobe + character creation. To restore the whole roster next patch, set
# ENABLED_SKIN_IDS back to an empty array (empty = no filter, show everything).
const ENABLED_SKIN_IDS: Array[int] = [1, 2, 3, 4]  # knight, rogue, wizard, goblin


## All skin ids, sorted ascending (so the original starters lead) - every entry in the
## `sprites` registry. Used by the wardrobe + character creation to list buyable skins.
## While ENABLED_SKIN_IDS is non-empty the roster is filtered down to that whitelist.
static func ids() -> Array[int]:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return []
	var out: Array[int] = registry.all_ids()
	if not ENABLED_SKIN_IDS.is_empty():
		var allowed: Array[int] = []
		for id: int in out:
			if ENABLED_SKIN_IDS.has(id):
				allowed.append(id)
		out = allowed
	out.sort()
	return out


## True when [param skin_id] resolves to a real sprite. Server-side anti-cheat: stops a
## client buying/equipping an id that doesn't exist in the registry.
static func is_valid(skin_id: int) -> bool:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	return registry != null and registry.has_id(skin_id)


## Readable display name for a skin id, from its file slug ("royal_guard" -> "Royal Guard");
## empty string if the id isn't in the registry.
static func display_name(skin_id: int) -> String:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return ""
	return String(registry.slug_from_id(skin_id)).capitalize()
