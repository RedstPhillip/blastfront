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

	for item in ExtensionInventory.get_inventory_for_local():
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
	if not ExtensionInventory.inventory_changed.is_connected(_on_inventory_changed):
		ExtensionInventory.inventory_changed.connect(_on_inventory_changed)

	if not ExtensionInventory.loadout_changed.is_connected(_on_loadout_changed):
		ExtensionInventory.loadout_changed.connect(_on_loadout_changed)


func _on_inventory_changed(_player_slot: int) -> void:
	_rebuild_inventory()


func _on_loadout_changed(_player_slot: int) -> void:
	if _weapon_preview != null:
		_weapon_preview.refresh()
