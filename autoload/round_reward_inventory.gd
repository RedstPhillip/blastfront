extends Node

signal rewards_changed

const REWARD_EXTENSION: StringName = &"extension"
const REWARD_ARMOR: StringName = &"armor"
const SOURCE_OFFER: StringName = &"offer"
const SOURCE_SAVED: StringName = &"saved"
const OFFER_COUNT_PER_TYPE: int = 3
const SAVED_SLOT_COUNT: int = 2

var offers: Array[Dictionary] = []
var saved_rewards: Array[Dictionary] = []

var _last_round_key: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_clear_saved_slots()


func prepare_for_round(round_key: int) -> void:
	if round_key <= 0 or round_key == _last_round_key:
		return
	_last_round_key = round_key
	_generate_offers()
	rewards_changed.emit()


func reset_match() -> void:
	_last_round_key = -1
	offers.clear()
	_clear_saved_slots()
	rewards_changed.emit()


func get_offer(index: int) -> Dictionary:
	if index < 0 or index >= offers.size():
		return {}
	return offers[index]


func get_saved_reward(index: int) -> Dictionary:
	if index < 0 or index >= saved_rewards.size():
		return {}
	return saved_rewards[index]


func move_to_saved(source_kind: StringName, source_index: int, target_index: int) -> bool:
	if target_index < 0 or target_index >= saved_rewards.size():
		return false
	var reward: Dictionary = _get_reward(source_kind, source_index)
	if reward.is_empty():
		return false

	var displaced_reward: Dictionary = saved_rewards[target_index]
	saved_rewards[target_index] = reward
	_set_reward(source_kind, source_index, displaced_reward)
	rewards_changed.emit()
	return true


func claim_reward(source_kind: StringName, source_index: int) -> bool:
	var reward: Dictionary = _get_reward(source_kind, source_index)
	if reward.is_empty():
		return false

	var reward_type: StringName = StringName(str(reward.get("type", "")))
	var item_variant: Variant = reward.get("item", null)
	var claimed: bool = false
	if reward_type == REWARD_EXTENSION:
		var extension_item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		claimed = ExtensionInventory.add_item_for_local(extension_item)
	elif reward_type == REWARD_ARMOR:
		var armor_item: ArmorItemData = item_variant as ArmorItemData
		if armor_item != null:
			ArmorInventory.register_item(armor_item)
			claimed = true

	if not claimed:
		return false
	_set_reward(source_kind, source_index, {})
	rewards_changed.emit()
	return true


func _generate_offers() -> void:
	offers.clear()
	var extension_definitions: Array[WeaponExtensionDefinition] = ExtensionInventory.get_all_definitions()
	var armor_definitions: Array[ArmorItemData] = ArmorInventory.get_reward_definitions()
	_shuffle_array(extension_definitions)
	_shuffle_array(armor_definitions)

	for row_index in range(OFFER_COUNT_PER_TYPE):
		offers.append(_create_extension_reward(extension_definitions, row_index))
		offers.append(_create_armor_reward(armor_definitions, row_index))


func _create_extension_reward(definitions: Array[WeaponExtensionDefinition], index: int) -> Dictionary:
	if definitions.is_empty():
		return {}
	var definition: WeaponExtensionDefinition = definitions[index % definitions.size()]
	var item: WeaponExtensionItem = WeaponExtensionItem.create(definition, ItemCondition.roll(_rng))
	return {
		"type": REWARD_EXTENSION,
		"item": item,
	}


func _create_armor_reward(definitions: Array[ArmorItemData], index: int) -> Dictionary:
	if definitions.is_empty():
		return {}
	var definition: ArmorItemData = definitions[index % definitions.size()]
	var item: ArmorItemData = definition.duplicate(true) as ArmorItemData
	if item == null:
		return {}
	item.condition = ItemCondition.roll(_rng)
	return {
		"type": REWARD_ARMOR,
		"item": item,
	}


func _get_reward(source_kind: StringName, source_index: int) -> Dictionary:
	if source_kind == SOURCE_OFFER:
		return get_offer(source_index)
	if source_kind == SOURCE_SAVED:
		return get_saved_reward(source_index)
	return {}


func _set_reward(source_kind: StringName, source_index: int, reward: Dictionary) -> void:
	if source_kind == SOURCE_OFFER and source_index >= 0 and source_index < offers.size():
		offers[source_index] = reward
	elif source_kind == SOURCE_SAVED and source_index >= 0 and source_index < saved_rewards.size():
		saved_rewards[source_index] = reward


func _clear_saved_slots() -> void:
	saved_rewards.clear()
	for slot_index in range(SAVED_SLOT_COUNT):
		saved_rewards.append({})


func _shuffle_array(items: Array) -> void:
	for item_index in range(items.size() - 1, 0, -1):
		var swap_index: int = _rng.randi_range(0, item_index)
		var previous_value: Variant = items[item_index]
		items[item_index] = items[swap_index]
		items[swap_index] = previous_value
