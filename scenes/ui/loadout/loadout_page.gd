extends Control
class_name LoadoutPage

const ARMOR_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout/armor_item_card.tscn")
const WEAPON_EXTENSION_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout/weapon_extension_item_card.tscn")
const STAT_COMPARISON_ROW_SCENE: PackedScene = preload("res://scenes/ui/loadout/stat_comparison_row.tscn")
const BASE_RELOAD_TIME: float = 1.2
const BASE_AMMO: float = 3.0
const MAX_VISIBLE_STATS: int = 4
const WEAPON_STAT_PRIORITY: Array[StringName] = [
	&"damage",
	&"fire_interval",
	&"reload_time",
	&"ammo_max",
	&"projectile_speed",
	&"projectile_max_distance",
	&"shots_per_fire",
	&"shot_spread_degrees",
	&"shot_random_spread_degrees",
	&"projectile_gravity",
	&"recoil_rotation_degrees",
	&"projectile_scale",
	&"projectile_linear_damping",
]
const ARMOR_STAT_PRIORITY: Array[StringName] = [
	&"max_health",
	&"move_speed",
	&"air_speed",
	&"jump_velocity",
	&"damage_reduction",
	&"stationary_damage_reduction",
	&"freeze_resistance",
	&"reflect_chance",
	&"delayed_damage_duration",
	&"block_strength",
	&"frosty_radius",
	&"healing_rate",
	&"pull_strength",
	&"adrenaline_speed_bonus",
	&"escape_speed_bonus",
	&"chase_speed_bonus",
]
const DEFAULT_WEAPON_STATS: Array[StringName] = [
	&"damage",
	&"fire_interval",
	&"reload_time",
	&"ammo_max",
]
const HOVER_CLEAR_DELAY: float = 0.12
const MIN_WEAPON_INVENTORY_SLOTS: int = 30
const MIN_ARMOR_INVENTORY_SLOTS: int = 18

var _weapon_slots: Dictionary = {}
var _armor_slots: Dictionary = {}
var _offer_reward_slots: Array[RoundRewardSlot] = []
var _saved_reward_slots: Array[RoundRewardSlot] = []
var _inspecting_item: bool = false
var _pending_merge_source: WeaponExtensionItem = null
var _pending_merge_target: WeaponExtensionItem = null
var _merge_dialog: ConfirmationDialog = null
var _merge_warning_dialog: AcceptDialog = null
var _saved_reward_spacer: Control = null
var _hover_clear_timer: float = 0.0

@onready var _description_title: Label = %DescriptionTitle
@onready var _description_meta: Label = %DescriptionMeta
@onready var _description_body: Label = %DescriptionBody
@onready var _description_accent: ColorRect = %Accent
@onready var _condition_bar: ProgressBar = %ConditionBar
@onready var _condition_label: Label = %ConditionLabel
@onready var _changes_title: Label = %ChangesTitle
@onready var _changes_vbox: VBoxContainer = %ChangesVBox
@onready var _no_changes_label: Label = %NoChangesLabel
@onready var _weapon_slot_one: WeaponExtensionSlot = %WeaponSlotOne
@onready var _weapon_slot_two: WeaponExtensionSlot = %WeaponSlotTwo
@onready var _weapon_slot_three: WeaponExtensionSlot = %WeaponSlotThree
@onready var _weapon_inventory_grid: FlowContainer = %WeaponInventoryGrid
@onready var _weapon_inventory_empty_label: Label = %WeaponInventoryEmptyLabel
@onready var _weapon_inventory_panel: RewardInventoryDropTarget = %WeaponInventoryPanel
@onready var _armor_inventory_grid: FlowContainer = %ArmorInventoryGrid
@onready var _armor_inventory_empty_label: Label = %ArmorInventoryEmptyLabel
@onready var _armor_inventory_panel: RewardInventoryDropTarget = %ArmorInventoryPanel
@onready var _boots_slot: ArmorOverlaySlot = %BootsSlot
@onready var _vest_slot: ArmorOverlaySlot = %VestSlot
@onready var _shield_slot: ArmorOverlaySlot = %ShieldSlot
@onready var _coin_balance_label: Label = %CoinBalanceLabel
@onready var _offer_grid: GridContainer = %OfferGrid
@onready var _recycler_drop_target: Control = %RecyclerDropTarget


# This controller joins owned items, equipped loadout and current round rewards.
func _ready() -> void:
	_weapon_slots = {
		WeaponExtensionDefinition.SLOT_FRONT: _weapon_slot_one,
		WeaponExtensionDefinition.SLOT_MIDDLE: _weapon_slot_two,
		WeaponExtensionDefinition.SLOT_AMMO: _weapon_slot_three,
	}
	_armor_slots = {
		ArmorItemData.CATEGORY_BOOTS: _boots_slot,
		ArmorItemData.CATEGORY_VEST: _vest_slot,
		ArmorItemData.CATEGORY_SHIELD: _shield_slot,
	}
	_offer_reward_slots = [
		%ExtensionRewardOne,
		%ArmorRewardOne,
		%ExtensionRewardTwo,
		%ArmorRewardTwo,
		%ExtensionRewardThree,
		%ArmorRewardThree,
	]
	_saved_reward_slots = [
		%SavedRewardOne,
		%SavedRewardTwo,
		%SavedRewardThree,
		%SavedRewardFour,
	]

	_setup_weapon_placeholders()
	_setup_armor_slots()
	_setup_reward_slots()
	_setup_saved_reward_spacer()
	_setup_merge_dialog()
	_connect_inventory_signals()
	_refresh_weapon_inventory()
	_refresh_weapon_slots()
	_refresh_armor_inventory()
	_refresh_armor_slots()
	_refresh_round_rewards()
	_refresh_research_unlocks()
	_show_default_description()


