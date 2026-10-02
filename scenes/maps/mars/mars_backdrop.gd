class_name MarsBackdrop
extends Node2D

## Procedural landscape silhouettes behind the Martian arena, one node per parallax layer: the broad
## shield volcano and distant ridges far away, flat-topped mesas with sediment bands in the middle, and a
## dark jagged ridge with boulders up close. Colours fade towards the sky colour with distance. Built
## once; nothing here runs per frame.

enum Kind { FAR, MID, NEAR }

@export var kind: Kind = Kind.MID
@export var span: float = 5200.0
@export var baseline: float = 0.0
@export var top_color: Color = Color(0.62, 0.34, 0.22)
@export var base_color: Color = Color(0.36, 0.17, 0.11)
@export var band_color: Color = Color(1.0, 0.8, 0.6, 0.08)
@export var rim_color: Color = Color(1.0, 0.78, 0.55, 0.35)
@export var seed_value: int = 7

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _profile_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_rng.seed = seed_value
	var profile: PackedVector2Array = _profile()
	_profile_points = profile
	var depth: float = 900.0
	var polygon: PackedVector2Array = profile.duplicate()
	polygon.append(Vector2(span * 0.5, baseline + depth))
	polygon.append(Vector2(-span * 0.5, baseline + depth))
	var top_y: float = INF
	for point in profile:
		top_y = minf(top_y, point.y)
	var colors: PackedColorArray = PackedColorArray()
	for point in polygon:
		var t: float = clampf((point.y - top_y) / maxf(baseline + 160.0 - top_y, 1.0), 0.0, 1.0)
		colors.append(top_color.lerp(base_color, t))
	var body: Polygon2D = Polygon2D.new()
	body.polygon = polygon
	body.vertex_colors = colors
	add_child(body)
	if kind == Kind.MID:
		_add_bands(profile)
	var rim: Line2D = Line2D.new()
	rim.points = profile
	rim.width = 1.6 if kind == Kind.NEAR else 1.2
	rim.default_color = rim_color
	rim.antialiased = true
	add_child(rim)
	if kind == Kind.NEAR:
		_add_boulders(profile)


## Height of the silhouette's top edge at a local x (for placing props on the ground).
func surface_y(x: float) -> float:
	if _profile_points.is_empty():
		return baseline
	var step: float = _profile_points[1].x - _profile_points[0].x
	var index: int = clampi(int((x - _profile_points[0].x) / step), 0, _profile_points.size() - 2)
	var a: Vector2 = _profile_points[index]
	var b: Vector2 = _profile_points[index + 1]
	return lerpf(a.y, b.y, clampf((x - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0))


func _profile() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var step: float = 10.0 if kind != Kind.NEAR else 7.0
	var x: float = -span * 0.5
	var mesas: Array = _mesas()
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	while x <= span * 0.5:
		var h: float = 0.0
		match kind:
			Kind.FAR:
				# Shield volcano: a very wide gentle cone with a caldera notch, plus low ridges.
				var v: float = x - 380.0
				h = 120.0 * exp(-pow(v / 760.0, 2.0)) - 14.0 * exp(-pow(v / 90.0, 2.0))
				h += 30.0 + sin(x * 0.0021 + phase_a) * 16.0 + sin(x * 0.0057 + phase_b) * 7.0
			Kind.MID:
				h = 34.0 + sin(x * 0.003 + phase_a) * 14.0 + sin(x * 0.011 + phase_b) * 5.0
				for mesa in mesas:
					var edge: float = (absf(x - float(mesa["x"])) - float(mesa["w"]) * 0.5) / float(mesa["soft"])
					var plateau: float = 1.0 - smoothstep(0.0, 1.0, edge)
					var tier_edge: float = (absf(x - float(mesa["x"]) - float(mesa["tier_shift"])) - float(mesa["w"]) * float(mesa["tier"]) * 0.5) / (float(mesa["soft"]) * 0.6)
					var tier: float = (1.0 - smoothstep(0.0, 1.0, tier_edge)) * float(mesa["tier_h"])
					h = maxf(h, float(mesa["h"]) * plateau + tier + sin(x * 0.05 + float(mesa["x"])) * 1.6)
			Kind.NEAR:
				h = 40.0 + sin(x * 0.006 + phase_a) * 26.0 + sin(x * 0.019 + phase_b) * 11.0
				h += absf(sin(x * 0.043 + phase_a * 2.0)) * 14.0 + _rng.randf_range(-2.0, 2.0)
		points.append(Vector2(x, baseline - h))
		x += step
	return points


func _mesas() -> Array:
	var mesas: Array = []
	if kind != Kind.MID:
		return mesas
	var x: float = -span * 0.5 + _rng.randf_range(80.0, 260.0)
	while x < span * 0.5:
		var width: float = _rng.randf_range(140.0, 420.0)
		mesas.append({
			"x": x + width * 0.5, "w": width, "h": _rng.randf_range(70.0, 150.0), "soft": _rng.randf_range(10.0, 26.0),
			"tier": _rng.randf_range(0.3, 0.6), "tier_h": _rng.randf_range(0.0, 46.0) if _rng.randf() < 0.65 else 0.0,
			"tier_shift": _rng.randf_range(-0.2, 0.2) * width,
		})
		x += width + _rng.randf_range(160.0, 460.0)
	return mesas


## Pale horizontal sediment bands clipped to the mesa silhouettes.
func _add_bands(profile: PackedVector2Array) -> void:
	for band in range(6):
		var y: float = baseline - 30.0 - float(band) * 22.0 - _rng.randf_range(0.0, 8.0)
		var segment: PackedVector2Array = PackedVector2Array()
		for point in profile:
			if point.y < y - 3.0:
				segment.append(Vector2(point.x, y + sin(point.x * 0.02 + float(band)) * 1.5))
			elif segment.size() > 1:
				_add_band_line(segment)
				segment = PackedVector2Array()
			else:
				segment = PackedVector2Array()
		if segment.size() > 1:
			_add_band_line(segment)


func _add_band_line(points: PackedVector2Array) -> void:
	var line: Line2D = Line2D.new()
	line.points = points
	line.width = _rng.randf_range(1.5, 3.5)
	line.default_color = band_color
	add_child(line)


func _add_boulders(profile: PackedVector2Array) -> void:
	for index in range(18):
		var point: Vector2 = profile[_rng.randi() % profile.size()]
		var radius: float = _rng.randf_range(6.0, 16.0)
		var boulder: Polygon2D = Polygon2D.new()
		var shape: PackedVector2Array = PackedVector2Array()
		for corner in range(7):
			var angle: float = TAU * float(corner) / 7.0
			shape.append(point + Vector2(cos(angle) * radius * _rng.randf_range(0.8, 1.15), sin(angle) * radius * 0.6 * _rng.randf_range(0.8, 1.1) + 2.0))
		boulder.polygon = shape
		boulder.color = base_color.lerp(top_color, 0.35)
		add_child(boulder)
