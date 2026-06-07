class_name GrenadeEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Node = null) -> void:
	if target == null:
		return

	var origin: Vector2 = target.global_position
	if projectile != null:
		var proj: Node = projectile
		origin = proj.get("global_position")

	var delay: float = float(effect_data.get("delay", 0.5))
	var radius: float = float(effect_data.get("radius", 80.0))
	var damage: int = int(effect_data.get("damage_per_hit", effect_data.get("damage", 10)))

	var tree: SceneTree = target.get_tree()
	if tree == null:
		return

	var detonator: GrenadeDetonator = GrenadeDetonator.new()
	detonator.origin = origin
	detonator.delay = delay
	detonator.radius = radius
	detonator.damage = damage
	target.add_child(detonator)
