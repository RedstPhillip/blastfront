extends Node

signal inventory_changed
signal loadout_changed

const ARMOR_ITEMS_DIR: String = "res://data/armor/items"

var inventory: Array[ArmorItemData] = []
var loadout: ArmorLoadout = ArmorLoadout.new()


func _ready() -> void:
	loadout.loadout_changed.connect(_on_loadout_changed)
	reload_definitions()


func reload_definitions() -> void:
	inventory.clear()
	_load_items_from_dir(ARMOR_ITEMS_DIR)
	inventory_changed.emit()


func equip_item(item: ArmorItemData) -> bool:
	var was_equipped: bool = loadout.equip_item(item)
	return was_equipped


func unequip_category(category_id: StringName) -> void:
	loadout.unequip_category(category_id)


func get_equipped_item(category_id: StringName) -> ArmorItemData:
	return loadout.get_equipped_item(category_id)


func get_inventory_for_category(category_id: StringName) -> Array[ArmorItemData]:
	var items: Array[ArmorItemData] = []
	for item in inventory:
		if item != null and item.category == category_id:
			items.append(item)
	return items


func get_scaled_attributes() -> Dictionary:
	return loadout.get_scaled_attributes()


func get_effect_modifiers() -> Array[Dictionary]:
	return loadout.get_effect_modifiers()


func register_item(item: ArmorItemData) -> void:
	if item == null or not item.is_valid_category():
		return
	if not inventory.has(item):
		inventory.append(item)
		inventory_changed.emit()


func _load_items_from_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		var child_path: String = path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_load_items_from_dir(child_path)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var loaded_resource: Resource = ResourceLoader.load(child_path)
			var armor_item: ArmorItemData = loaded_resource as ArmorItemData
			if armor_item != null:
				register_item(armor_item)
		file_name = dir.get_next()
	dir.list_dir_end()


func _on_loadout_changed() -> void:
	loadout_changed.emit()
