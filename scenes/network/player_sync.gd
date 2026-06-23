extends SyncModule

var _send_timer: float = 0.0
var _last_sent_by_slot: Dictionary = {}
var _last_sent_time_by_slot: Dictionary = {}
var _last_received_tick_by_slot: Dictionary = {}


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
		var host_player: Player = _get_player(game_sync.get_local_slot())
		if host_player != null:
			_send_player_snapshot_if_needed(game_sync.get_local_slot(), host_player)
	else:
		var local_player: Player = _get_player(game_sync.get_local_slot())
		if local_player != null:
			_send_player_snapshot_if_needed(game_sync.get_local_slot(), local_player)


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = _get_payload(packet)
	var sender_slot: int = int(packet.get("from_slot", 0))
	var slot: int = int(payload.get("slot", sender_slot))
	var packet_tick: int = int(packet.get("tick", 0))

	if game_sync.is_host():
		slot = sender_slot

	if slot == 0:
		return

	if slot == game_sync.get_local_slot():
		return

	_apply_player_snapshot(slot, payload, packet_tick)


func build_snapshot() -> Dictionary:
	return {}


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
	var snapshot: Dictionary = {
		"slot": player.player_slot,
		"position": player.global_position,
		"velocity": player.velocity,
		"aim": player.get_aim_world_position(),
		"facing": player.last_dir,
	}
	var gun: Gun = player.get_gun()
	if gun != null:
		snapshot["ammo"] = gun.get_current_ammo()
		snapshot["reloading"] = gun.is_reloading()
		snapshot["reload_ratio"] = gun.get_reload_ratio()
	return snapshot


func _send_player_snapshot_if_needed(slot: int, player: Player) -> void:
	var snapshot: Dictionary = _build_player_snapshot(player)
	if not _should_send_snapshot(slot, snapshot):
		return
	game_sync.send_unreliable(GameSettings.PACKET_PLAYER_SNAPSHOT, snapshot, GameSettings.NETWORK_CHANNEL_STATE)
	_remember_sent_snapshot(slot, snapshot)


func _should_send_snapshot(slot: int, snapshot: Dictionary) -> bool:
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	var last_time: float = float(_last_sent_time_by_slot.get(slot, GameSettings.NETWORK_LAST_SHOT_INITIAL_TIME))
	if now_seconds - last_time >= 1.0 / GameSettings.NETWORK_PLAYER_HEARTBEAT_RATE:
		return true

	var previous_variant: Variant = _last_sent_by_slot.get(slot, {})
	if not (previous_variant is Dictionary):
		return true
	var previous: Dictionary = previous_variant

	var position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var previous_position: Vector2 = previous.get("position", position)
	if position.distance_squared_to(previous_position) >= GameSettings.NETWORK_PLAYER_POSITION_EPSILON * GameSettings.NETWORK_PLAYER_POSITION_EPSILON:
		return true

	var velocity: Vector2 = snapshot.get("velocity", Vector2.ZERO)
	var previous_velocity: Vector2 = previous.get("velocity", velocity)
	if velocity.distance_squared_to(previous_velocity) >= GameSettings.NETWORK_PLAYER_VELOCITY_EPSILON * GameSettings.NETWORK_PLAYER_VELOCITY_EPSILON:
		return true

	var aim: Vector2 = snapshot.get("aim", Vector2.ZERO)
	var previous_aim: Vector2 = previous.get("aim", aim)
	if aim.distance_squared_to(previous_aim) >= GameSettings.NETWORK_PLAYER_AIM_EPSILON * GameSettings.NETWORK_PLAYER_AIM_EPSILON:
		return true

	return int(snapshot.get("ammo", 0)) != int(previous.get("ammo", 0)) \
		or bool(snapshot.get("reloading", false)) != bool(previous.get("reloading", false))


func _remember_sent_snapshot(slot: int, snapshot: Dictionary) -> void:
	_last_sent_by_slot[slot] = snapshot.duplicate()
	_last_sent_time_by_slot[slot] = Time.get_ticks_msec() / 1000.0


func _apply_player_snapshot(slot: int, snapshot: Dictionary, packet_tick: int = 0) -> void:
	if packet_tick > 0:
		var last_tick: int = int(_last_received_tick_by_slot.get(slot, -1))
		if packet_tick <= last_tick:
			return
		_last_received_tick_by_slot[slot] = packet_tick

	var player: Player = _get_player(slot)
	if player == null:
		return

	player.apply_remote_snapshot(snapshot)


func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)
