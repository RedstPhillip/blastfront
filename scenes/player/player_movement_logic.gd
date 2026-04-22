extends RefCounted
class_name PlayerMovementLogic

enum MovementState {
	RUNNING,
	FALLING,
	SLIDING,
}

# Current movement state. For parity with old behavior, this is driven only by grounded state.
var _state: int = MovementState.FALLING

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


func setup(player) -> void:
	# Initialize feet exactly like the old player.gd setup.
	player.foot_pos_l = player.global_position + Vector2(-player.foot_spread, player.hover_dist)
	player.foot_pos_r = player.global_position + Vector2(player.foot_spread, player.hover_dist)

	_step_from_l = player.foot_pos_l
	_step_to_l = player.foot_pos_l
	_step_from_r = player.foot_pos_r
	_step_to_r = player.foot_pos_r


func physics_process(player, delta: float) -> void:
	# Keep update order identical to preserve movement feel.
	_step_clock += delta

	# Ground sensing from both foot rays.
	var hit_l: bool = player._ray_l.is_colliding()
	var hit_r: bool = player._ray_r.is_colliding()
	var grounded: bool = hit_l or hit_r

	var floor_y: float = player.global_position.y + player.hover_dist
	if hit_l:
		floor_y = minf(floor_y, player._ray_l.get_collision_point().y)
	if hit_r:
		floor_y = minf(floor_y, player._ray_r.get_collision_point().y)

	_sync_state_from_ground(grounded)

	# Core horizontal movement + jump logic (unchanged from old code).
	if grounded:
		var compression: float = player.hover_dist - (floor_y - player.global_position.y)
		if compression > 0.0:
			player.apply_central_force(Vector2(0.0, -player.spring_str * compression - player.damp_str * player.linear_velocity.y))

	var dir: float = Input.get_axis("left", "right")
	if dir != 0.0:
		player.last_dir = signf(dir)
		player.apply_central_force(Vector2(dir * player.move_force, 0.0))
		player.linear_velocity.x = clampf(player.linear_velocity.x, -player.max_speed, player.max_speed)
	elif grounded:
		player.linear_velocity.x = lerp(player.linear_velocity.x, 0.0, 15.0 * delta)

	if Input.is_action_just_pressed("jump") and grounded:
		player.linear_velocity.y = -player.jump_force

	# Hip anchor is computed before the final tilt, same as before.
	var hip: Vector2 = player.global_position + Vector2(0.0, player.hip_y_offset).rotated(player.rotation)

	match _state:
		MovementState.RUNNING:
			_update_running_state(player, delta, hip, hit_l, hit_r, floor_y)
		MovementState.FALLING:
			_update_falling_state(player, delta, hip)
		MovementState.SLIDING:
			# Placeholder state: keeps grounded stepping behavior for now.
			_update_sliding_state(player, delta, hip, hit_l, hit_r, floor_y)

	# Final body tilt (same formula and position in frame as old script).
	player.rotation = lerp_angle(player.rotation, dir * 0.1, delta * 10.0)


func _sync_state_from_ground(grounded: bool) -> void:
	# Force parity with old grounded/air branch behavior.
	var target_state: int = MovementState.RUNNING if grounded else MovementState.FALLING
	if target_state == _state:
		return
	_state = target_state
	print("Player state changed to: %s" % _state_name(_state))


func _state_name(state: int) -> String:
	match state:
		MovementState.RUNNING:
			return "RUNNING"
		MovementState.FALLING:
			return "FALLING"
		MovementState.SLIDING:
			return "SLIDING"
		_:
			return "UNKNOWN"


func _update_running_state(player, delta: float, hip: Vector2, hit_l: bool, hit_r: bool, floor_y: float) -> void:
	_update_steps(player, delta, hip, hit_l, hit_r, floor_y)


func _update_falling_state(player, delta: float, hip: Vector2) -> void:
	_step_t_l = 1.0
	_step_t_r = 1.0
	_gait_timer = 0.0
	player.bounce_t = 0.0
	var air_l: Vector2 = hip + Vector2(-player.air_foot_tuck_x, player.hover_dist * 0.7 - player.air_foot_tuck_y)
	var air_r: Vector2 = hip + Vector2(player.air_foot_tuck_x, player.hover_dist * 0.7 - player.air_foot_tuck_y)
	player.foot_pos_l = player.foot_pos_l.lerp(air_l, delta * 10.0)
	player.foot_pos_r = player.foot_pos_r.lerp(air_r, delta * 10.0)


func _update_sliding_state(player, delta: float, hip: Vector2, hit_l: bool, hit_r: bool, floor_y: float) -> void:
	_update_steps(player, delta, hip, hit_l, hit_r, floor_y)


