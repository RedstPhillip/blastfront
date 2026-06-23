extends Resource
class_name ArmorItemData

const CATEGORY_BOOTS: StringName = &"boots"
const CATEGORY_VEST: StringName = &"vest"
const CATEGORY_SHIELD: StringName = &"shield"
const MAX_MARK: int = 3

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = CATEGORY_BOOTS
@export_range(0.0, 100.0, 0.1) var condition: float = 100.0:
	set(value):
		condition = ItemCondition.clamp_value(value)
@export_range(0.0, 1.0, 0.01) var minimum_condition_scale: float = 0.25
@export var visual_scene: PackedScene = null
@export var attributes: Dictionary = {}
@export_multiline var description: String = ""
@export var metadata: Dictionary = {}


func is_valid_category() -> bool:
	return category == CATEGORY_BOOTS or category == CATEGORY_VEST or category == CATEGORY_SHIELD


func get_category_display_name() -> String:
	return category_display_name(category)


func get_condition_scale() -> float:
	return ItemCondition.get_scale(condition, minimum_condition_scale)


func get_condition_name() -> String:
	return ItemCondition.get_grade_name(condition)


func get_condition_color() -> Color:
	return ItemCondition.get_grade_color(condition)


func get_mark() -> int:
	var metadata_variant: Variant = metadata
	if metadata_variant is Dictionary:
		var item_metadata: Dictionary = metadata_variant
		return clampi(int(item_metadata.get("mark", 1)), 1, MAX_MARK)
	return 1


func get_mark_power_multiplier() -> float:
	match get_mark():
		2:
			return 1.25
		3:
			return 1.65
	return 1.0


func get_scaled_attributes() -> Dictionary:
	var scale: float = get_condition_scale()
	var mark_multiplier: float = get_mark_power_multiplier()
	var scaled_attributes: Dictionary = {}
	for raw_key in attributes.keys():
		var key: StringName = StringName(str(raw_key))
		var value: Variant = attributes[raw_key]
		if value is int or value is float:
			var numeric_value: float = float(value) * scale
			if _attribute_scales_with_mark(key):
				numeric_value *= mark_multiplier
			scaled_attributes[key] = numeric_value
		else:
			scaled_attributes[key] = value
	return scaled_attributes


func get_hover_title() -> String:
	if display_name.is_empty():
		return str(item_id)
	return display_name


func get_hover_text() -> String:
	var lines: Array[String] = []
	lines.append("%s | MK%d | %s" % [get_category_display_name(), get_mark(), get_condition_name()])
	lines.append("Condition: %d / 100" % int(round(condition)))
	if not description.is_empty():
		lines.append(description)
	return "\n".join(lines)


func _attribute_scales_with_mark(attribute: StringName) -> bool:
	return attribute != &"instant_reload_on_block"


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