func _process(delta: float) -> void:
	if not _inspecting_item:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if _is_inspectable_control(hovered):
		_hover_clear_timer = HOVER_CLEAR_DELAY
		return

	_hover_clear_timer -= delta
	if _hover_clear_timer <= 0.0:
		_show_default_description()


func _exit_tree() -> void:
	if ArmorInventory.inventory_changed.is_connected(_refresh_armor_inventory):
		ArmorInventory.inventory_changed.disconnect(_refresh_armor_inventory)
	if ArmorInventory.loadout_changed.is_connected(_refresh_armor_slots):
		ArmorInventory.loadout_changed.disconnect(_refresh_armor_slots)
	if ExtensionInventory.inventory_changed.is_connected(_on_extension_inventory_changed):
		ExtensionInventory.inventory_changed.disconnect(_on_extension_inventory_changed)
	if ExtensionInventory.loadout_changed.is_connected(_on_extension_loadout_changed):
		ExtensionInventory.loadout_changed.disconnect(_on_extension_loadout_changed)
	if RoundRewardInventory.rewards_changed.is_connected(_refresh_round_rewards):
		RoundRewardInventory.rewards_changed.disconnect(_refresh_round_rewards)
	if OnlineMatch.state_changed.is_connected(_refresh_shop_state):
		OnlineMatch.state_changed.disconnect(_refresh_shop_state)
	if ResearchManager.research_changed.is_connected(_refresh_research_unlocks):
		ResearchManager.research_changed.disconnect(_refresh_research_unlocks)


func _setup_weapon_placeholders() -> void:
	for slot_key in _weapon_slots.keys():
		var slot_button: WeaponExtensionSlot = _weapon_slots[slot_key] as WeaponExtensionSlot
		if slot_button == null:
			continue
		slot_button.setup(slot_key, ExtensionInventory.get_equipped_item_for_local(slot_key))
		slot_button.extension_hovered.connect(_show_weapon_extension_description)
		slot_button.extension_dropped.connect(_on_weapon_extension_selected)
		slot_button.extension_cleared.connect(_on_weapon_extension_cleared)


func _setup_armor_slots() -> void:
	_boots_slot.setup(ArmorItemData.CATEGORY_BOOTS, ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_BOOTS))
	_vest_slot.setup(ArmorItemData.CATEGORY_VEST, ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_VEST))
	_shield_slot.setup(ArmorItemData.CATEGORY_SHIELD, ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_SHIELD))

	for category_id in _armor_slots.keys():
		var slot: ArmorOverlaySlot = _armor_slots[category_id] as ArmorOverlaySlot
		if slot == null:
			continue
		slot.armor_hovered.connect(_show_armor_description)
		slot.armor_dropped.connect(_on_armor_selected)
		slot.armor_cleared.connect(_on_armor_cleared)


func _setup_reward_slots() -> void:
	for offer_index in range(_offer_reward_slots.size()):
		var offer_slot: RoundRewardSlot = _offer_reward_slots[offer_index]
		offer_slot.setup(RoundRewardInventory.SOURCE_OFFER, offer_index, false)
		offer_slot.reward_hovered.connect(_show_round_reward_description)
		offer_slot.reward_claimed.connect(_on_round_reward_claimed)

	for saved_index in range(_saved_reward_slots.size()):
		var saved_slot: RoundRewardSlot = _saved_reward_slots[saved_index]
		saved_slot.setup(RoundRewardInventory.SOURCE_SAVED, saved_index, true)
		saved_slot.reward_hovered.connect(_show_round_reward_description)
		saved_slot.reward_claimed.connect(_on_round_reward_claimed)
		saved_slot.reward_dropped.connect(_on_reward_dropped_to_saved)

	_weapon_inventory_panel.reward_dropped.connect(_on_reward_dropped_to_inventory)
	_armor_inventory_panel.reward_dropped.connect(_on_reward_dropped_to_inventory)


