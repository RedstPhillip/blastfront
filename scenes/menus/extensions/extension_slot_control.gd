class_name ExtensionSlotControl
extends PanelContainer

@export_enum("middle", "ammo", "front") var slot_key: String = "middle"
@export var display_name: String = "Slot"

@onready var _title_label: Label = %TitleLabel
@onready var _equipped_label: Label = %EquippedLabel
@onready var _condition_label: Label = %ConditionLabel
@onready var _clear_button: Button = %ClearButton


func _ready() -> void:
	_title_label.text = display_name
	_clear_button.pressed.connect(_on_clear_pressed)
	_connect_extension_inventory()
	refresh()


func refresh() -> void:
	var item: WeaponExtensionItem = _get_equipped_item()
	if item == null:
		_equipped_label.text = "Empty"
		_condition_label.text = "Drag a matching extension here"
		_condition_label.add_theme_color_override("font_color", Color(0.7, 0.76, 0.78, 1.0))
		_clear_button.disabled = true
		return

	var tier_color: Color = item.get_condition_color()
	_equipped_label.text = item.get_display_name()
	_condition_label.text = "%s  %.1f" % [item.get_condition_tier_name(), item.condition]
	_equipped_label.add_theme_color_override("font_color", tier_color)
	_condition_label.add_theme_color_override("font_color", tier_color)
	_clear_button.disabled = false


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var item: WeaponExtensionItem = _extract_item(data)
	return item != null and item.get_slot() == StringName(slot_key)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var item: WeaponExtensionItem = _extract_item(data)
	if item == null:
		return

	ExtensionInventory.equip_item_for_local(item)


func _extract_item(data: Variant) -> WeaponExtensionItem:
	if not (data is Dictionary):
		return null

	var drag_data: Dictionary = data
	if str(drag_data.get("kind", "")) != ExtensionInventoryCard.DRAG_KIND:
		return null

	return drag_data.get("item", null) as WeaponExtensionItem


func _get_equipped_item() -> WeaponExtensionItem:
	return ExtensionInventory.get_equipped_item_for_local(StringName(slot_key))


func _connect_extension_inventory() -> void:
	var callback: Callable = Callable(self, "_on_loadout_changed")
	if not ExtensionInventory.loadout_changed.is_connected(callback):
		ExtensionInventory.loadout_changed.connect(callback)


func _on_loadout_changed(_player_slot: int) -> void:
	refresh()


func _on_clear_pressed() -> void:
	ExtensionInventory.unequip_local(StringName(slot_key))
