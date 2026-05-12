extends "res://scenes/network/sync_module.gd"

var _send_timer: float = 0.0


func get_module_name() -> StringName:
	return GameSettings.MODULE_PLAYER


func get_packet_types() -> Array[StringName]:
	return [GameSettings.PACKET_PLAYER_SNAPSHOT]


func physics_sync_tick(delta: float) -> void:
	if game_sync == null or not game_sync.is_network_active():
		return

	_send_timer -= delta
	if _send_timer > 0.0:
		return

	_send_timer = 1.0 / GameSettings.NETWORK_PLAYER_STATE_RATE
	if game_sync.is_host():
		for slot in GameSettings.player_slots():
			var player := _get_player(slot)
			if player != null:
				game_sync.send_unreliable(GameSettings.PACKET_PLAYER_SNAPSHOT, _build_player_snapshot(player), GameSettings.NETWORK_CHANNEL_STATE)
	else:
		var local_player := _get_player(game_sync.get_local_slot())
		if local_player != null:
			game_sync.send_unreliable(GameSettings.PACKET_PLAYER_SNAPSHOT, _build_player_snapshot(local_player), GameSettings.NETWORK_CHANNEL_STATE)


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	var sender_slot: int = int(packet.get("from_slot", 0))
	var slot: int = int(payload.get("slot", sender_slot))

	if game_sync.is_host():
		slot = sender_slot

	if slot == 0:
		return

	if slot == game_sync.get_local_slot():
		return

	_apply_player_snapshot(slot, payload)


func build_snapshot() -> Dictionary:
	if game == null or game_sync == null or not game_sync.is_host():
		return {}

	var snapshots: Array[Dictionary] = []
	for slot in GameSettings.player_slots():
		var player := _get_player(slot)
		if player != null:
			snapshots.append(_build_player_snapshot(player))

	return {"players": snapshots}


func apply_snapshot(data: Dictionary) -> void:
	var players: Variant = data.get("players", [])
	if not (players is Array):
		return

	for snapshot in players:
		if not (snapshot is Dictionary):
			continue
		var slot: int = int(snapshot.get("slot", 0))
		if slot == 0:
			continue
		if slot == game_sync.get_local_slot():
			continue
		_apply_player_snapshot(slot, snapshot)


func _build_player_snapshot(player: Player) -> Dictionary:
	return {
		"slot": player.player_slot,
		"position": player.global_position,
		"velocity": player.velocity,
		"aim": player.get_aim_world_position(),
		"facing": player.last_dir,
		"grounded": player.update_grounded(),
		"on_wall": player.is_on_wall(),
	}


func _apply_player_snapshot(slot: int, snapshot: Dictionary) -> void:
	var player := _get_player(slot)
	if player == null:
		return

	player.apply_remote_snapshot(snapshot)


func _get_player(slot: int) -> Player:
	if game == null or not game.has_method("get_player_by_slot"):
		return null
	return game.get_player_by_slot(slot)


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
