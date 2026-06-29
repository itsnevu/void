class_name TradeTable
extends Area2D
## A world trade table. Click to claim a seat; place items + gold into your offer; both
## players accept; after a short countdown the server performs an atomic swap. The table
## broadcasts its full state to the whole instance, so seats AND offers are visible
## in-world to everyone nearby (no separate spectator system needed).
##
## ANTI-DUPE via ESCROW: the moment a player ACCEPTS, their offered items+gold are
## removed from their inventory and held in `seat_escrow`. Un-accepting, changing the
## offer, leaving, walking away, or DISCONNECTING refunds the escrow to the owner.
## Completion just hands each side's escrow to the other. So an offered item can never
## be in two places at once: it's either in the owner's bag, in escrow, or delivered -
## never duplicated by a mid-trade save/disconnect, and never swapped after the offer
## changed (changing the offer refunds + un-accepts).
##
## Setup: Area2D + CollisionShape2D over the table, a unique table_id, direct child of
## the Map (like the merchant / crafting station).

@export var table_id: int = 0
## Max distance a player can be from the table to claim or keep a seat (auto-removed past it).
@export var seat_range: float = 80.0
## Gold charged once to claim a seat (a small anti-abuse tax; kept whether or not the
## trade completes). 0 = free.
@export var join_cost: int = 3

const COUNTDOWN_MS: int = 12000
## Max distinct items one player can put in an offer (keeps trades simple).
const MAX_OFFER_ITEMS: int = 6
## Server-only group so disconnect cleanup can sweep every table without a registry.
const SERVER_GROUP: StringName = &"trade_tables"

## Server only. Per seat (index 0 = A, 1 = B):
var seat_players: Array = [null, null]               # Player ref or null
var seat_offers: Array = []                          # {"items": {item_id:int -> amount:int}, "gold": int}
var seat_accepted: Array[bool] = [false, false]
## Goods actually pulled out of the player's inventory on accept (the escrow). Same
## shape as an offer. Refunded on cancel/disconnect, delivered on completion.
var seat_escrow: Array = []
## When (ticks_msec) the swap fires once both have accepted (0 = no countdown running).
var countdown_until: int = 0
## Re-entrancy guard so the swap can never double-execute.
var _completing: bool = false

var _seat_labels: Array[Label] = []
var _countdown_label: Label


func _ready() -> void:
	if multiplayer.is_server():
		seat_offers = [_empty_offer(), _empty_offer()]
		seat_escrow = [_empty_offer(), _empty_offer()]
		add_to_group(SERVER_GROUP)
		input_pickable = false
		set_physics_process(true) # auto-leave + countdown
		return
	set_physics_process(false)
	input_pickable = true
	input_event.connect(_on_input_event)
	_build_display()
	Client.subscribe(&"trade.table", _on_table_state)


static func _empty_offer() -> Dictionary:
	return {"items": {}, "gold": 0}


# --- Server session ---

func _physics_process(_delta: float) -> void:
	var changed: bool = false

	# Auto-remove players who walked away, disconnected, or whose node went away.
	for i: int in seat_players.size():
		var occupant = seat_players[i]
		if occupant == null:
			continue
		var gone: bool = not is_instance_valid(occupant) \
			or int(occupant.player_resource.current_peer_id) <= 0 \
			or occupant.global_position.distance_to(global_position) > seat_range
		if gone:
			_clear_seat(i)
			changed = true

	# Fire the swap when the countdown elapses.
	if countdown_until > 0 and Time.get_ticks_msec() >= countdown_until:
		_complete_trade()
		changed = true

	if changed:
		var instance: Node = _server_instance()
		if instance:
			TradeService.broadcast(instance, self)


func _clear_seat(index: int) -> void:
	_refund_escrow(index)            # give back what THIS seat escrowed (player still set)
	seat_players[index] = null
	seat_offers[index] = _empty_offer()
	_reset_accepts()                 # refunds the OTHER seat + clears accepts/countdown


## Any change to seats/offers invalidates both accepts, refunds both escrows, and
## cancels a pending swap. Escrow refund is what makes "change offer after accept"
## safe - the accepted goods go back before anything can be swapped.
func _reset_accepts() -> void:
	_refund_escrow(0)
	_refund_escrow(1)
	seat_accepted = [false, false]
	countdown_until = 0


func server_remove_player(player: Player) -> bool:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return false
	_clear_seat(seat)
	return true


## Disconnect path: the world server has the PlayerResource (not the Player node), so
## match by resource. Refund happens into resource.inventory, which the caller then
## persists - so a disconnect during a trade returns the escrowed goods cleanly.
func server_remove_player_by_resource(resource: PlayerResource) -> bool:
	for i: int in seat_players.size():
		var p = seat_players[i]
		if is_instance_valid(p) and p.player_resource != null \
				and p.player_resource.player_id == resource.player_id:
			# Refund THIS seat's escrow straight into the resource being persisted,
			# then free the seat. _reset_accepts() refunds the OTHER seat to its
			# (still-online) player.
			_grant_to_inventory(seat_escrow[i], resource.inventory)
			seat_escrow[i] = _empty_offer()
			seat_players[i] = null
			seat_offers[i] = _empty_offer()
			_reset_accepts()
			return true
	return false


func server_set_offer(player: Player, items: Dictionary, gold: int) -> void:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return
	seat_offers[seat] = {"items": items, "gold": gold}
	_reset_accepts() # changing an offer un-confirms both sides (and refunds escrow)


