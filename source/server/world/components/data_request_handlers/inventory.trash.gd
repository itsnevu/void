extends DataRequestHandler
## Permanently destroys an inventory slot ("Trash"). No gold, no recovery - the
## client gates it behind a confirm. Refuses currency and equipped items (equip is
## id-based; trashing equipped gear would dangle the reference - unequip first).
##
## Returns {"ok": true, "removed": int} or {"ok": false, "reason": "equipped|currency|none"}.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player or player.player_resource == null:
		return {"ok": false}

	var slot_uid: int = int(args.get("slot_uid", 0))
	var inventory: Dictionary = player.player_resource.inventory
	if not inventory.has(slot_uid):
		return {"ok": false, "reason": "none"}

	var item_id: int = int(inventory[slot_uid].get("id", 0))
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	# Guard gold/alt-currency so a fat-finger can't burn the wallet.
	if item != null and item.is_currency:
		return {"ok": false, "reason": "currency"}
	# Equipped gear is referenced by id elsewhere - make them unequip first.
	if item_id in player.equipment_component.slots.values.values():
		return {"ok": false, "reason": "equipped"}

	var amount: int = int(inventory[slot_uid].get("a", 1))
	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed <= 0:
		return {"ok": false, "reason": "none"}
	return {"ok": true, "removed": removed}
