class_name Fireflies
extends Node2D

## Wandering, pulsing fireflies drawn in a single additive pass.

const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")

@export var area: Rect2 = Rect2(0.0, 150.0, 2280.0, 520.0)
@export var count: int = 36
@export var tint: Color = Color(0.85, 1.0, 0.55, 1.0)
@export var size_range: Vector2 = Vector2(10.0, 22.0)

var _flies: Array[Dictionary] = []
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	material = FxLib.additive_material()
	_noise.seed = randi()
	_noise.frequency = 0.6
	var actual_count: int = int(round(float(count) * clampf(GameJuice.particles_multiplier, 0.0, 1.0)))
	for index in range(actual_count):
		_flies.append({
			"pos": Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)),
			"seed": randf() * 1000.0,
			"speed": randf_range(14.0, 34.0),
			"size": randf_range(size_range.x, size_range.y),
			"rate": randf_range(0.6, 1.6),
		})


func _process(delta: float) -> void:
	_time += delta
	for fly in _flies:
		var seed_value: float = fly["seed"]
		var heading: float = _noise.get_noise_2d(seed_value, _time * 0.25) * TAU * 1.5
		var pos: Vector2 = fly["pos"]
		pos += Vector2(cos(heading), sin(heading) * 0.6) * float(fly["speed"]) * delta
		if not area.has_point(pos):
			pos = pos.lerp(area.get_center(), 0.02)
		fly["pos"] = pos
	queue_redraw()


func _draw() -> void:
	for fly in _flies:
		var pulse: float = 0.5 + 0.5 * sin(_time * float(fly["rate"]) * 2.4 + float(fly["seed"]))
		pulse = pulse * pulse
		var size: float = float(fly["size"]) * (0.55 + pulse * 0.45)
		var rect: Rect2 = Rect2((fly["pos"] as Vector2) - Vector2.ONE * size * 0.5, Vector2.ONE * size)
		draw_texture_rect(GLOW_TEXTURE, rect, false, Color(tint.r, tint.g, tint.b, 0.2 + pulse * 0.75))
