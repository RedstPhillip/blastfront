extends Node

signal inventory_changed(player_slot: int)
signal loadout_changed(player_slot: int)

const EXTENSION_DEFINITION_PATHS: Array[String] = [
	"res://scenes/weapons/extensions/poison_rounds_mk1.tres",
	"res://scenes/weapons/extensions/big_bullets_mk1.tres",
	"res://scenes/weapons/extensions/reload_improver_mk1.tres",
	"res://scenes/weapons/extensions/multi_barrel_mk1.tres",
	"res://scenes/weapons/extensions/freeze_rounds_mk1.tres",
	"res://scenes/weapons/extensions/shocking_rounds_mk1.tres",
	"res://scenes/weapons/extensions/bouncy_bullets_mk1.tres",
	"res://scenes/weapons/extensions/drill_bullets_mk1.tres",
	"res://scenes/weapons/extensions/explosive_bullet_mk1.tres",
	"res://scenes/weapons/extensions/grenades_mk1.tres",
	"res://scenes/weapons/extensions/shotgun_mk1.tres",
	"res://scenes/weapons/extensions/sniper_barrel_mk1.tres",
	"res://scenes/weapons/extensions/extended_barrel_mk1.tres",
	"res://scenes/weapons/extensions/kinetic_amplifier_mk1.tres",
	"res://scenes/weapons/extensions/heavy_barrel_mk1.tres",
	"res://scenes/weapons/extensions/lighter_barrel_mk1.tres",
	"res://scenes/weapons/extensions/ground_hover_mk1.tres",
	"res://scenes/weapons/extensions/laser_scope_mk1.tres",
	"res://scenes/weapons/extensions/standard_scope_mk1.tres",
]

var _definitions_by_id: Dictionary = {}
var _inventory_by_player: Dictionary = {}
var _equipped_by_player: Dictionary = {}
var _is_applying_online_state: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_definitions()
	_ensure_player_state(GameSettings.PLAYER_ONE_SLOT)
	_ensure_player_state(GameSettings.PLAYER_TWO_SLOT)
	_connect_online_match()
	_apply_online_match_loadouts()


func get_local_player_slot() -> int:
	if NetworkSession.is_steam_match_active():
		return NetworkSession.local_player_slot
	return GameSettings.PLAYER_ONE_SLOT


func get_inventory_for_local() -> Array[WeaponExtensionItem]:
	return get_inventory_for_player(get_local_player_slot())


func get_inventory_for_player(player_slot: int) -> Array[WeaponExtensionItem]:
	_ensure_player_state(player_slot)

	var result: Array[WeaponExtensionItem] = []
	var inventory: Array = _inventory_by_player.get(player_slot, [])
	for item_variant in inventory:
		var item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if item != null:
			result.append(item)
	return result


func add_item_for_local(item: WeaponExtensionItem) -> bool:
	return add_item_for_player(get_local_player_slot(), item)


func add_all_definitions_for_local() -> void:
	add_all_definitions_for_player(get_local_player_slot())


func add_all_definitions_for_player(player_slot: int) -> void:
	if not _is_player_slot(player_slot):
		return
	_ensure_player_state(player_slot)
	var inventory: Array = _inventory_by_player.get(player_slot, [])
	for definition in get_all_definitions():
		if definition == null:
			continue
		inventory.append(WeaponExtensionItem.create(definition, definition.default_condition, definition.mark))
	_inventory_by_player[player_slot] = inventory
	inventory_changed.emit(player_slot)


func add_item_for_player(player_slot: int, item: WeaponExtensionItem) -> bool:
	if item == null or item.definition == null or not _is_player_slot(player_slot):
		return false
	_ensure_player_state(player_slot)
	var inventory: Array = _inventory_by_player.get(player_slot, [])
	inventory.append(item)
	_inventory_by_player[player_slot] = inventory
	inventory_changed.emit(player_slot)
	return true


