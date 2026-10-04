extends Node2D
class_name ArmorVisualRoot

## Dresses the in-match character in its equipped armor, drawn with ArmorArt: the vest on the body, a boot
## on each rendered foot (toes towards where the player last moved) and the shield in the guard hand.

@onready var _boots_anchor: Node2D = %BootsAnchor
@onready var _vest_anchor: Node2D = %VestAnchor
@onready var _shield_anchor: Node2D = %ShieldAnchor

@export var leg_renderer_path: NodePath = NodePath("../LegRenderer")
@export var arm_renderer_path: NodePath = NodePath("../ArmRenderer")

## Pieces are small on screen in a match; a heavier outline keeps them as crisp as the held carbine.
const IN_GAME_OUTLINE: float = 2.1
const BOOT_FLOOR_OFFSET: Vector2 = Vector2(0.0, -2.0)

var _equipped_boots: ArmorItemData = null
var _leg_renderer: Variant = null
var _arm_renderer: Variant = null
var _team_color: Color = ArmorArt.DEFAULT_TEAM
var _boot_facing: float = 1.0


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


## Starter pieces carry the owner's colour, like the stock carbine's accent.
func set_team_color(color: Color) -> void:
	_team_color = color
	for anchor in [_boots_anchor, _vest_anchor]:
		for node in anchor.find_children("*", "", true, false):
			var view: ArmorArtView = node as ArmorArtView
			if view != null:
				view.set_team_color(color)
	if _arm_renderer != null:
		_arm_renderer.set_shield_team_color(color)


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
	anchor.add_child(ArmorArtView.create(item, _team_color, IN_GAME_OUTLINE))


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
	_boots_anchor.add_child(foot_anchor)
	foot_anchor.add_child(ArmorArtView.create(_equipped_boots, _team_color, IN_GAME_OUTLINE))


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

	var player: Player = get_parent() as Player
	if player != null and signf(player.last_dir) != 0.0:
		_boot_facing = signf(player.last_dir)
	left_boot.position = foot_positions[0] + BOOT_FLOOR_OFFSET
	right_boot.position = foot_positions[1] + BOOT_FLOOR_OFFSET
	left_boot.scale = Vector2(_boot_facing, 1.0)
	right_boot.scale = Vector2(_boot_facing, 1.0)


func _apply_shield(item: ArmorItemData) -> void:
	_clear_anchor(_shield_anchor)
	if _arm_renderer == null:
		return
	if item != null:
		_arm_renderer.set_shield_item(item, _team_color, IN_GAME_OUTLINE)
	else:
		_clear_hand_shield()


func _clear_hand_shield() -> void:
	if _arm_renderer != null:
		_arm_renderer.clear_shield_item()


func _clear_anchor(anchor: Node2D) -> void:
	if anchor == null:
		return
	for child in anchor.get_children():
		child.queue_free()
