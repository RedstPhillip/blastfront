class_name GrenadeEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Node = null) -> void:
	if target == null and projectile == null:
		return

	var origin: Vector2 = target.global_position if target != null else Vector2.ZERO
	var projectile_node: Node2D = projectile as Node2D
	if projectile_node != null:
		origin = projectile_node.global_position

	var delay: float = float(effect_data.get("delay", 0.5))
	var radius: float = float(effect_data.get("radius", 80.0))
	var damage: int = int(effect_data.get("damage_per_hit", effect_data.get("damage", 10)))

	var tree: SceneTree = target.get_tree() if target != null else projectile.get_tree()
	if tree == null:
		return

	var detonator: GrenadeDetonator = GrenadeDetonator.new()
	detonator.origin = origin
	detonator.delay = delay
	detonator.radius = radius
	detonator.damage = damage
	detonator.owner_slot = int(projectile.get("owner_slot")) if projectile != null else 0
	var effect_parent: Node = tree.current_scene
	if effect_parent == null:
		effect_parent = tree.root
	effect_parent.add_child(detonator)
