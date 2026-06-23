class_name ExplosiveEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Projectile) -> void:
	var origin: Vector2 = projectile.global_position
	var radius: float = float(effect_data.get("radius", 80.0))
	var splash_damage: int = int(effect_data.get("splash_damage", effect_data.get("damage_per_hit", 0)))
	if splash_damage <= 0:
		splash_damage = int(effect_data.get("damage", GameSettings.PROJECTILE_DAMAGE))

	var tree: SceneTree = projectile.get_tree()
	if tree == null:
		return
	var owner_slot: int = projectile.owner_slot

	var players: Array[Node] = tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP)
	for node in players:
		var player: Player = node as Player
		if player == null or player.is_eliminated():
			continue
		if owner_slot > 0 and player.player_slot == owner_slot:
			continue

		var dist: float = player.global_position.distance_to(origin)
		if dist > radius:
			continue

		var falloff: float = 1.0 - (dist / radius)
		var base_damage: int = maxi(1, int(roundf(splash_damage * falloff)))
		var final_damage: int = ResearchManager.apply_rage_to_damage(owner_slot, base_damage)
		var old_health: int = player.health_component.health
		player.health_component.damage(final_damage)
		player.apply_hit_feedback(origin, final_damage)
		if player.player_slot != owner_slot:
			var applied_damage: int = mini(final_damage, old_health)
			ResearchManager.apply_local_life_steal(owner_slot, applied_damage)
