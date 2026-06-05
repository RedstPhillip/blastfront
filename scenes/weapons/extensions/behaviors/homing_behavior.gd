class_name HomingBehavior
extends ExtensionBehavior


func update(projectile: Projectile, delta: float, effect_data: Dictionary = {}) -> void:
	var projectile_node: Node2D = projectile as Node2D
	if projectile_node == null:
		return

	var strength: float = float(effect_data.get("strength", 0.0))
	if strength <= 0.0:
		return

	var current_velocity_variant: Variant = projectile.get("velocity")
	if not (current_velocity_variant is Vector2):
		return

	var current_velocity: Vector2 = current_velocity_variant
	if current_velocity.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return

	var target: Player = _find_nearest_target(projectile_node, int(projectile.get("owner_slot")))
	if target == null:
		return

	var desired_velocity: Vector2 = projectile_node.global_position.direction_to(target.global_position) * current_velocity.length()
	projectile.set("velocity", current_velocity.lerp(desired_velocity, clampf(strength * delta, 0.0, 1.0)))


func _find_nearest_target(projectile: Node2D, owner_slot: int) -> Player:
	var tree: SceneTree = projectile.get_tree()
	if tree == null:
		return null

	var nearest_player: Player = null
	var nearest_distance_squared: float = INF
	var players: Array[Node] = tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP)
	for node in players:
		var player: Player = node as Player
		if player == null or int(player.player_slot) == owner_slot or player.is_eliminated():
			continue

		var distance_squared: float = projectile.global_position.distance_squared_to(player.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_player = player
	return nearest_player