# Apply wear once per item even if a future loadout exposes it through several slots.
func apply_condition_wear_for_local(amount: float) -> void:
	if amount <= 0.0:
		return
	var player_slot: int = get_local_player_slot()
	var changed: bool = false
	var worn_items: Array[WeaponExtensionItem] = []
	var equipped: Dictionary = _get_loadout_for_player(player_slot)
	for slot in WeaponExtensionDefinition.all_slots():
		var item: WeaponExtensionItem = equipped.get(slot, null) as WeaponExtensionItem
		if item == null:
			continue
		if worn_items.has(item):
			continue
		worn_items.append(item)
		item.condition = ItemCondition.clamp_value(item.condition - amount)
		changed = true
	if changed:
		inventory_changed.emit(player_slot)
		loadout_changed.emit(player_slot)
		_publish_local_loadout_if_needed(player_slot)


func reset_match() -> void:
	_inventory_by_player.clear()
	_equipped_by_player.clear()
	_ensure_player_state(GameSettings.PLAYER_ONE_SLOT)
	_ensure_player_state(GameSettings.PLAYER_TWO_SLOT)
	for player_slot in GameSettings.player_slots():
		inventory_changed.emit(player_slot)
		loadout_changed.emit(player_slot)


func get_equipped_for_local() -> Dictionary:
	return get_equipped_for_player(get_local_player_slot())


func get_equipped_for_player(player_slot: int) -> Dictionary:
	_ensure_player_state(player_slot)
	return _get_loadout_for_player(player_slot).duplicate()


func get_equipped_item_for_local(slot: StringName) -> WeaponExtensionItem:
	return get_equipped_item_for_player(get_local_player_slot(), slot)


func get_equipped_item_for_player(player_slot: int, slot: StringName) -> WeaponExtensionItem:
	_ensure_player_state(player_slot)
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	return loadout.get(slot, null) as WeaponExtensionItem


func equip_item_for_local(item: WeaponExtensionItem) -> bool:
	return equip_item_for_player(get_local_player_slot(), item)


func equip_item_for_player(player_slot: int, item: WeaponExtensionItem) -> bool:
	if item == null or item.definition == null or not _is_player_slot(player_slot):
		return false

	var extension_slot: StringName = item.get_slot()
	if not WeaponExtensionDefinition.is_valid_slot(extension_slot):
		return false

	_ensure_player_state(player_slot)
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	var inventory: Array = _inventory_by_player.get(player_slot, [])
	var previous_item: WeaponExtensionItem = loadout.get(extension_slot, null) as WeaponExtensionItem
	var inventory_changed_for_equip: bool = false
	if inventory.has(item):
		inventory.erase(item)
		inventory_changed_for_equip = true
	if previous_item != null and previous_item != item and not inventory.has(previous_item):
		inventory.append(previous_item)
		inventory_changed_for_equip = true

	loadout[extension_slot] = item
	_inventory_by_player[player_slot] = inventory
	_equipped_by_player[player_slot] = loadout
	if inventory_changed_for_equip:
		inventory_changed.emit(player_slot)
	loadout_changed.emit(player_slot)
	_publish_local_loadout_if_needed(player_slot)
	return true


func unequip_local(slot: StringName) -> void:
	unequip_for_player(get_local_player_slot(), slot)


func unequip_for_player(player_slot: int, slot: StringName) -> void:
	if not WeaponExtensionDefinition.is_valid_slot(slot):
		return

	_ensure_player_state(player_slot)
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	var item: WeaponExtensionItem = loadout.get(slot, null) as WeaponExtensionItem
	loadout[slot] = null
	_equipped_by_player[player_slot] = loadout
	if item != null:
		var inventory: Array = _inventory_by_player.get(player_slot, [])
		if not inventory.has(item):
			inventory.append(item)
			_inventory_by_player[player_slot] = inventory
			inventory_changed.emit(player_slot)
	loadout_changed.emit(player_slot)
	_publish_local_loadout_if_needed(player_slot)


func get_definition(extension_id: StringName) -> WeaponExtensionDefinition:
	return _definitions_by_id.get(str(extension_id), null) as WeaponExtensionDefinition


func get_all_definitions() -> Array[WeaponExtensionDefinition]:
	var result: Array[WeaponExtensionDefinition] = []
	for definition_variant in _definitions_by_id.values():
		var definition: WeaponExtensionDefinition = definition_variant as WeaponExtensionDefinition
		if definition != null:
			result.append(definition)
	return result


