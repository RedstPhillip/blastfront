extends Resource
class_name ArmorLoadout

signal loadout_changed

var equipped_items: Dictionary = {}


func _init() -> void:
	clear()


func clear() -> void:
	equipped_items = {}
	for category_id in ArmorItemData.category_ids():
		equipped_items[category_id] = null
	loadout_changed.emit()


func equip_item(item: ArmorItemData) -> bool:
	if item == null or not item.is_valid_category():
		return false
	equipped_items[item.category] = item
	loadout_changed.emit()
	return true


func unequip_category(category_id: StringName) -> void:
	if not equipped_items.has(category_id):
		return
	equipped_items[category_id] = null
	loadout_changed.emit()


func get_equipped_item(category_id: StringName) -> ArmorItemData:
	var item_variant: Variant = equipped_items.get(category_id, null)
	return item_variant as ArmorItemData


func get_scaled_attributes() -> Dictionary:
	var totals: Dictionary = {}
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = get_equipped_item(category_id)
		if item == null:
			continue
		var attributes: Dictionary = item.get_scaled_attributes()
		for raw_key in attributes.keys():
			var key: Variant = raw_key
			var value: Variant = attributes[key]
			if value is int or value is float:
				totals[key] = float(totals.get(key, 0.0)) + float(value)
			else:
				totals[key] = value
	return totals


func get_effect_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = get_equipped_item(category_id)
		if item != null:
			modifiers.append_array(item.get_effect_modifiers())
	return modifiers
