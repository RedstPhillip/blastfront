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


static func has_effect(effect_name: StringName) -> bool:
	return effects.has(effect_name)


static func apply_projectile_effects(target: Player, projectile: Projectile) -> void:
	var projectile_effects: Dictionary = projectile.extension_effects
	for raw_effect_name in projectile_effects.keys():
		var effect_name: StringName = StringName(str(raw_effect_name))	
		var effect: ExtensionEffect = effects.get(effect_name, null) as ExtensionEffect
		if effect == null:
			continue

		var effect_data: Variant = projectile_effects[raw_effect_name]
		effect.apply(target, effect_data, projectile)
