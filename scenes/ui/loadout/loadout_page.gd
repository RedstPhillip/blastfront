extends Control
class_name LoadoutPage

const ARMOR_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout/ArmorItemCard.tscn")

var _armor_slots: Dictionary = {}

@onready var _description_title: Label = %DescriptionTitle
@onready var _description_body: Label = %DescriptionBody
@onready var _weapon_slot_one: Button = %WeaponSlotOne
@onready var _weapon_slot_two: Button = %WeaponSlotTwo
@onready var _weapon_slot_three: Button = %WeaponSlotThree
@onready var _weapon_inventory_empty_label: Label = %WeaponInventoryEmptyLabel
@onready var _armor_inventory_grid: FlowContainer = %ArmorInventoryGrid
@onready var _armor_inventory_empty_label: Label = %ArmorInventoryEmptyLabel
@onready var _boots_slot: ArmorOverlaySlot = %BootsSlot
@onready var _vest_slot: ArmorOverlaySlot = %VestSlot
@onready var _shield_slot: ArmorOverlaySlot = %ShieldSlot


func _ready() -> void:
	_armor_slots = {
		ArmorItemData.CATEGORY_BOOTS: _boots_slot,
		ArmorItemData.CATEGORY_VEST: _vest_slot,
		ArmorItemData.CATEGORY_SHIELD: _shield_slot,
	}

	_setup_weapon_placeholders()
	_setup_armor_slots()
	_connect_inventory_signals()
	_refresh_armor_inventory()
	_refresh_armor_slots()
	_show_default_description()


func _exit_tree() -> void:
	if ArmorInventory.inventory_changed.is_connected(_refresh_armor_inventory):
		ArmorInventory.inventory_changed.disconnect(_refresh_armor_inventory)
	if ArmorInventory.loadout_changed.is_connected(_refresh_armor_slots):
		ArmorInventory.loadout_changed.disconnect(_refresh_armor_slots)


func _setup_weapon_placeholders() -> void:
	var weapon_slots: Array[Button] = [_weapon_slot_one, _weapon_slot_two, _weapon_slot_three]
	for slot_index in range(weapon_slots.size()):
		var slot_button: Button = weapon_slots[slot_index]
		slot_button.text = ""
		slot_button.tooltip_text = "Weapon Extension slot %d" % (slot_index + 1)
		slot_button.mouse_entered.connect(_show_weapon_placeholder_description.bind(slot_index + 1))
	_weapon_inventory_empty_label.text = "Weapon Extensions werden hier angezeigt, sobald das Extension-System Daten bereitstellt."


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


func _show_weapon_placeholder_description(slot_number: int) -> void:
	_description_title.text = "Weapon Extension Slot %d" % slot_number
	_description_body.text = "Dieser Bereich ist vorbereitet, damit bestehende Weapon Extensions links neben Armor dargestellt werden koennen."


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
