extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	# Only players actually in this instance may read a table's state (it's already
	# broadcast in-world to them); blocks out-of-instance / forged-instance polling.
	if instance.players_by_peer_id.get(peer_id, null) == null:
		return {}
	var table: TradeTable = instance.instance_map.get_trade_table(int(args.get("table", 0)))
	if table == null:
		return {}
	return TradeService.build_state(table)