# Each data source refreshes only the UI region it owns.
func _connect_inventory_signals() -> void:
	if not ArmorInventory.inventory_changed.is_connected(_refresh_armor_inventory):
		ArmorInventory.inventory_changed.connect(_refresh_armor_inventory)
	if not ArmorInventory.loadout_changed.is_connected(_refresh_armor_slots):
		ArmorInventory.loadout_changed.connect(_refresh_armor_slots)
	if not ExtensionInventory.inventory_changed.is_connected(_on_extension_inventory_changed):
		ExtensionInventory.inventory_changed.connect(_on_extension_inventory_changed)
	if not ExtensionInventory.loadout_changed.is_connected(_on_extension_loadout_changed):
		ExtensionInventory.loadout_changed.connect(_on_extension_loadout_changed)
	if not RoundRewardInventory.rewards_changed.is_connected(_refresh_round_rewards):
		RoundRewardInventory.rewards_changed.connect(_refresh_round_rewards)
	if not OnlineMatch.state_changed.is_connected(_refresh_shop_state):
		OnlineMatch.state_changed.connect(_refresh_shop_state)
	if not ResearchManager.research_changed.is_connected(_refresh_research_unlocks):
		ResearchManager.research_changed.connect(_refresh_research_unlocks)
	if _recycler_drop_target.has_signal("reward_recycled"):
		var recycle_callback: Callable = Callable(self, "_on_reward_recycled")
		if not _recycler_drop_target.is_connected("reward_recycled", recycle_callback):
			_recycler_drop_target.connect("reward_recycled", recycle_callback)


func _refresh_weapon_inventory() -> void:
	for child in _weapon_inventory_grid.get_children():
		child.queue_free()

	var items: Array[WeaponExtensionItem] = ExtensionInventory.get_inventory_for_local()
	_weapon_inventory_empty_label.visible = false

	var visible_item_count: int = 0
	for item in items:
		if item == null:
			continue
		var card: WeaponExtensionItemCard = WEAPON_EXTENSION_ITEM_CARD_SCENE.instantiate() as WeaponExtensionItemCard
		if card == null:
			continue
		card.setup(item)
		card.set_merge_partner_available(ExtensionInventory.has_merge_partner_for_local(item))
		card.extension_hovered.connect(_show_weapon_extension_description)
		card.extension_selected.connect(_on_weapon_extension_selected)
		card.extension_merge_requested.connect(_on_weapon_extension_merge_requested)
		_weapon_inventory_grid.add_child(card)
		visible_item_count += 1
	_add_empty_weapon_inventory_slots(maxi(MIN_WEAPON_INVENTORY_SLOTS - visible_item_count, 0))


func _add_empty_weapon_inventory_slots(slot_count: int) -> void:
	for slot_index in range(slot_count):
		var card: WeaponExtensionItemCard = WEAPON_EXTENSION_ITEM_CARD_SCENE.instantiate() as WeaponExtensionItemCard
		if card == null:
			continue
		card.setup(null)
		_weapon_inventory_grid.add_child(card)


func _refresh_weapon_slots() -> void:
	for slot_key in _weapon_slots.keys():
		var slot_button: WeaponExtensionSlot = _weapon_slots[slot_key] as WeaponExtensionSlot
		if slot_button == null:
			continue
		slot_button.set_item(ExtensionInventory.get_equipped_item_for_local(slot_key))


func _refresh_armor_inventory() -> void:
	for child in _armor_inventory_grid.get_children():
		child.queue_free()

	var equipped_items: Array[ArmorItemData] = [
		ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_BOOTS),
		ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_VEST),
		ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_SHIELD),
	]

	var visible_item_count: int = 0
	for item in ArmorInventory.inventory:
		if item == null or equipped_items.has(item):
			continue
		var card: ArmorItemCard = ARMOR_ITEM_CARD_SCENE.instantiate() as ArmorItemCard
		if card == null:
			continue
		card.setup(item)
		card.armor_hovered.connect(_show_armor_description)
		card.armor_selected.connect(_on_armor_selected)
		_armor_inventory_grid.add_child(card)
		visible_item_count += 1

	_armor_inventory_empty_label.visible = false
	_add_empty_armor_inventory_slots(maxi(MIN_ARMOR_INVENTORY_SLOTS - visible_item_count, 0))


func _add_empty_armor_inventory_slots(slot_count: int) -> void:
	for slot_index in range(slot_count):
		var card: ArmorItemCard = ARMOR_ITEM_CARD_SCENE.instantiate() as ArmorItemCard
		if card == null:
			continue
		card.setup(null)
		_armor_inventory_grid.add_child(card)


func _refresh_armor_slots() -> void:
	_boots_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_BOOTS))
	_vest_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_VEST))
	_shield_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_SHIELD))
	_refresh_armor_inventory()


func _refresh_round_rewards() -> void:
	for offer_index in range(_offer_reward_slots.size()):
		_offer_reward_slots[offer_index].set_reward(RoundRewardInventory.get_offer(offer_index))
	for saved_index in range(_saved_reward_slots.size()):
		_saved_reward_slots[saved_index].set_reward(RoundRewardInventory.get_saved_reward(saved_index))
	_refresh_research_unlocks()
	_refresh_shop_state()


