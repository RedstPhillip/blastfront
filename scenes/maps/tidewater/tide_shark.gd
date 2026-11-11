class_name TideShark
extends Node2D

## One of Tidewater's sharks, as it looks and moves: steered by TidewaterSharks, drawn here every frame.
## Local space has the snout on +x.
##
## It swims the way a shark does, seen from the side. The tail beats sideways, towards and away from the
## viewer, so the beat shows as the tail fin narrowing and widening and the tail stock shortening a touch,
## never as the body waving up and down. Strokes come hard while it accelerates and fade into a glide
## when it does not. The body is not a rigid stick either: every section follows the path the head took a
## moment earlier, so diving under a floor or arcing out of the water bends it along its own line. A turn
## is an arc in depth: the body foreshortens through the turn and opens out again facing the other way,
## it never rotates through the vertical. The jaw opens on `jaw` (0..1) to a dark mouth and two rows of
## teeth. It sits under the sea's own layer, so the water tints and bends everything below the line.

const LENGTH: float = 176.0
const SECTIONS: int = 16
const BODY_SPAN: float = 150.0
const DORSAL_RISE: float = 32.0
## Sideways speed at which the body is seen fully side-on; slower than this it is part-way through a turn.
const SIDE_ON_SPEED: float = 64.0
## Thinnest the body gets while it points at (or away from) the viewer in a turn.
const TURN_MIN_WIDTH: float = 0.2
## Steepest nose-up or nose-down while swimming; a lunge may stand it almost on end.
const SWIM_PITCH: float = 0.62
const LUNGE_PITCH: float = 1.45
const TRAIL_LENGTH: int = 48
const BACK_COLOR: Color = Color(0.2, 0.28, 0.34)
const FLANK_COLOR: Color = Color(0.33, 0.43, 0.49)
const BELLY_COLOR: Color = Color(0.82, 0.88, 0.88)
const BELLY_SHADE: Color = Color(0.62, 0.71, 0.74)
const FIN_COLOR: Color = Color(0.17, 0.24, 0.3)
const FAR_FIN_COLOR: Color = Color(0.12, 0.17, 0.22)
const OUTLINE_COLOR: Color = Color(0.04, 0.07, 0.09, 0.95)
const MOUTH_COLOR: Color = Color(0.24, 0.05, 0.07)
const GUM_COLOR: Color = Color(0.62, 0.3, 0.32)
const TOOTH_COLOR: Color = Color(0.97, 0.97, 0.92)
const RIM_COLOR: Color = Color(0.62, 0.84, 0.88, 0.4)

## How far the jaw is open (0 shut .. 1 wide).
var jaw: float = 0.0

var _swim_phase: float = 0.0
## Strength of the tail beat right now (0 gliding .. 1 all out), eased so strokes swell and fade.
var _stroke: float = 0.2
## Signed width of the body as seen: +1 side-on facing right, -1 facing left, small in the middle of a turn.
var _side: float = 1.0
var _pitch: float = 0.0
var _speed: float = 0.0
var _frame_time: float = 1.0 / 60.0
## The pitch of the last frames, newest first: what the rear of the body still follows.
var _trail: PackedFloat32Array = PackedFloat32Array()
var _top: PackedVector2Array = PackedVector2Array()
var _bottom: PackedVector2Array = PackedVector2Array()
var _center: PackedFloat32Array = PackedFloat32Array()
var _tail_angle: float = 0.0


## Moves the swimming on by one frame from how it is travelling. `effort` (0..1) is how hard it is working
## (accelerating, rushing); `lunging` lets it pitch as steep as its path and snaps a turn through.
func animate(delta: float, velocity: Vector2, effort: float, lunging: bool) -> void:
	_frame_time = maxf(delta, 0.001)
	_speed = velocity.length()
	# Facing: side-on at speed, foreshortened while the sideways speed passes through zero in a turn.
	var side_target: float = clampf(velocity.x / SIDE_ON_SPEED, -1.0, 1.0)
	if absf(velocity.x) < 4.0:
		side_target = _side
	_side = move_toward(_side, side_target, delta * (9.0 if lunging else 3.4))
	var eased: float = sin(_side * PI * 0.5)
	var width: float = signf(eased) * maxf(absf(eased), TURN_MIN_WIDTH) if absf(eased) > 0.001 else TURN_MIN_WIDTH
	# Pitch: along the path, but a swimming shark never stands on its nose.
	var forward: float = maxf(absf(velocity.x), 1.0 if lunging else 120.0)
	var limit: float = LUNGE_PITCH if lunging else SWIM_PITCH
	var pitch_target: float = clampf(atan2(velocity.y, forward), -limit, limit)
	_pitch = lerp_angle(_pitch, pitch_target, 1.0 - exp(-delta * (20.0 if lunging else 6.5)))
	scale = Vector2(width, 1.0)
	rotation = _pitch * signf(width)
	if _trail.size() != TRAIL_LENGTH:
		_trail.resize(TRAIL_LENGTH)
		_trail.fill(_pitch)
	for index in range(TRAIL_LENGTH - 1, 0, -1):
		_trail[index] = _trail[index - 1]
	_trail[0] = _pitch
	# The beat: quicker with speed, hard when working, fading into a glide.
	var stroke_target: float = clampf(0.14 + effort * 0.86, 0.0, 1.0)
	_stroke = move_toward(_stroke, stroke_target, delta * (4.5 if stroke_target > _stroke else 1.3))
	_swim_phase = fmod(_swim_phase + delta * TAU * (0.5 + _speed / 290.0 + _stroke * 1.5), TAU)
	queue_redraw()


