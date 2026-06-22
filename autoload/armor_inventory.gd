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
	if not GameSettings.START_WITH_ALL_ARMOR_ITEMS:
		inventory.clear()
	inventory_changed.emit()


func reset_match() -> void:
	loadout.clear()
	_online_loadouts = GameSettings.default_armor_loadouts()
	reload_definitions()


func equip_item(item: ArmorItemData) -> bool:
	if item == null or not item.is_valid_category():
		return false

	var previous_item: ArmorItemData = loadout.get_equipped_item(item.category)
	var inventory_changed_for_equip: bool = false
	if inventory.has(item):
		inventory.erase(item)
		inventory_changed_for_equip = true
	if previous_item != null and previous_item != item and not inventory.has(previous_item):
		inventory.append(previous_item)
		inventory_changed_for_equip = true

	var was_equipped: bool = loadout.equip_item(item)
	if inventory_changed_for_equip:
		inventory_changed.emit()
	return was_equipped


func unequip_category(category_id: StringName) -> void:
	var item: ArmorItemData = loadout.get_equipped_item(category_id)
	loadout.unequip_category(category_id)
	if item != null and not inventory.has(item):
		inventory.append(item)
		inventory_changed.emit()


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


func add_all_definitions_for_local() -> void:
	var changed: bool = false
	for definition in definitions:
		if definition == null or _owns_item_id(definition.item_id):
			continue
		var item: ArmorItemData = definition.duplicate(true) as ArmorItemData
		if item == null:
			continue
		inventory.append(item)
		changed = true
	if changed:
		inventory_changed.emit()


func apply_condition_wear_for_local(amount: float) -> void:
	if amount <= 0.0:
		return
	var changed: bool = false
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = loadout.get_equipped_item(category_id)
		if item == null:
			continue
		item.condition = ItemCondition.clamp_value(item.condition - amount)
		changed = true
	if changed:
		inventory_changed.emit()
		loadout_changed.emit()
		_publish_local_loadout_if_needed(get_local_player_slot())


func get_reward_definitions() -> Array[ArmorItemData]:
	var result: Array[ArmorItemData] = []
	for definition in definitions:
		if definition == null:
			continue
		var metadata_variant: Variant = definition.metadata
		var mark: int = 1
		if metadata_variant is Dictionary:
			var metadata: Dictionary = metadata_variant
			mark = int(metadata.get("mark", 1))
		if mark == 1:
			result.append(definition)
	return result


func get_local_player_slot() -> int:
	if NetworkSession.is_steam_match_active():
		return NetworkSession.local_player_slot
	return GameSettings.PLAYER_ONE_SLOT


func get_definition(item_id: StringName) -> ArmorItemData:
	return _definitions_by_id.get(str(item_id), null) as ArmorItemData


func get_merge_cost_for_next_mark(next_mark: int) -> int:
	var base_cost: int = 0
	match next_mark:
		2:
			base_cost = GameSettings.ARMOR_MERGE_MK2_COST
		3:
			base_cost = GameSettings.ARMOR_MERGE_MK3_COST
	if base_cost <= 0:
		return 0
	return maxi(1, int(roundf(float(base_cost) * ResearchManager.get_upgrade_cost_multiplier())))


func get_merge_cost_for_items(first_item: ArmorItemData, second_item: ArmorItemData) -> int:
	if not can_merge_items(first_item, second_item):
		return 0
	return get_merge_cost_for_next_mark(first_item.get_mark() + 1)


func can_merge_items(first_item: ArmorItemData, second_item: ArmorItemData) -> bool:
	if first_item == null or second_item == null:
		return false
	if first_item == second_item:
		return false
	if first_item.category != second_item.category:
		return false
	if _base_item_key(first_item) != _base_item_key(second_item):
		return false
	if first_item.get_mark() != second_item.get_mark():
		return false
	return first_item.get_mark() < ArmorItemData.MAX_MARK


func has_merge_partner_for_local(item: ArmorItemData) -> bool:
	if item == null:
		return false
	for candidate in inventory:
		if can_merge_items(item, candidate):
			return true
	return false


func try_merge_items_for_local(first_item: ArmorItemData, second_item: ArmorItemData) -> ArmorItemData:
	if not can_merge_items(first_item, second_item):
		return null

	var first_index: int = inventory.find(first_item)
	var second_index: int = inventory.find(second_item)
	if first_index < 0 or second_index < 0:
		return null

	var merged_item: ArmorItemData = _create_merged_item(first_item, second_item)
	if merged_item == null:
		return null

	var merge_cost: int = get_merge_cost_for_items(first_item, second_item)
	if merge_cost <= 0 or not OnlineMatch.try_spend_local_coins(merge_cost):
		return null

	inventory.remove_at(maxi(first_index, second_index))
	inventory.remove_at(mini(first_index, second_index))
	inventory.append(merged_item)
	inventory_changed.emit()
	return merged_item


