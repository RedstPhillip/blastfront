extends Node2D
class_name ArmorVisualRoot

@onready var _boots_anchor: Node2D = %BootsAnchor
@onready var _vest_anchor: Node2D = %VestAnchor
@onready var _shield_anchor: Node2D = %ShieldAnchor

@export var leg_renderer_path: NodePath = NodePath("../LegRenderer")
@export var arm_renderer_path: NodePath = NodePath("../ArmRenderer")

var _equipped_boots: ArmorItemData = null
var _leg_renderer: Variant = null
var _arm_renderer: Variant = null
const BOOT_FLOOR_OFFSET: Vector2 = Vector2(0.0, -2.0)


func _ready() -> void:
	_leg_renderer = get_node_or_null(leg_renderer_path)
	_arm_renderer = get_node_or_null(arm_renderer_path)
	_boots_anchor.position = Vector2.ZERO


func _process(_delta: float) -> void:
	_update_boot_positions()


func apply_loadout(loadout: ArmorLoadout) -> void:
	if loadout == null:
		clear_all()
		return
	_apply_boots(loadout.get_equipped_item(ArmorItemData.CATEGORY_BOOTS))
	_apply_item_to_anchor(_vest_anchor, loadout.get_equipped_item(ArmorItemData.CATEGORY_VEST))
	_apply_shield(loadout.get_equipped_item(ArmorItemData.CATEGORY_SHIELD))


func apply_item(item: ArmorItemData) -> void:
	if item == null:
		return
	var anchor: Node2D = _get_anchor(item.category)
	if item.category == ArmorItemData.CATEGORY_BOOTS:
		_apply_boots(item)
	elif item.category == ArmorItemData.CATEGORY_SHIELD:
		_apply_shield(item)
	elif anchor != null:
		_apply_item_to_anchor(anchor, item)


func clear_all() -> void:
	_equipped_boots = null
	_clear_anchor(_boots_anchor)
	_clear_anchor(_vest_anchor)
	_clear_anchor(_shield_anchor)
	_clear_hand_shield()


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


func _apply_boots(item: ArmorItemData) -> void:
	_equipped_boots = item
	_clear_anchor(_boots_anchor)
	if item == null:
		return

	_add_boot_visual("LeftBootVisual")
	_add_boot_visual("RightBootVisual")
	_update_boot_positions()


func _add_boot_visual(node_name: String) -> void:
	if _equipped_boots == null:
		return

	var foot_anchor: Node2D = Node2D.new()
	foot_anchor.name = node_name
	foot_anchor.scale = Vector2(0.58, 0.58)
	_boots_anchor.add_child(foot_anchor)

	if _equipped_boots.visual_scene != null:
		foot_anchor.add_child(_equipped_boots.visual_scene.instantiate())
		return

	var texture: Texture2D = _equipped_boots.preview_texture
	if texture == null:
		texture = _equipped_boots.icon
	if texture == null:
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.modulate = _equipped_boots.get_condition_color()
	sprite.scale = Vector2(0.04, 0.04)
	foot_anchor.add_child(sprite)


func _update_boot_positions() -> void:
	if _equipped_boots == null or _boots_anchor == null or _leg_renderer == null:
		return
	if _boots_anchor.get_child_count() < 2:
		return

	var foot_positions: Array[Vector2] = _leg_renderer.get_rendered_foot_positions()
	if foot_positions.size() < 2:
		return

	var left_boot: Node2D = _boots_anchor.get_child(0) as Node2D
	var right_boot: Node2D = _boots_anchor.get_child(1) as Node2D
	if left_boot == null or right_boot == null:
		return

	left_boot.position = foot_positions[0] + BOOT_FLOOR_OFFSET
	right_boot.position = foot_positions[1] + BOOT_FLOOR_OFFSET


func _apply_shield(item: ArmorItemData) -> void:
	_clear_anchor(_shield_anchor)
	if _arm_renderer == null:
		return
	if item != null and item.visual_scene != null:
		_arm_renderer.set_shield_visual_scene(item.visual_scene)
	else:
		_clear_hand_shield()


func _clear_hand_shield() -> void:
	if _arm_renderer != null:
		_arm_renderer.clear_shield_visual_scene()


func _clear_anchor(anchor: Node2D) -> void:
	if anchor == null:
		return
	for child in anchor.get_children():
		child.queue_free()
