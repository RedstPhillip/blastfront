class_name ExtensionWorkbench
extends Control

const CARD_SCENE: PackedScene = preload("res://scenes/menus/extensions/extension_inventory_card.tscn")

@onready var _inventory_row: HBoxContainer = %InventoryRow
@onready var _weapon_preview: WeaponPreview2D = %WeaponPreview
@onready var _weapon_canvas: Control = %WeaponCanvas


func _ready() -> void:
	_connect_extension_inventory()
	_rebuild_inventory()
	_position_weapon_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_position_weapon_preview()


func _rebuild_inventory() -> void:
	for child in _inventory_row.get_children():
		child.queue_free()

	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null or not inventory_node.has_method("get_inventory_for_local"):
		return

	var inventory_variant: Variant = inventory_node.call("get_inventory_for_local")
	if not (inventory_variant is Array):
		return

	var inventory_items: Array = inventory_variant
	for item_variant in inventory_items:
		var item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if item == null:
			continue

		var card: ExtensionInventoryCard = CARD_SCENE.instantiate() as ExtensionInventoryCard
		_inventory_row.add_child(card)
		card.setup(item)


func _position_weapon_preview() -> void:
	if _weapon_preview == null or _weapon_canvas == null:
		return

	var canvas_size: Vector2 = _weapon_canvas.size
	_weapon_preview.position = canvas_size * 0.5 + Vector2(20.0, 8.0)
	_weapon_preview.scale = Vector2(4.2, 4.2)


func _connect_extension_inventory() -> void:
	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null:
		return

	if inventory_node.has_signal("inventory_changed"):
		var inventory_callback: Callable = Callable(self, "_on_inventory_changed")
		if not inventory_node.is_connected("inventory_changed", inventory_callback):
			inventory_node.connect("inventory_changed", inventory_callback)

	if inventory_node.has_signal("loadout_changed"):
		var loadout_callback: Callable = Callable(self, "_on_loadout_changed")
		if not inventory_node.is_connected("loadout_changed", loadout_callback):
			inventory_node.connect("loadout_changed", loadout_callback)


func _on_inventory_changed(_player_slot: int) -> void:
	_rebuild_inventory()


func _on_loadout_changed(_player_slot: int) -> void:
	if _weapon_preview != null:
		_weapon_preview.refresh()