func serialize_loadout_for_local() -> Dictionary:
	var result: Dictionary = {}
	for category_id in ArmorItemData.category_ids():
		var item: ArmorItemData = loadout.get_equipped_item(category_id)
		if item != null:
			result[str(category_id)] = {
				"id": str(item.item_id),
				"condition": item.condition,
				"mark": item.get_mark(),
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

	# Armor definitions are discovered recursively so content can be organized in subfolders.
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
	var mark_value: int = int(loadout_data.get("mark", definition.get_mark()))
	item.metadata = _metadata_with_mark(item.metadata, mark_value)
	return item


func _create_merged_item(first_item: ArmorItemData, second_item: ArmorItemData) -> ArmorItemData:
	var next_mark: int = first_item.get_mark() + 1
	var definition: ArmorItemData = _get_next_mark_definition(first_item, next_mark)
	var merged_item: ArmorItemData = null
	if definition != null:
		merged_item = definition.duplicate(true) as ArmorItemData
	else:
		merged_item = first_item.duplicate(true) as ArmorItemData
	if merged_item == null:
		return null

	merged_item.condition = (first_item.condition + second_item.condition) * 0.5
	merged_item.metadata = _metadata_with_mark(merged_item.metadata, next_mark)
	return merged_item


func _get_next_mark_definition(item: ArmorItemData, next_mark: int) -> ArmorItemData:
	if item == null:
		return null
	var item_id_text: String = str(item.item_id)
	var current_mark: int = item.get_mark()
	var current_suffix: String = "_mk%d" % current_mark
	if item_id_text.ends_with(current_suffix):
		var next_id: StringName = StringName(item_id_text.substr(0, item_id_text.length() - current_suffix.length()) + "_mk%d" % next_mark)
		var next_definition: ArmorItemData = get_definition(next_id)
		if next_definition != null:
			return next_definition
	return item


func _base_item_key(item: ArmorItemData) -> String:
	var item_id_text: String = str(item.item_id)
	var current_suffix: String = "_mk%d" % item.get_mark()
	if item_id_text.ends_with(current_suffix):
		return item_id_text.substr(0, item_id_text.length() - current_suffix.length())
	return item_id_text


func _metadata_with_mark(metadata_variant: Variant, mark: int) -> Dictionary:
	var result: Dictionary = {}
	if metadata_variant is Dictionary:
		result = (metadata_variant as Dictionary).duplicate(true)
	result["mark"] = clampi(mark, 1, ArmorItemData.MAX_MARK)
	return result


func _owns_item_id(item_id: StringName) -> bool:
	for item_variant in inventory:
		var item: ArmorItemData = item_variant as ArmorItemData
		if item != null and item.item_id == item_id:
			return true
	for category_id in ArmorItemData.category_ids():
		var equipped_item: ArmorItemData = loadout.get_equipped_item(category_id)
		if equipped_item != null and equipped_item.item_id == item_id:
			return true
	return false


func _ensure_online_loadouts() -> void:
	for player_slot in GameSettings.player_slots():
		if not _online_loadouts.has(player_slot):
			var empty_loadout: Dictionary = {}
			for category_id in ArmorItemData.category_ids():
				empty_loadout[category_id] = null
			_online_loadouts[player_slot] = empty_loadout


func _connect_online_match() -> void:
	if not OnlineMatch.state_changed.is_connected(_on_online_match_state_changed):
		OnlineMatch.state_changed.connect(_on_online_match_state_changed)


func _on_online_match_state_changed() -> void:
	_apply_online_match_loadouts()


func _apply_online_match_loadouts() -> void:
	apply_online_loadouts(OnlineMatch.get_armor_loadouts())


func _publish_local_loadout_if_needed(player_slot: int) -> void:
	if _is_applying_online_state:
		return
	if not NetworkSession.is_steam_match_active():
		return
	if player_slot != get_local_player_slot():
		return

	OnlineMatch.set_local_armor_loadout(serialize_loadout_for_local())


func _is_player_slot(player_slot: int) -> bool:
	return player_slot == GameSettings.PLAYER_ONE_SLOT or player_slot == GameSettings.PLAYER_TWO_SLOT