func _update_steps(player, delta: float, hip: Vector2, hit_l: bool, hit_r: bool, floor_y: float) -> void:
	var floor_l: float = player._ray_l.get_collision_point().y if hit_l else floor_y
	var floor_r: float = player._ray_r.get_collision_point().y if hit_r else floor_y
	var speed_norm: float = clampf(absf(player.linear_velocity.x) / player.max_speed, 0.0, 1.0)

	if absf(player.linear_velocity.x) > 10.0:
		player.bounce_t += delta * 10.0 * (0.35 + speed_norm)
	else:
		player.bounce_t = lerp(player.bounce_t, 0.0, delta * 6.0)

	if _step_t_l < 1.0:
		_step_t_l = minf(_step_t_l + delta / _step_dur_l, 1.0)
		player.foot_pos_l = _arc(_step_from_l, _step_to_l, _step_t_l, _step_arc_l)

	if _step_t_r < 1.0:
		_step_t_r = minf(_step_t_r + delta / _step_dur_r, 1.0)
		player.foot_pos_r = _arc(_step_from_r, _step_to_r, _step_t_r, _step_arc_r)

	if _step_t_l < 1.0 or _step_t_r < 1.0:
		return

	var spread_l: float = player.foot_spread if hit_l else player.foot_spread * 0.35
	var spread_r: float = player.foot_spread if hit_r else player.foot_spread * 0.35
	var look: float = player.linear_velocity.x * player.look_ahead

	var ideal_l: Vector2 = Vector2(hip.x - spread_l + look * 0.35, floor_l)
	var ideal_r: Vector2 = Vector2(hip.x + spread_r + look * 0.35, floor_r)

	var dl: float = player.foot_pos_l.distance_to(ideal_l)
	var dr: float = player.foot_pos_r.distance_to(ideal_r)

	var scale: float = _leg_scale(player)
	var min_interval: float = player.stride_min_interval * scale

	var l_ready: bool = (_step_clock - _last_step_time_l) >= min_interval
	var r_ready: bool = (_step_clock - _last_step_time_r) >= min_interval

	_gait_timer += delta
	var cycle: float = (player.stride_cycle_base * scale) / (1.0 + speed_norm * player.speed_step_boost)

	var force_l: bool = dl > player.step_trigger * 1.7
	var force_r: bool = dr > player.step_trigger * 1.7

	if _gait_timer < cycle and not force_l and not force_r:
		return

	var prefer_left: bool = _last_stepped == 1

	if prefer_left:
		if (dl > player.step_trigger or force_l) and l_ready:
			_begin_step(player, true, hip, floor_l, hit_l, speed_norm)
			_gait_timer = 0.0
		elif (dr > player.step_trigger or force_r) and r_ready:
			_begin_step(player, false, hip, floor_r, hit_r, speed_norm)
			_gait_timer = 0.0
	else:
		if (dr > player.step_trigger or force_r) and r_ready:
			_begin_step(player, false, hip, floor_r, hit_r, speed_norm)
			_gait_timer = 0.0
		elif (dl > player.step_trigger or force_l) and l_ready:
			_begin_step(player, true, hip, floor_l, hit_l, speed_norm)
			_gait_timer = 0.0


func _begin_step(player, is_left: bool, hip: Vector2, floor_y: float, has_ground: bool, speed_norm: float) -> void:
	var spread: float = player.foot_spread if has_ground else player.foot_spread * 0.35
	var look: float = player.linear_velocity.x * player.look_ahead if has_ground else 0.0
	var x: float = (hip.x - spread + look) if is_left else (hip.x + spread + look)

	var tgt: Vector2 = Vector2(x, floor_y)

	var scale: float = _leg_scale(player)
	var base_dur: float = player.step_duration * lerpf(1.0, scale, 0.5)
	var dur: float = maxf(0.055, base_dur * lerpf(1.0, player.fast_step_duration_scale, speed_norm))
	var arc: float = player.step_arc_h * lerpf(1.0, player.fast_step_arc_scale, speed_norm)

	if is_left:
		_step_from_l = player.foot_pos_l
		_step_to_l = tgt
		_step_t_l = 0.0
		_step_dur_l = dur
		_step_arc_l = arc
		_last_stepped = 0
		_last_step_time_l = _step_clock
	else:
		_step_from_r = player.foot_pos_r
		_step_to_r = tgt
		_step_t_r = 0.0
		_step_dur_r = dur
		_step_arc_r = arc
		_last_stepped = 1
		_last_step_time_r = _step_clock


func _leg_scale(player) -> float:
	var current: float = player.hip_y_offset + player.hover_dist * 0.5
	return current / player.BASE_LEG_LENGTH


func _arc(a: Vector2, b: Vector2, t: float, h: float) -> Vector2:
	var p := a.lerp(b, t)
	p.y -= sin(t * PI) * h
	return p
