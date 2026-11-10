class_name RimefallBackdrop
extends Node2D

## The mountains behind Rimefall, one node per parallax layer. FAR: a pale range under the aurora. MID:
## nearer, darker peaks over the frozen plain. Both are flat-shaded: every peak has a face turned to the
## moon and one in shadow, split by a ragged ridge line, and a snow cap with a toothed lower edge.
## NEAR: a snow ridge carrying a dark pine forest. Every layer is one mesh, built once.

enum Kind { FAR, MID, NEAR }

@export var kind: Kind = Kind.MID
@export var span: float = 4400.0
## Local y of the ground the layer stands on.
@export var baseline: float = 60.0
## +1 when the moon stands to the right of the scene, -1 to the left.
@export var moon_side: float = 1.0
@export var rock_shadow: Color = Color(0.07, 0.09, 0.2)
@export var rock_lit: Color = Color(0.11, 0.14, 0.27)
@export var snow_shadow: Color = Color(0.2, 0.26, 0.47)
@export var snow_lit: Color = Color(0.42, 0.51, 0.76)
## What the feet of the layer fade into (the plain below it).
@export var ground_color: Color = Color(0.22, 0.28, 0.46)
@export var ground_deep: Color = Color(0.1, 0.13, 0.26)
@export var tree_color: Color = Color(0.03, 0.05, 0.11)
@export var seed_value: int = 7

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _mesh: BackdropMesh = BackdropMesh.new()


func _ready() -> void:
	_rng.seed = seed_value
	match kind:
		Kind.FAR:
			_build_range(Vector2(120.0, 250.0), Vector2(320.0, 640.0), 150.0)
		Kind.MID:
			_build_range(Vector2(80.0, 180.0), Vector2(240.0, 470.0), 240.0)
		Kind.NEAR:
			_build_forest()
	_mesh.commit(self, "Silhouettes")


# --- Mountains ----------------------------------------------------------------------------------------------

## Peaks of random size along the layer, the tall ones drawn first so the foothills stand in front of them,
## then the plain at their feet.
func _build_range(heights: Vector2, widths: Vector2, spacing: float) -> void:
	var peaks: Array = []
	var x: float = -span * 0.5
	while x < span * 0.5:
		var height: float = _rng.randf_range(heights.x, heights.y)
		var width: float = clampf(height * _rng.randf_range(1.9, 2.6), widths.x, widths.y)
		peaks.append({"x": x, "h": height, "w": width})
		x += spacing * _rng.randf_range(0.6, 1.5)
	peaks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["h"]) > float(b["h"]))
	# Tall peaks stand behind: draw them first, then the foothills over their feet.
	for peak in peaks:
		_peak(float(peak["x"]), float(peak["w"]), float(peak["h"]))
	_mesh.box(Rect2(-span * 0.5, baseline - 2.0, span, 44.0), ground_color, ground_color)
	_mesh.box(Rect2(-span * 0.5, baseline + 42.0, span, 1700.0), ground_color, ground_deep)


func _peak(center: float, width: float, height: float) -> void:
	var summit: Vector2 = Vector2(center + width * _rng.randf_range(-0.12, 0.12), baseline - height)
	var left: PackedVector2Array = _slope(summit, Vector2(center - width * 0.5, baseline + 2.0))
	var right: PackedVector2Array = _slope(summit, Vector2(center + width * 0.5, baseline + 2.0))
	# Outline: up the left slope, down the right one.
	var outline: PackedVector2Array = PackedVector2Array()
	for index in range(left.size() - 1, -1, -1):
		outline.append(left[index])
	for index in range(1, right.size()):
		outline.append(right[index])
	_mesh.polygon_shaded(outline, rock_shadow, rock_shadow.lerp(ground_color, 0.55), summit.y, baseline)
	# The ridge runs from the summit down into the mountain, away from the moon; the face on the moon's
	# side of it is lit.
	var ridge: PackedVector2Array = PackedVector2Array([summit])
	var steps: int = 6
	var foot: Vector2 = Vector2(summit.x - moon_side * width * _rng.randf_range(0.04, 0.16), baseline + 2.0)
	for index in range(1, steps + 1):
		var t: float = float(index) / float(steps)
		var point: Vector2 = summit.lerp(foot, t)
		point.x += (1.0 if index % 2 == 0 else -1.0) * width * 0.035 * _rng.randf_range(0.4, 1.0) * (1.0 - t * 0.5)
		ridge.append(point)
	var lit_slope: PackedVector2Array = right if moon_side > 0.0 else left
	var face: PackedVector2Array = PackedVector2Array()
	for point in lit_slope:
		face.append(point)
	for index in range(ridge.size() - 1, 0, -1):
		face.append(ridge[index])
	_mesh.polygon_shaded(face, rock_lit, rock_lit.lerp(ground_color, 0.6), summit.y, baseline)
	# Snow: everything above a toothed line, bright where it lies on the lit face.
	var snow_y: float = summit.y + height * _rng.randf_range(0.34, 0.5)
	var cap: PackedVector2Array = _snow_cap(left, right, snow_y, height)
	if cap.size() < 3:
		return
	_mesh.polygon(cap, snow_shadow)
	for piece in Geometry2D.intersect_polygons(cap, face):
		_mesh.polygon(piece, snow_lit)


