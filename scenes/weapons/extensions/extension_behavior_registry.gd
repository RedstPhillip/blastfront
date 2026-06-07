class_name ExtensionBehaviorRegistry
extends Node

const HOVER_BEHAVIOR_SCRIPT: Script = preload("res://scenes/weapons/extensions/behaviors/hover_behavior.gd")

static var behaviors: Dictionary = {
	&"hover": HOVER_BEHAVIOR_SCRIPT.new(),
}


static func register_behavior(tag: StringName, behavior: ExtensionBehavior) -> void:
	if behavior == null:
		return
	behaviors[tag] = behavior


static func unregister_behavior(tag: StringName) -> void:
	behaviors.erase(tag)


static func has_behavior(tag: StringName) -> bool:
	return behaviors.has(tag)


static func update_projectile_behaviors(projectile: Projectile, delta: float) -> void:
	if projectile == null:
		return

	var tags: Array[String] = _get_projectile_tags(projectile)
	var effects: Dictionary = _get_projectile_effects(projectile)
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


static func _get_projectile_tags(projectile: Node) -> Array[String]:
	var result: Array[String] = []
	var tags_variant: Variant = projectile.get("extension_tags")
	if not (tags_variant is Array):
		return result

	var tags: Array = tags_variant
	for raw_tag in tags:
		result.append(str(raw_tag))
	return result


static func _get_projectile_effects(projectile: Node) -> Dictionary:
	var effects_variant: Variant = projectile.get("extension_effects")
	if effects_variant is Dictionary:
		var effects: Dictionary = effects_variant
		return effects
	return {}