# Research controls saved blueprint capacity and recycler visibility.
func _refresh_research_unlocks() -> void:
	var saved_count: int = ResearchManager.get_blueprint_slot_count()
	for saved_index in range(_saved_reward_slots.size()):
		var saved_slot: RoundRewardSlot = _saved_reward_slots[saved_index]
		saved_slot.visible = saved_index < saved_count
		saved_slot.modulate = Color(0.72, 0.76, 0.78, 1.0)
	if _saved_reward_spacer != null:
		_saved_reward_spacer.visible = saved_count > 0 and saved_count % 2 == 1
	if _recycler_drop_target.has_method("refresh"):
		_recycler_drop_target.call("refresh")


func _setup_saved_reward_spacer() -> void:
	_saved_reward_spacer = Control.new()
	_saved_reward_spacer.custom_minimum_size = Vector2(64, 64)
	_saved_reward_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saved_reward_spacer.visible = false
	_offer_grid.add_child(_saved_reward_spacer)
	if not _offer_reward_slots.is_empty():
		_offer_grid.move_child(_saved_reward_spacer, _offer_reward_slots[0].get_index())


func _refresh_shop_state() -> void:
	_coin_balance_label.text = "%d COINS" % OnlineMatch.get_local_coin_balance()
	for offer_slot in _offer_reward_slots:
		offer_slot.refresh_affordability()
	for saved_slot in _saved_reward_slots:
		saved_slot.refresh_affordability()


# The details panel also summarizes the currently equipped stats.
func _show_default_description() -> void:
	_inspecting_item = false
	_hover_clear_timer = 0.0
	_description_title.text = "Loadout"
	_description_meta.text = "ITEM DETAILS"
	_description_body.text = "Hover over an item to inspect its type, condition and effects."
	_set_description_condition(0.0, Color8(98, 104, 110, 255), false)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	_show_default_weapon_stats(current_modifiers)


func _show_weapon_extension_description(item: WeaponExtensionItem) -> void:
	if item == null or item.definition == null:
		_show_default_description()
		return
	_inspecting_item = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	_description_title.text = item.get_display_name()
	_description_meta.text = "%s  |  MK%d  |  %s" % [
		item.get_slot_display_name().to_upper(),
		item.mark,
		item.get_condition_tier_name().to_upper(),
	]
	_description_body.text = _short_description(item.definition.description)
	if ExtensionInventory.has_merge_partner_for_local(item):
		var merge_cost: int = ExtensionInventory.get_merge_cost_for_next_mark(item.mark + 1)
		if merge_cost > 0:
			_description_body.text += " Merge cost: %d coins." % merge_cost
	_set_description_condition(item.condition, item.get_condition_color(), true)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	if _is_weapon_extension_equipped(item):
		_show_equipped_weapon_extension_stats(item)
	else:
		var preview_modifiers: Dictionary = _build_weapon_preview_modifiers(item, current_modifiers)
		_show_weapon_stat_changes(current_modifiers, preview_modifiers)


func _show_armor_description(item: ArmorItemData) -> void:
	if item == null:
		_show_default_description()
		return
	_inspecting_item = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	_description_title.text = item.get_hover_title()
	_description_meta.text = "ARMOR  |  %s  |  MK%d  |  %s" % [
		item.get_category_display_name().to_upper(),
		item.get_mark(),
		item.get_condition_name().to_upper(),
	]
	_description_body.text = _short_description(item.description)
	_set_description_condition(item.condition, item.get_condition_color(), true)
	var current_modifiers: Dictionary = ArmorInventory.get_scaled_attributes()
	var preview_modifiers: Dictionary = _build_armor_preview_modifiers(item, current_modifiers)
	_show_armor_stat_changes(current_modifiers, preview_modifiers)


func _set_description_condition(value: float, color: Color, visible: bool) -> void:
	_description_accent.color = color
	_condition_bar.visible = visible
	_condition_label.visible = visible
	_condition_bar.value = value
	_condition_label.text = "%d%%" % int(round(value))
	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_right = 3
	fill_style.corner_radius_bottom_left = 3
	_condition_bar.add_theme_stylebox_override("fill", fill_style)


func _get_current_weapon_modifiers() -> Dictionary:
	var stats: Dictionary = ExtensionInventory.build_effective_stats_for_player(ExtensionInventory.get_local_player_slot())
	var attributes_variant: Variant = stats.get("attributes", {})
	if attributes_variant is Dictionary:
		var attributes: Dictionary = attributes_variant
		return attributes.duplicate()
	return {}


func _is_weapon_extension_equipped(item: WeaponExtensionItem) -> bool:
	if item == null:
		return false
	return ExtensionInventory.get_equipped_item_for_local(item.get_slot()) == item


func _build_weapon_preview_modifiers(item: WeaponExtensionItem, current: Dictionary) -> Dictionary:
	var preview: Dictionary = current.duplicate()
	# Preview the replacement result by removing the equipped item before applying the candidate.
	var equipped_item: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_local(item.get_slot())
	if equipped_item != null:
		var equipped_stats: Dictionary = equipped_item.build_effective_stats()
		_apply_numeric_modifiers(preview, equipped_stats.get("attributes", {}), -1.0)
	var item_stats: Dictionary = item.build_effective_stats()
	_apply_numeric_modifiers(preview, item_stats.get("attributes", {}), 1.0)
	return preview


