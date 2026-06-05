class_name PoisonEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, _projectile: Node = null) -> void:
	if target == null:
		return

	var damage_per_hit: int = int(effect_data.get("damage_per_hit", 0))
	if damage_per_hit <= 0:
		return

	target.health_component.damage(damage_per_hit)