func get_reward_definitions() -> Array[WeaponExtensionDefinition]:
	var result: Array[WeaponExtensionDefinition] = []
	for definition in get_all_definitions():
		if definition != null and definition.mark == 1:
			result.append(definition)
	return result


func get_merge_cost_for_next_mark(next_mark: int) -> int:
	var base_cost: int = 0
	match next_mark:
		2:
			base_cost = GameSettings.EXTENSION_MERGE_MK2_COST
		3:
			base_cost = GameSettings.EXTENSION_MERGE_MK3_COST
	if base_cost <= 0:
		return 0
	return maxi(1, int(roundf(float(base_cost) * ResearchManager.get_upgrade_cost_multiplier())))


func get_merge_cost_for_items(first_item: WeaponExtensionItem, second_item: WeaponExtensionItem) -> int:
	if not can_merge_items(first_item, second_item):
		return 0
	return get_merge_cost_for_next_mark(first_item.mark + 1)


func can_merge_items(first_item: WeaponExtensionItem, second_item: WeaponExtensionItem) -> bool:
	if first_item == null or second_item == null:
		return false
	if first_item == second_item:
		return false
	if first_item.definition == null or second_item.definition == null:
		return false
	if first_item.get_definition_id() != second_item.get_definition_id():
		return false
	if first_item.mark != second_item.mark:
		return false
	return first_item.mark < GameSettings.EXTENSION_MAX_MARK


func has_merge_partner_for_local(item: WeaponExtensionItem) -> bool:
	return has_merge_partner_for_player(get_local_player_slot(), item)


func has_merge_partner_for_player(player_slot: int, item: WeaponExtensionItem) -> bool:
	if item == null:
		return false
	for candidate in get_inventory_for_player(player_slot):
		if can_merge_items(item, candidate):
			return true
	return false


func try_merge_items_for_local(first_item: WeaponExtensionItem, second_item: WeaponExtensionItem) -> WeaponExtensionItem:
	return try_merge_items_for_player(get_local_player_slot(), first_item, second_item)


# Merging consumes equal items, preserves the better parts of their condition and promotes the resulting mark.
func try_merge_items_for_player(player_slot: int, first_item: WeaponExtensionItem, second_item: WeaponExtensionItem) -> WeaponExtensionItem:
	if not _is_player_slot(player_slot) or not can_merge_items(first_item, second_item):
		return null
	_ensure_player_state(player_slot)

	var inventory: Array = _inventory_by_player.get(player_slot, [])
	var first_index: int = inventory.find(first_item)
	var second_index: int = inventory.find(second_item)
	if first_index < 0 or second_index < 0:
		return null

	var merge_cost: int = get_merge_cost_for_items(first_item, second_item)
	if merge_cost <= 0 or not OnlineMatch.try_spend_local_coins(merge_cost):
		return null

	var average_condition: float = (first_item.condition + second_item.condition) * 0.5
	var better_condition: float = maxf(first_item.condition, second_item.condition)
	var merged_condition: float = ItemCondition.clamp_value(average_condition + (better_condition - average_condition) * 0.35 + 6.0)
	var merged_item: WeaponExtensionItem = WeaponExtensionItem.create(first_item.definition, merged_condition, first_item.mark + 1)
	inventory.remove_at(maxi(first_index, second_index))
	inventory.remove_at(mini(first_index, second_index))
	inventory.append(merged_item)
	_inventory_by_player[player_slot] = inventory

	var loadout_changed_for_merge: bool = _replace_consumed_equipped_items(player_slot, first_item, second_item, merged_item)
	inventory_changed.emit(player_slot)
	if loadout_changed_for_merge:
		loadout_changed.emit(player_slot)
		_publish_local_loadout_if_needed(player_slot)
	return merged_item


