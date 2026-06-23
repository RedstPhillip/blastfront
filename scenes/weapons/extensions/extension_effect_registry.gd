class_name ExtensionEffectRegistry
extends Node

const POISON_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/poison_effect.gd")
const FREEZE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/freeze_effect.gd")
const SHOCK_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/shock_effect.gd")
const EXPLOSIVE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/explosive_effect.gd")
const GRENADE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/grenade_effect.gd")

static var effects: Dictionary = {
	&"poison": POISON_EFFECT_SCRIPT.new(),
	&"freeze": FREEZE_EFFECT_SCRIPT.new(),
	&"shock": SHOCK_EFFECT_SCRIPT.new(),
	&"explosive": EXPLOSIVE_EFFECT_SCRIPT.new(),
	&"grenade": GRENADE_EFFECT_SCRIPT.new(),
}


static func register_effect(effect_name: StringName, effect: ExtensionEffect) -> void:
	if effect == null:
		return
	effects[effect_name] = effect


static func unregister_effect(effect_name: StringName) -> void:
	effects.erase(effect_name)


static func has_effect(effect_name: StringName) -> bool:
	return effects.has(effect_name)


static func apply_projectile_effects(target: Player, projectile: Node) -> void:
	if projectile == null:
		return

	var projectile_effects: Dictionary = _get_projectile_effects(projectile)
	for raw_effect_name in projectile_effects.keys():
		var effect_name: StringName = StringName(str(raw_effect_name))
		var effect: ExtensionEffect = effects.get(effect_name, null) as ExtensionEffect
		if effect == null:
			continue

		var effect_data: Dictionary = {}
		var effect_data_variant: Variant = projectile_effects[raw_effect_name]
		if effect_data_variant is Dictionary:
			effect_data = effect_data_variant
		effect.apply(target, effect_data, projectile)


static func _get_projectile_effects(projectile: Node) -> Dictionary:
	var effects_variant: Variant = projectile.extension_effects
	if effects_variant is Dictionary:
		var projectile_effects: Dictionary = effects_variant
		return projectile_effects
	return {}
