class_name MarsGeyser
extends Node2D

## CO2 vent in the crater floor. It rests, rumbles (a hiss and a few frost puffs give it away) and then
## erupts, throwing anyone standing over it high into the air: a way up to the floating slabs and the
## spire. Place the node on the ground, centred on the vent.

const SOFT_TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const REST_TIME: Vector2 = Vector2(3.4, 5.0)
const RUMBLE_TIME: float = 1.0
const ERUPT_TIME: float = 1.1
const LAUNCH_SPEED: float = 1020.0
const TRIGGER_HALF_WIDTH: float = 26.0
const TRIGGER_HEIGHT: float = 70.0

enum Phase { REST, RUMBLE, ERUPT }

@export var phase_offset: float = 0.0

var _phase: Phase = Phase.REST
var _timer: float = 2.0
var _launched: Array[Player] = []
var _plume: CPUParticles2D = null
var _idle: CPUParticles2D = null
var _hiss: CPUParticles2D = null
var _glow: Sprite2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = int(global_position.x)
	_timer = 2.0 + phase_offset
	z_index = 2
	_idle = _make_particles(5, 2.6, Vector2(0.0, -30.0), 0.1, 0.2, Color(0.95, 0.92, 0.9, 0.16))
	_idle.initial_velocity_min = 12.0
	_idle.initial_velocity_max = 30.0
	_idle.emitting = true
	_hiss = _make_particles(16, 0.9, Vector2(0.0, -40.0), 0.14, 0.26, Color(0.95, 0.9, 0.85, 0.4))
	_plume = _make_particles(110, 1.1, Vector2(0.0, -620.0), 0.22, 0.55, Color(0.98, 0.95, 0.92, 0.32))
	_plume.spread = 7.0
	_plume.initial_velocity_min = 420.0
	_plume.initial_velocity_max = 620.0
	_plume.damping_min = 120.0
	_plume.damping_max = 220.0
	_glow = Sprite2D.new()
	_glow.texture = GLOW_TEXTURE
	_glow.scale = Vector2(0.9, 0.35)
	_glow.position = Vector2(0.0, -4.0)
	_glow.modulate = Color(1.0, 0.8, 0.6, 0.0)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = additive
	add_child(_glow)
	queue_redraw()


func _make_particles(amount: int, lifetime: float, gravity: Vector2, scale_min: float, scale_max: float, color: Color) -> CPUParticles2D:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.texture = SOFT_TEXTURE
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.direction = Vector2.UP
	particles.spread = 18.0
	particles.gravity = gravity * 0.1
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 90.0
	particles.scale_amount_min = scale_min
	particles.scale_amount_max = scale_max
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(9.0, 2.0)
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	particles.color_ramp = ramp
	particles.color = color
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 1.8))
	particles.scale_amount_curve = curve
	add_child(particles)
	return particles


func _physics_process(delta: float) -> void:
	_timer -= delta
	match _phase:
		Phase.REST:
			if _timer <= 0.0:
				_phase = Phase.RUMBLE
				_timer = RUMBLE_TIME
				_hiss.emitting = true
				AudioDirector.play_at(&"geyser_rumble", global_position)
		Phase.RUMBLE:
			_glow.modulate.a = (1.0 - _timer / RUMBLE_TIME) * 0.35
			if _timer <= 0.0:
				_phase = Phase.ERUPT
				_timer = ERUPT_TIME
				_hiss.emitting = false
				_plume.emitting = true
				_launched.clear()
				AudioDirector.play_at(&"geyser_blast", global_position)
				GameJuice.add_trauma(0.18)
		Phase.ERUPT:
			_glow.modulate.a = 0.5 * (_timer / ERUPT_TIME)
			_launch_players()
			if _timer <= 0.0:
				_phase = Phase.REST
				_timer = _rng.randf_range(REST_TIME.x, REST_TIME.y)
				_plume.emitting = false
				_glow.modulate.a = 0.0


func _launch_players() -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or _launched.has(player) or player.is_eliminated():
			continue
		var offset: Vector2 = player.global_position - global_position
		if absf(offset.x) > TRIGGER_HALF_WIDTH or offset.y > 8.0 or offset.y < -TRIGGER_HEIGHT:
			continue
		_launched.append(player)
		player.launch(Vector2(player.velocity.x * 0.4, -LAUNCH_SPEED))
		AudioDirector.play_at(&"jump", player.global_position)


func _draw() -> void:
	# Vent mound: a low frosty cone around a dark mouth.
	var mound: PackedVector2Array = PackedVector2Array([
		Vector2(-40, 3), Vector2(-28, -4), Vector2(-14, -9), Vector2(14, -9), Vector2(28, -4), Vector2(40, 3)])
	draw_colored_polygon(mound, Color(0.13, 0.05, 0.03))
	draw_colored_polygon(PackedVector2Array([Vector2(-37, 2), Vector2(-26, -3), Vector2(-13, -7.6), Vector2(13, -7.6), Vector2(26, -3), Vector2(37, 2)]), Color(0.5, 0.26, 0.16))
	# Frost rim and the dark vent mouth.
	draw_polyline(PackedVector2Array([Vector2(-26, -3), Vector2(-13, -7.6), Vector2(13, -7.6), Vector2(26, -3)]), Color(0.92, 0.9, 0.92, 0.75), 2.0, true)
	for streak in [-20.0, -9.0, 8.0, 19.0]:
		draw_line(Vector2(streak, -6.0 + absf(streak) * 0.12), Vector2(streak * 1.35, 1.0), Color(0.9, 0.88, 0.9, 0.35), 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -7.4), Vector2(9, -7.4), Vector2(5, -4.5), Vector2(-5, -4.5)]), Color(0.06, 0.03, 0.02))
