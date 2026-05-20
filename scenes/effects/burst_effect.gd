extends Node2D

@onready var _particles: CPUParticles2D = $Particles
@onready var _specks: CPUParticles2D = $Specks
@onready var _core_flash: Polygon2D = $CoreFlash
@onready var _ring: Line2D = $Ring

var _kind: StringName = &"run_dust"
var _direction: Vector2 = Vector2.UP
var _tint: Color = Color.WHITE
var _life: float = 0.45
var _flash_tween: Tween = null


func configure(kind: StringName, direction: Vector2, tint: Color = Color.WHITE) -> void:
	_kind = kind
	_direction = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.UP
	_tint = tint
	if is_node_ready():
		_apply_settings()


func _ready() -> void:
	_apply_settings()
	await get_tree().create_timer(_life + 0.2).timeout
	queue_free()


func _apply_settings() -> void:
	_reset_flash_nodes()
	match _kind:
		&"run_dust":
			_configure_particles(7, 0.30, Vector2(-_direction.x, -0.12), 42.0, 108.0, 54.0, Color(0.74, 0.67, 0.52, 0.60), 0.75, 1.85)
			_configure_specks(4, 0.23, Vector2(-_direction.x, -0.08), 30.0, 76.0, 62.0, Color(0.90, 0.82, 0.62, 0.46), 0.42, 1.05)
		&"jump":
			_configure_particles(20, 0.38, Vector2(0.0, 1.0), 72.0, 185.0, 82.0, Color(0.82, 0.78, 0.62, 0.66), 0.95, 2.65)
			_configure_specks(10, 0.31, Vector2(0.0, 1.0), 54.0, 140.0, 94.0, Color(1.0, 0.92, 0.68, 0.58), 0.42, 1.24)
		&"land":
			_configure_particles(28, 0.48, Vector2.UP, 82.0, 220.0, 94.0, Color(0.72, 0.66, 0.54, 0.72), 1.15, 3.25)
			_configure_specks(16, 0.38, Vector2.UP, 56.0, 156.0, 104.0, Color(0.96, 0.84, 0.58, 0.58), 0.46, 1.30)
		&"hit":
			_configure_particles(42, 0.42, _direction, 165.0, 390.0, 64.0, _tint.lerp(Color(1.0, 0.96, 0.76, 1.0), 0.30), 0.92, 2.45)
			_configure_specks(30, 0.36, _direction, 125.0, 340.0, 78.0, Color(1.0, 0.88, 0.28, 0.90), 0.42, 1.12)
			_play_flash_ring(Color(1.0, 0.88, 0.30, 0.72), 5.0, 28.0, 0.22, 7.0, 0.48)
		&"impact":
			_configure_particles(30, 0.36, _direction, 135.0, 320.0, 72.0, Color(0.96, 0.42, 0.12, 0.82), 0.80, 1.95)
			_configure_specks(22, 0.30, _direction, 120.0, 330.0, 82.0, Color(0.18, 0.12, 0.06, 0.62), 0.38, 0.92)
			_play_flash_ring(Color(0.98, 0.55, 0.18, 0.64), 5.0, 24.0, 0.20, 6.5, 0.44)
		&"spawn":
			var spawn_color: Color = _tint.lerp(Color(0.60, 0.90, 1.0, 1.0), 0.42)
			_configure_particles(32, 0.52, Vector2.UP, 66.0, 230.0, 180.0, Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.70), 0.85, 2.85)
			_configure_specks(22, 0.44, Vector2.UP, 84.0, 275.0, 180.0, Color(1.0, 0.96, 0.70, 0.64), 0.36, 1.05)
			_play_flash_ring(Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.84), 7.0, 38.0, 0.44, 8.0, 0.48)
		&"death":
			var death_color: Color = _tint.lerp(Color(1.0, 0.28, 0.18, 1.0), 0.48)
			_configure_particles(54, 0.62, Vector2.UP, 120.0, 430.0, 180.0, Color(death_color.r, death_color.g, death_color.b, 0.82), 0.80, 3.10)
			_configure_specks(36, 0.52, Vector2.UP, 132.0, 450.0, 180.0, Color(1.0, 0.78, 0.32, 0.78), 0.42, 1.24)
			_play_flash_ring(Color(1.0, 0.34, 0.18, 0.88), 9.0, 54.0, 0.50, 11.5, 0.66)
		_:
			_configure_particles(10, 0.30, _direction, 60.0, 150.0, 60.0, _tint, 0.6, 1.5)
			_configure_specks(5, 0.24, _direction, 40.0, 110.0, 70.0, _tint, 0.3, 0.8)

	_particles.restart()
	_specks.restart()
	_particles.emitting = true
	_specks.emitting = true


func _configure_particles(amount: int, lifetime: float, direction: Vector2, min_velocity: float, max_velocity: float, spread: float, color: Color, min_scale: float, max_scale: float) -> void:
	_life = maxf(_life, lifetime)
	var particle_direction: Vector2 = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.UP
	_particles.amount = amount
	_particles.lifetime = lifetime
	_particles.direction = particle_direction
	_particles.initial_velocity_min = min_velocity
	_particles.initial_velocity_max = max_velocity
	_particles.spread = spread
	_particles.color = color
	_particles.scale_amount_min = min_scale
	_particles.scale_amount_max = max_scale


func _configure_specks(amount: int, lifetime: float, direction: Vector2, min_velocity: float, max_velocity: float, spread: float, color: Color, min_scale: float, max_scale: float) -> void:
	_life = maxf(_life, lifetime)
	var speck_direction: Vector2 = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.UP
	_specks.amount = amount
	_specks.lifetime = lifetime
	_specks.direction = speck_direction
	_specks.initial_velocity_min = min_velocity
	_specks.initial_velocity_max = max_velocity
	_specks.spread = spread
	_specks.color = color
	_specks.scale_amount_min = min_scale
	_specks.scale_amount_max = max_scale


func _reset_flash_nodes() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _core_flash != null:
		_core_flash.visible = false
		_core_flash.modulate = Color.WHITE
		_core_flash.scale = Vector2.ONE
	if _ring != null:
		_ring.visible = false
		_ring.modulate = Color.WHITE
		_ring.scale = Vector2.ONE


func _play_flash_ring(color: Color, start_radius: float, end_radius: float, duration: float, core_radius: float, core_alpha: float) -> void:
	if _ring == null or _core_flash == null:
		return

	_life = maxf(_life, duration)
	_ring.visible = true
	_ring.modulate = color
	_ring.scale = Vector2.ONE * start_radius
	_core_flash.visible = true
	_core_flash.modulate = Color(1.0, 0.96, 0.78, core_alpha)
	_core_flash.scale = Vector2.ONE * core_radius

	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_ring, "scale", Vector2.ONE * end_radius, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_ring, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_core_flash, "scale", Vector2.ONE * core_radius * 1.55, duration * 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_core_flash, "modulate:a", 0.0, duration * 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
