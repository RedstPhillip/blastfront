class_name ExplosiveEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Node = null) -> void:
	if target == null:
		return

	var origin: Vector2 = target.global_position
	if projectile != null:
		var proj: Node = projectile
		origin = proj.get("global_position")

	var radius: float = float(effect_data.get("radius", 80.0))
	var splash_damage: int = int(effect_data.get("splash_damage", effect_data.get("damage_per_hit", 0)))
	if splash_damage <= 0:
		splash_damage = int(effect_data.get("damage", 10))

	var tree: SceneTree = target.get_tree()
	if tree == null:
		return

	var players: Array[Node] = tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP)
	for node in players:
		var player: Player = node as Player
		if player == null or player.is_eliminated():
			continue

		var dist: float = player.global_position.distance_to(origin)
		if dist > radius:
			continue

		var falloff: float = 1.0 - (dist / radius)
		var final_damage: int = maxi(1, int(roundf(splash_damage * falloff)))
		player.health_component.damage(final_damage)
		player.apply_hit_feedback(origin, final_damage)
