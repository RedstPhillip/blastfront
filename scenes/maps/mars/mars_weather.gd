class_name MarsWeather
extends Node2D

## Dust gusts on Mars. Between calm spells the storm front on the horizon flares up, a toast and a
## rising howl announce the gust, then the wind pushes every projectile sideways for a few seconds while
## sand sheets race across the arena. The wind lives in WorldConditions so projectiles just read it.

const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")
const FOG_SHADER: Shader = preload("res://scenes/maps/environment/fog.gdshader")
const STREAK_TEXTURE: Texture2D = preload("res://assets/fx/sand_streak.png")
const CALM_TIME: Vector2 = Vector2(16.0, 24.0)
const WARNING_TIME: float = 2.4
const GUST_TIME: Vector2 = Vector2(6.0, 8.5)
const MAX_WIND: float = 320.0

enum Phase { CALM, WARNING, GUST }

@export var storm_wall_path: NodePath
@export var arena_rect: Rect2 = Rect2(0.0, 0.0, 2160.0, 800.0)
@export var sand_color: Color = Color(0.86, 0.58, 0.38)

var _phase: Phase = Phase.CALM
var _timer: float = 9.0
var _gust_length: float = 7.0
var _direction: float = 1.0
var _strength: float = 0.0
var _storm_wall: CanvasItem = null
var _storm_base_alpha: float = 1.0
var _veil: ColorRect = null
var _veil_material: ShaderMaterial = null
var _streaks: CPUParticles2D = null
var _drift: CPUParticles2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 14
	_storm_wall = get_node_or_null(storm_wall_path) as CanvasItem
	if _storm_wall != null:
		_storm_base_alpha = _storm_wall.modulate.a
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.position = arena_rect.position - Vector2(600.0, 200.0)
	_veil.size = arena_rect.size + Vector2(1200.0, 400.0)
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = FOG_SHADER
	_veil_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	_veil_material.set_shader_parameter(&"fog_color", sand_color)
	_veil_material.set_shader_parameter(&"density", 0.0)
	_veil_material.set_shader_parameter(&"speed", 0.25)
	_veil_material.set_shader_parameter(&"scale", 1.6)
	_veil_material.set_shader_parameter(&"top_softness", 0.25)
	_veil_material.set_shader_parameter(&"bottom_softness", 0.1)
	_veil.material = _veil_material
	add_child(_veil)
	_streaks = _make_streaks(150, 1.1)
	_drift = _make_streaks(30, 2.4)
	_drift.scale_amount_min = 0.25
	_drift.scale_amount_max = 0.45
	_drift.color = Color(sand_color.r, sand_color.g, sand_color.b, 0.22)
	_drift.emitting = true


func _exit_tree() -> void:
	WorldConditions.wind = Vector2.ZERO


func _make_streaks(amount: int, lifetime: float) -> CPUParticles2D:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.texture = STREAK_TEXTURE
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.emitting = false
	particles.position = arena_rect.get_center()
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = arena_rect.size * 0.62
	particles.direction = Vector2.RIGHT
	particles.spread = 4.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 380.0
	particles.initial_velocity_max = 720.0
	particles.particle_flag_align_y = true
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.5
	particles.color = Color(sand_color.r * 1.1, sand_color.g * 1.1, sand_color.b * 1.1, 0.5)
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	particles.color_ramp = ramp
	add_child(particles)
	return particles


func _process(delta: float) -> void:
	_timer -= delta
	match _phase:
		Phase.CALM:
			_strength = move_toward(_strength, 0.0, delta * 0.6)
			if _timer <= 0.0:
				_phase = Phase.WARNING
				_timer = WARNING_TIME
				_direction = 1.0 if _rng.randf() < 0.5 else -1.0
				AudioDirector.play(&"dust_gust")
				HudToasts.notify("DUST GUST", "Shots drift %s" % ("east  ▶" if _direction > 0.0 else "◀  west"), Color(0.96, 0.62, 0.36), &"")
		Phase.WARNING:
			_strength = move_toward(_strength, 0.25, delta * 0.2)
			if _timer <= 0.0:
				_phase = Phase.GUST
				_gust_length = _rng.randf_range(GUST_TIME.x, GUST_TIME.y)
				_timer = _gust_length
		Phase.GUST:
			var t: float = 1.0 - _timer / _gust_length
			_strength = clampf(sin(t * PI) * 1.25, 0.0, 1.0)
			if _timer <= 0.0:
				_phase = Phase.CALM
				_timer = _rng.randf_range(CALM_TIME.x, CALM_TIME.y)
	var gusting: float = _strength if _phase == Phase.GUST else _strength * 0.4
	WorldConditions.wind = Vector2(_direction * MAX_WIND * gusting, 0.0)
	_veil_material.set_shader_parameter(&"density", 0.3 * _strength)
	_veil.visible = _strength > 0.01
	_veil_material.set_shader_parameter(&"speed", 0.25 * _direction)
	_streaks.emitting = _strength > 0.2
	_streaks.direction = Vector2(_direction, 0.04)
	_streaks.speed_scale = 0.5 + _strength
	_drift.direction = Vector2(_direction if _strength > 0.1 else 1.0, -0.15)
	_drift.speed_scale = 0.08 + _strength * 0.6
	if _storm_wall != null and _storm_wall.material is ShaderMaterial:
		(_storm_wall.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.5 + _strength)
