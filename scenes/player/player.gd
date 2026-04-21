extends RigidBody2D

@export var move_force := 600.0
@export var max_speed := 210.0
@export var jump_force := 460.0
@export var hover_dist := 30.0
@export var spring_str := 150.0
@export var damp_str := 15.0
@export var foot_spread := 12.0
@export var hip_y_offset := 13.5
@export var bounce_amp := 1.5

@export var step_trigger := 8.5
@export var step_duration := 0.11
@export var step_arc_h := 7.5
@export var look_ahead := 0.155

@export var air_foot_tuck_x := 10.5
@export var air_foot_tuck_y := 7.5

@export var stride_min_interval := 0.065
@export var stride_cycle_base := 0.19
@export var speed_step_boost := 0.55
@export var fast_step_duration_scale := 0.725
@export var fast_step_arc_scale := 1.35

const BASE_LEG_LENGTH := 25.0

var foot_pos_l: Vector2
var foot_pos_r: Vector2
var bounce_t := 0.0
var last_dir := 1.0

var _step_clock := 0.0
var _gait_timer := 0.0
var _last_stepped := 1
var _last_step_time_l := -1000.0
var _last_step_time_r := -1000.0

var _step_from_l: Vector2
var _step_to_l: Vector2
var _step_t_l := 1.0
var _step_dur_l := 0.11
var _step_arc_l := 7.5

var _step_from_r: Vector2
var _step_to_r: Vector2
var _step_t_r := 1.0
var _step_dur_r := 0.11
var _step_arc_r := 7.5

@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR


func _leg_scale() -> float:
	var current := hip_y_offset + hover_dist * 0.5
	return current / BASE_LEG_LENGTH


func _ready() -> void:
	foot_pos_l = global_position + Vector2(-foot_spread, hover_dist)
	foot_pos_r = global_position + Vector2( foot_spread, hover_dist)

	_step_from_l = foot_pos_l
	_step_to_l = foot_pos_l
	_step_from_r = foot_pos_r
	_step_to_r = foot_pos_r


func _physics_process(delta: float) -> void:
	_step_clock += delta

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
			apply_central_force(Vector2(0.0, -spring_str * compression - damp_str * linear_velocity.y))

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
		_update_steps(delta, hip, hit_l, hit_r, floor_y)
	else:
		_step_t_l = 1.0
		_step_t_r = 1.0
		_gait_timer = 0.0
		bounce_t = 0.0
		var air_l := hip + Vector2(-air_foot_tuck_x, hover_dist * 0.7 - air_foot_tuck_y)
		var air_r := hip + Vector2( air_foot_tuck_x, hover_dist * 0.7 - air_foot_tuck_y)
		foot_pos_l = foot_pos_l.lerp(air_l, delta * 10.0)
		foot_pos_r = foot_pos_r.lerp(air_r, delta * 10.0)

	rotation = lerp_angle(rotation, dir * 0.1, delta * 10.0)


func _update_steps(delta: float, hip: Vector2, hit_l: bool, hit_r: bool, floor_y: float) -> void:
	var floor_l := _ray_l.get_collision_point().y if hit_l else floor_y
	var floor_r := _ray_r.get_collision_point().y if hit_r else floor_y
	var speed_norm := clampf(absf(linear_velocity.x) / max_speed, 0.0, 1.0)

	if absf(linear_velocity.x) > 10.0:
		bounce_t += delta * 10.0 * (0.35 + speed_norm)
	else:
		bounce_t = lerp(bounce_t, 0.0, delta * 6.0)

	if _step_t_l < 1.0:
		_step_t_l = minf(_step_t_l + delta / _step_dur_l, 1.0)
		foot_pos_l = _arc(_step_from_l, _step_to_l, _step_t_l, _step_arc_l)

	if _step_t_r < 1.0:
		_step_t_r = minf(_step_t_r + delta / _step_dur_r, 1.0)
		foot_pos_r = _arc(_step_from_r, _step_to_r, _step_t_r, _step_arc_r)

	if _step_t_l < 1.0 or _step_t_r < 1.0:
		return

	var spread_l := foot_spread if hit_l else foot_spread * 0.35
	var spread_r := foot_spread if hit_r else foot_spread * 0.35
	var look := linear_velocity.x * look_ahead

	var ideal_l := Vector2(hip.x - spread_l + look * 0.35, floor_l)
	var ideal_r := Vector2(hip.x + spread_r + look * 0.35, floor_r)

	var dl := foot_pos_l.distance_to(ideal_l)
	var dr := foot_pos_r.distance_to(ideal_r)

	var scale := _leg_scale()
	var min_interval := stride_min_interval * scale

	var l_ready := (_step_clock - _last_step_time_l) >= min_interval
	var r_ready := (_step_clock - _last_step_time_r) >= min_interval

	_gait_timer += delta
	var cycle := (stride_cycle_base * scale) / (1.0 + speed_norm * speed_step_boost)

	var force_l := dl > step_trigger * 1.7
	var force_r := dr > step_trigger * 1.7

	if _gait_timer < cycle and not force_l and not force_r:
		return

	var prefer_left := _last_stepped == 1

	if prefer_left:
		if (dl > step_trigger or force_l) and l_ready:
			_begin_step(true, hip, floor_l, hit_l, speed_norm)
			_gait_timer = 0.0
		elif (dr > step_trigger or force_r) and r_ready:
			_begin_step(false, hip, floor_r, hit_r, speed_norm)
			_gait_timer = 0.0
	else:
		if (dr > step_trigger or force_r) and r_ready:
			_begin_step(false, hip, floor_r, hit_r, speed_norm)
			_gait_timer = 0.0
		elif (dl > step_trigger or force_l) and l_ready:
			_begin_step(true, hip, floor_l, hit_l, speed_norm)
			_gait_timer = 0.0


func _begin_step(is_left: bool, hip: Vector2, floor_y: float, has_ground: bool, speed_norm: float) -> void:
	var spread := foot_spread if has_ground else foot_spread * 0.35
	var look := linear_velocity.x * look_ahead if has_ground else 0.0
	var x := (hip.x - spread + look) if is_left else (hip.x + spread + look)

	var tgt := Vector2(x, floor_y)

	var scale := _leg_scale()
	var base_dur := step_duration * lerpf(1.0, scale, 0.5)
	var dur := maxf(0.055, base_dur * lerpf(1.0, fast_step_duration_scale, speed_norm))
	var arc := step_arc_h * lerpf(1.0, fast_step_arc_scale, speed_norm)

	if is_left:
		_step_from_l = foot_pos_l
		_step_to_l = tgt
		_step_t_l = 0.0
		_step_dur_l = dur
		_step_arc_l = arc
		_last_stepped = 0
		_last_step_time_l = _step_clock
	else:
		_step_from_r = foot_pos_r
		_step_to_r = tgt
		_step_t_r = 0.0
		_step_dur_r = dur
		_step_arc_r = arc
		_last_stepped = 1
		_last_step_time_r = _step_clock


func _arc(a: Vector2, b: Vector2, t: float, h: float) -> Vector2:
	var p := a.lerp(b, t)
	p.y -= sin(t * PI) * h
	return p
