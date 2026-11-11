class_name TideShark
extends Node2D

## One of Tidewater's sharks, as it looks and moves: steered by TidewaterSharks, drawn here every frame.
## Local space has the snout on +x. The body is a spine of sections with a swimming wave running down it
## (stronger towards the tail), dark slate on the back and pale on the belly, with the fins hung on it:
## the tall notched dorsal that cuts the surface, the tail whose beat is seen as the fin narrowing and
## widening, pectorals that spread in a strike. The jaw opens on `jaw` (0..1) to a dark mouth and two rows
## of teeth. It sits under the sea's own layer, so the water tints and bends everything below the line.

const LENGTH: float = 176.0
const SECTIONS: int = 16
const BODY_SPAN: float = 150.0
const DORSAL_RISE: float = 32.0
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
## 0 = cruising, 1 = all out: a harder tail beat and spread fins.
var thrash: float = 0.0

var _swim_phase: float = 0.0
var _top: PackedVector2Array = PackedVector2Array()
var _bottom: PackedVector2Array = PackedVector2Array()
var _center: PackedFloat32Array = PackedFloat32Array()


## Points the shark along `heading` (never upside down) and moves its swimming on by one frame.
func animate(delta: float, heading: Vector2, speed: float) -> void:
	if heading.length_squared() > 0.0001:
		rotation = heading.angle()
		scale = Vector2(1.0, -1.0 if heading.x < 0.0 else 1.0)
	_swim_phase = fmod(_swim_phase + delta * (2.6 + speed * 0.024 + thrash * 5.0), TAU)
	queue_redraw()


## The tip of the dorsal fin in world space: where the wake starts while it cuts the surface.
func fin_tip() -> Vector2:
	return to_global(Vector2(_section_x(0.5) - 2.0, -DORSAL_RISE - 14.0))


## The jaws in world space: where a bite lands.
func head() -> Vector2:
	return to_global(Vector2(LENGTH * 0.5 - 22.0, 6.0))


func _section_x(u: float) -> float:
	return LENGTH * 0.5 - u * BODY_SPAN


## Height of the spine at u (0 snout .. 1 tail root): the swimming wave, and the snout carried a little high.
func _spine(u: float) -> float:
	var wave: float = sin(_swim_phase - u * 3.4) * (3.2 + 6.5 * thrash) * pow(u, 1.6)
	return wave - 2.6 * exp(-u * 8.0)


func _girth(u: float) -> float:
	return pow(sin(PI * pow(u, 0.7)), 0.85)


func _build_sections() -> void:
	_top.resize(SECTIONS + 1)
	_bottom.resize(SECTIONS + 1)
	_center.resize(SECTIONS + 1)
	for index in range(SECTIONS + 1):
		var u: float = float(index) / float(SECTIONS)
		var x: float = _section_x(u)
		var y: float = _spine(u)
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
	_build_sections()
	_draw_tail()
	_draw_pectoral(8.0, FAR_FIN_COLOR, 0.82)
	_draw_dorsals()
	_draw_lower_fins()
	_draw_body()
	_draw_pectoral(0.0, FIN_COLOR, 1.0)
	_draw_head()


func _fin(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.3, true)


## The tail fin swings with the last of the wave; its sideways beat shows as the fin narrowing.
func _draw_tail() -> void:
	var root: Vector2 = Vector2(_section_x(1.0), _center[SECTIONS])
	var swing: float = cos(_swim_phase - 3.4) * (0.2 + 0.3 * thrash)
	var narrow: float = 0.72 + 0.28 * absf(sin(_swim_phase - 3.0))
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
	var tip: Vector2 = Vector2(_section_x(0.5) - 2.0, _at_top(0.45).y - DORSAL_RISE)
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


## A pectoral fin: swept down and back, paddling a little, spread wide in a strike.
func _draw_pectoral(offset_x: float, color: Color, size: float) -> void:
	var root_front: Vector2 = _at_bottom(0.27).lerp(_at_top(0.27), 0.22) + Vector2(offset_x, 0.0)
	var root_back: Vector2 = _at_bottom(0.4).lerp(_at_top(0.4), 0.2) + Vector2(offset_x, 0.0)
	var sweep: float = 0.52 + sin(_swim_phase * 0.5) * 0.08 - thrash * 0.34
	var tip: Vector2 = root_front + Vector2(-36.0 * size, 0.0).rotated(-sweep - 0.55) * Vector2(1.0, 1.0)
	_fin(PackedVector2Array([
		root_front, root_front.lerp(tip, 0.5) + Vector2(4.0, 3.0), tip, root_back.lerp(tip, 0.45) + Vector2(-2.0, -1.0), root_back,
	]), color)


## Back, flank and belly: dark above, pale below, split along an uneven line under the midline.
func _draw_body() -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	for index in range(SECTIONS + 1):
		outline.append(_top[index])
		colors.append(BACK_COLOR)
	for index in range(SECTIONS, -1, -1):
		outline.append(_bottom[index])
		colors.append(FLANK_COLOR)
	draw_polygon(outline, colors)
	var belly: PackedVector2Array = PackedVector2Array()
	var belly_colors: PackedColorArray = PackedColorArray()
	for index in range(SECTIONS + 1):
		var u: float = float(index) / float(SECTIONS)
		var split: float = 0.42 + 0.06 * sin(u * 11.0) - 0.16 * u
		belly.append(_top[index].lerp(_bottom[index], clampf(split + 0.18, 0.0, 0.96)))
		belly_colors.append(BELLY_SHADE)
	for index in range(SECTIONS, -1, -1):
		belly.append(_bottom[index])
		belly_colors.append(BELLY_COLOR)
	draw_polygon(belly, belly_colors)
	outline.append(outline[0])
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
	draw_colored_polygon(PackedVector2Array([hinge, upper_front, lower_front]), MOUTH_COLOR)
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
		draw_colored_polygon(PackedVector2Array([base, base + along * 0.9, base + along * 0.45 + inward * size]), TOOTH_COLOR)
