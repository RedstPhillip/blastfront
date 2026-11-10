class_name RimefallWeather
extends Node2D

## Rimefall's snowfall: a steady fall that thickens into a flurry now and then as the wind picks up.
## Looks only; the ice is the world's rule, not the weather.

const SNOW_SHADER: Shader = preload("res://scenes/maps/environment/snow.gdshader")

@export var arena_rect: Rect2 = Rect2(0.0, 0.0, 2200.0, 800.0)
@export var base_wind: float = 24.0

var _material: ShaderMaterial = null
var _snow: ColorRect = null
var _gust: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_gust.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gust.frequency = 0.045
	_gust.seed = randi()
	_snow = ColorRect.new()
	_snow.name = "Snowfall"
	_snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snow.position = arena_rect.position - Vector2(700.0, 500.0)
	_snow.size = arena_rect.size + Vector2(1400.0, 700.0)
	_snow.z_index = 15
	_material = ShaderMaterial.new()
	_material.shader = SNOW_SHADER
	_material.set_shader_parameter(&"wind", base_wind)
	_snow.material = _material
	add_child(_snow)


func _process(delta: float) -> void:
	_time += delta
	var detail: float = clampf(GameJuice.particles_multiplier, 0.0, 1.0)
	_snow.visible = detail > 0.01
	if not _snow.visible:
		return
	# Mostly a quiet fall; the noise climbs into a flurry for a few seconds every so often.
	var flurry: float = smoothstep(0.25, 0.7, _gust.get_noise_1d(_time))
	_material.set_shader_parameter(&"intensity", (0.75 + flurry * 0.7) * detail)
