class_name FlakeBurst
extends Node2D

## Ice flakes or electric arcs drawn by one node (instead of a Line2D per stroke): they drift, turn and
## fade, then the node frees itself.

enum Kind { FLAKES, ARCS }

var kind: Kind = Kind.FLAKES
var count: int = 4
var duration: float = 0.5

var _items: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	z_index = 6 if kind == Kind.ARCS else 5
	if kind == Kind.ARCS:
		material = FxLib.additive_material()
	for index in range(count):
		var item: Dictionary = {
			"from": Vector2(randf_range(-16.0, 16.0), randf_range(-18.0, 12.0)),
			"drift": Vector2(randf_range(-8.0, 8.0), randf_range(-24.0, -8.0)),
			"angle": randf_range(0.0, TAU),
			"spin": randf_range(-1.4, 1.4),
			"size": randf_range(4.0, 7.5) * randf_range(0.75, 1.35),
			"width": randf_range(1.6, 2.6),
		}
		if kind == Kind.ARCS:
			item["from"] = Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, 10.0))
			item["points"] = _arc_points(randf_range(16.0, 28.0), randi_range(4, 6))
			item["grow"] = randf_range(1.2, 1.6)
		_items.append(item)


func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_time / duration, 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
	var alpha: float = 1.0 - t * t
	for item in _items:
		var angle: float = float(item["angle"]) + float(item["spin"]) * t
		if kind == Kind.FLAKES:
			var center: Vector2 = (item["from"] as Vector2) + (item["drift"] as Vector2) * eased
			var radius: float = float(item["size"])
			var color: Color = Color(0.82, 0.97, 1.0, 0.9 * alpha)
			for arm in range(3):
				var direction: Vector2 = Vector2.from_angle(angle + float(arm) * TAU / 3.0) * radius
				draw_line(center - direction, center + direction, color, 1.2, true)
		else:
			var scale_factor: float = lerpf(1.0, float(item["grow"]), eased)
			var xform: Transform2D = Transform2D(angle, Vector2.ONE * scale_factor, 0.0, item["from"])
			var points: PackedVector2Array = xform * (item["points"] as PackedVector2Array)
			draw_polyline(points, Color(1.0, 0.96, 0.5, alpha), float(item["width"]), true)


func _arc_points(length: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var half: float = length * 0.5
	for index in range(segments + 1):
		var ratio: float = float(index) / float(segments)
		var y: float = 0.0 if index == 0 or index == segments else randf_range(-5.0, 5.0)
		points.append(Vector2(lerpf(-half, half, ratio), y))
	return points