## A mountain flank from the summit down to its foot: a straight line broken into shoulders and steps.
func _slope(summit: Vector2, foot: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([summit])
	var steps: int = 7
	var bulge: float = _rng.randf_range(-0.05, 0.1)
	for index in range(1, steps):
		var t: float = float(index) / float(steps)
		var point: Vector2 = summit.lerp(foot, t)
		# Steeper near the top, flaring out towards the foot, with a little raggedness.
		point.x = lerpf(summit.x, foot.x, pow(t, 1.0 + bulge * 3.0) * (0.9 + 0.1 * t))
		point.y += (foot.y - summit.y) * _rng.randf_range(-0.035, 0.035)
		points.append(point)
	points.append(foot)
	return points


func _point_on(path: PackedVector2Array, t: float) -> Vector2:
	var scaled: float = clampf(t, 0.0, 1.0) * float(path.size() - 1)
	var index: int = mini(int(scaled), path.size() - 2)
	return path[index].lerp(path[index + 1], scaled - float(index))


## The part of a peak above `snow_y`, closed below by a line of teeth where the snow runs out in gullies.
func _snow_cap(left: PackedVector2Array, right: PackedVector2Array, snow_y: float, height: float) -> PackedVector2Array:
	var cap: PackedVector2Array = PackedVector2Array()
	var left_cut: Vector2 = _cut_at(left, snow_y)
	var right_cut: Vector2 = _cut_at(right, snow_y)
	cap.append(left_cut)
	for index in range(left.size() - 1, -1, -1):
		if left[index].y < snow_y:
			cap.append(left[index])
	for index in range(1, right.size()):
		if right[index].y < snow_y:
			cap.append(right[index])
	cap.append(right_cut)
	var teeth: int = maxi(3, int((right_cut.x - left_cut.x) / 26.0))
	for index in range(teeth - 1, 0, -1):
		var t: float = float(index) / float(teeth)
		var drop: float = height * (0.1 if index % 2 == 0 else -0.05) * _rng.randf_range(0.5, 1.2)
		cap.append(Vector2(lerpf(left_cut.x, right_cut.x, t), snow_y + drop))
	return cap


## Where a flank (summit first) crosses a height.
func _cut_at(path: PackedVector2Array, y: float) -> Vector2:
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		if a.y <= y and b.y >= y and b.y > a.y:
			return a.lerp(b, (y - a.y) / (b.y - a.y))
	return path[path.size() - 1]


# --- Forest -------------------------------------------------------------------------------------------------

## A rolling snow ridge with pines standing on it in loose stands, the gaps between them left open.
func _build_forest() -> void:
	var profile: PackedVector2Array = PackedVector2Array()
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var x: float = -span * 0.5
	while x <= span * 0.5:
		var rise: float = 18.0 + sin(x * 0.0031 + phase_a) * 16.0 + sin(x * 0.0083 + phase_b) * 7.0
		profile.append(Vector2(x, baseline - rise))
		x += 14.0
	# Back row first (smaller, hazier), then the ridge, then the front row on top of it.
	_tree_row(profile, 0.72, tree_color.lerp(ground_color, 0.3), 26.0, -4.0)
	_mesh.skirt(profile, baseline + 60.0, snow_lit.lerp(ground_color, 0.25), ground_color, baseline - 40.0)
	_mesh.box(Rect2(-span * 0.5, baseline + 60.0, span, 1500.0), ground_color, ground_deep)
	_tree_row(profile, 1.0, tree_color, 34.0, 3.0)


func _tree_row(profile: PackedVector2Array, size: float, color: Color, spacing: float, sink: float) -> void:
	var x: float = -span * 0.5 + _rng.randf_range(0.0, spacing)
	var stand: float = _rng.randf_range(120.0, 420.0)
	while x < span * 0.5:
		stand -= spacing
		if stand < 0.0:
			# A clearing, then the next stand.
			x += _rng.randf_range(70.0, 260.0)
			stand = _rng.randf_range(120.0, 480.0)
		var ground: float = _ground_at(profile, x) + sink
		_pine(Vector2(x, ground), _rng.randf_range(44.0, 92.0) * size, color)
		x += spacing * _rng.randf_range(0.55, 1.35)


func _ground_at(profile: PackedVector2Array, x: float) -> float:
	var step: float = profile[1].x - profile[0].x
	var index: int = clampi(int((x - profile[0].x) / step), 0, profile.size() - 2)
	var a: Vector2 = profile[index]
	var b: Vector2 = profile[index + 1]
	return lerpf(a.y, b.y, clampf((x - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0))


## A pine: a trunk and tiers of drooping boughs that shrink towards the tip, snow lying on the moon's side.
func _pine(foot: Vector2, height: float, color: Color) -> void:
	var half: float = height * _rng.randf_range(0.17, 0.23)
	_mesh.box(Rect2(foot.x - 1.6, foot.y - height * 0.2, 3.2, height * 0.2 + 2.0), color, color)
	var tiers: int = 4 if height < 60.0 else 5
	var snow: Color = snow_lit.lerp(Color(0.8, 0.87, 1.0), 0.45)
	for tier in range(tiers):
		var t: float = float(tier) / float(tiers)
		var tier_bottom: float = foot.y - height * (0.14 + t * 0.72)
		var tier_top: float = foot.y - height * minf(0.14 + (t + 0.55) * 0.72 + 0.1, 1.0)
		var tier_half: float = half * (1.0 - t * 0.78)
		var lean: float = _rng.randf_range(-1.0, 1.0)
		var apex: Vector2 = Vector2(foot.x + lean, tier_top)
		var left: Vector2 = Vector2(foot.x - tier_half, tier_bottom + 2.0)
		var right: Vector2 = Vector2(foot.x + tier_half, tier_bottom + 2.0)
		_mesh.tri(left, apex, right, color)
		_mesh.tri(left, Vector2(foot.x, tier_bottom - 2.5), right, color)
		# Snow on the bough facing the moon: a sliver along its upper edge.
		var tip: Vector2 = right if moon_side > 0.0 else left
		var along: Vector2 = apex.lerp(tip, 0.2)
		_mesh.tri(along, tip, apex.lerp(tip, 0.62) + Vector2(0.0, 3.2), snow)
