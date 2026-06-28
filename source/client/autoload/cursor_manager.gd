extends Node
## Custom in-game cursors - the armored-gauntlet set sliced from assets/cursor.png
## into assets/cursors/*.png. Client-only: we register a texture per Godot
## CursorShape, then the engine swaps them automatically - POINTING_HAND over
## clickable Controls, BUSY/WAIT while loading, FORBIDDEN on a blocked action,
## DRAG/CAN_DROP while dragging. Headless dedicated servers have no mouse, so we
## skip the whole thing there.
##
## Hotspots were computed from each sliced sprite's pointing tip (see the slicing
## step). They're in pixels within the 48px-tall cursor images.

const DIR: String = "res://assets/cursors/"

## shape -> [filename, hotspot]. The directional point_* sprites (up/right/down/
## left) are shipped in assets/cursors/ too but have no matching CursorShape, so
## they're left for explicit use (Input.set_custom_mouse_cursor) if needed later.
const CURSORS: Dictionary = {
	Input.CURSOR_ARROW:         ["arrow.png",     Vector2i(4, 0)],
	Input.CURSOR_POINTING_HAND: ["point.png",     Vector2i(8, 0)],
	Input.CURSOR_BUSY:          ["busy.png",      Vector2i(5, 0)],
	Input.CURSOR_WAIT:          ["busy.png",      Vector2i(5, 0)],
	Input.CURSOR_FORBIDDEN:     ["forbidden.png", Vector2i(4, 0)],
	Input.CURSOR_DRAG:          ["drag.png",      Vector2i(19, 24)],
	Input.CURSOR_CAN_DROP:      ["open.png",      Vector2i(20, 24)],
}


func _ready() -> void:
	# No cursor on a headless dedicated server (master / gateway / world).
	if not GameMode.is_client() or DisplayServer.get_name() == "headless":
		return
	for shape: int in CURSORS:
		var entry: Array = CURSORS[shape]
		var tex: Texture2D = load(DIR + String(entry[0]))
		if tex == null:
			push_warning("CursorManager: missing cursor texture %s" % entry[0])
			continue
		Input.set_custom_mouse_cursor(tex, shape, Vector2(entry[1]))