## The tip of the dorsal fin in world space: where the wake starts while it cuts the surface.
func fin_tip() -> Vector2:
	return to_global(Vector2(_section_x(0.5) - 2.0, -DORSAL_RISE - 14.0))


## Whether it is seen side-on right now (not in the thin middle of a turn).
func is_side_on() -> bool:
	return absf(_side) > 0.6


func _section_x(u: float) -> float:
	return LENGTH * 0.5 - u * BODY_SPAN


func _girth(u: float) -> float:
	return pow(sin(PI * pow(u, 0.7)), 0.85)


## The pitch the head had when it was where the section at u is now.
func _trail_pitch(u: float) -> float:
	var seconds: float = minf(u * BODY_SPAN / maxf(_speed, 70.0), 0.7)
	return _trail[mini(int(seconds / _frame_time), TRAIL_LENGTH - 1)]


func _build_sections() -> void:
	_top.resize(SECTIONS + 1)
	_bottom.resize(SECTIONS + 1)
	_center.resize(SECTIONS + 1)
	var bend: float = 0.0
	var segment: float = BODY_SPAN / float(SECTIONS)
	for index in range(SECTIONS + 1):
		var u: float = float(index) / float(SECTIONS)
		# The body lies along the path the head took: where the head has since pitched, the rear lags.
		var lag: float = clampf(_trail_pitch(u) - _pitch, -0.75, 0.75)
		if index > 0:
			bend -= sin(lag) * segment
		_tail_angle = lag
		# The sideways beat, seen from the side: the tail stock swings towards the viewer and away, which
		# shortens it a touch; only a trace of it shows as height.
		var beat: float = sin(_swim_phase - u * 3.2)
		var x: float = _section_x(u) + (1.0 - absf(beat)) * 3.4 * _stroke * u * u
		var y: float = bend + beat * 0.9 * _stroke * pow(u, 1.8) - 2.6 * exp(-u * 8.0)
		var girth: float = _girth(u)
		_center[index] = y
		_top[index] = Vector2(x, y - (19.0 * girth + 1.2 + 2.2 * u))
		_bottom[index] = Vector2(x, y + (23.0 * girth * (1.0 - 0.3 * u) + 1.2 + 1.6 * u))


func _at_top(u: float) -> Vector2:
	var scaled: float = clampf(u, 0.0, 1.0) * float(SECTIONS)
	var index: int = mini(int(scaled), SECTIONS - 1)
	return _top[index].lerp(_top[index + 1], scaled - float(index))


func _at_bottom(u: float) -> Vector2:
	var scaled: float = clampf(u, 0.0, 1.0) * float(SECTIONS)
	var index: int = mini(int(scaled), SECTIONS - 1)
	return _bottom[index].lerp(_bottom[index + 1], scaled - float(index))


func _draw() -> void:
	if _trail.size() != TRAIL_LENGTH:
		return
	_build_sections()
	_draw_tail()
	_draw_pectoral(8.0, FAR_FIN_COLOR, 0.82)
	_draw_dorsals()
	_draw_lower_fins()
	_draw_body()
	_draw_pectoral(0.0, FIN_COLOR, 1.0)
	_draw_head()


## A fin (or the jaw): a fan of triangles from its first point, then its outline. Fans cannot fail the way
## polygon triangulation does when a bent body folds a shape over itself for a frame.
func _fin(points: PackedVector2Array, color: Color) -> void:
	_fan(points, color)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.3, true)


