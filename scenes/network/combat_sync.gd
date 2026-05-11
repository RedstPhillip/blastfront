extends "res://scenes/network/sync_module.gd"

const DEFAULT_HEALTH := 100
const PROJECTILE_DAMAGE := 1

var _health: Dictionary = {
	1: DEFAULT_HEALTH,
	2: DEFAULT_HEALTH,
}


func get_module_name() -> StringName:
	return &"combat"


func get_packet_types() -> Array[StringName]:
	return [&"player_hit", &"health_changed", &"player_killed"]


func setup(sync: Node, game_world: Node) -> void:
	game_sync = sync
	game = game_world
	_reset_health()


func apply_hit(target_slot: int, source_slot: int, projectile_id: int, damage: int = PROJECTILE_DAMAGE) -> void:
	if game_sync == null or not game_sync.is_host():
		return

	var new_health: int = _damage_player(target_slot, damage)
	_health[target_slot] = new_health

	game_sync.send_reliable(&"player_hit", {
		"target_slot": target_slot,
		"source_slot": source_slot,
		"projectile_id": projectile_id,
		"damage": damage,
	}, NetworkSession.CHANNEL_EVENTS)
	game_sync.send_reliable(&"health_changed", {
		"slot": target_slot,
		"health": new_health,
	}, NetworkSession.CHANNEL_EVENTS)

	if new_health <= 0:
		_handle_player_killed(target_slot, source_slot)


func _handle_player_killed(target_slot: int, source_slot: int) -> void:
	_reset_health()

	game_sync.send_reliable(&"health_changed", {
		"slot": 1,
		"health": DEFAULT_HEALTH,
	}, NetworkSession.CHANNEL_EVENTS)
	game_sync.send_reliable(&"health_changed", {
		"slot": 2,
		"health": DEFAULT_HEALTH,
	}, NetworkSession.CHANNEL_EVENTS)
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
	var payload: Dictionary = _get_payload(packet)
	match str(packet.get("type", "")):
		"health_changed":
			var slot: int = int(payload.get("slot", 0))
			var health: int = int(payload.get("health", DEFAULT_HEALTH))
			_health[slot] = health
			_set_player_health(slot, health)
		"player_hit":
			pass
		"player_killed":
			_reset_health()
			if game != null and game.has_method("respawn_players"):
				game.respawn_players()


func build_snapshot() -> Dictionary:
	return {"health": _health.duplicate()}


func apply_snapshot(data: Dictionary) -> void:
	var health_data: Variant = data.get("health", {})
	if health_data is Dictionary:
		_health = health_data.duplicate()
		for slot in _health.keys():
			_set_player_health(int(slot), int(_health[slot]))


func get_health(slot: int) -> int:
	return int(_health.get(slot, DEFAULT_HEALTH))


func _reset_health() -> void:
	_health[1] = DEFAULT_HEALTH
	_health[2] = DEFAULT_HEALTH
	for slot in [1, 2]:
		var player: Player = _get_player(slot)
		if player != null and player.health_component != null:
			player.health_component.max_health = DEFAULT_HEALTH
			player.health_component.health = DEFAULT_HEALTH


func _damage_player(slot: int, damage: int) -> int:
	var player: Player = _get_player(slot)
	if player != null and player.health_component != null:
		player.health_component.damage(damage)
		return player.health_component.health

	var current_health: int = int(_health.get(slot, DEFAULT_HEALTH))
	return maxi(current_health - damage, 0)


func _set_player_health(slot: int, health: int) -> void:
	var player: Player = _get_player(slot)
	if player != null and player.health_component != null:
		player.health_component.max_health = DEFAULT_HEALTH
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
