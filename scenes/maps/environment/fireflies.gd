class_name Fireflies
extends Node2D

## Wandering, pulsing fireflies drawn in a single additive pass. Per-fly data lives in packed arrays
## (no per-fly dictionaries), so the per-frame update stays a tight loop.

const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")

@export var area: Rect2 = Rect2(0.0, 150.0, 2280.0, 520.0)
@export var count: int = 36
@export var tint: Color = Color(0.85, 1.0, 0.55, 1.0)
@export var size_range: Vector2 = Vector2(10.0, 22.0)

var _positions: PackedVector2Array = PackedVector2Array()
var _seeds: PackedFloat32Array = PackedFloat32Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _sizes: PackedFloat32Array = PackedFloat32Array()
var _rates: PackedFloat32Array = PackedFloat32Array()
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	material = FxLib.additive_material()
	_noise.seed = randi()
	_noise.frequency = 0.6
	var actual_count: int = int(round(float(count) * clampf(GameJuice.particles_multiplier, 0.0, 1.0)))
	for index in range(actual_count):
		_positions.append(Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)))
		_seeds.append(randf() * 1000.0)
		_speeds.append(randf_range(14.0, 34.0))
		_sizes.append(randf_range(size_range.x, size_range.y))
		_rates.append(randf_range(0.6, 1.6))
	set_process(actual_count > 0)


func _process(delta: float) -> void:
	_time += delta
	var center: Vector2 = area.get_center()
	for index in range(_positions.size()):
		var heading: float = _noise.get_noise_2d(_seeds[index], _time * 0.25) * TAU * 1.5
		var pos: Vector2 = _positions[index] + Vector2(cos(heading), sin(heading) * 0.6) * (_speeds[index] * delta)
		if not area.has_point(pos):
			pos = pos.lerp(center, 0.02)
		_positions[index] = pos
	queue_redraw()


func _draw() -> void:
	for index in range(_positions.size()):
		var pulse: float = 0.5 + 0.5 * sin(_time * _rates[index] * 2.4 + _seeds[index])
		pulse *= pulse
		var size: float = _sizes[index] * (0.55 + pulse * 0.45)
		draw_texture_rect(GLOW_TEXTURE, Rect2(_positions[index] - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(tint.r, tint.g, tint.b, 0.2 + pulse * 0.75))
