class_name QuickSlotDrop
extends Button
## An in-inventory drop target for one HUD quick slot (keys 1/2/3). Drag a bag
## cell ([BagItemButton]) onto it to bind that item to the slot. It reads/writes
## the SHARED ClientState.quick_slots store, so the HUD quick-slot bar updates
## live and the binding persists - identical end state to the "Hotkey" button.
##
## Why it lives in the menu and not on the HUD: an open menu draws a full-screen
## dim backdrop over the HUD, so the HUD slots can't receive a drop while you're
## dragging from the bag. These in-menu mirrors are the reachable drop targets.

const SLOT_COUNT: int = 3

var slot_index: int = -1


## Build slot [param index] (0..2). Mirrors the HUD slot's look: a square button
## with a corner key hint that shows the bound item's icon, the number when empty.
func setup(index: int) -> void:
	slot_index = index
	custom_minimum_size = Vector2(46, 46)
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"SlotButton"
	add_theme_constant_override(&"icon_max_width", 40)
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_text = "Quick slot %d (key %d) - drag an item here. Click to clear." % [index + 1, index + 1]
	pressed.connect(_clear)

	var key_label: Label = Label.new()
	key_label.text = str(index + 1)
	key_label.add_theme_font_size_override(&"font_size", 9)
	key_label.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
	key_label.position = Vector2(4, 2)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key_label)

	ClientState.quick_slots.data_changed.connect(_on_slot_changed)
	_refresh()


func _on_slot_changed(index: Variant, _value: Variant) -> void:
	if int(index) == slot_index:
		_refresh()


func _refresh() -> void:
	var item: Item = ClientState.quick_slots.get_key(slot_index) as Item
	if item != null and item.item_icon != null:
		icon = item.item_icon
		text = ""
	else:
		icon = null
		text = str(slot_index + 1)


## Click an occupied slot to unbind it (drag is for binding; this is the inverse).
func _clear() -> void:
	if ClientState.quick_slots.get_key(slot_index) != null:
		ClientState.quick_slots.set_key(slot_index, null)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", &"") == &"bag_item" and data.get("item") is Item


## Bind the dropped item here. MOVE semantics (matching the Hotkey picker):
## vacate any OTHER slot already holding it so one item never sits on two keys.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var item: Item = (data as Dictionary).get("item") as Item
	if item == null:
		return
	for i: int in SLOT_COUNT:
		if i != slot_index and (ClientState.quick_slots.get_key(i) as Item) == item:
			ClientState.quick_slots.set_key(i, null)
	ClientState.quick_slots.set_key(slot_index, item)
