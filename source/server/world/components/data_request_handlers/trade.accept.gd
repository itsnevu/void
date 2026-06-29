extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	# Throttle accept toggles: stops a client spamming accept to churn the
	# escrow/countdown or grief the partner's timer.
	if not RateLimiter.check(peer_id, &"trade.accept", 10, 2_000):
		return {"ok": false, "reason": "rate"}

	var table: TradeTable = instance.instance_map.get_trade_table(int(args.get("table", 0)))
	if table == null or not table.seat_players.has(player):
		return {"ok": false}

	table.server_set_accepted(player, bool(args.get("accepted", true)))
	TradeService.broadcast(instance, table)
	return {"ok": true}
