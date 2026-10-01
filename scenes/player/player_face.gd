class_name PlayerFace
extends Node2D

## Procedural eyes for the ball characters. Drawn in body-texture space (512 px ≈ one body) and
## scaled with the body sprite so squash and stretch carry over.

enum Mood { NORMAL, HURT, FOCUS, HAPPY, SHOCKED }

const BODY_TEXTURE_SIZE: float = 512.0
const EYE_HALF_SIZE: Vector2 = Vector2(30.0, 58.0)
const EYE_SPACING: float = 170.0
const EYE_BASE_Y: float = -22.0
const LOOK_RANGE: Vector2 = Vector2(62.0, 40.0)
const EYE_COLOR: Color = Color(0.02, 0.025, 0.03, 1.0)
const HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.92)
const DOT_TEXTURE: Texture2D = preload("res://assets/fx/dot.png")

var body_sprite: Sprite2D = null
var look_target: Vector2 = Vector2.RIGHT

var _look: Vector2 = Vector2.RIGHT * 0.6
var _blink: float = 0.0
var _blink_timer: float = 2.0
var _double_blink: bool = false
var _expression: Mood = Mood.NORMAL
var _expression_timer: float = 0.0
var _sweat: bool = false
var _sweat_phase: float = 0.0
var _pupil_pulse: float = 0.0
var _drawn_look: Vector2 = Vector2(INF, INF)
var _drawn_expression: Mood = Mood.NORMAL
var _was_animating: bool = true


func _ready() -> void:
	_blink_timer = randf_range(1.2, 3.5)


func set_expression(expression: Mood, duration: float) -> void:
	_expression = expression
	_expression_timer = duration
	if expression == Mood.SHOCKED:
		_pupil_pulse = 1.0


func set_sweating(enabled: bool) -> void:
	_sweat = enabled


func _process(delta: float) -> void:
	if body_sprite != null:
		scale = body_sprite.scale
		position = body_sprite.position
	_look = _look.lerp(look_target.limit_length(1.0), 1.0 - exp(-14.0 * delta))
	_update_blink(delta)
	if _expression_timer > 0.0:
		_expression_timer -= delta
		if _expression_timer <= 0.0:
			_expression = Mood.NORMAL
	_pupil_pulse = maxf(_pupil_pulse - delta * 3.0, 0.0)
	_sweat_phase += delta
	var animating: bool = _blink > 0.0 or _pupil_pulse > 0.0 or _sweat
	if animating or _look.distance_squared_to(_drawn_look) > 0.00002 or _expression != _drawn_expression or _was_animating:
		_drawn_look = _look
		_drawn_expression = _expression
		queue_redraw()
	_was_animating = animating


func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink <= 0.0:
		_blink = 1.0
		_blink_timer = 0.12 if _double_blink else randf_range(2.2, 5.5)
		_double_blink = not _double_blink and randf() < 0.22
	if _blink > 0.0:
		_blink = maxf(_blink - delta / 0.14, 0.0)


func _draw() -> void:
	var pair_center: Vector2 = Vector2(_look.x * LOOK_RANGE.x, EYE_BASE_Y + _look.y * LOOK_RANGE.y)
	var spacing: float = EYE_SPACING * (1.0 - absf(_look.x) * 0.12)
	for side in [-1.0, 1.0]:
		var center: Vector2 = pair_center + Vector2(side * spacing * 0.5, 0.0)
		var edge_ratio: float = clampf(absf(center.x) / 235.0, 0.0, 0.95)
		var squeeze: float = sqrt(1.0 - edge_ratio * edge_ratio)
		match _expression:
			Mood.HURT:
				_draw_chevron(center, side, squeeze)
			Mood.HAPPY:
				_draw_arc_eye(center, squeeze)
			_:
				_draw_oval_eye(center, squeeze, side)
	if _sweat:
		_draw_sweat_drop(pair_center)


func _draw_oval_eye(center: Vector2, squeeze: float, side: float) -> void:
	var half: Vector2 = EYE_HALF_SIZE * Vector2(squeeze, 1.0)
	var openness: float = 1.0
	if _blink > 0.0:
		openness = absf(_blink * 2.0 - 1.0)
		openness = maxf(openness, 0.08)
	if _expression == Mood.FOCUS:
		openness = minf(openness, 0.55)
	if _expression == Mood.SHOCKED:
		half *= 1.0 + _pupil_pulse * 0.25
	half.y *= openness
	if openness < 0.2:
		draw_line(center + Vector2(-half.x, 0.0), center + Vector2(half.x, 0.0), EYE_COLOR, 12.0, true)
		return
	_draw_ellipse(center, half, EYE_COLOR)
	if _expression == Mood.FOCUS:
		var brow_y: float = center.y - half.y - 10.0
		draw_line(center + Vector2(-half.x * 1.3, brow_y - center.y - 6.0 * side), center + Vector2(half.x * 1.3, brow_y - center.y + 6.0 * side), EYE_COLOR, 13.0, true)
	var highlight: Vector2 = center + Vector2(-half.x * 0.35, -half.y * 0.45)
	_draw_ellipse(highlight, Vector2(half.x * 0.32, half.y * 0.2), HIGHLIGHT_COLOR)


func _draw_chevron(center: Vector2, side: float, squeeze: float) -> void:
	var w: float = EYE_HALF_SIZE.x * 1.25 * squeeze
	var h: float = EYE_HALF_SIZE.y * 0.6
	var tip: Vector2 = center + Vector2(side * -w * 0.5, 0.0)
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(side * w * 0.7, -h),
		tip,
		center + Vector2(side * w * 0.7, h),
	])
	draw_polyline(points, EYE_COLOR, 16.0, true)


func _draw_arc_eye(center: Vector2, squeeze: float) -> void:
	var w: float = EYE_HALF_SIZE.x * 1.2 * squeeze
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(9):
		var t: float = float(index) / 8.0
		points.append(center + Vector2(lerpf(-w, w, t), -sin(t * PI) * EYE_HALF_SIZE.y * 0.55 + 8.0))
	draw_polyline(points, EYE_COLOR, 15.0, true)


func _draw_sweat_drop(pair_center: Vector2) -> void:
	var drip: float = fmod(_sweat_phase * 0.6, 1.0)
	var base: Vector2 = Vector2(pair_center.x + EYE_SPACING * 0.78, -120.0 + drip * 60.0)
	var alpha: float = 1.0 - drip
	var color: Color = Color(0.72, 0.9, 1.0, 0.9 * alpha)
	_draw_ellipse(base, Vector2(18.0, 24.0), color)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-15.0, -8.0), base + Vector2(0.0, -46.0), base + Vector2(15.0, -8.0)]), color)


func _draw_ellipse(center: Vector2, half: Vector2, color: Color) -> void:
	# Texture-based ellipse gets smooth, mipmapped edges at the tiny on-screen size.
	draw_texture_rect(DOT_TEXTURE, Rect2(center - half * 1.06, half * 2.12), false, color)
