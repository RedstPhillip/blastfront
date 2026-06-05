extends Resource
class_name ArmorItemData

const CATEGORY_BOOTS: StringName = &"boots"
const CATEGORY_VEST: StringName = &"vest"
const CATEGORY_SHIELD: StringName = &"shield"

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = CATEGORY_BOOTS
@export_range(0.0, 100.0, 0.1) var condition: float = 100.0:
	set(value):
		condition = ArmorCondition.clamp_condition(value)
@export_range(0.0, 1.0, 0.01) var minimum_condition_scale: float = 0.25
@export var rarity: StringName = &""
@export var icon: Texture2D = null
@export var preview_texture: Texture2D = null
@export var visual_scene: PackedScene = null
@export var attributes: Dictionary = {}
@export var effects: Array[ArmorEffectData] = []
@export_multiline var description: String = ""
@export var metadata: Dictionary = {}


func is_valid_category() -> bool:
	return category == CATEGORY_BOOTS or category == CATEGORY_VEST or category == CATEGORY_SHIELD


func get_category_display_name() -> String:
	return category_display_name(category)


func get_condition_scale() -> float:
	return ArmorCondition.get_scale(condition, minimum_condition_scale)


func get_condition_name() -> String:
	return ArmorCondition.get_grade_name(condition)


func get_condition_color() -> Color:
	return ArmorCondition.get_grade_color(condition)


func get_scaled_attributes() -> Dictionary:
	var scale: float = get_condition_scale()
	var scaled_attributes: Dictionary = {}
	for raw_key in attributes.keys():
		var key: Variant = raw_key
		var value: Variant = attributes[key]
		if value is int or value is float:
			scaled_attributes[key] = float(value) * scale
		else:
			scaled_attributes[key] = value
	return scaled_attributes


func get_effect_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	var scale: float = get_condition_scale()
	for effect in effects:
		if effect != null:
			modifiers.append(effect.to_modifier(scale))
	return modifiers


func get_hover_title() -> String:
	if display_name.is_empty():
		return str(item_id)
	return display_name


func get_hover_text() -> String:
	var lines: Array[String] = []
	lines.append("%s | %s" % [get_category_display_name(), get_condition_name()])
	lines.append("Condition: %d / 100" % int(round(condition)))
	if not description.is_empty():
		lines.append(description)
	return "\n".join(lines)


static func category_display_name(category_id: StringName) -> String:
	match category_id:
		CATEGORY_BOOTS:
			return "Boots"
		CATEGORY_VEST:
			return "Vest"
		CATEGORY_SHIELD:
			return "Shield"
		_:
			return "Armor"


static func category_ids() -> Array[StringName]:
	return [
		CATEGORY_BOOTS,
		CATEGORY_VEST,
		CATEGORY_SHIELD,
	]
