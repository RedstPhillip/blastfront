class_name FreezeEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, _projectile: Node = null) -> void:
	if target == null or target.status_effect_manager == null:
		return
	target.status_effect_manager.apply_effect("freeze", effect_data)
