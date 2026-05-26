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
			_configure_particles(6, 0.28, Vector2(-_direction.x, -0.12), 34.0, 88.0, 50.0, Color(0.74, 0.67, 0.52, 0.54), 0.55, 1.35)
			_configure_specks(3, 0.21, Vector2(-_direction.x, -0.08), 24.0, 62.0, 58.0, Color(0.90, 0.82, 0.62, 0.40), 0.32, 0.78)
		&"jump":
			_configure_particles(12, 0.32, Vector2(0.0, 1.0), 52.0, 138.0, 72.0, Color(0.82, 0.78, 0.62, 0.58), 0.68, 1.72)
			_configure_specks(6, 0.26, Vector2(0.0, 1.0), 40.0, 108.0, 84.0, Color(1.0, 0.92, 0.68, 0.48), 0.32, 0.88)
		&"land":
			_configure_particles(14, 0.34, Vector2.UP, 56.0, 150.0, 84.0, Color(0.72, 0.66, 0.54, 0.56), 0.72, 1.92)
			_configure_specks(7, 0.27, Vector2.UP, 38.0, 112.0, 92.0, Color(0.96, 0.84, 0.58, 0.44), 0.32, 0.86)
		&"hit":
			_configure_particles(16, 0.30, _direction, 80.0, 190.0, 50.0, _tint.lerp(Color(1.0, 0.96, 0.76, 1.0), 0.22), 0.45, 1.10)
			_configure_specks(10, 0.24, _direction, 60.0, 160.0, 58.0, Color(_tint.r, _tint.g, _tint.b, 0.76), 0.22, 0.55)
			_play_flash_ring(Color(_tint.r, _tint.g, _tint.b, 0.62), 2.5, 12.0, 0.14, 3.0, 0.34)
		&"impact":
			_configure_particles(10, 0.24, _direction, 60.0, 140.0, 54.0, Color(0.86, 0.28, 0.08, 0.66), 0.35, 0.80)
			_configure_specks(6, 0.20, _direction, 50.0, 130.0, 60.0, Color(0.14, 0.10, 0.06, 0.52), 0.18, 0.45)
			_play_flash_ring(Color(0.88, 0.36, 0.12, 0.42), 2.0, 9.0, 0.12, 2.5, 0.26)
		&"spawn":
			var spawn_color: Color = _tint.lerp(Color(0.60, 0.90, 1.0, 1.0), 0.42)
			_configure_particles(18, 0.42, Vector2.UP, 48.0, 168.0, 180.0, Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.58), 0.62, 1.85)
			_configure_specks(10, 0.34, Vector2.UP, 62.0, 205.0, 180.0, Color(1.0, 0.96, 0.70, 0.50), 0.28, 0.82)
			_play_flash_ring(Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.66), 5.0, 25.0, 0.34, 5.5, 0.34)
		&"death":
			var death_color: Color = _tint.lerp(Color(1.0, 0.28, 0.18, 1.0), 0.48)
			_configure_particles(30, 0.48, Vector2.UP, 92.0, 315.0, 180.0, Color(death_color.r, death_color.g, death_color.b, 0.72), 0.64, 2.10)
			_configure_specks(18, 0.40, Vector2.UP, 98.0, 325.0, 180.0, Color(1.0, 0.78, 0.32, 0.62), 0.32, 0.96)
			_play_flash_ring(Color(1.0, 0.34, 0.18, 0.70), 6.0, 34.0, 0.36, 7.2, 0.44)
		_:
			_configure_particles(10, 0.30, _direction, 60.0, 150.0, 60.0, _tint, 0.6, 1.5)
			_configure_specks(5, 0.24, _direction, 40.0, 110.0, 70.0, _tint, 0.3, 0.8)

	_particles.restart()
	_specks.restart()
	_particles.emitting = GameJuice.particles_multiplier > 0.0
	_specks.emitting = GameJuice.particles_multiplier > 0.0


func _configure_particles(amount: int, lifetime: float, direction: Vector2, min_velocity: float, max_velocity: float, spread: float, color: Color, min_scale: float, max_scale: float) -> void:
	_life = maxf(_life, lifetime)
	var particle_direction: Vector2 = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.UP
	_particles.amount = maxi(1, int(amount * GameJuice.particles_multiplier))
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
	_specks.amount = maxi(1, int(amount * GameJuice.particles_multiplier))
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
