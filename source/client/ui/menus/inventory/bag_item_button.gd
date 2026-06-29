class_name BagItemButton
extends Button
## A bag grid cell you can DRAG onto a HUD quick slot (keys 1/2/3). It carries
## the [Item] it shows and hands a typed payload to Godot's drag-and-drop; the
## drop itself is handled by [ItemSlots]. Clicking still selects the item (the
## inventory wires `pressed` as before) - drag and click are separate gestures,
## so the existing "Hotkey" button path is untouched.
##
## Desktop only in practice: on touch the bag's DragScroll claims drags to
## scroll the list, so mobile players assign via the Hotkey button instead.


## The bag item this cell represents. Set by the inventory when the cell is built.
var item: Item


## Start a drag carrying this cell's item. Returns null (so the cell isn't
## draggable) for empty cells and for items that can't sit on a quick slot -
## the same equip/use/hold rule the inventory's Hotkey button gates on, so a
## raw material can't be bound to a key. A faded icon ghost rides the cursor.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null or not _is_quick_usable(item):
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = item.item_icon
	preview.custom_minimum_size = Vector2(44, 44)
	preview.size = Vector2(44, 44)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
	set_drag_preview(preview)
	return {"kind": &"bag_item", "item": item}


## Equip / use / hold-able items are the ones a quick slot can act on (mirrors
## inventory_menu's Action/Hotkey gating). GearItem covers WeaponItem too.
func _is_quick_usable(check: Item) -> bool:
	return check is GearItem or check is WeaponItem or check is ConsumableItem or check.holdable
