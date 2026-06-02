class_name WeaponPreview2D
extends Node2D

@onready var _extension_visuals: WeaponExtensionVisuals = $ExtensionVisuals


func _ready() -> void:
	_connect_extension_inventory()
	refresh()


func refresh() -> void:
	if _extension_visuals == null:
		return

	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null or not inventory_node.has_method("get_equipped_for_local"):
		_extension_visuals.clear_all()
		return

	var equipped_variant: Variant = inventory_node.call("get_equipped_for_local")
	if equipped_variant is Dictionary:
		var equipped: Dictionary = equipped_variant
		_extension_visuals.set_extensions_by_slot(equipped)


func _connect_extension_inventory() -> void:
	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null or not inventory_node.has_signal("loadout_changed"):
		return
	var callback: Callable = Callable(self, "_on_loadout_changed")
	if not inventory_node.is_connected("loadout_changed", callback):
		inventory_node.connect("loadout_changed", callback)


func _on_loadout_changed(_player_slot: int) -> void:
	refresh()
