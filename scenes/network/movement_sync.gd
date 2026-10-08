extends SyncModule

## Movement moves the owner starts and the other side has to see: the dash (trail, sound, cooldown and, on
## the host, the protection window hits are judged by) and its shockwave. The host decides who a shockwave
## throws and tells the thrown player's owner, who applies the throw.

func get_module_name() -> StringName:
	return GameSettings.MODULE_MOVEMENT


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_DASH,
		GameSettings.PACKET_DASH_SHOCKWAVE,
		GameSettings.PACKET_KNOCKBACK,
	]


func send_dash(slot: int, direction: float, protected: bool, shockwave: bool) -> void:
	if game_sync == null or not game_sync.is_network_active():
		return
	game_sync.send_reliable(GameSettings.PACKET_DASH, {
		"slot": slot,
		"direction": direction,
		"protected": protected,
		"shockwave": shockwave,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


## The local player's shockwave went off (its feedback already played here): the host resolves it and shows
## it to the client, a client hands it to the host.
func request_shockwave(slot: int, origin: Vector2, direction: float) -> void:
	if game_sync == null or not game_sync.is_network_active():
		return
	game_sync.send_reliable(GameSettings.PACKET_DASH_SHOCKWAVE, {
		"slot": slot,
		"origin": origin,
		"direction": direction,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)
	if game_sync.is_host():
		_resolve_shockwave(slot, origin, direction)


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = NetworkSession.get_payload(packet)
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	var slot: int = int(payload.get("slot", packet.get("from_slot", 0)))
	# A client only ever speaks for its own player.
	if game_sync.is_host():
		slot = int(packet.get("from_slot", slot))

	match packet_type:
		GameSettings.PACKET_DASH:
			var dasher: Player = _get_remote_player(slot)
			if dasher != null:
				dasher.apply_remote_dash(float(payload.get("direction", 0.0)), payload.get("protected", false) == true)
		GameSettings.PACKET_DASH_SHOCKWAVE:
			var origin_variant: Variant = payload.get("origin", null)
			var dasher: Player = _get_remote_player(slot)
			if dasher == null or not (origin_variant is Vector2):
				return
			var direction: float = float(payload.get("direction", 0.0))
			dasher.play_dash_shockwave_feedback(origin_variant, direction)
			if game_sync.is_host():
				_resolve_shockwave(slot, origin_variant, direction)
		GameSettings.PACKET_KNOCKBACK:
			if game_sync.is_host():
				return
			var target: Player = _get_player(int(payload.get("target_slot", 0)))
			var knockback: Variant = payload.get("velocity", null)
			var origin: Variant = payload.get("origin", Vector2.ZERO)
			if target != null and knockback is Vector2 and origin is Vector2:
				target.receive_knockback(knockback, origin)


## Host only: throws everyone the shockwave reaches. The host's own player is thrown here; the client's is
## thrown by the client when the knockback packet arrives (this side only shows the hit).
func _resolve_shockwave(slot: int, origin: Vector2, direction: float) -> void:
	if not OnlineMatch.is_playing_set():
		return
	var dasher: Player = _get_player(slot)
	if dasher == null:
		return
	for hit in dasher.get_dash_shockwave_hits(origin, direction):
		var target: Player = hit["target"]
		var knockback: Vector2 = hit["velocity"]
		target.receive_knockback(knockback, origin)
		game_sync.send_reliable(GameSettings.PACKET_KNOCKBACK, {
			"target_slot": target.player_slot,
			"velocity": knockback,
			"origin": origin,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _get_remote_player(slot: int) -> Player:
	if slot == 0 or slot == game_sync.get_local_slot():
		return null
	return _get_player(slot)


func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)
