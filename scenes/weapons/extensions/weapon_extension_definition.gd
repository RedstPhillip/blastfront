class_name WeaponExtensionDefinition
extends Resource

## One weapon part type (a .tres): slot, display data, stat modifiers per mark and its projectile
## tags and effects. Every mark past the first also adds a trait of its own (mk2_trait / mk3_trait, shown in
## the loadout): a new behaviour from the extra tags and effect keys of that mark, not only bigger numbers.

const MAX_CONDITION_DRAWBACK_PENALTY: float = 1.25

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
@export var mk2_attribute_modifiers: Dictionary = {}
@export var mk3_attribute_modifiers: Dictionary = {}
@export var projectile_tags: Array[String] = []
@export var projectile_effects: Dictionary = {}
@export var mk2_projectile_effects: Dictionary = {}
@export var mk3_projectile_effects: Dictionary = {}
## Tags a mark adds on top of the ones before it (MK II's stay at MK III).
@export var mk2_projectile_tags: Array[String] = []
@export var mk3_projectile_tags: Array[String] = []
## What MK II / MK III add, in a few words ("Hits shove the target.").
@export var mk2_trait: String = ""
@export var mk3_trait: String = ""
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
			return "Middle/Top"
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
	return ItemCondition.get_scale(condition, minimum_condition_factor)


func get_effective_attribute_modifiers(condition: float, item_mark: int = mark) -> Dictionary:
	var result: Dictionary = {}
	var condition_multiplier: float = get_condition_multiplier(condition)
	var modifiers: Dictionary = get_attribute_modifiers_for_mark(item_mark)
	for raw_key in modifiers.keys():
		var attribute_name: StringName = StringName(str(raw_key))
		var raw_value: Variant = modifiers[raw_key]
		if raw_value is float or raw_value is int:
			var numeric_value: float = float(raw_value)
			if condition_scales_attributes:
				numeric_value *= _get_condition_attribute_factor(attribute_name, numeric_value, condition_multiplier)
			result[attribute_name] = numeric_value
		else:
			result[attribute_name] = raw_value
	return result


func get_effective_projectile_tags(item_mark: int = mark) -> Array[String]:
	var result: Array[String] = []
	for tag in get_projectile_tags_for_mark(item_mark):
		if not result.has(tag):
			result.append(tag)
	return result


func get_effective_projectile_effects(condition: float, item_mark: int = mark) -> Dictionary:
	var effects_copy: Dictionary = get_projectile_effects_for_mark(item_mark).duplicate(true)
	if not condition_scales_projectile_effects:
		return effects_copy
	return _scale_projectile_effects(effects_copy, get_condition_multiplier(condition))


func get_attribute_modifiers_for_mark(item_mark: int) -> Dictionary:
	match clampi(item_mark, 1, GameSettings.EXTENSION_MAX_MARK):
		2:
			if not mk2_attribute_modifiers.is_empty():
				return mk2_attribute_modifiers
			return _build_default_attribute_modifiers(2)
		3:
			if not mk3_attribute_modifiers.is_empty():
				return mk3_attribute_modifiers
			return _build_default_attribute_modifiers(3)
	return attribute_modifiers


func get_projectile_tags_for_mark(item_mark: int) -> Array[String]:
	var mark_value: int = clampi(item_mark, 1, GameSettings.EXTENSION_MAX_MARK)
	if mark_value < 2 or (mk2_projectile_tags.is_empty() and mk3_projectile_tags.is_empty()):
		return projectile_tags
	var result: Array[String] = projectile_tags.duplicate()
	for tag in mk2_projectile_tags:
		if not result.has(tag):
			result.append(tag)
	if mark_value >= 3:
		for tag in mk3_projectile_tags:
			if not result.has(tag):
				result.append(tag)
	return result


## The trait a mark adds ("" for MK I). Numbers in it come from the mark's effects at the given condition,
## written as {effect.key} (a plain number) or {effect.key%} (a share as a percentage), so a worn copy
## reads what it really does: "Each bounce adds {growth.bounce%} damage." → "Each bounce adds 19% damage."
func get_mark_trait(item_mark: int, condition: float = 100.0) -> String:
	var text: String = ""
	match item_mark:
		2:
			text = mk2_trait
		3:
			text = mk3_trait
	if text.find("{") < 0:
		return text
	var effects: Dictionary = get_effective_projectile_effects(condition, item_mark)
	var pattern: RegEx = RegEx.create_from_string("\\{([a-z_]+)\\.([a-z_]+)(%?)\\}")
	for found in pattern.search_all(text):
		var effect: Variant = effects.get(found.get_string(1), {})
		var value: float = float((effect as Dictionary).get(found.get_string(2), 0.0)) if effect is Dictionary else 0.0
		var shown: String = "%d%%" % roundi(value * 100.0) if found.get_string(3) == "%" else String.num(value, 1)
		text = text.replace(found.get_string(0), shown)
	return text


