class_name GrenadeEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Projectile) -> void:
	var origin: Vector2 = projectile.global_position
	var delay: float = float(effect_data.get("delay", 0.5))
	var radius: float = float(effect_data.get("radius", 80.0))
	var damage: int = int(effect_data.get("damage_per_hit", effect_data.get("damage", GameSettings.PROJECTILE_DAMAGE)))

	var tree: SceneTree = projectile.get_tree()
	if tree == null:
		return

	var detonator: GrenadeDetonator = GrenadeDetonator.new()
	detonator.origin = origin
	detonator.delay = delay
	detonator.radius = radius
	detonator.damage = damage
	detonator.owner_slot = projectile.owner_slot
	var effect_parent: Node = tree.current_scene
	if effect_parent == null:
		effect_parent = tree.root
	effect_parent.add_child(detonator)
