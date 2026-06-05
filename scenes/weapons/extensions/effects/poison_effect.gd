class_name PoisonEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, _projectile: Node = null) -> void:
	if target == null:
		return

	if target.status_effect_manager == null:
		return
	target.status_effect_manager.apply_effect("poison", effect_data)
