class_name WeaponPreview2D
extends Node2D

@onready var _extension_visuals: WeaponExtensionVisuals = $ExtensionVisuals


func _ready() -> void:
	_connect_extension_inventory()
	refresh()


func refresh() -> void:
	if _extension_visuals == null:
		return

	_extension_visuals.set_extensions_by_slot(ExtensionInventory.get_equipped_for_local())


func _connect_extension_inventory() -> void:
	if not ExtensionInventory.loadout_changed.is_connected(_on_loadout_changed):
		ExtensionInventory.loadout_changed.connect(_on_loadout_changed)


func _on_loadout_changed(_player_slot: int) -> void:
	refresh()
