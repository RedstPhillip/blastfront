class_name LoadoutDragGhost
extends Control

## Drag preview that feels picked up: the card lifts out of its tile, eases onto the cursor and tilts
## with the hand's motion, like holding a physical part.

const LIFT_SCALE: float = 1.0

var _card: LoadoutItemTile = null
var _offset: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _tilt: float = 0.0
var _grow: float = 0.0


static func create(source: LoadoutItemTile) -> LoadoutDragGhost:
	return create_for_item(source.item, source.global_position, source.get_global_mouse_position())


static func create_for_item(item: Variant, source_global: Vector2, mouse_global: Vector2) -> LoadoutDragGhost:
	var ghost: LoadoutDragGhost = LoadoutDragGhost.new()
	ghost.process_mode = Node.PROCESS_MODE_ALWAYS
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 100
	var card: LoadoutItemTile = LoadoutItemTile.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.price = -1
	ghost.add_child(card)
	card.setup(item, false, false)
	card.focus_mode = Control.FOCUS_NONE
	card.set_process(false)
	card._hover = 1.0
	card.pivot_offset = card.size * 0.5
	ghost._card = card
	ghost._offset = source_global - mouse_global
	# The card hangs just below-right of the cursor so the hologram under the cursor stays visible.
	ghost._target = Vector2(14.0, 12.0)
	card.position = ghost._offset
	return ghost


func _ready() -> void:
	_last_position = global_position


func _process(delta: float) -> void:
	if _card == null:
		return
	_offset = _offset.lerp(_target, 1.0 - exp(-20.0 * delta))
	_grow = move_toward(_grow, 1.0, delta * 8.0)
	var moved: Vector2 = global_position - _last_position
	_last_position = global_position
	var desired_tilt: float = clampf(moved.x * 0.012, -0.32, 0.32) if delta > 0.0 else 0.0
	_tilt = lerpf(_tilt, desired_tilt, 1.0 - exp(-10.0 * delta))
	_card.position = _offset
	_card.rotation = _tilt
	_card.scale = Vector2.ONE * lerpf(1.06, 0.86, _grow * _grow * (3.0 - 2.0 * _grow))
	_card.modulate = Color(1.0, 1.0, 1.0, 0.96)
