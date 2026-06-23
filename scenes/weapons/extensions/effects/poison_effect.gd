class_name PoisonEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Projectile) -> void:
	if target == null or target.status_effect_manager == null:
		return

	var local_effect_data: Dictionary = effect_data.duplicate(true)
	local_effect_data["source_slot"] = projectile.owner_slot
	target.status_effect_manager.apply_effect("poison", local_effect_data)
