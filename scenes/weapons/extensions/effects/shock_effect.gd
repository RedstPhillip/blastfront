class_name ShockEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, _projectile: Projectile) -> void:
	if target == null or target.status_effect_manager == null:
		return
	target.status_effect_manager.apply_effect("shock", effect_data)
