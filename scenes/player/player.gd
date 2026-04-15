extends RigidBody2D

@export var move_force   : float = 800.0
@export var max_speed    : float = 280.0
@export var jump_force   : float = 480.0
@export var hover_dist   : float = 40.0
@export var spring_str   : float = 200.0
@export var damp_str     : float = 20.0
@export var foot_spread  : float = 16.0
@export var hip_y_offset : float = 18.0
@export var bounce_amp   : float = 2.0

# Werte anpassen — Füße müssen mit dem Body mithalten
@export var step_trigger  : float = 12.0   # größer = Schritt früher ausgelöst
@export var step_duration : float = 0.07   # schneller
@export var step_arc_h    : float = 10.0
@export var look_ahead    : float = 0.11   # weiter vorausschauen

@export var air_foot_tuck_x : float = 14.0
@export var air_foot_tuck_y : float = 10.0

var foot_pos_l : Vector2
var foot_pos_r : Vector2
var bounce_t   : float = 0.0

var _step_from_l  : Vector2
var _step_from_r  : Vector2
var _step_to_l    : Vector2
var _step_to_r    : Vector2
var _step_t_l     : float = 1.0
var _step_t_r     : float = 1.0
var _last_stepped : int = 1

var last_dir : float = 1.0

var last_dir : float = 1.0

@onready var _ray_l : RayCast2D = $RayL
@onready var _ray_r : RayCast2D = $RayR

func _ready() -> void:
	foot_pos_l = global_position + Vector2(-foot_spread, hover_dist)
	foot_pos_r = global_position + Vector2(foot_spread, hover_dist)

	_step_to_l = foot_pos_l
	_step_from_l = foot_pos_l
	_step_to_r = foot_pos_r
	_step_from_r = foot_pos_r

func _physics_process(delta: float) -> void:
	var hit_l := _ray_l.is_colliding()
	var hit_r := _ray_r.is_colliding()
	var grounded := hit_l or hit_r

	var floor_y := global_position.y + hover_dist
	if hit_l:
		floor_y = minf(floor_y, _ray_l.get_collision_point().y)
	if hit_r:
		floor_y = minf(floor_y, _ray_r.get_collision_point().y)

	if grounded:
		var compression := hover_dist - (floor_y - global_position.y)
		if compression > 0.0:
			apply_central_force(Vector2(
				0.0,
				(-spring_str * compression) - (damp_str * linear_velocity.y)
			))

	var dir := Input.get_axis("left", "right")

	if dir != 0.0:
		last_dir = signf(dir)
		apply_central_force(Vector2(dir * move_force, 0.0))
		linear_velocity.x = clampf(linear_velocity.x, -max_speed, max_speed)
	elif grounded:
		linear_velocity.x = lerp(linear_velocity.x, 0.0, 15.0 * delta)

	if Input.is_action_just_pressed("jump") and grounded:
		linear_velocity.y = -jump_force

	var hip := global_position + Vector2(0.0, hip_y_offset).rotated(rotation)

	if grounded:
		_update_steps(delta, hip, floor_y)
	else:
		_step_t_l = 1.0
		_step_t_r = 1.0
		bounce_t = 0.0

		var air_l_target := hip + Vector2(-air_foot_tuck_x, hover_dist * 0.7)
		var air_r_target := hip + Vector2( air_foot_tuck_x, hover_dist * 0.7)

		foot_pos_l = foot_pos_l.lerp(air_l_target, delta * 10.0)
		foot_pos_r = foot_pos_r.lerp(air_r_target, delta * 10.0)

	rotation = lerp_angle(rotation, dir * 0.1, delta * 10.0)

func _update_steps(delta: float, hip: Vector2, floor_y: float) -> void:
	if absf(linear_velocity.x) > 10.0:
		bounce_t += delta * 12.0 * (absf(linear_velocity.x) / max_speed)

	if _step_t_l < 1.0:
		_step_t_l = minf(_step_t_l + delta / step_duration, 1.0)
		foot_pos_l = _arc(_step_from_l, _step_to_l, _step_t_l)

	if _step_t_r < 1.0:
		_step_t_r = minf(_step_t_r + delta / step_duration, 1.0)
		foot_pos_r = _arc(_step_from_r, _step_to_r, _step_t_r)

	var ideal_l := Vector2(hip.x - foot_spread, floor_y)
	var ideal_r := Vector2(hip.x + foot_spread, floor_y)
	var dl      := foot_pos_l.distance_to(ideal_l)
	var dr      := foot_pos_r.distance_to(ideal_r)

	# Einer muss immer am Boden bleiben — nie beide gleichzeitig steppen
	var l_stepping := _step_t_l < 1.0
	var r_stepping := _step_t_r < 1.0

	# Nächster Schritt erst wenn aktueller 60% fertig
	var l_ready := _step_t_l > 0.6
	var r_ready := _step_t_r > 0.6

	if l_stepping and not r_stepping:
		# Links ist in der Luft → rechts darf erst starten wenn links fast fertig
		if l_ready and dr > step_trigger:
			_begin_step(false, hip, floor_y)
	elif r_stepping and not l_stepping:
		# Rechts ist in der Luft → links darf erst starten wenn rechts fast fertig
		if r_ready and dl > step_trigger:
			_begin_step(true, hip, floor_y)
	elif not l_stepping and not r_stepping:
		# Beide am Boden → strikt abwechseln, nur EINER startet
		if _last_stepped == 0 and dr > step_trigger:
			_begin_step(false, hip, floor_y)
		elif _last_stepped == 1 and dl > step_trigger:
			_begin_step(true, hip, floor_y)
		# Fallback wenn der "dran"-Fuß noch nicht weit genug: anderen nehmen
		elif dl > step_trigger * 1.5:
			_begin_step(true, hip, floor_y)
		elif dr > step_trigger * 1.5:
			_begin_step(false, hip, floor_y)

func _begin_step(is_left: bool, hip: Vector2, floor_y: float) -> void:
	var overstep_x : float

	if is_left:
		overstep_x = hip.x - foot_spread + linear_velocity.x * look_ahead
	else:
		overstep_x = hip.x + foot_spread + linear_velocity.x * look_ahead

	var tgt := Vector2(overstep_x, floor_y)

	if is_left:
		_step_from_l = foot_pos_l
		_step_to_l = tgt
		_step_t_l = 0.0
		_last_stepped = 0
	else:
		_step_from_r = foot_pos_r
		_step_to_r = tgt
		_step_t_r = 0.0
		_last_stepped = 1

func _arc(from: Vector2, to: Vector2, t: float) -> Vector2:
	var p := from.lerp(to, t)
	p.y -= sin(t * PI) * step_arc_h
	return p