func server_set_accepted(player: Player, accepted: bool) -> void:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return
	if accepted == seat_accepted[seat]:
		return # idempotent: re-pressing accept can't re-escrow or re-arm the countdown
	if accepted:
		# Escrow the offer NOW (atomic removal from inventory). If they can't afford
		# it anymore, leave them un-accepted.
		if not _escrow_seat(seat):
			return
		seat_accepted[seat] = true
	else:
		_refund_escrow(seat)
		seat_accepted[seat] = false

	if seat_accepted[0] and seat_accepted[1]:
		countdown_until = Time.get_ticks_msec() + COUNTDOWN_MS
	else:
		countdown_until = 0


## Move a seat's offered gold+items out of the player's inventory into escrow.
## All-or-nothing: validates affordability first, honours every remove return value,
## and rolls back (refunds) if any removal unexpectedly fails. Returns success.
func _escrow_seat(seat: int) -> bool:
	var player = seat_players[seat]
	if not is_instance_valid(player):
		return false
	var offer: Dictionary = seat_offers[seat]
	var inv: Dictionary = player.player_resource.inventory
	if not _can_afford(inv, offer):
		return false

	var esc: Dictionary = _empty_offer()
	var gold: int = int(offer.get("gold", 0))
	if gold > 0:
		if not Inventory.remove_amount_by_id(inv, Economy.gold_id(), gold):
			_grant(esc, player) # nothing escrowed yet; safe no-op
			return false
		esc["gold"] = gold
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		var amount: int = int(items[item_id])
		if not Inventory.remove_amount_by_id(inv, int(item_id), amount):
			_grant(esc, player) # roll back whatever we already pulled
			return false
		esc["items"][int(item_id)] = amount
	seat_escrow[seat] = esc
	return true


## Refund a seat's escrow back to its own player and clear it. Idempotent.
func _refund_escrow(index: int) -> void:
	if index < 0 or index >= seat_escrow.size():
		return
	_grant(seat_escrow[index], seat_players[index])
	seat_escrow[index] = _empty_offer()


## Hand a seat's escrow to a (different) recipient and clear it - used on completion.
func _deliver_escrow(from_seat: int, to_player) -> void:
	_grant(seat_escrow[from_seat], to_player)
	seat_escrow[from_seat] = _empty_offer()


## Add an escrow's gold + items into [param player]'s inventory (no-op if invalid).
func _grant(escrow: Dictionary, player) -> void:
	if not is_instance_valid(player):
		return
	_grant_to_inventory(escrow, player.player_resource.inventory)


## Add an escrow's gold + items straight into an inventory dict. Used on disconnect,
## where we must refund into the exact PlayerResource the world server is about to
## persist (not whatever the seat node happens to reference).
func _grant_to_inventory(escrow: Dictionary, inventory: Dictionary) -> void:
	var gold: int = int(escrow.get("gold", 0))
	if gold > 0:
		Inventory.add_item(inventory, Economy.gold_id(), gold)
	var items: Dictionary = escrow.get("items", {})
	for item_id in items:
		for _i: int in int(items[item_id]):
			Inventory.add_item(inventory, int(item_id), 1)


func _complete_trade() -> void:
	countdown_until = 0
	if _completing:
		return
	_completing = true

	var a = seat_players[0]
	var b = seat_players[1]
	var ok: bool = is_instance_valid(a) and is_instance_valid(b)
	if ok:
		# Goods are already escrowed; just hand each side's escrow to the other.
		_deliver_escrow(0, b)
		_deliver_escrow(1, a)
	else:
		# A participant vanished mid-countdown - refund both, swap nothing.
		_refund_escrow(0)
		_refund_escrow(1)

	# Clear the table either way; players stay seated and can trade again.
	seat_offers = [_empty_offer(), _empty_offer()]
	seat_accepted = [false, false]

	for participant in [a, b]:
		if is_instance_valid(participant):
			var peer_id: int = int(participant.player_resource.current_peer_id)
			if peer_id > 0:
				WorldServer.curr.data_push.rpc_id(peer_id, &"trade.result", {"ok": ok})

	_completing = false


func _can_afford(inventory: Dictionary, offer: Dictionary) -> bool:
	if Inventory.count(inventory, Economy.gold_id()) < int(offer.get("gold", 0)):
		return false
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		if Inventory.count(inventory, int(item_id)) < int(items[item_id]):
			return false
	return true


func _server_instance() -> Node:
	var node: Node = get_parent()
	while node and not (node is SubViewport):
		node = node.get_parent()
	return node


# --- Client input + in-world display ---

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked:
		# Just open the panel (view). Joining a seat is an explicit button (costs gold).
		ClientState.set_viewed_trade(table_id)


func _build_display() -> void:
	for i: int in 2:
		var label: Label = Label.new()
		label.position = Vector2(-60.0, -96.0 + i * 40.0)
		label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.4))
		add_child(label)
		_seat_labels.append(label)
	_countdown_label = Label.new()
	_countdown_label.position = Vector2(-60.0, -112.0)
	_countdown_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
	add_child(_countdown_label)


func _on_table_state(data: Dictionary) -> void:
	if int(data.get("id", 0)) != table_id:
		return
	var seats: Array = data.get("seats", [])
	for i: int in _seat_labels.size():
		_seat_labels[i].text = _format_seat(seats[i]) if i < seats.size() else ""
	var countdown: int = int(data.get("countdown", 0))
	_countdown_label.text = "Trading in %d..." % countdown if countdown > 0 else ""


func _format_seat(seat: Dictionary) -> String:
	var occupant: String = str(seat.get("name", ""))
	if occupant.is_empty():
		return ""
	var text: String = occupant + (" v" if seat.get("accepted", false) else "")
	for item: Dictionary in seat.get("items", []):
		text += "\n  %dx %s" % [int(item.get("amount", 1)), str(item.get("name", ""))]
	var gold: int = int(seat.get("gold", 0))
	if gold > 0:
		text += "\n  %dg" % gold
	return text
