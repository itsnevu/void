class_name EmoteRegistry
## Shared emote table + server broadcast helper. Lives in common/ so the client
## (render the bubble) and the server (validate + broadcast) agree on the ids.
##
## Emotes are one-shot social "pops" above the head — purely cosmetic, broadcast
## to everyone in the instance. Triggered by chat commands (/wave, /emote dance,
## ...) so they work on desktop, web AND mobile (no extra input/UI needed).
##
## NOTE: glyphs are plain text/symbols, not color emoji — the project's UI fonts
## (Cinzel / Atkinson) don't ship an emoji set, so emoji would render as tofu.

const WAVE: int = 0
const DANCE: int = 1
const CHEER: int = 2
const LAUGH: int = 3
const CRY: int = 4
const HEART: int = 5
const SLEEP: int = 6
const POINT: int = 7
const YES: int = 8
const NO: int = 9

## id == array index (stable across client/server). Append new emotes at the end.
const EMOTES: Array[Dictionary] = [
	{"key": "wave",  "glyph": "o/",      "label": "Wave"},
	{"key": "dance", "glyph": "~dance~", "label": "Dance"},
	{"key": "cheer", "glyph": "\\o/",    "label": "Cheer"},
	{"key": "laugh", "glyph": "haha!",   "label": "Laugh"},
	{"key": "cry",   "glyph": "T_T",     "label": "Cry"},
	{"key": "heart", "glyph": "<3",      "label": "Heart"},
	{"key": "sleep", "glyph": "zzZ",     "label": "Sleep"},
	{"key": "point", "glyph": "look!",   "label": "Point"},
	{"key": "yes",   "glyph": "yes!",    "label": "Yes"},
	{"key": "no",    "glyph": "no!",     "label": "No"},
]


static func get_emote(id: int) -> Dictionary:
	if id < 0 or id >= EMOTES.size():
		return {}
	return EMOTES[id]


## Resolve a typed key (e.g. "wave") to its id, or -1 if unknown.
static func id_of(key: String) -> int:
	var needle: String = key.strip_edges().to_lower()
	for i: int in EMOTES.size():
		if String(EMOTES[i]["key"]) == needle:
			return i
	return -1


## Comma-joined list of every emote key, for usage / help text.
static func key_list() -> String:
	var keys: PackedStringArray = PackedStringArray()
	for e: Dictionary in EMOTES:
		keys.append(String(e["key"]))
	return ", ".join(keys)


## Server only: broadcast an emote to everyone in the emoter's instance. Mirrors
## the combat.hit broadcast pattern (propagate_rpc + data_push). No-op on the
## client (WorldServer.curr is a stub there) or with a bad instance.
static func broadcast(instance: Node, emoter_peer_id: int, emote_id: int) -> void:
	if instance == null or WorldServer.curr == null:
		return
	if get_emote(emote_id).is_empty():
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"emote", {"p": emoter_peer_id, "e": emote_id}),
		instance.name
	)
