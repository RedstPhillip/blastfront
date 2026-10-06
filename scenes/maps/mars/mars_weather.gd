class_name MarsWeather
extends Node2D

## Weather director for Mars. Calm spells with a light, wandering breeze alternate with dust storms. A storm
## is announced several seconds ahead: the storm wall rolls in on the upwind side, a deep howl rises and the
## pennants swing round. Then it blows from that side with gusts: players are shoved (much less in the lee
## of rock), every round drifts (slow, light ones the most) and sand streams through the air. Every few
## storms one turns severe: the air goes brown, sight closes in to a pocket around you and distant sounds
## are swallowed. All gameplay values go through WorldConditions, so what you see is what pushes you.

enum Phase { CALM, BUILDUP, STORM, EASE }

const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")
const FOG_SHADER: Shader = preload("res://scenes/maps/environment/fog.gdshader")
const VEIL_SHADER: Shader = preload("res://scenes/maps/mars/storm_veil.gdshader")
const STREAK_TEXTURE: Texture2D = preload("res://assets/fx/sand_streak.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const STORM_LOOP: AudioStream = preload("res://assets/audio/music/storm_loop.ogg")

const FIRST_STORM: float = 9.0
const CALM_TIME: Vector2 = Vector2(15.0, 22.0)
const BUILDUP_TIME: float = 5.0
const STORM_TIME: Vector2 = Vector2(9.0, 12.0)
const SEVERE_TIME: Vector2 = Vector2(12.0, 15.0)
const EASE_TIME: float = 3.5
const BREEZE: float = 30.0
const STORM_WIND: float = 195.0
const SEVERE_WIND: float = 245.0
const STORM_WALL_REST: float = -620.0

@export var storm_wall_path: NodePath
@export var arena_rect: Rect2 = Rect2(0.0, 0.0, 2160.0, 800.0)
@export var sand_color: Color = Color(0.86, 0.58, 0.38)

var _phase: Phase = Phase.CALM
var _timer: float = FIRST_STORM
var _phase_length: float = FIRST_STORM
var _direction: float = 1.0
var _severe: bool = false
var _storm_count: int = 0
var _last_directions: Array[float] = []
var _time: float = 0.0
var _wind: float = 0.0
var _storm: float = 0.0
var _severity: float = 0.0
var _gust: FastNoiseLite = FastNoiseLite.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Counts phase changes so the online client can tell new weather from a late copy of the old.
var _step: int = 0
## Online client: the host's weather drives this one (see WorldSync), so both players feel the same wind.
var _follow_host: bool = false

var _storm_wall: CanvasItem = null
var _storm_wall_x: float = 0.0
var _sky_material: ShaderMaterial = null
var _haze_materials: Array[ShaderMaterial] = []
var _haze_base: Array[float] = []
var _environment: CanvasItem = null
var _sun: PointLight2D = null
var _sun_energy: float = 0.0
var _motes: CPUParticles2D = null
var _veil: ColorRect = null
var _veil_material: ShaderMaterial = null
var _streaks: CPUParticles2D = null
var _drift: CPUParticles2D = null
var _spindrift: CPUParticles2D = null
var _local_dust: CPUParticles2D = null
var _tint: CanvasModulate = null
var _screen_layer: CanvasLayer = null
var _screen_veil: ColorRect = null
var _screen_material: ShaderMaterial = null
var _audio: AudioStreamPlayer = null


func _ready() -> void:
	_rng.randomize()
	_gust.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gust.frequency = 0.35
	_gust.seed = _rng.randi()
	_direction = 1.0 if _rng.randf() < 0.5 else -1.0
	_follow_host = NetworkSession.is_client()
	add_to_group(WorldSync.GROUP)
	z_index = 14
	_bind_environment()
	_build_world_fx()
	_build_screen_fx.call_deferred()
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Ambience"
	_audio.stream = STORM_LOOP
	_audio.volume_db = -40.0
	add_child(_audio)
	_audio.play()


func _exit_tree() -> void:
	WorldConditions.wind = Vector2.ZERO
	WorldConditions.storm = 0.0
	WorldConditions.visibility = 1.0
	AudioDirector.set_environment_muffle(0.0)
	GameJuice.set_ambient_motion(Vector2.ZERO, 0.0)
	if _screen_layer != null and is_instance_valid(_screen_layer):
		_screen_layer.queue_free()


# --- Setup ------------------------------------------------------------------------------------------------

func _bind_environment() -> void:
	_storm_wall = get_node_or_null(storm_wall_path) as CanvasItem
	if _storm_wall is Control:
		_storm_wall_x = (_storm_wall as Control).position.x
	var arena: Node = get_parent()
	_environment = arena.get_node_or_null(^"Environment") as CanvasItem
	var sky: CanvasItem = arena.get_node_or_null(^"Environment/FarLayer/Sky") as CanvasItem
	if sky != null and sky.material is ShaderMaterial:
		_sky_material = sky.material as ShaderMaterial
	for path in [^"Environment/FarLayer/FarHaze", ^"Environment/MidLayer/MidHaze"]:
		var haze: CanvasItem = arena.get_node_or_null(path) as CanvasItem
		if haze != null and haze.material is ShaderMaterial:
			var material: ShaderMaterial = haze.material as ShaderMaterial
			_haze_materials.append(material)
			_haze_base.append(float(material.get_shader_parameter(&"density")))
	_sun = arena.get_node_or_null(^"Environment/SunLight") as PointLight2D
	if _sun != null:
		_sun_energy = _sun.energy
	_motes = arena.get_node_or_null(^"Environment/DustMotes") as CPUParticles2D


func _build_world_fx() -> void:
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
	_streaks = _make_streaks(170, 1.1)
	_drift = _make_streaks(30, 2.4)
	_drift.scale_amount_min = 0.25
	_drift.scale_amount_max = 0.45
	_drift.color = Color(sand_color.r, sand_color.g, sand_color.b, 0.22)
	_drift.emitting = true
	_spindrift = _make_spindrift()
	_local_dust = _make_streaks(46, 0.5)
	_local_dust.emission_rect_extents = Vector2(200.0, 90.0)
	_local_dust.scale_amount_min = 0.35
	_local_dust.scale_amount_max = 0.8
	_local_dust.preprocess = 0.0
	_tint = CanvasModulate.new()
	_tint.color = Color.WHITE
	add_child(_tint)


## The game this map belongs to: found through the tree, not the group, because while one match is torn
## down and the next one set up both games are briefly in the group.
func _owning_game() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.is_in_group(GameSettings.GAME_WORLD_GROUP):
			return node
		node = node.get_parent()
	return null


func _build_screen_fx() -> void:
	if not is_inside_tree():
		return
	var game: Node = _owning_game()
	if game == null:
		return
	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "StormVeil"
	_screen_layer.layer = 4
	game.add_child(_screen_layer)
	_screen_veil = ColorRect.new()
	_screen_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = VEIL_SHADER
	_screen_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	_screen_material.set_shader_parameter(&"dust_color", sand_color.darkened(0.12))
	_screen_veil.material = _screen_material
	_screen_veil.visible = false
	_screen_layer.add_child(_screen_veil)


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


## Sand lifting off every exposed rock top and streaming downwind.
func _make_spindrift() -> CPUParticles2D:
	var points: PackedVector2Array = _crest_points()
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.texture = SOFT_TEXTURE
	particles.amount = 240
	particles.lifetime = 1.4
	particles.emitting = false
	particles.local_coords = false
	if points.is_empty():
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = arena_rect.size * 0.5
		particles.position = arena_rect.get_center()
	else:
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
		particles.emission_points = points
	particles.direction = Vector2(1.0, -0.35)
	particles.spread = 14.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 170.0
	particles.damping_min = 10.0
	particles.damping_max = 30.0
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.24
	particles.color = Color(sand_color.r * 1.05, sand_color.g, sand_color.b * 0.92, 0.62)
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	particles.color_ramp = ramp
	add_child(particles)
	return particles


func _crest_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var arena: Node = get_parent()
	for child in arena.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		var shape: CollisionPolygon2D = body.get_node_or_null(^"CollisionPolygon2D") as CollisionPolygon2D
		if shape == null or shape.polygon.size() < 3:
			continue
		var polygon: PackedVector2Array = shape.polygon
		var clockwise: bool = Geometry2D.is_polygon_clockwise(polygon)
		for index in range(polygon.size()):
			var a: Vector2 = body.to_global(polygon[index])
			var b: Vector2 = body.to_global(polygon[(index + 1) % polygon.size()])
			var edge: Vector2 = b - a
			if edge.length() < 16.0:
				continue
			var normal: Vector2 = Vector2(edge.y, -edge.x).normalized()
			if not clockwise:
				normal = -normal
			if normal.y > -0.6 or a.y > arena_rect.end.y - 60.0:
				continue
			var steps: int = int(edge.length() / 26.0)
			for step in range(steps + 1):
				points.append(a + edge * (float(step) / float(maxi(steps, 1))) + Vector2(0.0, -3.0) - global_position)
	return points


# --- Director -----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_timer -= delta
	if _timer <= 0.0 and not _follow_host:
		_advance_phase()
	_update_wind(delta)
	WorldConditions.wind = Vector2(_wind, 0.0)
	WorldConditions.storm = _storm
	WorldConditions.visibility = clampf(1.0 - 0.8 * _severity - 0.08 * _storm, 0.12, 1.0)
	_update_visuals(delta)
	_update_screen()
	_update_audio()


func _advance_phase() -> void:
	match _phase:
		Phase.CALM:
			_begin_buildup()
		Phase.BUILDUP:
			_enter_phase(Phase.STORM, _rng.randf_range(SEVERE_TIME.x, SEVERE_TIME.y) if _severe else _rng.randf_range(STORM_TIME.x, STORM_TIME.y))
		Phase.STORM:
			_enter_phase(Phase.EASE, EASE_TIME)
		Phase.EASE:
			_enter_phase(Phase.CALM, _rng.randf_range(CALM_TIME.x, CALM_TIME.y))


func _enter_phase(next_phase: Phase, length: float) -> void:
	_phase = next_phase
	_phase_length = length
	_timer = length
	_step += 1


func _begin_buildup(forced_direction: float = 0.0, forced_severe: int = -1) -> void:
	_enter_phase(Phase.BUILDUP, BUILDUP_TIME)
	_storm_count += 1
	# Mostly random sides, but never the same side three storms running.
	_direction = 1.0 if _rng.randf() < 0.5 else -1.0
	if _last_directions.size() >= 2 and _last_directions[-1] == _direction and _last_directions[-2] == _direction:
		_direction = -_direction
	if forced_direction != 0.0:
		_direction = signf(forced_direction)
	_last_directions.append(_direction)
	if _last_directions.size() > 4:
		_last_directions.pop_front()
	_severe = _storm_count % 3 == 0 or _rng.randf() < 0.15
	if forced_severe >= 0:
		_severe = forced_severe == 1
	_announce_storm()


func _announce_storm() -> void:
	AudioDirector.play(&"storm_warning")
	var arrow: String = "▶" if _direction > 0.0 else "◀"
	if _severe:
		HudToasts.notify("SEVERE DUST STORM", "%s  Low visibility" % arrow, Color(1.0, 0.45, 0.25), &"")
	else:
		HudToasts.notify("DUST STORM", "%s  Wind and drift" % arrow, Color(0.96, 0.62, 0.36), &"")


func _update_wind(delta: float) -> void:
	var breeze: float = BREEZE * _gust.get_noise_1d(_time * 0.05 + 300.0) * 1.6
	var peak: float = SEVERE_WIND if _severe else STORM_WIND
	var gust: float = 0.78 + 0.3 * _gust.get_noise_1d(_time * 0.35) + 0.2 * maxf(_gust.get_noise_1d(_time * 1.1 + 50.0), 0.0)
	var target_wind: float = breeze
	var target_storm: float = 0.0
	var target_severity: float = 0.0
	var progress: float = 1.0 - clampf(_timer / maxf(_phase_length, 0.01), 0.0, 1.0)
	match _phase:
		Phase.BUILDUP:
			target_wind = lerpf(breeze, _direction * peak * 0.3, smoothstep(0.3, 1.0, progress))
			target_storm = 0.45 * progress
		Phase.STORM:
			target_wind = _direction * peak * gust
			target_storm = 1.0
			target_severity = 1.0 if _severe else 0.0
		Phase.EASE:
			target_wind = lerpf(_direction * peak * 0.7, breeze, progress)
			target_storm = 1.0 - progress
	_wind = move_toward(_wind, target_wind, delta * 260.0)
	_storm = move_toward(_storm, target_storm, delta * 0.7)
	_severity = move_toward(_severity, target_severity, delta * (0.45 if target_severity > _severity else 0.3))


# --- Presentation -------------------------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	var strength: float = clampf(absf(_wind) / SEVERE_WIND, 0.0, 1.0)
	var side: float = signf(_wind) if absf(_wind) > 1.0 else _direction
	var storm_side: float = _direction if _phase != Phase.CALM else side
	_veil_material.set_shader_parameter(&"density", 0.07 * strength + 0.2 * _storm + 0.06 * _severity)
	_veil_material.set_shader_parameter(&"speed", 0.12 * side + _wind * 0.0012)
	_veil.visible = _storm > 0.01 or strength > 0.15
	_streaks.emitting = strength > 0.3
	_streaks.direction = Vector2(side, 0.05)
	_streaks.speed_scale = 0.4 + strength * 1.1
	_streaks.modulate.a = clampf(strength * 1.4, 0.0, 1.0)
	_drift.direction = Vector2(side, -0.15)
	_drift.speed_scale = 0.08 + strength * 0.9
	if _spindrift != null:
		_spindrift.emitting = strength > 0.22
		_spindrift.direction = Vector2(side, -0.35)
		_spindrift.gravity = Vector2(_wind * 1.4, -10.0)
		_spindrift.speed_scale = 0.7 + strength * 0.8
		_spindrift.modulate.a = clampf((strength - 0.15) * 1.6, 0.0, 1.0)
	if _motes != null:
		_motes.direction = Vector2(side, -0.1)
		_motes.speed_scale = 1.0 + strength * 6.0
	_update_local_dust(side)
	if _storm_wall != null:
		# The wall sits on the upwind horizon and rolls closer as a storm builds.
		var control: Control = _storm_wall as Control
		var approach: float = clampf(_storm * 1.4, 0.0, 1.0)
		if control != null:
			var offset: float = lerpf(STORM_WALL_REST, 0.0, approach)
			if storm_side > 0.0:
				control.scale.x = 1.0
				control.position.x = _storm_wall_x + offset
			else:
				control.scale.x = -1.0
				control.position.x = -_storm_wall_x + (-offset)
		_storm_wall.modulate.a = 0.35 + 0.65 * approach
		if _storm_wall.material is ShaderMaterial:
			(_storm_wall.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.4 + _storm * 0.8)
	if _sky_material != null:
		_sky_material.set_shader_parameter(&"dust", _storm * 0.45 + _severity * 0.45)
		_sky_material.set_shader_parameter(&"wind", _wind / SEVERE_WIND)
	for index in range(_haze_materials.size()):
		_haze_materials[index].set_shader_parameter(&"density", _haze_base[index] * (1.0 + 1.3 * _storm + 0.8 * _severity))
	if _sun != null:
		_sun.energy = _sun_energy * (1.0 - 0.4 * _storm - 0.35 * _severity)
	if _environment != null:
		_environment.modulate = Color.WHITE.lerp(Color(0.84, 0.68, 0.56), 0.35 * _storm + 0.3 * _severity)
	_tint.color = Color.WHITE.lerp(Color(0.88, 0.76, 0.66), 0.18 * _storm + 0.42 * _severity)
	var lean: Vector2 = Vector2(_wind * 0.012, 0.0)
	GameJuice.set_ambient_motion(lean, 0.6 * _storm + 1.4 * _severity)


func _update_local_dust(side: float) -> void:
	var player: Player = _local_player()
	if player == null:
		_local_dust.emitting = false
		return
	var exposure: float = player.get_wind_exposure()
	_local_dust.global_position = player.global_position + Vector2(-side * 60.0, -10.0)
	_local_dust.direction = Vector2(side, 0.04)
	_local_dust.speed_scale = 0.5 + absf(_wind) / SEVERE_WIND
	_local_dust.emitting = _storm > 0.25 and exposure > 0.35
	_local_dust.modulate.a = clampf(_storm * exposure, 0.0, 1.0)


func _update_screen() -> void:
	if _screen_material == null or not is_instance_valid(_screen_veil):
		return
	var player: Player = _local_player()
	var thick: float = _severity
	var front: float = 0.0
	var front_alpha: float = 0.0
	var phase_progress: float = 1.0 - clampf(_timer / maxf(_phase_length, 0.01), 0.0, 1.0)
	if _phase == Phase.BUILDUP:
		front = 0.12 + 0.62 * smoothstep(0.0, 1.0, phase_progress)
		front_alpha = 0.66 * smoothstep(0.0, 0.25, phase_progress)
	elif _phase == Phase.STORM:
		# The wall rolls over the screen in the first seconds of the storm.
		var elapsed: float = _phase_length - _timer
		front = 0.74 + elapsed * 0.9
		front_alpha = 0.66 * (1.0 - smoothstep(0.4, 1.7, elapsed))
	_screen_material.set_shader_parameter(&"front", front)
	_screen_material.set_shader_parameter(&"front_alpha", front_alpha)
	_screen_material.set_shader_parameter(&"front_side", _direction)
	_screen_veil.visible = thick > 0.01 or _storm > 0.05 or front_alpha > 0.01
	if not _screen_veil.visible:
		return
	var viewport: Viewport = get_viewport()
	var screen: Vector2 = viewport.get_visible_rect().size
	var center: Vector2 = screen * 0.5
	if player != null:
		center = player.get_global_transform_with_canvas().origin
	_screen_material.set_shader_parameter(&"screen_size", screen)
	_screen_material.set_shader_parameter(&"clear_center", center)
	_screen_material.set_shader_parameter(&"clear_radius", lerpf(screen.x * 0.9, 250.0, thick))
	_screen_material.set_shader_parameter(&"softness", lerpf(400.0, 280.0, thick))
	_screen_material.set_shader_parameter(&"density", 0.05 * _storm + 0.78 * thick)
	_screen_material.set_shader_parameter(&"pocket_density", 0.04 * _storm + 0.08 * thick)
	_screen_material.set_shader_parameter(&"wind", _wind / SEVERE_WIND)


func _update_audio() -> void:
	var level: float = 0.05 + 0.7 * _storm + 0.25 * _severity
	_audio.volume_db = linear_to_db(maxf(level, 0.0001)) - 4.0
	_audio.pitch_scale = 0.92 + 0.14 * clampf(absf(_wind) / SEVERE_WIND, 0.0, 1.0)
	AudioDirector.set_environment_muffle(_severity * 0.85)


func _local_player() -> Player:
	var game: Node = _owning_game()
	if game == null or not game.has_method(&"get_local_player"):
		return null
	var player: Player = game.get_local_player() as Player
	if player == null or not is_instance_valid(player) or player.is_eliminated():
		return null
	return player


func net_state() -> Dictionary:
	return {
		"step": _step,
		"phase": int(_phase),
		"timer": _timer,
		"length": _phase_length,
		"direction": _direction,
		"severe": _severe,
		"count": _storm_count,
		"time": _time,
		"seed": _gust.seed,
	}


func apply_net_state(state: Dictionary) -> void:
	var step: int = int(state.get("step", _step))
	var next_phase: Phase = int(state.get("phase", _phase)) as Phase
	var announce: bool = step != _step and next_phase == Phase.BUILDUP
	_step = step
	_phase = next_phase
	_timer = float(state.get("timer", _timer))
	_phase_length = float(state.get("length", _phase_length))
	_direction = float(state.get("direction", _direction))
	_severe = state.get("severe", _severe) == true
	_storm_count = int(state.get("count", _storm_count))
	_time = float(state.get("time", _time))
	var gust_seed: int = int(state.get("seed", _gust.seed))
	if gust_seed != _gust.seed:
		_gust.seed = gust_seed
	if announce:
		_announce_storm()


## Tests: start a storm now (with or without its warning phase).
func skip_to_storm(severe: bool = false, direction: float = 0.0, with_warning: bool = true) -> void:
	_begin_buildup(direction, 1 if severe else 0)
	if not with_warning:
		_timer = 0.05
