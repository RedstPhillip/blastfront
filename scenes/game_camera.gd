class_name GameCamera
extends Camera2D

## Smoothly frames the action. The owning game supplies a focus point and zoom each frame;
## the camera adds aim look-ahead, clamps to the playable bounds and layers GameJuice shake,
## kicks and zoom punches on top.

const LOOK_AHEAD_DISTANCE: float = 70.0
const LOOK_AHEAD_SPEED: float = 3.5
const VERTICAL_SLACK_TOP: float = GameSettings.CAMERA_BOARD_MARGIN_Y
## Dead zone around the framed point: small hops and dodges leave the view still (easier aiming); the
## camera only moves once the focus leaves this box, and then just enough to keep it at the edge.
const DEAD_ZONE: Vector2 = Vector2(56.0, 28.0)

@export var follow_speed: float = 5.5
@export var zoom_speed: float = 4.0

var focus_position: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0
var look_ahead_target: Vector2 = Vector2.ZERO
var bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS

var _base_position: Vector2 = Vector2.ZERO
var _base_zoom: float = 1.0
var _look_ahead: Vector2 = Vector2.ZERO
var _anchor: Vector2 = Vector2.INF


func _ready() -> void:
	ignore_rotation = false
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000
	position_smoothing_enabled = false


func uses_juice_values() -> bool:
	return true


func snap_to_target() -> void:
	_base_zoom = target_zoom
	_look_ahead = look_ahead_target
	_anchor = focus_position
	_base_position = _clamp_to_bounds(focus_position + _look_ahead, _base_zoom)
	_apply()


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001) if Engine.time_scale < 1.0 else delta
	real_delta = minf(real_delta, 0.1)
	_look_ahead = _look_ahead.lerp(look_ahead_target, 1.0 - exp(-LOOK_AHEAD_SPEED * real_delta))
	_base_zoom = lerpf(_base_zoom, target_zoom, 1.0 - exp(-zoom_speed * real_delta))
	var desired: Vector2 = _clamp_to_bounds(_dead_zone_anchor() + _look_ahead, _base_zoom)
	_base_position = _base_position.lerp(desired, 1.0 - exp(-follow_speed * real_delta))
	_apply()


func _dead_zone_anchor() -> Vector2:
	if _anchor == Vector2.INF:
		_anchor = focus_position
	var offset: Vector2 = focus_position - _anchor
	_anchor += Vector2(
		signf(offset.x) * maxf(absf(offset.x) - DEAD_ZONE.x, 0.0),
		signf(offset.y) * maxf(absf(offset.y) - DEAD_ZONE.y, 0.0)
	)
	return _anchor


func _apply() -> void:
	var final_zoom: float = _base_zoom * GameJuice.get_zoom_factor()
	zoom = Vector2.ONE * final_zoom
	global_position = _clamp_to_bounds(_base_position, final_zoom)
	offset = GameJuice.get_camera_offset()
	rotation = GameJuice.get_camera_roll()


## Where the mouse points in the world as the camera frames it before shake, kicks, roll and zoom punches.
## Aiming uses this, so screen feedback never moves what the player is aiming at.
func stable_mouse_world_position() -> Vector2:
	var viewport: Viewport = get_viewport()
	var screen: Vector2 = viewport.get_mouse_position()
	var center: Vector2 = _clamp_to_bounds(_base_position, _base_zoom)
	return center + (screen - viewport.get_visible_rect().size * 0.5) / maxf(_base_zoom, 0.01)


func get_view_size(at_zoom: float) -> Vector2:
	return get_viewport_rect().size / maxf(at_zoom, 0.01)


func _clamp_to_bounds(point: Vector2, at_zoom: float) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return point
	var half: Vector2 = get_view_size(at_zoom) * 0.5
	var result: Vector2 = point
	if half.x * 2.0 >= bounds.size.x:
		result.x = bounds.get_center().x
	else:
		result.x = clampf(point.x, bounds.position.x + half.x, bounds.end.x - half.x)
	# The view never reaches below the bottom border, where the terrain has faded into the abyss; a view
	# taller than the board (zoomed out) sits on that line and shows more sky instead.
	var top: float = bounds.position.y - VERTICAL_SLACK_TOP
	var bottom: float = bounds.end.y
	if half.y * 2.0 >= bottom - top:
		result.y = bottom - half.y
	else:
		result.y = clampf(point.y, top + half.y, bottom - half.y)
	return result
