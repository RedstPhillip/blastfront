extends "res://scenes/network/sync_module.gd"

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

var _next_projectile_id: int = GameSettings.NETWORK_FIRST_PROJECTILE_ID
var _projectiles: Dictionary = {}
var _last_shot_time_by_slot: Dictionary = {}


func get_module_name() -> StringName:
	return GameSettings.MODULE_PROJECTILE


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_SHOT_REQUEST,
		GameSettings.PACKET_PROJECTILE_SPAWNED,
		GameSettings.PACKET_PROJECTILE_DESPAWNED,
		GameSettings.PACKET_PROJECTILE_SNAPSHOT,
	]


func request_shot(owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	if game_sync == null or not game_sync.is_network_active():
		_spawn_projectile(0, owner_slot, spawn_position, direction, projectile_data, true)
		return

	if game_sync.is_host():
		_spawn_authoritative_projectile_for_owner(owner_slot, spawn_position, direction, projectile_data)
	else:
		game_sync.send_reliable(GameSettings.PACKET_SHOT_REQUEST, {
			"owner_slot": owner_slot,
			"request_tick": game_sync.tick,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = _get_payload(packet)

	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_SHOT_REQUEST:
		if not game_sync.is_host():
			return
		var owner_slot: int = int(packet.get("from_slot", payload.get("owner_slot", game_sync.get_remote_slot())))
		if owner_slot != game_sync.get_remote_slot():
			owner_slot = game_sync.get_remote_slot()
		_spawn_authoritative_projectile_for_owner(owner_slot)
	elif packet_type == GameSettings.PACKET_PROJECTILE_SPAWNED:
		_apply_projectile_spawn(payload)
	elif packet_type == GameSettings.PACKET_PROJECTILE_DESPAWNED:
		_apply_projectile_despawn(payload)
	elif packet_type == GameSettings.PACKET_PROJECTILE_SNAPSHOT:
		apply_snapshot(payload)


func build_snapshot() -> Dictionary:
	if game_sync == null or not game_sync.is_host() or _projectiles.is_empty():
		return {}

	return {"projectiles": _build_projectile_snapshots()}


func apply_snapshot(data: Dictionary) -> void:
	var snapshots: Variant = data.get("projectiles", [])
	if not (snapshots is Array):
		return

	for snapshot in snapshots:
		if not (snapshot is Dictionary):
			continue

		var net_id: int = int(snapshot.get("net_id", 0))
		var projectile: Node = _projectiles.get(net_id, null) as Node
		if projectile == null:
			continue

		if projectile.has_method("apply_network_snapshot"):
			projectile.call("apply_network_snapshot", snapshot)


func _spawn_authoritative_projectile_for_owner(
	owner_slot: int,
	fallback_spawn_position: Vector2 = Vector2.ZERO,
	fallback_direction: Vector2 = Vector2.LEFT,
	fallback_projectile_data: Dictionary = {}
) -> void:
	var shot_data: Dictionary = _build_authoritative_shot(owner_slot)
	var spawn_position: Vector2 = fallback_spawn_position
	var direction: Vector2 = fallback_direction
	var fire_interval: float = 0.0
	var projectile_data: Dictionary = fallback_projectile_data

	if not shot_data.is_empty():
		var spawn_position_variant: Variant = shot_data.get("spawn_position", spawn_position)
		if spawn_position_variant is Vector2:
			spawn_position = spawn_position_variant

		var direction_variant: Variant = shot_data.get("direction", direction)
		if direction_variant is Vector2:
			var shot_direction: Vector2 = direction_variant
			if shot_direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
				direction = shot_direction.normalized()

		var projectile_data_variant: Variant = shot_data.get("projectile", projectile_data)
		if projectile_data_variant is Dictionary:
			projectile_data = projectile_data_variant

		var fire_interval_variant: Variant = shot_data.get("fire_interval", fire_interval)
		if fire_interval_variant is float or fire_interval_variant is int:
			fire_interval = maxf(float(fire_interval_variant), 0.0)

	if projectile_data.is_empty():
		return

	if not _can_authoritative_shoot(owner_slot, fire_interval):
		return

	var net_id: int = _next_projectile_id
	_next_projectile_id += 1

	_spawn_projectile(net_id, owner_slot, spawn_position, direction, projectile_data, true)
	game_sync.send_reliable(GameSettings.PACKET_PROJECTILE_SPAWNED, {
		"net_id": net_id,
		"owner_slot": owner_slot,
		"spawn_position": spawn_position,
		"direction": direction,
		"projectile": projectile_data,
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _build_authoritative_shot(owner_slot: int) -> Dictionary:
	if game == null or not game.has_method("build_authoritative_shot"):
		return {}

	var shot_data_variant: Variant = game.call("build_authoritative_shot", owner_slot)
	if shot_data_variant is Dictionary:
		return shot_data_variant
	return {}


func _can_authoritative_shoot(owner_slot: int, fire_interval: float) -> bool:
	if fire_interval <= 0.0:
		return true

	var now_seconds: float = Time.get_ticks_msec() / GameSettings.MILLISECONDS_PER_SECOND
	var last_shot_time: float = float(_last_shot_time_by_slot.get(owner_slot, GameSettings.NETWORK_LAST_SHOT_INITIAL_TIME))
	if now_seconds - last_shot_time < fire_interval:
		return false

	_last_shot_time_by_slot[owner_slot] = now_seconds
	return true


func _apply_projectile_spawn(payload: Dictionary) -> void:
	var net_id: int = int(payload.get("net_id", 0))
	if net_id == 0 or _projectiles.has(net_id):
		return

	var spawn_position: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.LEFT
	var projectile_data: Dictionary = {}

	var spawn_position_variant: Variant = payload.get("spawn_position", spawn_position)
	if spawn_position_variant is Vector2:
		spawn_position = spawn_position_variant

	var direction_variant: Variant = payload.get("direction", direction)
	if direction_variant is Vector2:
		var spawned_direction: Vector2 = direction_variant
		if spawned_direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
			direction = spawned_direction.normalized()

	var projectile_data_variant: Variant = payload.get("projectile", {})
	if projectile_data_variant is Dictionary:
		projectile_data = projectile_data_variant

	_spawn_projectile(
		net_id,
		int(payload.get("owner_slot", 0)),
		spawn_position,
		direction,
		projectile_data,
		false
	)


func _apply_projectile_despawn(payload: Dictionary) -> void:
	var net_id: int = int(payload.get("net_id", 0))
	var projectile: Node = _projectiles.get(net_id, null) as Node
	if projectile != null:
		projectile.queue_free()
	_projectiles.erase(net_id)


func _spawn_projectile(net_id: int, owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary, authority: bool) -> Node:
	if game == null or not game.has_method("spawn_projectile"):
		return null

	var projectile: Node2D = PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("net_id", net_id)
	projectile.set("owner_slot", owner_slot)
	projectile.set("is_network_authority", authority)
	projectile.set("direction", direction)
	var muzzle_speed: float = float(projectile_data.get("muzzle_speed", projectile.get("muzzle_speed")))
	projectile.set("muzzle_speed", muzzle_speed)
	projectile.set("gravity", float(projectile_data.get("gravity", projectile.get("gravity"))))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile.get("linear_damping"))))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile.get("max_distance"))))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * muzzle_speed))

	if not authority:
		projectile.set("collision_mask", GameSettings.PROJECTILE_REMOTE_COLLISION_MASK)

	if net_id != 0:
		_projectiles[net_id] = projectile
		projectile.connect("tree_exited", Callable(self, "_on_projectile_tree_exited").bind(net_id))
		if projectile.has_signal("despawn_requested"):
			projectile.connect("despawn_requested", Callable(self, "_on_projectile_despawn_requested").bind(net_id))

	game.spawn_projectile(projectile, spawn_position)
	return projectile


func _on_projectile_despawn_requested(projectile: Node, reason: StringName, collider, net_id: int) -> void:
	if game_sync == null or not game_sync.is_host() or net_id == 0:
		return

	var hit_player: Player = collider as Player
	if hit_player != null and int(hit_player.player_slot) != int(projectile.get("owner_slot")):
		var combat_sync: Variant = game_sync.get_module(GameSettings.MODULE_COMBAT)
		if combat_sync != null and combat_sync.has_method("apply_hit"):
			combat_sync.call("apply_hit", int(hit_player.player_slot), int(projectile.get("owner_slot")), net_id)

	game_sync.send_reliable(GameSettings.PACKET_PROJECTILE_DESPAWNED, {
		"net_id": net_id,
		"reason": str(reason),
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _on_projectile_tree_exited(net_id: int) -> void:
	_projectiles.erase(net_id)


func _build_projectile_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for net_id in _projectiles.keys():
		var projectile: Node2D = _projectiles[net_id] as Node2D
		if projectile == null or not is_instance_valid(projectile):
			continue

		snapshots.append({
			"net_id": int(net_id),
			"position": projectile.global_position,
			"velocity": projectile.get("velocity"),
			"rotation": projectile.global_rotation,
		})
	return snapshots


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