func _build_armor_preview_modifiers(item: ArmorItemData, current: Dictionary) -> Dictionary:
	var preview: Dictionary = current.duplicate()
	var equipped_item: ArmorItemData = ArmorInventory.get_equipped_item(item.category)
	if equipped_item != null:
		_apply_numeric_modifiers(preview, equipped_item.get_scaled_attributes(), -1.0)
	_apply_numeric_modifiers(preview, item.get_scaled_attributes(), 1.0)
	return preview


func _apply_numeric_modifiers(target: Dictionary, incoming_variant: Variant, factor: float) -> void:
	if not (incoming_variant is Dictionary):
		return
	var incoming: Dictionary = incoming_variant
	for raw_key in incoming.keys():
		var value: Variant = incoming[raw_key]
		if value is int or value is float:
			var key: StringName = StringName(str(raw_key))
			target[key] = float(target.get(key, 0.0)) + float(value) * factor


# Order comparisons by player-facing importance and limit them for readability.
func _show_weapon_stat_changes(current: Dictionary, preview: Dictionary) -> void:
	var keys: Array[StringName] = _ordered_changed_keys(current, preview, WEAPON_STAT_PRIORITY)
	_changes_title.text = "ITEM CHANGES"
	_clear_stat_changes("This item does not change numeric weapon attributes.")
	var visible_count: int = 0
	for key in keys:
		var before_value: float = _weapon_display_value(key, current)
		var after_value: float = _weapon_display_value(key, preview)
		if is_equal_approx(before_value, after_value):
			continue
		_add_stat_row(
			_weapon_attribute_name(key),
			before_value,
			after_value,
			_weapon_attribute_suffix(key),
			_weapon_attribute_decimals(key),
			_weapon_attribute_lower_is_better(key)
		)
		visible_count += 1
		if visible_count >= MAX_VISIBLE_STATS:
			break


func _show_equipped_weapon_extension_stats(item: WeaponExtensionItem) -> void:
	var item_stats: Dictionary = item.build_effective_stats()
	var attributes_variant: Variant = item_stats.get("attributes", {})
	var item_modifiers: Dictionary = {}
	if attributes_variant is Dictionary:
		item_modifiers = attributes_variant
	var keys: Array[StringName] = _ordered_changed_keys({}, item_modifiers, WEAPON_STAT_PRIORITY)
	_changes_title.text = "ACTIVE ITEM STATS"
	_clear_stat_changes("This equipped item has no numeric weapon attributes.")
	var visible_count: int = 0
	for key in keys:
		var base_value: float = _weapon_display_value(key, {})
		var item_value: float = _weapon_display_value(key, item_modifiers)
		if is_equal_approx(base_value, item_value):
			continue
		_add_stat_row(
			_weapon_attribute_name(key),
			base_value,
			item_value,
			_weapon_attribute_suffix(key),
			_weapon_attribute_decimals(key),
			_weapon_attribute_lower_is_better(key)
		)
		visible_count += 1
		if visible_count >= MAX_VISIBLE_STATS:
			break


func _show_armor_stat_changes(current: Dictionary, preview: Dictionary) -> void:
	var keys: Array[StringName] = _ordered_changed_keys(current, preview, ARMOR_STAT_PRIORITY)
	_changes_title.text = "ITEM CHANGES"
	_clear_stat_changes("This item does not change numeric armor attributes.")
	var visible_count: int = 0
	for key in keys:
		var before_value: float = _armor_display_value(key, current)
		var after_value: float = _armor_display_value(key, preview)
		if is_equal_approx(before_value, after_value):
			continue
		_add_stat_row(
			_armor_attribute_name(key),
			before_value,
			after_value,
			_armor_attribute_suffix(key),
			_armor_attribute_decimals(key),
			_armor_attribute_lower_is_better(key)
		)
		visible_count += 1
		if visible_count >= MAX_VISIBLE_STATS:
			break


func _show_default_weapon_stats(current: Dictionary) -> void:
	_changes_title.text = "KEY STATS"
	_clear_stat_changes("")
	for attribute in DEFAULT_WEAPON_STATS:
		var value: float = _weapon_display_value(attribute, current)
		_add_stat_row(
			_weapon_attribute_name(attribute),
			value,
			value,
			_weapon_attribute_suffix(attribute),
			_weapon_attribute_decimals(attribute),
			false
		)


func _ordered_changed_keys(
	current: Dictionary,
	preview: Dictionary,
	priority: Array[StringName]
) -> Array[StringName]:
	var result: Array[StringName] = []
	for key in priority:
		if _numeric_value_changed(key, current, preview):
			result.append(key)
	for raw_key in current.keys():
		var key: StringName = StringName(str(raw_key))
		if not result.has(key) and _numeric_value_changed(key, current, preview):
			result.append(key)
	for raw_key in preview.keys():
		var key: StringName = StringName(str(raw_key))
		if not result.has(key) and _numeric_value_changed(key, current, preview):
			result.append(key)
	return result


