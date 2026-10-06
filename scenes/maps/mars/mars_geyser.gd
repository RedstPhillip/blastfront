class_name MarsGeyser
extends Node2D

## CO2 vent in the crater floor. It rests, rumbles (a hiss and a few frost puffs give it away) and then
## erupts, throwing anyone standing over it high into the air: a way up to the floating slabs and the
## spire. Jumping into the beam mid-air catches too, and throws you to the same top. Place the node on the ground, centred on the vent.

const SOFT_TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const REST_TIME: Vector2 = Vector2(3.4, 5.0)
const RUMBLE_TIME: float = 1.0
const ERUPT_TIME: float = 1.1
const LAUNCH_SPEED: float = 1020.0
const TRIGGER_HALF_WIDTH: float = 26.0
const TRIGGER_HEIGHT: float = 70.0
## The beam spreads as it rises: extra trigger half width per pixel of height.
const BEAM_WIDENING: float = 0.06
## Even at the very top of the beam the throw is a real kick, not a nudge.
const BEAM_MIN_SPEED: float = 420.0

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
var _step: int = 0
## Online client: erupts when the host's vent does (see WorldSync), so both players see the same launch.
var _follow_host: bool = false


func _ready() -> void:
	_rng.seed = int(global_position.x)
	_timer = 2.0 + phase_offset
	_follow_host = NetworkSession.is_client()
	add_to_group(WorldSync.GROUP)
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
	# Plumes and vapour lean with the wind.
	_plume.gravity.x = WorldConditions.wind.x * 1.3
	_idle.gravity.x = WorldConditions.wind.x * 0.45
	_hiss.gravity.x = WorldConditions.wind.x * 0.7
	_timer -= delta
	match _phase:
		Phase.RUMBLE:
			_glow.modulate.a = clampf(1.0 - _timer / RUMBLE_TIME, 0.0, 1.0) * 0.35
		Phase.ERUPT:
			_glow.modulate.a = 0.5 * clampf(_timer / ERUPT_TIME, 0.0, 1.0)
			_launch_players()
	if _timer <= 0.0 and not _follow_host:
		match _phase:
			Phase.REST:
				_enter_phase(Phase.RUMBLE, RUMBLE_TIME)
			Phase.RUMBLE:
				_enter_phase(Phase.ERUPT, ERUPT_TIME)
			Phase.ERUPT:
				_enter_phase(Phase.REST, _rng.randf_range(REST_TIME.x, REST_TIME.y))


func _enter_phase(next_phase: Phase, length: float) -> void:
	_phase = next_phase
	_timer = length
	_step += 1
	_hiss.emitting = next_phase == Phase.RUMBLE
	_plume.emitting = next_phase == Phase.ERUPT
	match next_phase:
		Phase.REST:
			_glow.modulate.a = 0.0
		Phase.RUMBLE:
			AudioDirector.play_at(&"geyser_rumble", global_position)
		Phase.ERUPT:
			_launched.clear()
			AudioDirector.play_at(&"geyser_blast", global_position)
			GameJuice.add_trauma(0.18)


func net_state() -> Dictionary:
	return {"step": _step, "phase": int(_phase), "timer": _timer}


func apply_net_state(state: Dictionary) -> void:
	var step: int = int(state.get("step", _step))
	var next_phase: Phase = int(state.get("phase", _phase)) as Phase
	if step != _step and next_phase != _phase:
		_enter_phase(next_phase, 0.0)
	_step = step
	_timer = float(state.get("timer", _timer))


func _launch_players() -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or _launched.has(player) or player.is_eliminated():
			continue
		# The whole beam catches, up to where a launch from the vent tops out; it widens with the plume.
		var gravity: float = maxf(player.gravity * WorldConditions.gravity_scale, 1.0)
		var top: float = player.hover_dist + LAUNCH_SPEED * LAUNCH_SPEED / (2.0 * gravity)
		var offset: Vector2 = player.global_position - global_position
		var height: float = maxf(-offset.y, 0.0)
		if offset.y > 8.0 or height > top or absf(offset.x) > TRIGGER_HALF_WIDTH + height * BEAM_WIDENING:
			continue
		_launched.append(player)
		# Caught higher up, the throw is just strong enough to reach the same top as standing on the vent.
		var speed: float = clampf(sqrt(2.0 * gravity * maxf(top - height, 0.0)), BEAM_MIN_SPEED, LAUNCH_SPEED)
		player.launch(Vector2(player.velocity.x * 0.4, minf(player.velocity.y, -speed)))
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