func get_projectile_effects_for_mark(item_mark: int) -> Dictionary:
	match clampi(item_mark, 1, GameSettings.EXTENSION_MAX_MARK):
		2:
			if not mk2_projectile_effects.is_empty():
				return mk2_projectile_effects
			return _build_default_projectile_effects(2)
		3:
			if not mk3_projectile_effects.is_empty():
				return mk3_projectile_effects
			return _build_default_projectile_effects(3)
	return projectile_effects


func _build_default_attribute_modifiers(item_mark: int) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in attribute_modifiers.keys():
		var key: StringName = StringName(str(raw_key))
		var raw_value: Variant = attribute_modifiers[raw_key]
		if raw_value is float or raw_value is int:
			result[key] = _scale_default_attribute(key, float(raw_value), item_mark)
		else:
			result[key] = raw_value
	return result


func _scale_default_attribute(attribute: StringName, value: float, item_mark: int) -> float:
	var benefit_factor: float = 2.0 if item_mark == 2 else 3.25
	var drawback_factor: float = 0.85 if item_mark == 2 else 0.7
	var is_benefit: bool = _is_attribute_benefit(attribute, value)
	return value * (benefit_factor if is_benefit else drawback_factor)


func _build_default_projectile_effects(item_mark: int) -> Dictionary:
	if projectile_effects.is_empty():
		return {}
	var effect_factor: float = 1.65 if item_mark == 2 else 2.5
	return _scale_projectile_effects(projectile_effects.duplicate(true), effect_factor)


func _get_condition_attribute_factor(attribute: StringName, value: float, condition_multiplier: float) -> float:
	if _is_attribute_benefit(attribute, value):
		return condition_multiplier
	return lerpf(MAX_CONDITION_DRAWBACK_PENALTY, 1.0, condition_multiplier)


func _is_attribute_benefit(attribute: StringName, value: float) -> bool:
	var lower_is_better: bool = _attribute_lower_is_better(attribute)
	return value < 0.0 if lower_is_better else value > 0.0


func _attribute_lower_is_better(attribute: StringName) -> bool:
	return attribute == &"fire_interval" \
		or attribute == &"reload_time" \
		or attribute == &"projectile_gravity" \
		or attribute == &"projectile_linear_damping" \
		or attribute == &"shot_spread_degrees" \
		or attribute == &"shot_random_spread_degrees" \
		or attribute == &"recoil_rotation_degrees"


func _scale_projectile_effects(source: Dictionary, factor: float) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in source.keys():
		var effect_data: Variant = source[raw_key]
		if effect_data is Dictionary:
			result[raw_key] = _scale_projectile_effect_data(effect_data, factor)
		else:
			result[raw_key] = _scale_projectile_effect_value(StringName(str(raw_key)), effect_data, factor)
	return result


func _scale_projectile_effect_data(source: Dictionary, factor: float) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in source.keys():
		result[raw_key] = _scale_projectile_effect_value(StringName(str(raw_key)), source[raw_key], factor)
	return result


func _scale_projectile_effect_array(parameter: StringName, source: Array, factor: float) -> Array:
	var result: Array = []
	for value in source:
		result.append(_scale_projectile_effect_value(parameter, value, factor))
	return result


func _scale_projectile_effect_value(parameter: StringName, value: Variant, factor: float) -> Variant:
	if value is float or value is int:
		var numeric_value: float = float(value)
		match parameter:
			&"delay", &"tick_interval", &"full_distance", &"range", &"through_shield", &"after_bounce", &"horizontal", &"boost_cap", &"stagger":
				return value
			&"speed_multiplier":
				return clampf(lerpf(1.0, numeric_value, factor), 0.05, 1.0)
			&"tick_count":
				return maxi(1, int(roundf(numeric_value * factor)))
			&"wall_passes":
				return maxi(0, int(roundf(numeric_value * factor)))
			_:
				return numeric_value * factor
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return _scale_projectile_effect_data(dictionary_value, factor)
	if value is Array:
		var array_value: Array = value
		return _scale_projectile_effect_array(parameter, array_value, factor)
	return value
