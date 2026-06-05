extends Node

signal inventory_changed(player_slot: int)
signal loadout_changed(player_slot: int)

const EXTENSION_DEFINITION_PATHS: Array[String] = [
	"res://scenes/weapons/extensions/red_dot_sight_mk1.tres",
	"res://scenes/weapons/extensions/cryo_rounds_mk1.tres",
	"res://scenes/weapons/extensions/long_barrel_mk1.tres",
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
	if item == null or item.definition == null:
		return false

	var extension_slot: StringName = item.get_slot()
	if not WeaponExtensionDefinition.is_valid_slot(extension_slot):
		return false

	_ensure_player_state(player_slot)
	var loadout: Dictionary = _get_loadout_for_player(player_slot)
	loadout[extension_slot] = item
	_equipped_by_player[player_slot] = loadout
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
	loadout[slot] = null
	_equipped_by_player[player_slot] = loadout
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
	return WeaponExtensionItem.create(definition, condition_value)


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
	if online_match == null or not online_match.has_method("get_extension_loadouts"):
		return

	var loadouts_variant: Variant = online_match.call("get_extension_loadouts")
	if loadouts_variant is Dictionary:
		var loadouts: Dictionary = loadouts_variant
		apply_online_loadouts(loadouts)


func _publish_local_loadout_if_needed(player_slot: int) -> void:
	if _is_applying_online_state:
		return
	if not NetworkSession.is_steam_match_active():
		return
	if player_slot != get_local_player_slot():
		return

	var online_match: Node = get_node_or_null("/root/OnlineMatch")
	if online_match == null or not online_match.has_method("set_local_extension_loadout"):
		return

	online_match.call("set_local_extension_loadout", serialize_loadout_for_player(player_slot))


func _is_player_slot(player_slot: int) -> bool:
	return player_slot == GameSettings.PLAYER_ONE_SLOT or player_slot == GameSettings.PLAYER_TWO_SLOT
