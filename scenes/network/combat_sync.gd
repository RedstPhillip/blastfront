extends "res://scenes/network/sync_module.gd"

const PROJECTILE_DAMAGE := 10


func get_module_name() -> StringName:
	return &"combat"


func get_packet_types() -> Array[StringName]:
	return [&"player_hit", &"health_changed", &"player_killed"]


func apply_hit(target_slot: int, source_slot: int, projectile_id: int, damage: int = PROJECTILE_DAMAGE) -> void:
	if game_sync == null or not game_sync.is_host():
		return

	var player: Player = _get_player(target_slot)
	if player == null or player.health_component == null:
		return

	player.health_component.damage(damage)
	var health := player.health_component.health

	game_sync.send_reliable(&"player_hit", {
		"target_slot": target_slot,
		"source_slot": source_slot,
		"projectile_id": projectile_id,
		"damage": damage,
	}, NetworkSession.CHANNEL_EVENTS)
	game_sync.send_reliable(&"health_changed", {
		"slot": target_slot,
		"health": health,
	}, NetworkSession.CHANNEL_EVENTS)

	if health <= 0:
		_handle_player_killed(target_slot, source_slot)


func _handle_player_killed(target_slot: int, source_slot: int) -> void:
	_heal_players()
	_broadcast_health_reset()
	game_sync.send_reliable(&"player_killed", {
		"target_slot": target_slot,
		"source_slot": source_slot,
	}, NetworkSession.CHANNEL_EVENTS)

	var round_sync = game_sync.get_module(&"round")
	if round_sync != null and round_sync.has_method("add_score"):
		round_sync.add_score(source_slot)

	if game != null and game.has_method("respawn_players"):
		game.respawn_players()


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	match str(packet.get("type", "")):
		"health_changed":
			var slot: int = int(payload.get("slot", 0))
			var health: int = int(payload.get("health", 0))
			_set_player_health(slot, health)
		"player_hit":
			pass
		"player_killed":
			_heal_players()
			if game != null and game.has_method("respawn_players"):
				game.respawn_players()


func build_snapshot() -> Dictionary:
	var health := {}
	for slot in [1, 2]:
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
	for slot in [1, 2]:
		var player: Player = _get_player(slot)
		if player != null and player.health_component != null:
			var max_health := player.health_component.max_health
			player.health_component.heal(max_health)


func _broadcast_health_reset() -> void:
	for slot in [1, 2]:
		var player: Player = _get_player(slot)
		var max_health := 100
		if player != null and player.health_component != null:
			max_health = player.health_component.max_health
		game_sync.send_reliable(&"health_changed", {
			"slot": slot,
			"health": max_health,
		}, NetworkSession.CHANNEL_EVENTS)


func _set_player_health(slot: int, health: int) -> void:
	var player: Player = _get_player(slot)
	if player != null and player.health_component != null:
		player.health_component.health = health


func _get_player(slot: int) -> Player:
	if game == null or not game.has_method("get_player_by_slot"):
		return null
	return game.get_player_by_slot(slot)


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}