func _numeric_value_changed(key: StringName, current: Dictionary, preview: Dictionary) -> bool:
	var current_value: Variant = current.get(key, 0.0)
	var preview_value: Variant = preview.get(key, 0.0)
	if not (current_value is int or current_value is float):
		return false
	if not (preview_value is int or preview_value is float):
		return false
	return not is_equal_approx(float(current_value), float(preview_value))


func _clear_stat_changes(empty_text: String) -> void:
	for child in _changes_vbox.get_children():
		if child == _no_changes_label:
			continue
		_changes_vbox.remove_child(child)
		child.queue_free()
	_no_changes_label.text = empty_text
	_no_changes_label.visible = not empty_text.is_empty()


func _add_stat_row(
	display_name: String,
	before_value: float,
	after_value: float,
	suffix: String,
	decimals: int,
	lower_is_better: bool
) -> void:
	var row: StatComparisonRow = STAT_COMPARISON_ROW_SCENE.instantiate() as StatComparisonRow
	if row == null:
		return
	_no_changes_label.visible = false
	_changes_vbox.add_child(row)
	row.setup(display_name, before_value, after_value, suffix, decimals, lower_is_better)


func _weapon_display_value(attribute: StringName, modifiers: Dictionary) -> float:
	var modifier: float = float(modifiers.get(attribute, 0.0))
	match attribute:
		&"damage":
			return maxf(1.0, float(GameSettings.PROJECTILE_DAMAGE) + modifier)
		&"fire_interval":
			return 1.0 / maxf(0.03, GameSettings.GUN_FIRE_INTERVAL + modifier)
		&"reload_time":
			return maxf(0.1, BASE_RELOAD_TIME + modifier)
		&"ammo_max":
			return maxf(1.0, BASE_AMMO + modifier)
		&"projectile_speed":
			return maxf(1.0, GameSettings.GUN_PROJECTILE_SPEED + modifier)
		&"projectile_gravity":
			return GameSettings.GUN_PROJECTILE_GRAVITY + modifier
		&"projectile_linear_damping":
			return maxf(0.0, GameSettings.GUN_PROJECTILE_LINEAR_DAMPING + modifier)
		&"projectile_max_distance":
			return maxf(50.0, GameSettings.GUN_PROJECTILE_MAX_DISTANCE + modifier)
		&"projectile_scale":
			return maxf(0.1, 1.0 + modifier)
		&"shots_per_fire":
			return maxf(1.0, 1.0 + modifier)
		&"recoil_rotation_degrees":
			return maxf(0.0, GameSettings.GUN_RECOIL_ROTATION_DEGREES + modifier)
		_:
			return modifier


func _armor_display_value(attribute: StringName, modifiers: Dictionary) -> float:
	var modifier: float = float(modifiers.get(attribute, 0.0))
	match attribute:
		&"max_health":
			return float(GameSettings.DEFAULT_MAX_HEALTH) + modifier
		&"move_speed":
			return GameSettings.PLAYER_SPEED + modifier
		&"block_strength":
			return modifier
		&"freeze_resistance", &"reflect_chance":
			return modifier * 100.0
		&"frosty_speed_multiplier":
			return modifier * 100.0
		_:
			return modifier


func _weapon_attribute_name(attribute: StringName) -> String:
	match attribute:
		&"damage":
			return "Damage"
		&"fire_interval":
			return "Fire rate"
		&"reload_time":
			return "Reload time"
		&"ammo_max":
			return "Ammo"
		&"projectile_speed":
			return "Projectile speed"
		&"projectile_gravity":
			return "Bullet drop"
		&"projectile_linear_damping":
			return "Air resistance"
		&"projectile_max_distance":
			return "Range"
		&"projectile_scale":
			return "Projectile size"
		&"shots_per_fire":
			return "Projectiles"
		&"shot_spread_degrees":
			return "Spread"
		&"shot_random_spread_degrees":
			return "Random spread"
		&"recoil_rotation_degrees":
			return "Recoil"
		_:
			return str(attribute).replace("_", " ").capitalize()


func _armor_attribute_name(attribute: StringName) -> String:
	match attribute:
		&"max_health":
			return "Health"
		&"move_speed":
			return "Movement speed"
		&"air_speed":
			return "Air speed"
		&"jump_velocity":
			return "Jump power"
		&"damage_reduction":
			return "Protection"
		&"stationary_damage_reduction":
			return "Still protection"
		&"freeze_resistance":
			return "Freeze resist"
		&"reflect_chance":
			return "Reflect chance"
		&"delayed_damage_duration":
			return "Damage delay"
		&"block_strength":
			return "Block strength"
		&"frosty_radius":
			return "Frost radius"
		&"frosty_duration":
			return "Frost duration"
		&"frosty_speed_multiplier":
			return "Enemy speed"
		&"healing_radius":
			return "Heal radius"
		&"healing_rate":
			return "Healing"
		&"pull_radius":
			return "Pull radius"
		&"pull_strength":
			return "Pull force"
		&"instant_reload_on_block":
			return "Block reload"
		&"adrenaline_duration":
			return "Adrenaline time"
		&"adrenaline_speed_bonus":
			return "Adrenaline speed"
		&"escape_speed_bonus":
			return "Low HP speed"
		&"chase_speed_bonus":
			return "Chase speed"
		_:
			return str(attribute).replace("_", " ").capitalize()


