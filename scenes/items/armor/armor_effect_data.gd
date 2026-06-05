extends Resource
class_name ArmorEffectData

const OPERATION_ADD: StringName = &"add"
const OPERATION_MULTIPLY: StringName = &"multiply"
const OPERATION_SET: StringName = &"set"

@export var effect_id: StringName = &""
@export var display_name: String = ""
@export var attribute_id: StringName = &""
@export var operation: StringName = OPERATION_ADD
@export var base_value: float = 0.0
@export var scales_with_condition: bool = true
@export var tags: Array[StringName] = []
@export var metadata: Dictionary = {}


func get_value(condition_scale: float) -> float:
	if not scales_with_condition:
		return base_value
	return base_value * clampf(condition_scale, 0.0, 1.0)


func to_modifier(condition_scale: float) -> Dictionary:
	return {
		"id": effect_id,
		"name": display_name,
		"attribute": attribute_id,
		"operation": operation,
		"value": get_value(condition_scale),
		"tags": tags.duplicate(),
		"metadata": metadata.duplicate(true),
	}
