class_name WeaponExtensionDefinition
extends Resource

const SLOT_MIDDLE: StringName = &"middle"
const SLOT_AMMO: StringName = &"ammo"
const SLOT_FRONT: StringName = &"front"

@export var extension_id: String = ""
@export var display_name: String = ""
@export_enum("middle", "ammo", "front") var slot_key: String = "middle"
@export_range(1, 3, 1) var mark: int = 1
@export_multiline var description: String = ""
@export_range(0.0, 100.0, 0.1) var default_condition: float = 100.0
@export_range(0.0, 1.0, 0.01) var minimum_condition_factor: float = 0.0
@export var condition_scales_attributes: bool = true
@export var condition_scales_projectile_effects: bool = true
@export var attribute_modifiers: Dictionary = {}
@export var projectile_tags: Array[String] = []
@export var projectile_effects: Dictionary = {}
@export var visual_scene: PackedScene = null
@export var icon_color: Color = Color.WHITE


static func all_slots() -> Array[StringName]:
	return [
		SLOT_MIDDLE,
		SLOT_AMMO,
		SLOT_FRONT,
	]


static func slot_display_name(slot: StringName) -> String:
	match slot:
		SLOT_MIDDLE:
			return "Mitte/Top"
		SLOT_AMMO:
			return "Ammo"
		SLOT_FRONT:
			return "Front"
	return "Unknown"


static func is_valid_slot(slot: StringName) -> bool:
	return all_slots().has(slot)


func get_id() -> StringName:
	return StringName(extension_id)


func get_slot() -> StringName:
	return StringName(slot_key)


func get_condition_multiplier(condition: float) -> float:
	return ExtensionCondition.get_condition_multiplier(condition, minimum_condition_factor)


func get_effective_attribute_modifiers(condition: float) -> Dictionary:
	var result: Dictionary = {}
	var condition_multiplier: float = get_condition_multiplier(condition)
	for raw_key in attribute_modifiers.keys():
		var attribute_name: StringName = StringName(str(raw_key))
		var raw_value: Variant = attribute_modifiers[raw_key]
		if raw_value is float or raw_value is int:
			var numeric_value: float = float(raw_value)
			if condition_scales_attributes:
				numeric_value *= condition_multiplier
			result[attribute_name] = numeric_value
		else:
			result[attribute_name] = raw_value
	return result


func get_effective_projectile_tags() -> Array[String]:
	var result: Array[String] = []
	for tag in projectile_tags:
		if not result.has(tag):
			result.append(tag)
	return result


func get_effective_projectile_effects(condition: float) -> Dictionary:
	var effects_copy: Dictionary = projectile_effects.duplicate(true)
	if not condition_scales_projectile_effects:
		return effects_copy
	return _scale_dictionary_numbers(effects_copy, get_condition_multiplier(condition))


func _scale_dictionary_numbers(source: Dictionary, factor: float) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in source.keys():
		result[raw_key] = _scale_variant(source[raw_key], factor)
	return result


func _scale_array_numbers(source: Array, factor: float) -> Array:
	var result: Array = []
	for value in source:
		result.append(_scale_variant(value, factor))
	return result


func _scale_variant(value: Variant, factor: float) -> Variant:
	if value is float or value is int:
		return float(value) * factor
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return _scale_dictionary_numbers(dictionary_value, factor)
	if value is Array:
		var array_value: Array = value
		return _scale_array_numbers(array_value, factor)
	return value
