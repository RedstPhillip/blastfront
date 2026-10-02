class_name WindPennant
extends Node2D

## Small cloth pennants (survey beacons, the outpost mast) that always show where the wind blows: they
## hang and sway in a breeze and stream out flat, snapping hard, when a storm comes through.

@export var anchors: PackedVector2Array = PackedVector2Array()
@export var length: float = 15.0
@export var width: float = 6.0
@export var cloth_color: Color = Color(0.95, 0.55, 0.2)
@export var full_wind: float = 200.0

const SEGMENTS: int = 5

var _time: float = 0.0
var _phases: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	for index in range(anchors.size()):
		_phases.append(float(index) * 1.7)


func _process(delta: float) -> void:
	_time += delta
	if not anchors.is_empty():
		queue_redraw()


func _draw() -> void:
	var wind: float = WorldConditions.wind.x
	var strength: float = clampf(absf(wind) / full_wind, 0.0, 1.0)
	var side: float = signf(wind) if absf(wind) > 1.0 else 1.0
	# Hanging (pointing down, a little downwind) in calm air, flat downwind in a storm.
	var base_angle: float = lerpf(PI * 0.5 - side * 0.35, 0.0 if side > 0.0 else PI, smoothstep(0.0, 0.75, strength))
	var flutter_speed: float = 4.0 + 16.0 * strength
	var flutter: float = 0.08 + 0.2 * strength
	for index in range(anchors.size()):
		var anchor: Vector2 = anchors[index]
		var phase: float = _phases[index] if index < _phases.size() else 0.0
		var top: PackedVector2Array = PackedVector2Array()
		var bottom: PackedVector2Array = PackedVector2Array()
		var angle: float = base_angle + sin(_time * 1.3 + phase) * (0.1 * (1.0 - strength))
		var point: Vector2 = anchor
		for segment in range(SEGMENTS + 1):
			var t: float = float(segment) / float(SEGMENTS)
			var wave: float = sin(_time * flutter_speed - t * 4.5 + phase) * flutter * t
			var direction: Vector2 = Vector2.from_angle(angle + wave)
			if segment > 0:
				point += direction * (length / float(SEGMENTS))
			var normal: Vector2 = direction.orthogonal()
			var half: float = width * 0.5 * (1.0 - t * 0.85)
			top.append(point - normal * half)
			bottom.append(point + normal * half)
		# Quads per segment (no triangulation, so a hard flap can never produce an invalid polygon).
		for segment in range(SEGMENTS):
			var shade: Color = cloth_color.darkened(0.18 * float(segment % 2))
			var quad: PackedVector2Array = PackedVector2Array([top[segment], top[segment + 1], bottom[segment + 1], bottom[segment]])
			draw_primitive(quad, PackedColorArray([shade, shade, shade, shade]), PackedVector2Array())
		draw_polyline(top, cloth_color.lightened(0.25), 1.0, true)
