extends "res://scenes/network/sync_module.gd"

func get_module_name() -> StringName:
	return GameSettings.MODULE_COMBAT


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_PLAYER_HIT,
		GameSettings.PACKET_HEALTH_CHANGED,
		GameSettings.PACKET_PLAYER_KILLED,
		GameSettings.PACKET_STATUS_EFFECT_APPLIED,
	]


func apply_hit(target_slot: int, source_slot: int, projectile_id: int, damage: int = GameSettings.PROJECTILE_DAMAGE) -> void:
	if game_sync == null or not game_sync.is_host():
		return
	if not OnlineMatch.is_playing_set():
		return

	var player: Player = _get_player(target_slot)
	if player == null or player.health_component == null:
		return

	var old_health: int = player.health_component.health
	player.health_component.damage(damage)
	var health: int = player.health_component.health
	var applied_damage: int = mini(maxi(damage, 0), old_health)
	OnlineMatch.record_damage(source_slot, target_slot, applied_damage)
	_apply_life_steal(source_slot, applied_damage)

	game_sync.send_reliable(GameSettings.PACKET_PLAYER_HIT, {
		"target_slot": target_slot,
		"source_slot": source_slot,
		"projectile_id": projectile_id,
		"damage": applied_damage,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)
	game_sync.send_reliable(GameSettings.PACKET_HEALTH_CHANGED, {
		"slot": target_slot,
		"health": health,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)

	if health <= 0:
		_handle_player_killed(target_slot, source_slot)


func _apply_life_steal(source_slot: int, applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	var ratio: float = ResearchManager.get_life_steal_ratio(source_slot)
	if ratio <= 0.0:
		return
	var source_player: Player = _get_player(source_slot)
	if source_player == null or source_player.health_component == null or source_player.is_eliminated():
		return
	var heal_amount: int = maxi(1, int(roundf(float(applied_damage) * ratio)))
	var old_health: int = source_player.health_component.health
	source_player.health_component.heal(heal_amount)
	if source_player.health_component.health == old_health:
		return
	game_sync.send_reliable(GameSettings.PACKET_HEALTH_CHANGED, {
		"slot": source_slot,
		"health": source_player.health_component.health,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _handle_player_killed(target_slot: int, source_slot: int) -> void:
	game_sync.send_reliable(GameSettings.PACKET_PLAYER_KILLED, {
		"target_slot": target_slot,
		"source_slot": source_slot,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)
	OnlineMatch.record_kill(source_slot)


func apply_status_effect(target_slot: int, source_slot: int, effect_name: StringName, effect_data: Dictionary) -> void:
	if game_sync == null or not game_sync.is_host():
		return
	if not OnlineMatch.is_playing_set():
		return

	var player: Player = _get_player(target_slot)
	if player == null or player.status_effect_manager == null:
		return

	var visual_data: Dictionary = effect_data.duplicate(true)
	var damage_per_tick: int = int(visual_data.get("damage_per_tick", 0))
	visual_data.erase("damage_per_tick")
	player.status_effect_manager.apply_effect(effect_name, visual_data)
	game_sync.send_reliable(GameSettings.PACKET_STATUS_EFFECT_APPLIED, {
		"target_slot": target_slot,
		"effect_name": str(effect_name),
		"effect_data": visual_data,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)

	if damage_per_tick > 0:
		var tick_interval: float = maxf(float(effect_data.get("tick_interval", 1.0)), 0.05)
		var tick_count: int = int(effect_data.get("tick_count", 1))
		_run_damage_over_time(target_slot, source_slot, damage_per_tick, tick_interval, maxi(tick_count, 1))


func _run_damage_over_time(
	target_slot: int,
	source_slot: int,
	damage_per_tick: int,
	tick_interval: float,
	tick_count: int
) -> void:
	for tick_index in range(tick_count):
		if not OnlineMatch.is_playing_set():
			return
		var player: Player = _get_player(target_slot)
		if player == null or player.is_eliminated():
			return
		var modified_damage: int = ResearchManager.apply_rage_to_damage(source_slot, damage_per_tick)
		apply_hit(target_slot, source_slot, 0, modified_damage)
		if tick_index < tick_count - 1:
			await get_tree().create_timer(tick_interval, false).timeout


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_PLAYER_HIT:
		var target_slot: int = int(payload.get("target_slot", 0))
		var source_slot: int = int(payload.get("source_slot", 0))
		var damage: int = int(payload.get("damage", GameSettings.PROJECTILE_DAMAGE))
		_apply_remote_hit_feedback(target_slot, source_slot, damage)
	elif packet_type == GameSettings.PACKET_HEALTH_CHANGED:
		var slot: int = int(payload.get("slot", 0))
		var health: int = int(payload.get("health", 0))
		_set_player_health(slot, health)
	elif packet_type == GameSettings.PACKET_PLAYER_KILLED:
		pass
	elif packet_type == GameSettings.PACKET_STATUS_EFFECT_APPLIED:
		var target_slot: int = int(payload.get("target_slot", 0))
		var effect_name: StringName = StringName(str(payload.get("effect_name", "")))
		var effect_data_variant: Variant = payload.get("effect_data", {})
		if effect_data_variant is Dictionary:
			var effect_data: Dictionary = effect_data_variant
			_apply_remote_status_effect(target_slot, effect_name, effect_data)


func build_snapshot() -> Dictionary:
	var health: Dictionary = {}
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player != null and player.health_component != null:
			health[slot] = player.health_component.health
	return {"health": health}


func apply_snapshot(data: Dictionary) -> void:
	var health_data: Variant = data.get("health", {})
	if health_data is Dictionary:
		for slot in health_data.keys():
			_set_player_health(int(slot), int(health_data[slot]))


func get_health(slot: int) -> int:
	var player: Player = _get_player(slot)
	if player != null and player.health_component != null:
		return player.health_component.health
	return 0


func _heal_players() -> void:
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player != null and player.health_component != null:
			var max_health := player.health_component.max_health
			player.health_component.heal(max_health)


func _broadcast_health_reset() -> void:
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		var max_health: int = GameSettings.DEFAULT_MAX_HEALTH
		if player != null and player.health_component != null:
			max_health = player.health_component.max_health
		game_sync.send_reliable(GameSettings.PACKET_HEALTH_CHANGED, {
			"slot": slot,
			"health": max_health,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _set_player_health(slot: int, health: int) -> void:
	var player: Player = _get_player(slot)
	if player != null and player.health_component != null:
		player.health_component.health = health


func _apply_remote_hit_feedback(target_slot: int, source_slot: int, damage: int) -> void:
	var target_player: Player = _get_player(target_slot)
	if target_player == null:
		return

	var source_position: Vector2 = target_player.global_position - Vector2(target_player.last_dir * 64.0, 0.0)
	var source_player: Player = _get_player(source_slot)
	if source_player != null:
		source_position = source_player.global_position
	target_player.apply_hit_feedback(source_position, damage)


func _apply_remote_status_effect(target_slot: int, effect_name: StringName, effect_data: Dictionary) -> void:
	var target_player: Player = _get_player(target_slot)
	if target_player == null or target_player.status_effect_manager == null:
		return
	target_player.status_effect_manager.apply_effect(effect_name, effect_data)


func _get_player(slot: int) -> Player:
	if game == null or not game.has_method("get_player_by_slot"):
		return null
	return game.get_player_by_slot(slot)


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