func _fan(points: PackedVector2Array, color: Color) -> void:
	var indices: PackedInt32Array = PackedInt32Array()
	for index in range(1, points.size() - 1):
		indices.append(0)
		indices.append(index)
		indices.append(index + 1)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, PackedColorArray([color]))


## A band between two rows of points (one colour per row), section by section.
func _band(upper: PackedVector2Array, lower: PackedVector2Array, upper_color: Color, lower_color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for index in range(upper.size()):
		points.append(upper[index])
		points.append(lower[index])
		colors.append(upper_color)
		colors.append(lower_color)
	for index in range(upper.size() - 1):
		var base: int = index * 2
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)


## The tail fin: it trails along the body's line, and its sideways beat shows as the fin narrowing as it
## swings through and widening at the end of each stroke.
func _draw_tail() -> void:
	var root: Vector2 = Vector2(_top[SECTIONS].x, _center[SECTIONS])
	var beat: float = sin(_swim_phase - 3.2)
	var narrow: float = 1.0 - (1.0 - absf(beat)) * (0.18 + 0.5 * _stroke)
	var swing: float = _tail_angle * 0.9 + cos(_swim_phase - 3.2) * 0.05 * _stroke
	var shape: PackedVector2Array = PackedVector2Array([
		Vector2(2.0, -4.0), Vector2(-14.0, -19.0), Vector2(-33.0, -37.0), Vector2(-24.0, -15.0),
		Vector2(-17.0, -1.0), Vector2(-21.0, 12.0), Vector2(-26.0, 24.0), Vector2(-11.0, 13.0), Vector2(2.0, 4.5),
	])
	var points: PackedVector2Array = PackedVector2Array()
	for point in shape:
		points.append(root + Vector2(point.x * narrow, point.y).rotated(swing))
	_fin(points, FIN_COLOR)


func _draw_dorsals() -> void:
	var front: Vector2 = _at_top(0.33)
	var back: Vector2 = _at_top(0.55)
	var tip: Vector2 = Vector2(_at_top(0.5).x - 2.0, _at_top(0.45).y - DORSAL_RISE)
	# The trailing edge is hollow, with an old notch torn out of it.
	_fin(PackedVector2Array([
		front + Vector2(0.0, 2.0), front.lerp(tip, 0.55) + Vector2(3.0, -2.0), tip, tip + Vector2(-5.0, 9.0),
		tip + Vector2(-2.0, 13.0), tip + Vector2(-7.0, 17.0), back + Vector2(4.0, -6.0), back + Vector2(0.0, 2.0),
	]), FIN_COLOR)
	var second: Vector2 = _at_top(0.76)
	_fin(PackedVector2Array([
		second + Vector2(0.0, 1.5), second + Vector2(-9.0, -9.0), second + Vector2(-12.0, -3.0), _at_top(0.84) + Vector2(0.0, 1.5),
	]), FIN_COLOR)


func _draw_lower_fins() -> void:
	var pelvic: Vector2 = _at_bottom(0.64)
	_fin(PackedVector2Array([
		pelvic + Vector2(0.0, -1.5), pelvic + Vector2(-11.0, 10.0), pelvic + Vector2(-13.0, 3.0), _at_bottom(0.72) + Vector2(0.0, -1.5),
	]), FIN_COLOR)
	var anal: Vector2 = _at_bottom(0.8)
	_fin(PackedVector2Array([
		anal + Vector2(0.0, -1.5), anal + Vector2(-8.0, 7.0), anal + Vector2(-10.0, 2.0), _at_bottom(0.86) + Vector2(0.0, -1.5),
	]), FIN_COLOR)


## A pectoral fin: held out and swept back like a wing while it glides, tucked a little with each hard
## stroke, dropped to steer when the nose comes up or goes down.
func _draw_pectoral(offset_x: float, color: Color, size: float) -> void:
	var root_front: Vector2 = _at_bottom(0.27).lerp(_at_top(0.27), 0.22) + Vector2(offset_x, 0.0)
	var root_back: Vector2 = _at_bottom(0.4).lerp(_at_top(0.4), 0.2) + Vector2(offset_x, 0.0)
	var sweep: float = 0.5 - _stroke * 0.26 + clampf(_trail_pitch(0.3) - _pitch, -0.3, 0.3)
	var tip: Vector2 = root_front + Vector2(-36.0 * size, 0.0).rotated(-sweep - 0.55)
	_fin(PackedVector2Array([
		root_front, root_front.lerp(tip, 0.5) + Vector2(4.0, 3.0), tip, root_back.lerp(tip, 0.45) + Vector2(-2.0, -1.0), root_back,
	]), color)


