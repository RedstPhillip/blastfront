class_name PoisonEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, projectile: Node = null) -> void:
	if target == null:
		return

	if target.status_effect_manager == null:
		return
	var local_effect_data: Dictionary = effect_data.duplicate(true)
	if projectile != null:
		local_effect_data["source_slot"] = int(projectile.owner_slot)
	target.status_effect_manager.apply_effect("poison", local_effect_data)
