class_name WeaponExtensionVisuals
extends Node2D

## Draws the held carbine with its equipped parts using the same art as the loadout, so a build is
## visible in the match too (yours and your opponent's). The art is mirrored into the gun's local space,
## where the barrel points to -x; the sibling sprite only stays as a fallback. The muzzle marker follows
## the installed barrel so shots leave from its tip.

const ART_SCALE: float = 1.1
const ART_OFFSET: Vector2 = Vector2(-27.75, -40.5)
const IN_GAME_OUTLINE: float = 4.2

@export var sprite_path: NodePath = NodePath("../Sprite2D")
@export var muzzle_path: NodePath = NodePath("../Muzzle")

var _config: Dictionary = {}
var _accent: Color = Color(0.32, 0.67, 1.0)


func _ready() -> void:
	var sprite: CanvasItem = get_node_or_null(sprite_path) as CanvasItem
	if sprite != null:
		sprite.visible = false
	_place_muzzle()
	queue_redraw()


func set_accent(color: Color) -> void:
	_accent = color
	queue_redraw()


func set_extensions_by_slot(equipped_by_slot: Dictionary) -> void:
	var equipped: Dictionary = {}
	for slot in WeaponExtensionDefinition.all_slots():
		equipped[slot] = equipped_by_slot.get(slot, equipped_by_slot.get(str(slot), null))
	_config = WeaponArt.config_from_equipped(equipped)
	_place_muzzle()
	queue_redraw()


func set_extension_visual(slot: StringName, extension_variant: Variant) -> void:
	var item: WeaponExtensionItem = extension_variant as WeaponExtensionItem
	if item != null and item.definition != null:
		_config[slot] = {"id": item.get_definition_id(), "mark": item.mark}
	else:
		_config.erase(slot)
	_place_muzzle()
	queue_redraw()


func clear_extension_visual(slot: StringName) -> void:
	_config.erase(slot)
	_place_muzzle()
	queue_redraw()


func clear_all() -> void:
	_config.clear()
	_place_muzzle()
	queue_redraw()


func _art_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(-ART_SCALE, ART_SCALE), 0.0, ART_OFFSET)


func _place_muzzle() -> void:
	var muzzle: Node2D = get_node_or_null(muzzle_path) as Node2D
	if muzzle != null:
		muzzle.position = position + _art_transform() * WeaponArt.muzzle_position(_config)


func _draw() -> void:
	WeaponArt.draw_weapon(self, _art_transform(), _config, {"accent": _accent, "outline": IN_GAME_OUTLINE})
