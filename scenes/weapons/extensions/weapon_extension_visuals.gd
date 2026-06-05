class_name WeaponExtensionVisuals
extends Node2D

var _spawned_visuals: Dictionary = {}


func set_extensions_by_slot(equipped_by_slot: Dictionary) -> void:
	for slot in WeaponExtensionDefinition.all_slots():
		var item_variant: Variant = equipped_by_slot.get(slot, equipped_by_slot.get(str(slot), null))
		set_extension_visual(slot, item_variant)


func set_extension_visual(slot: StringName, extension_variant: Variant) -> void:
	clear_extension_visual(slot)

	var socket: Node = _get_socket(slot)
	if socket == null:
		return

	var definition: WeaponExtensionDefinition = _get_definition(extension_variant)
	if definition == null or definition.visual_scene == null:
		return

	var visual_instance: Node = definition.visual_scene.instantiate()
	socket.add_child(visual_instance)
	_spawned_visuals[slot] = visual_instance


func clear_extension_visual(slot: StringName) -> void:
	var previous_visual: Node = _spawned_visuals.get(slot, null) as Node
	if previous_visual != null and is_instance_valid(previous_visual):
		previous_visual.queue_free()
	_spawned_visuals.erase(slot)


func clear_all() -> void:
	for slot in WeaponExtensionDefinition.all_slots():
		clear_extension_visual(slot)


func _get_definition(extension_variant: Variant) -> WeaponExtensionDefinition:
	var item: WeaponExtensionItem = extension_variant as WeaponExtensionItem
	if item != null:
		return item.definition

	var definition: WeaponExtensionDefinition = extension_variant as WeaponExtensionDefinition
	if definition != null:
		return definition

	return null


func _get_socket(slot: StringName) -> Node:
	match slot:
		WeaponExtensionDefinition.SLOT_MIDDLE:
			return get_node_or_null("MiddleSocket")
		WeaponExtensionDefinition.SLOT_AMMO:
			return get_node_or_null("AmmoSocket")
		WeaponExtensionDefinition.SLOT_FRONT:
			return get_node_or_null("FrontSocket")
	return null
