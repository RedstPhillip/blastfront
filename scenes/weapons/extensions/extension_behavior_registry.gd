class_name ExtensionBehaviorRegistry
extends Node

const HOVER_BEHAVIOR_SCRIPT: Script = preload("res://scenes/weapons/extensions/behaviors/hover_behavior.gd")

static var behaviors: Dictionary = {
	&"hover": HOVER_BEHAVIOR_SCRIPT.new(),
}


static func has_behavior(tag: StringName) -> bool:
	return behaviors.has(tag)


static func update_projectile_behaviors(projectile: Projectile, delta: float) -> void:
	if projectile == null:
		return

	var tags: Array[String] = projectile.extension_tags
	var effects: Dictionary = projectile.extension_effects
	for tag_text in tags:
		var tag: StringName = StringName(tag_text)
		var behavior: ExtensionBehavior = behaviors.get(tag, null) as ExtensionBehavior
		if behavior == null:
			continue

		var effect_data: Dictionary = {}
		var effect_data_variant: Variant = effects.get(tag_text, effects.get(tag, {}))
		if effect_data_variant is Dictionary:
			effect_data = effect_data_variant
		behavior.update(projectile, delta, effect_data)
