extends Control
class_name LoadoutPage

const ARMOR_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout/ArmorItemCard.tscn")
const WEAPON_EXTENSION_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout/WeaponExtensionItemCard.tscn")

var _weapon_slots: Dictionary = {}
var _armor_slots: Dictionary = {}

@onready var _description_title: Label = %DescriptionTitle
@onready var _description_body: Label = %DescriptionBody
@onready var _weapon_slot_one: WeaponExtensionSlot = %WeaponSlotOne
@onready var _weapon_slot_two: WeaponExtensionSlot = %WeaponSlotTwo
@onready var _weapon_slot_three: WeaponExtensionSlot = %WeaponSlotThree
@onready var _weapon_inventory_grid: FlowContainer = %WeaponInventoryGrid
@onready var _weapon_inventory_empty_label: Label = %WeaponInventoryEmptyLabel
@onready var _armor_inventory_grid: FlowContainer = %ArmorInventoryGrid
@onready var _armor_inventory_empty_label: Label = %ArmorInventoryEmptyLabel
@onready var _boots_slot: ArmorOverlaySlot = %BootsSlot
@onready var _vest_slot: ArmorOverlaySlot = %VestSlot
@onready var _shield_slot: ArmorOverlaySlot = %ShieldSlot


func _ready() -> void:
	_weapon_slots = {
		WeaponExtensionDefinition.SLOT_MIDDLE: _weapon_slot_one,
		WeaponExtensionDefinition.SLOT_FRONT: _weapon_slot_two,
		WeaponExtensionDefinition.SLOT_AMMO: _weapon_slot_three,
	}
	_armor_slots = {
		ArmorItemData.CATEGORY_BOOTS: _boots_slot,
		ArmorItemData.CATEGORY_VEST: _vest_slot,
		ArmorItemData.CATEGORY_SHIELD: _shield_slot,
	}

	_setup_weapon_placeholders()
	_setup_armor_slots()
	_connect_inventory_signals()
	_refresh_weapon_inventory()
	_refresh_weapon_slots()
	_refresh_armor_inventory()
	_refresh_armor_slots()
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


func _connect_inventory_signals() -> void:
	if not ArmorInventory.inventory_changed.is_connected(_refresh_armor_inventory):
		ArmorInventory.inventory_changed.connect(_refresh_armor_inventory)
	if not ArmorInventory.loadout_changed.is_connected(_refresh_armor_slots):
		ArmorInventory.loadout_changed.connect(_refresh_armor_slots)
	if not ExtensionInventory.inventory_changed.is_connected(_on_extension_inventory_changed):
		ExtensionInventory.inventory_changed.connect(_on_extension_inventory_changed)
	if not ExtensionInventory.loadout_changed.is_connected(_on_extension_loadout_changed):
		ExtensionInventory.loadout_changed.connect(_on_extension_loadout_changed)


func _refresh_weapon_inventory() -> void:
	for child in _weapon_inventory_grid.get_children():
		child.queue_free()

	var items: Array[WeaponExtensionItem] = ExtensionInventory.get_inventory_for_local()
	_weapon_inventory_empty_label.visible = items.is_empty()
	if items.is_empty():
		_weapon_inventory_empty_label.text = "Lege WeaponExtensionDefinition-Ressourcen in ExtensionInventory an, um Extensions hier anzuzeigen."
		return

	for item in items:
		if item == null:
			continue
		var card: WeaponExtensionItemCard = WEAPON_EXTENSION_ITEM_CARD_SCENE.instantiate() as WeaponExtensionItemCard
		if card == null:
			continue
		card.setup(item)
		card.extension_hovered.connect(_show_weapon_extension_description)
		card.extension_selected.connect(_on_weapon_extension_selected)
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

	_armor_inventory_empty_label.visible = ArmorInventory.inventory.is_empty()
	if ArmorInventory.inventory.is_empty():
		_armor_inventory_empty_label.text = "Lege ArmorItemData-Ressourcen in data/armor/items ab, um Armor hier anzuzeigen."
		return

	for item in ArmorInventory.inventory:
		if item == null:
			continue
		var card: ArmorItemCard = ARMOR_ITEM_CARD_SCENE.instantiate() as ArmorItemCard
		if card == null:
			continue
		card.setup(item)
		card.armor_hovered.connect(_show_armor_description)
		card.armor_selected.connect(_on_armor_selected)
		_armor_inventory_grid.add_child(card)


func _refresh_armor_slots() -> void:
	_boots_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_BOOTS))
	_vest_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_VEST))
	_shield_slot.set_item(ArmorInventory.get_equipped_item(ArmorItemData.CATEGORY_SHIELD))


func _show_default_description() -> void:
	_description_title.text = "Loadout"
	_description_body.text = "Hover ueber Weapon Extensions oder Armor, um Item-Details, Condition und spaetere Effekte hier zu sehen."


func _show_weapon_extension_description(item: WeaponExtensionItem) -> void:
	if item == null or item.definition == null:
		_show_default_description()
		return
	var lines: Array[String] = []
	lines.append("%s | Mark %d | %s" % [item.get_slot_display_name(), item.definition.mark, item.get_condition_tier_name()])
	lines.append("Condition: %d / 100" % int(round(item.condition)))
	if not item.definition.description.is_empty():
		lines.append(item.definition.description)
	_description_title.text = item.get_display_name()
	_description_body.text = "\n".join(lines)


func _show_armor_description(item: ArmorItemData) -> void:
	if item == null:
		_show_default_description()
		return
	_description_title.text = item.get_hover_title()
	_description_body.text = item.get_hover_text()


func _on_armor_selected(item: ArmorItemData) -> void:
	if item == null:
		return
	ArmorInventory.equip_item(item)
	_show_armor_description(item)


func _on_armor_cleared(category_id: StringName) -> void:
	ArmorInventory.unequip_category(category_id)
	_description_title.text = ArmorItemData.category_display_name(category_id)
	_description_body.text = "Slot geleert. Ziehe spaeter ein passendes Armor-Item aus dem Inventar hierher."


func _on_weapon_extension_selected(item: WeaponExtensionItem) -> void:
	if item == null:
		return
	ExtensionInventory.equip_item_for_local(item)
	_show_weapon_extension_description(item)


func _on_weapon_extension_cleared(slot_key: StringName) -> void:
	ExtensionInventory.unequip_local(slot_key)
	_description_title.text = WeaponExtensionDefinition.slot_display_name(slot_key)
	_description_body.text = "Slot geleert. Ziehe eine passende Weapon Extension aus dem Inventar hierher."


func _on_extension_inventory_changed(player_slot: int) -> void:
	if player_slot == ExtensionInventory.get_local_player_slot():
		_refresh_weapon_inventory()


func _on_extension_loadout_changed(player_slot: int) -> void:
	if player_slot == ExtensionInventory.get_local_player_slot():
		_refresh_weapon_slots()
