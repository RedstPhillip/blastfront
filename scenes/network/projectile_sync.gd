extends "res://scenes/network/sync_module.gd"

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/projectile.tscn")

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
			"spawn_position": spawn_position,
			"direction": direction,
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
		_spawn_authoritative_projectile_for_owner(
			owner_slot,
			_get_vector2(payload, "spawn_position", Vector2.ZERO),
			_get_vector2(payload, "direction", Vector2.LEFT),
			{}
		)
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
		var projectile: Projectile = _projectiles.get(net_id, null) as Projectile
		if projectile == null:
			continue

		projectile.apply_network_snapshot(snapshot)


func _spawn_authoritative_projectile_for_owner(
	owner_slot: int,
	fallback_spawn_position: Vector2 = Vector2.ZERO,
	fallback_direction: Vector2 = Vector2.LEFT,
	fallback_projectile_data: Dictionary = {}
) -> void:
	var shot_data: Dictionary = _build_authoritative_shot(owner_slot)
	var spawn_position: Vector2 = fallback_spawn_position
	var direction: Vector2 = fallback_direction
	var directions: Array[Vector2] = []
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

		var directions_variant: Variant = shot_data.get("directions", [])
		if directions_variant is Array:
			var raw_directions: Array = directions_variant
			for raw_direction in raw_directions:
				if raw_direction is Vector2:
					var volley_direction: Vector2 = raw_direction
					if volley_direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
						directions.append(volley_direction.normalized())

		var projectile_data_variant: Variant = shot_data.get("projectile", projectile_data)
		if projectile_data_variant is Dictionary:
			projectile_data = projectile_data_variant

		var fire_interval_variant: Variant = shot_data.get("fire_interval", fire_interval)
		if fire_interval_variant is float or fire_interval_variant is int:
			fire_interval = maxf(float(fire_interval_variant), 0.0)

		var sanitized_pose: Dictionary = _sanitize_requested_shot_pose(
			owner_slot,
			fallback_spawn_position,
			fallback_direction
		)
		if not sanitized_pose.is_empty():
			var requested_spawn: Variant = sanitized_pose.get("spawn_position", spawn_position)
			var requested_direction: Variant = sanitized_pose.get("direction", direction)
			if requested_spawn is Vector2:
				spawn_position = requested_spawn
			if requested_direction is Vector2:
				var fresh_direction: Vector2 = requested_direction
				directions = _reorient_authoritative_directions(directions, direction, fresh_direction)
				direction = fresh_direction

	if projectile_data.is_empty():
		return

	if not _can_authoritative_shoot(owner_slot, fire_interval):
		return

	if directions.is_empty():
		directions = Projectile.extract_shot_directions(projectile_data, direction)
	for shot_direction in directions:
		var net_id: int = _next_projectile_id
		_next_projectile_id += 1
		var shot_projectile_data: Dictionary = projectile_data.duplicate(true)
		shot_projectile_data.erase("volley_directions")
		shot_projectile_data["initial_velocity"] = shot_direction * float(shot_projectile_data.get("muzzle_speed", GameSettings.PROJECTILE_MUZZLE_SPEED))
		_spawn_projectile(net_id, owner_slot, spawn_position, shot_direction, shot_projectile_data, true)
		game_sync.send_reliable(GameSettings.PACKET_PROJECTILE_SPAWNED, {
			"net_id": net_id,
			"owner_slot": owner_slot,
			"spawn_position": spawn_position,
			"direction": shot_direction,
			"projectile": shot_projectile_data,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _sanitize_requested_shot_pose(owner_slot: int, spawn_position: Vector2, direction: Vector2) -> Dictionary:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return {}

	var owner: Player = _get_player(owner_slot)
	if owner == null:
		return {}

	var tolerance: float = GameSettings.NETWORK_SHOT_SPAWN_TOLERANCE
	if spawn_position.distance_squared_to(owner.global_position) > tolerance * tolerance:
		return {}

	return {
		"spawn_position": spawn_position,
		"direction": direction.normalized(),
	}


func _reorient_authoritative_directions(
	authoritative_directions: Array[Vector2],
	authoritative_base_direction: Vector2,
	requested_base_direction: Vector2
) -> Array[Vector2]:
	var requested_directions: Array[Vector2] = []
	if authoritative_base_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return requested_directions
	if requested_base_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return requested_directions

	var authoritative_base: Vector2 = authoritative_base_direction.normalized()
	var requested_base: Vector2 = requested_base_direction.normalized()
	for shot_direction in authoritative_directions:
		if shot_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
			continue
		var angle_offset: float = authoritative_base.angle_to(shot_direction.normalized())
		requested_directions.append(requested_base.rotated(angle_offset).normalized())
	return requested_directions


func _get_vector2(data: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var value: Variant = data.get(key, fallback)
	if value is Vector2:
		return value
	return fallback


func _build_authoritative_shot(owner_slot: int) -> Dictionary:
	if game == null:
		return {}

	var shot_data_variant: Variant = game.build_authoritative_shot(owner_slot)
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
	if game == null:
		return null

	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	projectile.configure_from_data(net_id, owner_slot, direction, projectile_data, authority)

	if not authority:
		projectile.collision_mask = _remote_projectile_collision_mask(projectile_data)

	if net_id != 0:
		_projectiles[net_id] = projectile
		projectile.tree_exited.connect(_on_projectile_tree_exited.bind(net_id))
		projectile.despawn_requested.connect(_on_projectile_despawn_requested.bind(net_id))

	game.spawn_projectile(projectile, spawn_position)
	return projectile


func _remote_projectile_collision_mask(projectile_data: Dictionary) -> int:
	var tags_variant: Variant = projectile_data.get("extension_tags", [])
	if tags_variant is Array:
		var tags: Array = tags_variant
		if tags.has("bouncy"):
			return 1
	return GameSettings.PROJECTILE_REMOTE_COLLISION_MASK


func _on_projectile_despawn_requested(projectile: Node, reason: StringName, collider, net_id: int) -> void:
	var shot: Projectile = projectile as Projectile
	if game_sync == null or not game_sync.is_host() or net_id == 0 or shot == null:
		return

	var hit_player: Player = collider as Player
	if hit_player != null and reason == &"blocked" and hit_player.player_slot != shot.owner_slot:
		OnlineMatch.record_block(hit_player.player_slot, shot.damage)
	if hit_player != null and reason != &"blocked" and hit_player.player_slot != shot.owner_slot:
		var combat_sync: Variant = game_sync.get_module(GameSettings.MODULE_COMBAT)
		if combat_sync != null:
			combat_sync.apply_hit(hit_player.player_slot, shot.owner_slot, net_id, shot.damage)
	if reason == &"collision":
		_apply_authoritative_extension_effects(shot, hit_player)

	game_sync.send_reliable(GameSettings.PACKET_PROJECTILE_DESPAWNED, {
		"net_id": net_id,
		"reason": str(reason),
	}, GameSettings.NETWORK_CHANNEL_EVENTS)


func _apply_authoritative_extension_effects(projectile: Projectile, direct_target: Player) -> void:
	var effects: Dictionary = projectile.extension_effects
	var owner_slot: int = projectile.owner_slot
	var source_extensions_variant: Variant = projectile.source_extensions
	var origin: Vector2 = _get_projectile_position(projectile, direct_target.global_position if direct_target != null else Vector2.ZERO)
	var combat_sync: Variant = game_sync.get_module(GameSettings.MODULE_COMBAT)
	if combat_sync == null:
		return

	for raw_effect_name in effects.keys():
		var effect_name: StringName = StringName(str(raw_effect_name))
		var effect_data_variant: Variant = effects[raw_effect_name]
		if not (effect_data_variant is Dictionary):
			continue
		var raw_effect_data: Dictionary = effect_data_variant
		var effect_data: Dictionary = _get_balanced_status_effect_data(
			effect_name,
			raw_effect_data,
			source_extensions_variant
		)
		match effect_name:
			&"freeze", &"shock", &"poison":
				if direct_target != null:
					combat_sync.apply_status_effect(direct_target.player_slot, owner_slot, effect_name, effect_data)
			&"explosive":
				_apply_area_damage(
					origin,
					owner_slot,
					float(effect_data.get("radius", 80.0)),
					int(effect_data.get("splash_damage", effect_data.get("damage", GameSettings.PROJECTILE_DAMAGE)))
				)
			&"grenade":
				_schedule_grenade_explosion(origin, owner_slot, effect_data)


func _get_balanced_status_effect_data(
	effect_name: StringName,
	effect_data: Dictionary,
	source_extensions_variant: Variant
) -> Dictionary:
	var balanced_data: Dictionary = effect_data.duplicate(true)
	if effect_name != &"poison" or not (source_extensions_variant is Array):
		return balanced_data

	var source_extensions: Array = source_extensions_variant
	if not source_extensions.has("shotgun_mk1"):
		return balanced_data

	var base_damage_per_tick: int = int(balanced_data.get("damage_per_tick", 0))
	var base_tick_count: int = int(balanced_data.get("tick_count", 1))
	balanced_data["damage_per_tick"] = clampi(base_damage_per_tick, 0, 8)
	balanced_data["tick_count"] = mini(base_tick_count, 3)
	balanced_data["duration"] = minf(float(balanced_data.get("duration", 3.0)), 3.0)
	return balanced_data


func _schedule_grenade_explosion(origin: Vector2, owner_slot: int, effect_data: Dictionary) -> void:
	var delay: float = maxf(float(effect_data.get("delay", 0.5)), 0.0)
	var radius: float = float(effect_data.get("radius", 80.0))
	var damage: int = int(effect_data.get("damage_per_hit", effect_data.get("damage", GameSettings.PROJECTILE_DAMAGE)))
	await get_tree().create_timer(delay, false).timeout
	if game_sync == null or not game_sync.is_host() or not OnlineMatch.is_playing_set():
		return
	_apply_area_damage(origin, owner_slot, radius, damage)


func _apply_area_damage(origin: Vector2, owner_slot: int, radius: float, damage: int) -> void:
	if game == null or radius <= 0.0 or damage <= 0:
		return
	var combat_sync: Variant = game_sync.get_module(GameSettings.MODULE_COMBAT)
	if combat_sync == null:
		return
	GameJuice.spawn_burst(&"impact", origin, Vector2.UP, Color(1.0, 0.42, 0.08, 0.95))
	GameJuice.shake(2.6, 0.12)
	for target_slot in GameSettings.player_slots():
		if target_slot == owner_slot:
			continue
		var player: Player = _get_player(target_slot)
		if player == null or player.is_eliminated():
			continue
		var distance: float = player.global_position.distance_to(origin)
		if distance > radius:
			continue
		var falloff: float = 1.0 - distance / radius
		var base_damage: int = maxi(1, int(roundf(float(damage) * falloff)))
		var final_damage: int = ResearchManager.apply_rage_to_damage(owner_slot, base_damage)
		combat_sync.apply_hit(target_slot, owner_slot, 0, final_damage)


func _get_projectile_position(projectile: Projectile, _fallback: Vector2) -> Vector2:
	return projectile.global_position


func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)


func _on_projectile_tree_exited(net_id: int) -> void:
	_projectiles.erase(net_id)


func _build_projectile_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for net_id in _projectiles.keys():
		var projectile: Projectile = _projectiles[net_id] as Projectile
		if projectile == null or not is_instance_valid(projectile):
			continue

		snapshots.append({
			"net_id": int(net_id),
			"position": projectile.global_position,
			"velocity": projectile.velocity,
			"rotation": projectile.global_rotation,
		})
	return snapshots
