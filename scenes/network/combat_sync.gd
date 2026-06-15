extends "res://scenes/network/sync_module.gd"

const STATUS_EFFECT_PACKET_COALESCE_MSEC: int = 120

var _active_damage_over_time: Dictionary = {}
var _last_status_packet_msec: Dictionary = {}


func get_module_name() -> StringName:
	return GameSettings.MODULE_COMBAT


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_PLAYER_HIT,
		GameSettings.PACKET_HEALTH_CHANGED,
		GameSettings.PACKET_STATUS_EFFECT_APPLIED,
	]


func apply_hit(
	target_slot: int,
	source_slot: int,
	projectile_id: int,
	damage: int = GameSettings.PROJECTILE_DAMAGE,
	allow_delay: bool = true
) -> void:
	if game_sync == null or not game_sync.is_host():
		return
	if not OnlineMatch.is_playing_set():
		return

	var player: Player = _get_player(target_slot)
	if player == null or player.health_component == null:
		return

	var source_position: Vector2 = player.global_position - Vector2(player.last_dir * 64.0, 0.0)
	var source_player: Player = _get_player(source_slot)
	if source_player != null:
		source_position = source_player.global_position

	var modified_damage: int = damage
	if allow_delay:
		modified_damage = player.get_modified_incoming_damage(damage)
	var delay_duration: float = player.get_delayed_damage_duration()
	if allow_delay and delay_duration > 0.0 and modified_damage > 1:
		_run_delayed_hit(target_slot, source_slot, projectile_id, modified_damage, delay_duration)
		return

	var applied_damage: int = player.apply_resolved_damage(modified_damage, source_position)
	var health: int = player.health_component.health
	OnlineMatch.record_damage(source_slot, target_slot, applied_damage)
	_apply_life_steal(source_slot, applied_damage)
	_note_source_damage_dealt(source_slot, applied_damage)

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


func _run_delayed_hit(
	target_slot: int,
	source_slot: int,
	projectile_id: int,
	damage: int,
	duration: float
) -> void:
	var tick_count: int = maxi(1, int(ceil(duration)))
	var tick_interval: float = duration / float(tick_count)
	var remaining_damage: int = damage
	for tick_index in range(tick_count):
		if not OnlineMatch.is_playing_set():
			return
		var player: Player = _get_player(target_slot)
		if player == null or player.is_eliminated():
			return
		var ticks_left: int = tick_count - tick_index
		var tick_damage: int = maxi(1, int(roundf(float(remaining_damage) / float(ticks_left))))
		remaining_damage -= tick_damage
		apply_hit(target_slot, source_slot, projectile_id, tick_damage, false)
		if tick_index < tick_count - 1:
			await get_tree().create_timer(tick_interval, false).timeout


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


func _note_source_damage_dealt(source_slot: int, applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	var source_player: Player = _get_player(source_slot)
	if source_player != null:
		source_player.note_damage_dealt(applied_damage)


func _handle_player_killed(_target_slot: int, source_slot: int) -> void:
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
	var effect_key: String = _status_effect_key(target_slot, source_slot, effect_name)
	if _should_send_status_packet(effect_key):
		game_sync.send_reliable(GameSettings.PACKET_STATUS_EFFECT_APPLIED, {
			"target_slot": target_slot,
			"effect_name": str(effect_name),
			"effect_data": visual_data,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)

	if damage_per_tick > 0:
		var tick_interval: float = maxf(float(effect_data.get("tick_interval", 1.0)), 0.05)
		var tick_count: int = int(effect_data.get("tick_count", 1))
		_start_or_refresh_damage_over_time(
			effect_key,
			target_slot,
			source_slot,
			damage_per_tick,
			tick_interval,
			maxi(tick_count, 1)
		)


func _start_or_refresh_damage_over_time(
	effect_key: String,
	target_slot: int,
	source_slot: int,
	damage_per_tick: int,
	tick_interval: float,
	tick_count: int
) -> void:
	if _active_damage_over_time.has(effect_key):
		var active_state: Dictionary = _active_damage_over_time[effect_key]
		active_state["damage_per_tick"] = maxi(int(active_state.get("damage_per_tick", 0)), damage_per_tick)
		active_state["ticks_remaining"] = maxi(int(active_state.get("ticks_remaining", 0)), tick_count)
		_active_damage_over_time[effect_key] = active_state
		return

	_active_damage_over_time[effect_key] = {
		"target_slot": target_slot,
		"source_slot": source_slot,
		"damage_per_tick": damage_per_tick,
		"tick_interval": tick_interval,
		"ticks_remaining": tick_count,
	}
	_run_damage_over_time(effect_key)


func _run_damage_over_time(effect_key: String) -> void:
	while _active_damage_over_time.has(effect_key):
		var wait_state: Dictionary = _active_damage_over_time[effect_key]
		var tick_interval: float = maxf(float(wait_state.get("tick_interval", 1.0)), 0.05)
		await get_tree().create_timer(tick_interval, false).timeout

		if not _active_damage_over_time.has(effect_key):
			return
		if not OnlineMatch.is_playing_set():
			_clear_damage_over_time(effect_key)
			return
		var active_state: Dictionary = _active_damage_over_time[effect_key]
		var target_slot: int = int(active_state.get("target_slot", 0))
		var source_slot: int = int(active_state.get("source_slot", 0))
		var player: Player = _get_player(target_slot)
		if player == null or player.is_eliminated():
			_clear_damage_over_time(effect_key)
			return
		var damage_per_tick: int = int(active_state.get("damage_per_tick", 0))
		var modified_damage: int = ResearchManager.apply_rage_to_damage(source_slot, damage_per_tick)
		apply_hit(target_slot, source_slot, 0, modified_damage)
		var ticks_remaining: int = int(active_state.get("ticks_remaining", 1)) - 1
		if ticks_remaining <= 0:
			_clear_damage_over_time(effect_key)
			return
		active_state["ticks_remaining"] = ticks_remaining
		_active_damage_over_time[effect_key] = active_state


func _status_effect_key(target_slot: int, source_slot: int, effect_name: StringName) -> String:
	return "%d:%d:%s" % [target_slot, source_slot, str(effect_name)]


func _should_send_status_packet(effect_key: String) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_status_packet_msec.get(effect_key, -STATUS_EFFECT_PACKET_COALESCE_MSEC))
	if now_msec - last_msec < STATUS_EFFECT_PACKET_COALESCE_MSEC:
		return false
	_last_status_packet_msec[effect_key] = now_msec
	return true


func _clear_damage_over_time(effect_key: String) -> void:
	_active_damage_over_time.erase(effect_key)
	_last_status_packet_msec.erase(effect_key)


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = _get_payload(packet)
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_PLAYER_HIT:
		var target_slot: int = int(payload.get("target_slot", 0))
		var source_slot: int = int(payload.get("source_slot", 0))
		var damage: int = int(payload.get("damage", GameSettings.PROJECTILE_DAMAGE))
		_apply_remote_hit_feedback(target_slot, source_slot, damage)
		_note_source_damage_dealt(source_slot, damage)
	elif packet_type == GameSettings.PACKET_HEALTH_CHANGED:
		var slot: int = int(payload.get("slot", 0))
		var health: int = int(payload.get("health", 0))
		_set_player_health(slot, health)
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
	if game == null:
		return null
	return game.get_player_by_slot(slot)