## Back, flank and belly: dark above, pale below, split along an uneven line under the midline.
func _draw_body() -> void:
	_band(_top, _bottom, BACK_COLOR, FLANK_COLOR)
	var split_line: PackedVector2Array = PackedVector2Array()
	for index in range(SECTIONS + 1):
		var u: float = float(index) / float(SECTIONS)
		var split: float = 0.42 + 0.06 * sin(u * 11.0) - 0.16 * u
		split_line.append(_top[index].lerp(_bottom[index], clampf(split + 0.18, 0.0, 0.96)))
	_band(split_line, _bottom, BELLY_SHADE, BELLY_COLOR)
	var outline: PackedVector2Array = _top.duplicate()
	for index in range(SECTIONS, -1, -1):
		outline.append(_bottom[index])
	outline.append(_top[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.5, true)
	# Moonlight along the back, where it breaks the surface.
	draw_polyline(_top.slice(1, SECTIONS - 2), RIM_COLOR, 1.0, true)


## Gills, eye and the jaw with its teeth.
func _draw_head() -> void:
	for index in range(4):
		var u: float = 0.2 + float(index) * 0.026
		var top: Vector2 = _at_top(u).lerp(_at_bottom(u), 0.3)
		var bottom: Vector2 = _at_top(u).lerp(_at_bottom(u), 0.68) + Vector2(-2.5, 0.0)
		draw_polyline(PackedVector2Array([top, top.lerp(bottom, 0.5) + Vector2(1.6, 0.0), bottom]), Color(0.08, 0.12, 0.15, 0.85), 1.2, true)
	var eye: Vector2 = _at_top(0.09).lerp(_at_bottom(0.09), 0.3)
	draw_circle(eye, 3.3, Color(0.03, 0.04, 0.05))
	draw_circle(eye + Vector2(0.9, -1.0), 0.9, Color(0.9, 0.95, 0.95, 0.9))
	# The brow that makes it look the way a shark looks at you.
	draw_polyline(PackedVector2Array([eye + Vector2(5.5, -2.2), eye + Vector2(0.5, -4.6), eye + Vector2(-4.5, -3.6)]), OUTLINE_COLOR, 1.4, true)

	var hinge: Vector2 = _at_top(0.17).lerp(_at_bottom(0.17), 0.66)
	var upper_front: Vector2 = _at_top(0.03).lerp(_at_bottom(0.03), 0.8) + Vector2(-1.0, 0.5)
	var open_angle: float = jaw * 0.62
	if open_angle < 0.03:
		# Shut: the mouth is a down-turned line under the snout.
		draw_polyline(PackedVector2Array([upper_front, upper_front.lerp(hinge, 0.5) + Vector2(0.0, 2.6), hinge]), OUTLINE_COLOR, 1.5, true)
		return
	var lower_front: Vector2 = hinge + (upper_front - hinge).rotated(open_angle) * 0.92
	var chin: Vector2 = hinge + (_at_bottom(0.07) - hinge).rotated(open_angle)
	var throat: Vector2 = _at_bottom(0.2)
	# Lower jaw, then the open mouth over it, then gums and teeth.
	_fin(PackedVector2Array([hinge, lower_front, chin, throat]), BELLY_COLOR)
	_fan(PackedVector2Array([hinge, upper_front, lower_front]), MOUTH_COLOR)
	draw_polyline(PackedVector2Array([hinge, upper_front]), GUM_COLOR, 2.2, true)
	draw_polyline(PackedVector2Array([hinge, lower_front]), GUM_COLOR, 2.0, true)
	_draw_teeth(upper_front, hinge, 7, 5.2, 1.0)
	_draw_teeth(lower_front, hinge, 6, 4.4, -1.0)


## A row of teeth from the front of a jaw back to the hinge, pointing into the mouth, smaller towards the back.
func _draw_teeth(front: Vector2, hinge: Vector2, count: int, length: float, side: float) -> void:
	var along: Vector2 = (hinge - front) / float(count + 1)
	var inward: Vector2 = along.normalized().orthogonal() * -side
	if inward.y * side < 0.0:
		inward = -inward
	for index in range(count):
		var base: Vector2 = front + along * (float(index) + 0.35)
		var size: float = length * (1.0 - 0.07 * float(index))
		_fan(PackedVector2Array([base, base + along * 0.9, base + along * 0.45 + inward * size]), TOOTH_COLOR)