func _weapon_attribute_suffix(attribute: StringName) -> String:
	match attribute:
		&"fire_interval":
			return "/s"
		&"reload_time":
			return "s"
		&"shot_spread_degrees", &"shot_random_spread_degrees", &"recoil_rotation_degrees":
			return " deg"
		_:
			return ""


func _weapon_attribute_decimals(attribute: StringName) -> int:
	if attribute == &"fire_interval" or attribute == &"reload_time" or attribute == &"projectile_scale":
		return 2
	return 0


func _armor_attribute_suffix(attribute: StringName) -> String:
	match attribute:
		&"freeze_resistance", &"reflect_chance", &"frosty_speed_multiplier":
			return "%"
		&"delayed_damage_duration", &"frosty_duration", &"adrenaline_duration":
			return "s"
		&"healing_rate":
			return "/s"
		_:
			return ""


func _armor_attribute_decimals(attribute: StringName) -> int:
	if attribute == &"freeze_resistance" or attribute == &"reflect_chance":
		return 0
	if attribute == &"delayed_damage_duration" \
			or attribute == &"frosty_duration" \
			or attribute == &"adrenaline_duration":
		return 1
	return 0


func _armor_attribute_lower_is_better(attribute: StringName) -> bool:
	return attribute == &"frosty_speed_multiplier"


func _weapon_attribute_lower_is_better(attribute: StringName) -> bool:
	return attribute == &"reload_time" \
		or attribute == &"projectile_gravity" \
		or attribute == &"projectile_linear_damping" \
		or attribute == &"shot_spread_degrees" \
		or attribute == &"shot_random_spread_degrees" \
		or attribute == &"recoil_rotation_degrees"


func _is_inspectable_control(control: Control) -> bool:
	var current: Control = control
	while current != null:
		if current is ArmorItemCard \
				or current is WeaponExtensionItemCard \
				or current is ArmorOverlaySlot \
				or current is WeaponExtensionSlot \
				or current is RoundRewardSlot:
			return true
		current = current.get_parent_control()
	return false


func _short_description(description: String) -> String:
	if description.is_empty():
		return "No description available."
	var sentences: PackedStringArray = description.split(". ")
	return sentences[0] + ("." if not sentences[0].ends_with(".") else "")


func _show_round_reward_description(reward: Dictionary) -> void:
	var reward_type: StringName = StringName(str(reward.get("type", "")))
	var item_variant: Variant = reward.get("item", null)
	if reward_type == RoundRewardInventory.REWARD_EXTENSION:
		var extension_item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		_show_weapon_extension_description(extension_item)
	elif reward_type == RoundRewardInventory.REWARD_ARMOR:
		var armor_item: ArmorItemData = item_variant as ArmorItemData
		_show_armor_description(armor_item)
	var price: int = int(reward.get("price", 0))
	_description_meta.text += "  |  %d COINS" % price


func _on_armor_selected(item: ArmorItemData) -> void:
	if item == null:
		return
	ArmorInventory.equip_item(item)
	_show_armor_description(item)


func _on_armor_cleared(category_id: StringName) -> void:
	ArmorInventory.unequip_category(category_id)
	_description_title.text = ArmorItemData.category_display_name(category_id)
	_description_meta.text = "ARMOR SLOT  |  EMPTY"
	_description_body.text = "Drag a matching armor item here to equip it."
	_set_description_condition(0.0, Color8(98, 104, 110, 255), false)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	_show_default_weapon_stats(current_modifiers)


func _on_weapon_extension_selected(item: WeaponExtensionItem) -> void:
	if item == null:
		return
	ExtensionInventory.equip_item_for_local(item)
	_show_weapon_extension_description(item)


# Validate compatibility and coin cost before showing the merge confirmation.
func _on_weapon_extension_merge_requested(source_item: WeaponExtensionItem, target_item: WeaponExtensionItem) -> void:
	if not ExtensionInventory.can_merge_items(source_item, target_item):
		_show_merge_error("Invalid merge", "Only two copies of the same extension and same MK can be merged.")
		return
	var next_mark: int = source_item.mark + 1
	var merge_cost: int = ExtensionInventory.get_merge_cost_for_items(source_item, target_item)
	if OnlineMatch.get_local_coin_balance() < merge_cost:
		_show_not_enough_merge_coins_warning(next_mark, merge_cost)
		return

	_pending_merge_source = source_item
	_pending_merge_target = target_item
	_merge_dialog.title = "Merge Extensions"
	_merge_dialog.dialog_text = "Merge two %s items into MK%d?\n\nCost: %d coins\nBalance: %d coins" % [
		source_item.get_display_name(),
		next_mark,
		merge_cost,
		OnlineMatch.get_local_coin_balance(),
	]
	_merge_dialog.ok_button_text = "Merge (%d C)" % merge_cost
	_merge_dialog.cancel_button_text = "Cancel"
	_merge_dialog.popup_centered()


