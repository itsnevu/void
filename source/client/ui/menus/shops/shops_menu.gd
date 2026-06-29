extends MenuShell
## A read-only DIRECTORY of the world's merchants: where each one is and what
## they sell. Shops stay NPC-based (you walk to the merchant to buy) - this just
## solves discovery ("where do I buy a sword?") without a global menu shop.
##
## Built entirely in code over [MenuShell]; stock + names are pulled LIVE from
## each [ShopResource] so the list never drifts from the real shops. Only the
## location hint is curated (the map a merchant stands in isn't on the resource).

## Merchant slug -> human location hint, in display order. Add a row here when a
## new merchant ships; an unknown/unregistered slug is skipped silently.
const DIRECTORY: Array[Dictionary] = [
	{"slug": &"start_shop", "where": "Guild House - Starter Merchant"},
	{"slug": &"quarry_counter", "where": "Overworld - Foreman (Quarry)"},
	{"slug": &"miras_apothecary", "where": "Overworld - Mira"},
	{"slug": &"rustic_shop", "where": "Smith House - Forge Smith"},
	{"slug": &"bone_shop", "where": "Forest - Bone Carver"},
]


func _ready() -> void:
	build_shell("Where to Shop", null, true)

	var hint: Label = Label.new()
	hint.text = "Walk up to a merchant to buy. Here's who sells what, and where:"
	hint.add_theme_color_override(&"font_color", Color(0.78, 0.81, 0.88))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 10)
	scroll.add_child(list)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"separation", 8)
	outer.add_child(hint)
	outer.add_child(scroll)
	content.add_child(outer)

	for entry: Dictionary in DIRECTORY:
		var card: Control = _build_shop_card(entry)
		if card != null:
			list.add_child(card)
	DragScroll.enable(scroll) # touch/mouse drag-scroll the directory


## One merchant card: name + location header, then its live stock (name - price).
## Returns null if the shop slug isn't registered (skipped by the caller).
func _build_shop_card(entry: Dictionary) -> Control:
	var shop_id: int = ContentRegistryHub.id_from_slug(&"shops", entry["slug"])
	if shop_id <= 0:
		return null
	var shop: ShopResource = ContentRegistryHub.load_by_id(&"shops", shop_id) as ShopResource
	if shop == null:
		return null

	var panel: PanelContainer = PanelContainer.new()
	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 12)
	pad.add_theme_constant_override(&"margin_right", 12)
	pad.add_theme_constant_override(&"margin_top", 8)
	pad.add_theme_constant_override(&"margin_bottom", 8)
	panel.add_child(pad)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	pad.add_child(box)

	var header: Label = Label.new()
	header.text = "%s  -  %s" % [shop.shop_name, String(entry["where"])]
	header.add_theme_font_size_override(&"font_size", 17)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	box.add_child(header)

	var sold_any: bool = false
	for shop_entry: ShopEntry in shop.entries:
		if shop_entry == null or shop_entry.item == null:
			continue
		sold_any = true
		var line: Label = Label.new()
		line.text = "    %s  -  %d gold" % [String(shop_entry.item.item_name), int(shop_entry.price)]
		line.add_theme_color_override(&"font_color", Color(0.82, 0.85, 0.9))
		box.add_child(line)
	if not sold_any:
		var none: Label = Label.new()
		none.text = "    (buys your loot for gold)"
		none.add_theme_color_override(&"font_color", Color(0.6, 0.63, 0.7))
		box.add_child(none)

	return panel
