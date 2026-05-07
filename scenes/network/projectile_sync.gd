extends "res://scenes/network/sync_module.gd"

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

var _next_projectile_id := 1
var _projectiles := {}


func get_module_name() -> StringName:
	return &"projectile"


func get_packet_types() -> Array[StringName]:
	return [&"shot_request", &"projectile_spawned", &"projectile_despawned", &"projectile_snapshot"]


func request_shot(owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	if game_sync == null or not game_sync.is_network_active():
		_spawn_projectile(0, owner_slot, spawn_position, direction, projectile_data, true)
		return

	if game_sync.is_host():
		_spawn_authoritative_projectile(owner_slot, spawn_position, direction, projectile_data)
	else:
		game_sync.send_reliable(&"shot_request", {
			"owner_slot": owner_slot,
			"spawn_position": spawn_position,
			"direction": direction,
			"projectile": projectile_data,
		}, NetworkSession.CHANNEL_EVENTS)


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)

	match str(packet.get("type", "")):
		"shot_request":
			if not game_sync.is_host():
				return
			var owner_slot := int(packet.get("from_slot", payload.get("owner_slot", 0)))
			_spawn_authoritative_projectile(
				owner_slot,
				payload.get("spawn_position", Vector2.ZERO),
				payload.get("direction", Vector2.LEFT),
				payload.get("projectile", {})
			)
		"projectile_spawned":
			_apply_projectile_spawn(payload)
		"projectile_despawned":
			_apply_projectile_despawn(payload)
		"projectile_snapshot":
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

		var net_id := int(snapshot.get("net_id", 0))
		var projectile = _projectiles.get(net_id, null)
		if projectile == null:
			continue

		if projectile.has_method("apply_network_snapshot"):
			projectile.call("apply_network_snapshot", snapshot)


func _spawn_authoritative_projectile(owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var net_id := _next_projectile_id
	_next_projectile_id += 1

	_spawn_projectile(net_id, owner_slot, spawn_position, direction, projectile_data, true)
	game_sync.send_reliable(&"projectile_spawned", {
		"net_id": net_id,
		"owner_slot": owner_slot,
		"spawn_position": spawn_position,
		"direction": direction,
		"projectile": projectile_data,
	}, NetworkSession.CHANNEL_EVENTS)


func _apply_projectile_spawn(payload: Dictionary) -> void:
	var net_id := int(payload.get("net_id", 0))
	if net_id == 0 or _projectiles.has(net_id):
		return

	_spawn_projectile(
		net_id,
		int(payload.get("owner_slot", 0)),
		payload.get("spawn_position", Vector2.ZERO),
		payload.get("direction", Vector2.LEFT),
		payload.get("projectile", {}),
		false
	)


func _apply_projectile_despawn(payload: Dictionary) -> void:
	var net_id := int(payload.get("net_id", 0))
	var projectile = _projectiles.get(net_id, null)
	if projectile != null:
		projectile.queue_free()
	_projectiles.erase(net_id)


func _spawn_projectile(net_id: int, owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary, authority: bool) -> Node:
	if game == null or not game.has_method("spawn_projectile"):
		return null

	var projectile := PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("net_id", net_id)
	projectile.set("owner_slot", owner_slot)
	projectile.set("is_network_authority", authority)
	projectile.set("direction", direction)
	var muzzle_speed := float(projectile_data.get("muzzle_speed", projectile.get("muzzle_speed")))
	projectile.set("muzzle_speed", muzzle_speed)
	projectile.set("gravity", float(projectile_data.get("gravity", projectile.get("gravity"))))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile.get("linear_damping"))))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile.get("max_distance"))))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * muzzle_speed))

	if not authority:
		projectile.set("collision_mask", 0)

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

	if collider is Player and int(collider.player_slot) != int(projectile.get("owner_slot")):
		var combat_sync = game_sync.get_module(&"combat")
		if combat_sync != null and combat_sync.has_method("apply_hit"):
			combat_sync.call("apply_hit", int(collider.player_slot), int(projectile.get("owner_slot")), net_id)

	game_sync.send_reliable(&"projectile_despawned", {
		"net_id": net_id,
		"reason": str(reason),
	}, NetworkSession.CHANNEL_EVENTS)


func _on_projectile_tree_exited(net_id: int) -> void:
	_projectiles.erase(net_id)


func _build_projectile_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for net_id in _projectiles.keys():
		var projectile := _projectiles[net_id] as Node2D
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