# Equipped definitions fold into one stat payload consumed by the gun.
func build_effective_stats_for_player(player_slot: int) -> Dictionary:
	_ensure_player_state(player_slot)

	var attributes: Dictionary = {}
	var projectile_tags: Array[String] = []
	var projectile_effects: Dictionary = {}
	var source_extensions: Array[String] = []
	var loadout: Dictionary = _get_loadout_for_player(player_slot)

	for slot in WeaponExtensionDefinition.all_slots():
		var item: WeaponExtensionItem = loadout.get(slot, null) as WeaponExtensionItem
		if item == null:
			continue

		var item_stats: Dictionary = item.build_effective_stats()
		_merge_attributes(attributes, item_stats.get("attributes", {}))
		_merge_tags(projectile_tags, item_stats.get("projectile_tags", []))
		_merge_effects(projectile_effects, item_stats.get("projectile_effects", {}))
		source_extensions.append(str(item.get_definition_id()))

	return {
		"attributes": attributes,
		"projectile_tags": projectile_tags,
		"projectile_effects": projectile_effects,
		"source_extensions": source_extensions,
	}


func serialize_loadout_for_player(player_slot: int) -> Dictionary:
	_ensure_player_state(player_slot)

	var result: Dictionary = {}
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	for slot in WeaponExtensionDefinition.all_slots():
		var item: WeaponExtensionItem = loadout.get(slot, null) as WeaponExtensionItem
		if item != null:
			result[str(slot)] = item.to_loadout_data()
	return result


# Network loadouts use stable definition IDs instead of synchronizing Resources.
func apply_loadout_data_for_player(player_slot: int, loadout_data: Dictionary) -> void:
	_ensure_player_state(player_slot)

	var next_loadout: Dictionary = _empty_loadout()
	for raw_slot in loadout_data.keys():
		var slot: StringName = StringName(str(raw_slot))
		if not WeaponExtensionDefinition.is_valid_slot(slot):
			continue

		var item_data_variant: Variant = loadout_data[raw_slot]
		if not (item_data_variant is Dictionary):
			continue

		var item_data: Dictionary = item_data_variant
		var item: WeaponExtensionItem = _create_item_from_loadout_data(item_data)
		if item != null and item.get_slot() == slot:
			next_loadout[slot] = item

	_equipped_by_player[player_slot] = next_loadout
	loadout_changed.emit(player_slot)


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


func _load_definitions() -> void:
	_definitions_by_id.clear()
	for definition_path in EXTENSION_DEFINITION_PATHS:
		var resource: Resource = load(definition_path)
		var definition: WeaponExtensionDefinition = resource as WeaponExtensionDefinition
		if definition == null:
			continue
		_definitions_by_id[str(definition.get_id())] = definition


func _ensure_player_state(player_slot: int) -> void:
	if not _is_player_slot(player_slot):
		return

	if not _inventory_by_player.has(player_slot):
		_inventory_by_player[player_slot] = _build_demo_inventory()
		inventory_changed.emit(player_slot)

	if not _equipped_by_player.has(player_slot):
		_equipped_by_player[player_slot] = _empty_loadout()


func _build_demo_inventory() -> Array[WeaponExtensionItem]:
	var result: Array[WeaponExtensionItem] = []
	if not GameSettings.START_WITH_ALL_WEAPON_EXTENSIONS:
		return result
	for definition in get_all_definitions():
		result.append(WeaponExtensionItem.create(definition, definition.default_condition))
	return result


func _empty_loadout() -> Dictionary:
	var loadout: Dictionary = {}
	for slot in WeaponExtensionDefinition.all_slots():
		loadout[slot] = null
	return loadout


func _get_loadout_for_player(player_slot: int) -> Dictionary:
	var loadout_variant: Variant = _equipped_by_player.get(player_slot, {})
	if loadout_variant is Dictionary:
		var loadout: Dictionary = loadout_variant
		return loadout
	return {}


func _create_item_from_loadout_data(loadout_data: Dictionary) -> WeaponExtensionItem:
	var raw_id: StringName = StringName(str(loadout_data.get("id", "")))
	var definition: WeaponExtensionDefinition = get_definition(raw_id)
	if definition == null:
		return null

	var condition_value: float = float(loadout_data.get("condition", definition.default_condition))
	var mark_value: int = int(loadout_data.get("mark", definition.mark))
	return WeaponExtensionItem.create(definition, condition_value, mark_value)