func _confirm_pending_extension_merge() -> void:
	var source_item: WeaponExtensionItem = _pending_merge_source
	var target_item: WeaponExtensionItem = _pending_merge_target
	_pending_merge_source = null
	_pending_merge_target = null

	var merge_cost: int = ExtensionInventory.get_merge_cost_for_items(source_item, target_item)
	var merged_item: WeaponExtensionItem = ExtensionInventory.try_merge_items_for_local(source_item, target_item)
	if merged_item == null:
		if OnlineMatch.get_local_coin_balance() < merge_cost:
			_show_not_enough_merge_coins_warning(source_item.mark + 1, merge_cost)
		else:
			_show_merge_error("Merge failed", "The merge could not be completed. Check coins and matching MK tiers.")
		return

	_refresh_shop_state()
	_show_weapon_extension_description(merged_item)
	_description_title.text = "Extension merged"
	_description_meta.text = "%s  |  MK%d  |  -%d COINS" % [
		merged_item.get_slot_display_name().to_upper(),
		merged_item.mark,
		merge_cost,
	]


func _show_merge_error(title: String, body: String) -> void:
	_description_title.text = title
	_description_meta.text = "MERGE"
	_description_body.text = body
	_set_description_condition(0.0, Color8(225, 82, 72, 255), false)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	_show_default_weapon_stats(current_modifiers)


func _show_not_enough_merge_coins_warning(next_mark: int, merge_cost: int) -> void:
	var balance: int = OnlineMatch.get_local_coin_balance()
	var body: String = "Merging into MK%d costs %d coins. You currently have %d." % [
		next_mark,
		merge_cost,
		balance,
	]
	_show_merge_error("Not enough coins", body)
	if _merge_warning_dialog == null:
		return
	_merge_warning_dialog.title = "Not Enough Coins"
	_merge_warning_dialog.dialog_text = "%s\n\nEarn more coins before merging these extensions." % body
	_merge_warning_dialog.popup_centered()


func _setup_merge_dialog() -> void:
	_merge_dialog = ConfirmationDialog.new()
	_merge_dialog.name = "ExtensionMergeDialog"
	add_child(_merge_dialog)
	_merge_dialog.confirmed.connect(_confirm_pending_extension_merge)

	_merge_warning_dialog = AcceptDialog.new()
	_merge_warning_dialog.name = "ExtensionMergeWarningDialog"
	_merge_warning_dialog.ok_button_text = "OK"
	add_child(_merge_warning_dialog)


func _on_weapon_extension_cleared(slot_key: StringName) -> void:
	ExtensionInventory.unequip_local(slot_key)
	_description_title.text = WeaponExtensionDefinition.slot_display_name(slot_key)
	_description_meta.text = "WEAPON SLOT  |  EMPTY"
	_description_body.text = "Drag a matching weapon extension here to equip it."
	_set_description_condition(0.0, Color8(98, 104, 110, 255), false)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	_show_default_weapon_stats(current_modifiers)


func _on_extension_inventory_changed(player_slot: int) -> void:
	if player_slot == ExtensionInventory.get_local_player_slot():
		_refresh_weapon_inventory()


func _on_extension_loadout_changed(player_slot: int) -> void:
	if player_slot == ExtensionInventory.get_local_player_slot():
		_refresh_weapon_slots()


# Shop claims report affordability and capacity errors through the details panel.
func _on_round_reward_claimed(source_kind: StringName, source_index: int) -> void:
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		_description_title.text = "Not enough coins"
		_description_meta.text = "SHOP  |  %d COINS REQUIRED" % price
		_description_body.text = "Earn coins through damage, survival, blocking and the first hit of a set."
		_set_description_condition(0.0, Color8(225, 82, 72, 255), false)
		var current_modifiers: Dictionary = _get_current_weapon_modifiers()
		_show_default_weapon_stats(current_modifiers)
		return
	if RoundRewardInventory.claim_reward(source_kind, source_index):
		_description_title.text = "Item purchased"
		_description_meta.text = "INVENTORY UPDATED  |  -%d COINS" % price
		_description_body.text = "The item was added to your inventory and is ready to equip."
		_set_description_condition(0.0, Color8(72, 190, 111, 255), false)
		var current_modifiers: Dictionary = _get_current_weapon_modifiers()
		_show_default_weapon_stats(current_modifiers)


func _on_reward_dropped_to_saved(payload: Dictionary, target_index: int) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	RoundRewardInventory.move_to_saved(source_kind, source_index, target_index)


func _on_reward_dropped_to_inventory(payload: Dictionary) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	_on_round_reward_claimed(source_kind, source_index)


func _on_reward_recycled(refund: int) -> void:
	_description_title.text = "Blueprint recycled"
	_description_meta.text = "RECYCLER  |  +%d COINS" % refund
	_description_body.text = "The blueprint was dismantled and its value returned to your balance."
	_set_description_condition(0.0, Color8(72, 190, 111, 255), false)
	var current_modifiers: Dictionary = _get_current_weapon_modifiers()
	_show_default_weapon_stats(current_modifiers)
