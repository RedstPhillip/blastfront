class_name WeaponExtensionItem
extends Resource

@export var definition: WeaponExtensionDefinition = null
@export_range(0.0, 100.0, 0.1) var condition: float = 100.0


static func create(definition_resource: WeaponExtensionDefinition, condition_value: float) -> WeaponExtensionItem:
	var item: WeaponExtensionItem = WeaponExtensionItem.new()
	item.definition = definition_resource
	item.condition = ItemCondition.clamp_value(condition_value)
	return item


func get_definition_id() -> StringName:
	if definition == null:
		return &""
	return definition.get_id()


func get_display_name() -> String:
	if definition == null:
		return "Unknown Extension"
	return definition.display_name


func get_slot() -> StringName:
	if definition == null:
		return &""
	return definition.get_slot()


func get_slot_display_name() -> String:
	return WeaponExtensionDefinition.slot_display_name(get_slot())


func get_condition_tier_id() -> StringName:
	return ItemCondition.get_grade(condition)


func get_condition_tier_name() -> String:
	return ItemCondition.get_grade_name(condition)


func get_condition_color() -> Color:
	return ItemCondition.get_grade_color(condition)


func get_condition_multiplier() -> float:
	if definition == null:
		return 0.0
	return definition.get_condition_multiplier(condition)


func build_effective_stats() -> Dictionary:
	if definition == null:
		return {}

	return {
		"extension_id": str(get_definition_id()),
		"slot": str(get_slot()),
		"mark": definition.mark,
		"condition": condition,
		"condition_tier": str(get_condition_tier_id()),
		"condition_multiplier": get_condition_multiplier(),
		"attributes": definition.get_effective_attribute_modifiers(condition),
		"projectile_tags": definition.get_effective_projectile_tags(),
		"projectile_effects": definition.get_effective_projectile_effects(condition),
	}


func to_loadout_data() -> Dictionary:
	return {
		"id": str(get_definition_id()),
		"condition": condition,
	}