func _replace_consumed_equipped_items(
	player_slot: int,
	first_item: WeaponExtensionItem,
	second_item: WeaponExtensionItem,
	merged_item: WeaponExtensionItem
) -> bool:
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	var changed: bool = false
	for slot in WeaponExtensionDefinition.all_slots():
		var equipped_item: WeaponExtensionItem = loadout.get(slot, null) as WeaponExtensionItem
		if equipped_item == first_item or equipped_item == second_item:
			loadout[slot] = merged_item
			changed = true
	_equipped_by_player[player_slot] = loadout
	return changed


func _merge_attributes(target: Dictionary, incoming_variant: Variant) -> void:
	if not (incoming_variant is Dictionary):
		return

	var incoming: Dictionary = incoming_variant
	for raw_key in incoming.keys():
		var attribute_name: StringName = StringName(str(raw_key))
		var raw_value: Variant = incoming[raw_key]
		if raw_value is float or raw_value is int:
			target[attribute_name] = float(target.get(attribute_name, 0.0)) + float(raw_value)
		else:
			target[attribute_name] = raw_value


func _merge_tags(target: Array[String], incoming_variant: Variant) -> void:
	if not (incoming_variant is Array):
		return

	var incoming: Array = incoming_variant
	for raw_tag in incoming:
		var tag: String = str(raw_tag)
		if not target.has(tag):
			target.append(tag)


func _merge_effects(target: Dictionary, incoming_variant: Variant) -> void:
	if not (incoming_variant is Dictionary):
		return

	var incoming: Dictionary = incoming_variant
	for raw_key in incoming.keys():
		target[raw_key] = _merge_effect_value(target.get(raw_key, null), incoming[raw_key])


# Nested effects merge recursively; numbers stack and arrays keep unique entries.
func _merge_effect_value(existing_value: Variant, incoming_value: Variant) -> Variant:
	if existing_value == null:
		if incoming_value is Dictionary:
			var incoming_dictionary_copy: Dictionary = incoming_value
			return incoming_dictionary_copy.duplicate(true)
		if incoming_value is Array:
			var incoming_array_copy: Array = incoming_value
			return incoming_array_copy.duplicate(true)
		return incoming_value

	if existing_value is Dictionary and incoming_value is Dictionary:
		var existing_dictionary: Dictionary = existing_value
		var merged_dictionary: Dictionary = existing_dictionary.duplicate(true)
		var incoming_dictionary: Dictionary = incoming_value
		for raw_key in incoming_dictionary.keys():
			merged_dictionary[raw_key] = _merge_effect_value(merged_dictionary.get(raw_key, null), incoming_dictionary[raw_key])
		return merged_dictionary

	if existing_value is Array and incoming_value is Array:
		var existing_array: Array = existing_value
		var merged_array: Array = existing_array.duplicate()
		var incoming_array: Array = incoming_value
		for entry in incoming_array:
			if not merged_array.has(entry):
				merged_array.append(entry)
		return merged_array

	if (existing_value is float or existing_value is int) and (incoming_value is float or incoming_value is int):
		return float(existing_value) + float(incoming_value)

	return incoming_value


func _connect_online_match() -> void:
	var callback: Callable = Callable(self, "_on_online_match_state_changed")
	if not OnlineMatch.state_changed.is_connected(callback):
		OnlineMatch.state_changed.connect(callback)


func _on_online_match_state_changed() -> void:
	_apply_online_match_loadouts()


func _apply_online_match_loadouts() -> void:
	apply_online_loadouts(OnlineMatch.get_extension_loadouts())


# Suppress echoes during remote updates and publish only the local player's loadout.
func _publish_local_loadout_if_needed(player_slot: int) -> void:
	if _is_applying_online_state:
		return
	if not NetworkSession.is_steam_match_active():
		return
	if player_slot != get_local_player_slot():
		return

	OnlineMatch.set_local_extension_loadout(serialize_loadout_for_player(player_slot))


func _is_player_slot(player_slot: int) -> bool:
	return player_slot == GameSettings.PLAYER_ONE_SLOT or player_slot == GameSettings.PLAYER_TWO_SLOT
