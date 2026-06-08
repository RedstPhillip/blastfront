extends Node

signal inventory_changed
signal loadout_changed
signal player_loadout_changed(player_slot: int)

const ARMOR_ITEMS_DIR: String = "res://data/armor/items"

var inventory: Array[ArmorItemData] = []
var definitions: Array[ArmorItemData] = []
var loadout: ArmorLoadout = ArmorLoadout.new()
var _definitions_by_id: Dictionary = {}
var _online_loadouts: Dictionary = {}
var _is_applying_online_state: bool = false


func _ready() -> void:
	loadout.loadout_changed.connect(_on_loadout_changed)
	reload_definitions()
	_ensure_online_loadouts()
	_connect_online_match()
	_apply_online_match_loadouts()


func reload_definitions() -> void:
	inventory.clear()
	definitions.clear()
	_definitions_by_id.clear()
	_load_items_from_dir(ARMOR_ITEMS_DIR)
	if not GameSettings.DEBUG_UNLOCK_ALL_ITEMS:
		inventory.clear()
	inventory_changed.emit()


func reset_match() -> void:
	loadout.clear()
	_online_loadouts = GameSettings.default_armor_loadouts()
	reload_definitions()


func equip_item(item: ArmorItemData) -> bool:
	var was_equipped: bool = loadout.equip_item(item)
	return was_equipped


func unequip_category(category_id: StringName) -> void:
	loadout.unequip_category(category_id)


func get_equipped_item(category_id: StringName) -> ArmorItemData:
	return loadout.get_equipped_item(category_id)


func get_equipped_item_for_player(player_slot: int, category_id: StringName) -> ArmorItemData:
	if player_slot == get_local_player_slot():
		return get_equipped_item(category_id)
	_ensure_online_loadouts()
	var loadout_data: Dictionary = _online_loadouts.get(player_slot, {})
	return loadout_data.get(category_id, loadout_data.get(str(category_id), null)) as ArmorItemData


func get_loadout_for_player(player_slot: int) -> ArmorLoadout:
	if player_slot == get_local_player_slot():
		return loadout
	_ensure_online_loadouts()
	var remote_loadout: ArmorLoadout = ArmorLoadout.new()
	var loadout_data: Dictionary = _online_loadouts.get(player_slot, {})
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = loadout_data.get(category_id, loadout_data.get(str(category_id), null)) as ArmorItemData
		if item != null:
			remote_loadout.equip_item(item)
	return remote_loadout


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


func get_reward_definitions() -> Array[ArmorItemData]:
	return definitions.duplicate()


func get_local_player_slot() -> int:
	if NetworkSession.is_steam_match_active():
		return NetworkSession.local_player_slot
	return GameSettings.PLAYER_ONE_SLOT


func get_definition(item_id: StringName) -> ArmorItemData:
	return _definitions_by_id.get(str(item_id), null) as ArmorItemData


func serialize_loadout_for_local() -> Dictionary:
	var result: Dictionary = {}
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = loadout.get_equipped_item(category_id)
		if item != null:
			result[str(category_id)] = {
				"id": str(item.item_id),
				"condition": item.condition,
			}
	return result


func apply_loadout_data_for_player(player_slot: int, loadout_data: Dictionary) -> void:
	_ensure_online_loadouts()
	var next_loadout: Dictionary = {}
	for category_id in ArmorItemData.category_ids():
		next_loadout[category_id] = null

	for raw_category in loadout_data.keys():
		var category_id: StringName = StringName(str(raw_category))
		if not ArmorItemData.category_ids().has(category_id):
			continue

		var item_data_variant: Variant = loadout_data[raw_category]
		if not (item_data_variant is Dictionary):
			continue

		var item_data: Dictionary = item_data_variant
		var item: ArmorItemData = _create_item_from_loadout_data(item_data)
		if item != null and item.category == category_id:
			next_loadout[category_id] = item

	_online_loadouts[player_slot] = next_loadout
	player_loadout_changed.emit(player_slot)


func apply_online_loadouts(loadouts: Dictionary) -> void:
	_is_applying_online_state = true
	for raw_slot in loadouts.keys():
		var player_slot: int = int(raw_slot)
		if not _is_player_slot(player_slot):
			continue

		var loadout_variant: Variant = loadouts[raw_slot]
		if loadout_variant is Dictionary:
			var loadout_data: Dictionary = loadout_variant
			apply_loadout_data_for_player(player_slot, loadout_data)
	_is_applying_online_state = false


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
				if not definitions.has(armor_item):
					definitions.append(armor_item)
				_definitions_by_id[str(armor_item.item_id)] = armor_item
				if not inventory.has(armor_item):
					inventory.append(armor_item)
		file_name = dir.get_next()
	dir.list_dir_end()


func _on_loadout_changed() -> void:
	var local_slot: int = get_local_player_slot()
	loadout_changed.emit()
	player_loadout_changed.emit(local_slot)
	_publish_local_loadout_if_needed(local_slot)


func _create_item_from_loadout_data(loadout_data: Dictionary) -> ArmorItemData:
	var item_id: StringName = StringName(str(loadout_data.get("id", "")))
	var definition: ArmorItemData = get_definition(item_id)
	if definition == null:
		return null

	var item: ArmorItemData = definition.duplicate(true) as ArmorItemData
	if item == null:
		return null
	item.condition = float(loadout_data.get("condition", definition.condition))
	return item


func _ensure_online_loadouts() -> void:
	for player_slot in GameSettings.player_slots():
		if not _online_loadouts.has(player_slot):
			var empty_loadout: Dictionary = {}
			for category_id in ArmorItemData.category_ids():
				empty_loadout[category_id] = null
			_online_loadouts[player_slot] = empty_loadout


func _connect_online_match() -> void:
	var online_match: Node = get_node_or_null("/root/OnlineMatch")
	if online_match == null or not online_match.has_signal("state_changed"):
		return

	var callback: Callable = Callable(self, "_on_online_match_state_changed")
	if not online_match.is_connected("state_changed", callback):
		online_match.connect("state_changed", callback)


func _on_online_match_state_changed() -> void:
	_apply_online_match_loadouts()


func _apply_online_match_loadouts() -> void:
	var online_match: Node = get_node_or_null("/root/OnlineMatch")
	if online_match == null or not online_match.has_method("get_armor_loadouts"):
		return

	var loadouts_variant: Variant = online_match.call("get_armor_loadouts")
	if loadouts_variant is Dictionary:
		apply_online_loadouts(loadouts_variant)


func _publish_local_loadout_if_needed(player_slot: int) -> void:
	if _is_applying_online_state:
		return
	if not NetworkSession.is_steam_match_active():
		return
	if player_slot != get_local_player_slot():
		return

	var online_match: Node = get_node_or_null("/root/OnlineMatch")
	if online_match == null or not online_match.has_method("set_local_armor_loadout"):
		return

	online_match.call("set_local_armor_loadout", serialize_loadout_for_local())


func _is_player_slot(player_slot: int) -> bool:
	return player_slot == GameSettings.PLAYER_ONE_SLOT or player_slot == GameSettings.PLAYER_TWO_SLOT
