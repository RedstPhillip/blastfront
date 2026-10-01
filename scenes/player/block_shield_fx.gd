class_name BlockShieldFx
extends Node2D

## Energy arc that visualises the active block cone in front of the player.

const INNER_RADIUS: float = 27.0
const OUTER_RADIUS: float = 36.0
const SEGMENTS: int = 28

var shield_color: Color = Color(0.55, 0.95, 1.0, 1.0)

var _player: Player = null
var _visibility: float = 0.0
var _pop: float = 0.0
var _was_blocking: bool = false
var _time: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	material = FxLib.additive_material()
	z_index = 4


func _process(delta: float) -> void:
	if _player == null:
		return
	_time += delta
	var blocking: bool = _player.is_blocking() and not _player.is_eliminated()
	if blocking and not _was_blocking:
		_pop = 1.0
	_was_blocking = blocking
	_visibility = move_toward(_visibility, 1.0 if blocking else 0.0, delta * (14.0 if blocking else 7.0))
	_pop = maxf(_pop - delta * 6.0, 0.0)
	global_rotation = 0.0
	if _visibility > 0.0:
		queue_redraw()
	elif visible:
		queue_redraw()


func _draw() -> void:
	if _visibility <= 0.001 or _player == null:
		return
	var direction: Vector2 = _player.get_block_direction()
	var half_angle: float = deg_to_rad(_player.block_cone_degrees * 0.5)
	var center_angle: float = direction.angle()
	var grow: float = lerpf(0.65, 1.0, _visibility) + _pop * 0.18
	var inner: float = INNER_RADIUS * grow
	var outer: float = OUTER_RADIUS * grow
	var shimmer: float = 0.75 + 0.25 * sin(_time * 22.0)
	var fill_color: Color = Color(shield_color.r, shield_color.g, shield_color.b, 0.22 * _visibility * shimmer)
	var edge_color: Color = Color(shield_color.r, shield_color.g, shield_color.b, 0.95 * _visibility)
	var band: PackedVector2Array = PackedVector2Array()
	var rim: PackedVector2Array = PackedVector2Array()
	for index in range(SEGMENTS + 1):
		var t: float = float(index) / float(SEGMENTS)
		var angle: float = center_angle - half_angle + t * half_angle * 2.0
		var direction_vector: Vector2 = Vector2(cos(angle), sin(angle))
		band.append(direction_vector * outer)
		rim.append(direction_vector * outer)
	for index in range(SEGMENTS, -1, -1):
		var t: float = float(index) / float(SEGMENTS)
		var angle: float = center_angle - half_angle + t * half_angle * 2.0
		band.append(Vector2(cos(angle), sin(angle)) * inner)
	draw_colored_polygon(band, fill_color)
	draw_polyline(rim, edge_color, 2.2 + _pop * 2.0, true)
	var hex_color: Color = Color(1.0, 1.0, 1.0, 0.35 * _visibility * shimmer)
	for index in range(1, 6):
		var t: float = float(index) / 6.0
		var angle: float = center_angle - half_angle + t * half_angle * 2.0
		var direction_vector: Vector2 = Vector2(cos(angle), sin(angle))
		draw_line(direction_vector * inner * 1.05, direction_vector * outer * 0.98, hex_color, 1.0, true)
