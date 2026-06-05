extends Node2D
class_name ArmorVisualRoot

@onready var _boots_anchor: Node2D = %BootsAnchor
@onready var _vest_anchor: Node2D = %VestAnchor
@onready var _shield_anchor: Node2D = %ShieldAnchor


func apply_loadout(loadout: ArmorLoadout) -> void:
	if loadout == null:
		clear_all()
		return
	_apply_item_to_anchor(_boots_anchor, loadout.get_equipped_item(ArmorItemData.CATEGORY_BOOTS))
	_apply_item_to_anchor(_vest_anchor, loadout.get_equipped_item(ArmorItemData.CATEGORY_VEST))
	_apply_item_to_anchor(_shield_anchor, loadout.get_equipped_item(ArmorItemData.CATEGORY_SHIELD))


func apply_item(item: ArmorItemData) -> void:
	if item == null:
		return
	var anchor: Node2D = _get_anchor(item.category)
	if anchor != null:
		_apply_item_to_anchor(anchor, item)


func clear_all() -> void:
	_clear_anchor(_boots_anchor)
	_clear_anchor(_vest_anchor)
	_clear_anchor(_shield_anchor)


func _get_anchor(category_id: StringName) -> Node2D:
	match category_id:
		ArmorItemData.CATEGORY_BOOTS:
			return _boots_anchor
		ArmorItemData.CATEGORY_VEST:
			return _vest_anchor
		ArmorItemData.CATEGORY_SHIELD:
			return _shield_anchor
		_:
			return null


func _apply_item_to_anchor(anchor: Node2D, item: ArmorItemData) -> void:
	_clear_anchor(anchor)
	if anchor == null or item == null:
		return

	if item.visual_scene != null:
		var visual: Node = item.visual_scene.instantiate()
		anchor.add_child(visual)
		return

	var texture: Texture2D = item.preview_texture
	if texture == null:
		texture = item.icon
	if texture == null:
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.modulate = item.get_condition_color()
	sprite.scale = Vector2(0.08, 0.08)
	anchor.add_child(sprite)


func _clear_anchor(anchor: Node2D) -> void:
	if anchor == null:
		return
	for child in anchor.get_children():
		child.queue_free()
