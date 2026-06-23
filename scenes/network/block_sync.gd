extends SyncModule

var _block_active: Dictionary = GameSettings.default_block_state()
var _block_direction: Dictionary = {}
var _block_cooldown_ratio: Dictionary = {}


func get_module_name() -> StringName:
	return GameSettings.MODULE_BLOCK


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_BLOCK_STARTED,
		GameSettings.PACKET_BLOCK_ENDED,
		GameSettings.PACKET_BLOCK_STATE,
	]


func physics_sync_tick(_delta: float) -> void:
	if game_sync == null or not game_sync.is_network_active() or not game_sync.is_host():
		return

	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player == null:
			continue
		_block_active[slot] = player.is_blocking()
		_block_direction[slot] = player.get_block_direction()
		_block_cooldown_ratio[slot] = player.get_block_cooldown_ratio()


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = _get_payload(packet)
	var slot: int = int(payload.get("slot", packet.get("from_slot", 0)))
	if game_sync != null and game_sync.is_host():
		slot = int(packet.get("from_slot", slot))

	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_BLOCK_STARTED:
		_apply_block_state(slot, true, payload.get("direction", Vector2.ZERO), payload.get("cooldown_ratio", GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO))
	elif packet_type == GameSettings.PACKET_BLOCK_ENDED:
		_apply_block_state(slot, false, payload.get("direction", Vector2.ZERO), payload.get("cooldown_ratio", 0.0))
	elif packet_type == GameSettings.PACKET_BLOCK_STATE:
		_apply_block_state(
			slot,
			bool(payload.get("active", false)),
			payload.get("direction", Vector2.ZERO),
			payload.get("cooldown_ratio", GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO)
		)

	if game_sync != null and game_sync.is_host():
		_send_block_state(slot, bool(_block_active.get(slot, false)))


func build_snapshot() -> Dictionary:
	return {
		"block_active": _block_active.duplicate(),
		"block_direction": _block_direction.duplicate(),
		"block_cooldown_ratio": _block_cooldown_ratio.duplicate(),
	}


func apply_snapshot(data: Dictionary) -> void:
	var block_data: Variant = data.get("block_active", {})
	if block_data is Dictionary:
		_block_active = block_data.duplicate()
	var direction_data: Variant = data.get("block_direction", {})
	if direction_data is Dictionary:
		_block_direction = direction_data.duplicate()
	var cooldown_data: Variant = data.get("block_cooldown_ratio", {})
	if cooldown_data is Dictionary:
		_block_cooldown_ratio = cooldown_data.duplicate()

	for raw_slot in _block_active.keys():
		var slot: int = int(raw_slot)
		_apply_block_state(
			slot,
			bool(_block_active.get(raw_slot, false)),
			_block_direction.get(raw_slot, Vector2.ZERO),
			_block_cooldown_ratio.get(raw_slot, GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO)
		)


func is_block_active(slot: int) -> bool:
	return bool(_block_active.get(slot, false))


func request_block_state(slot: int, active: bool, direction: Vector2, cooldown_ratio: float) -> void:
	if game_sync == null or not game_sync.is_network_active():
		return

	_apply_block_state(slot, active, direction, cooldown_ratio, false)
	_send_block_state(slot, active)


func _send_block_state(slot: int, active: bool) -> void:
	if game_sync == null or not game_sync.is_network_active():
		return

	var packet_type: StringName = GameSettings.PACKET_BLOCK_STARTED if active else GameSettings.PACKET_BLOCK_ENDED
	game_sync.send_reliable(packet_type, {
		"slot": slot,
		"active": active,
		"direction": _block_direction.get(slot, Vector2.ZERO),
		"cooldown_ratio": _block_cooldown_ratio.get(slot, GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO),
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _apply_block_state(slot: int, active: bool, direction_variant: Variant, cooldown_ratio_variant: Variant, update_player: bool = true) -> void:
	if slot == 0:
		return

	_block_active[slot] = active
	if direction_variant is Vector2:
		var direction: Vector2 = direction_variant
		if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
			_block_direction[slot] = direction.normalized()
	if cooldown_ratio_variant is float or cooldown_ratio_variant is int:
		_block_cooldown_ratio[slot] = clampf(float(cooldown_ratio_variant), 0.0, 1.0)

	if not update_player:
		return
	if game_sync != null and slot == game_sync.get_local_slot():
		return

	var player: Player = _get_player(slot)
	if player != null:
		player.apply_remote_block_state(
			active,
			_block_direction.get(slot, Vector2.ZERO),
			_block_cooldown_ratio.get(slot, GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO)
		)


func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)
