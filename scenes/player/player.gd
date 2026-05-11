extends CharacterBody2D
class_name Player

const CONTROL_LOCAL: StringName = &"local"
const CONTROL_REMOTE: StringName = &"remote"
const FLOOR_NORMAL_Y_THRESHOLD: float = -0.5

const BLUE_BODY_TEXTURE: Texture2D = preload("res://assets/Player/blue_ball.png")
const BLUE_BODY_TEXTURE_MIRRORED: Texture2D = preload("res://assets/Player/blue_ball_mirrored.png")
const RED_BODY_TEXTURE: Texture2D = preload("res://assets/Player/red_ball.png")
const RED_BODY_TEXTURE_MIRRORED: Texture2D = preload("res://assets/Player/red_ball_mirrored.png")

const BLUE_LIMB_COLOR: Color = Color8(80, 170, 255, 255)
const RED_LIMB_COLOR: Color = Color8(235, 80, 80, 255)

@export var gravity := 1350.0
@export var wall_slide_speed := 80.0
@export var air_speed := 120.0
@export var speed := 250.0
@export var ground_acceleration := 6000.0
@export var ground_friction := 5500.0
@export var air_acceleration := 3000.0
@export var air_friction := 1000.0
@export var fall_gravity_multiplier := 1.5
@export var low_jump_gravity_multiplier := 2.5
@export var jump_velocity := 500.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var wall_coyote_time := 0.15
@export var max_fall_speed := 720.0
@export var wall_jump_velocity := Vector2(320.0, -500.0)
@export var hover_dist := 24.0
@export var hover_snap_speed := 30.0
@export var foot_spread := 12.0
@export var hip_y_offset := 13.5
@export var bounce_amp := 1.5

@export var look_ahead := 0.155
@export var step_trigger := 7.5
@export var step_duration := 0.10
@export var step_arc_h := 5.0
@export var stride_min_interval := 0.08

@export var air_foot_tuck_x := 10.5
@export var air_foot_tuck_y := 7.5

@export var remote_interpolation_speed := 25.0

var player_slot := 0
var control_mode: StringName = CONTROL_LOCAL
var move_left_action: StringName = &"p1_move_left"
var move_right_action: StringName = &"p1_move_right"
var jump_action: StringName = &"p1_jump"
var shoot_action: StringName = &"p1_shoot"
var shooting_enabled := true

var foot_pos_l: Vector2
var foot_pos_r: Vector2
var bounce_t := 0.0
var last_dir := 1.0
var _last_visual_move_dir: float = 0.0
var _was_visual_grounded: bool = false

var _network_target_position := Vector2.ZERO
var _network_target_velocity := Vector2.ZERO
var _network_aim_world_position := Vector2.ZERO
var _has_network_target := false
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _wall_coyote_timer := 0.0
var _wall_coyote_dir := 0.0
var _step_clock := 0.0
var _last_stepped := 1
var _last_step_time_l := -1000.0
var _last_step_time_r := -1000.0
var _step_from_l := Vector2.ZERO
var _step_to_l := Vector2.ZERO
var _step_t_l := 1.0
var _step_from_r := Vector2.ZERO
var _step_to_r := Vector2.ZERO
var _step_t_r := 1.0

@onready var _body_sprite: Sprite2D = $Sprite2D
@onready var _glove: Sprite2D = $ArmRenderer/Glove

var _leg_renderer
var _arm_renderer

@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR
@onready var _state_machine: StateMachine = $State
@onready var health_component: HealthComponent = $HealthComponent


func _ready() -> void:
	_leg_renderer = get_node_or_null("LegRenderer")
	_arm_renderer = get_node_or_null("ArmRenderer")
	_update_ground_rays()
	_initialize_feet()
	_network_target_position = global_position
	_network_aim_world_position = global_position + Vector2.LEFT * 80.0
	_apply_control_mode()
	_apply_player_palette()


func _physics_process(delta: float) -> void:
	_update_ground_rays()
	_step_clock += delta
	if control_mode == CONTROL_REMOTE:
		_physics_process_remote(delta)
		return
	_update_movement_timers(delta)
	update_wall_coyote(delta)


func configure_local_control(slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, allow_shoot: bool) -> void:
	player_slot = slot
	control_mode = CONTROL_LOCAL
	move_left_action = move_left
	move_right_action = move_right
	jump_action = jump
	shoot_action = shoot
	shooting_enabled = allow_shoot
	_apply_control_mode()
	_apply_player_palette()


func configure_remote_control(slot: int) -> void:
	player_slot = slot
	control_mode = CONTROL_REMOTE
	shooting_enabled = false
	_network_target_position = global_position
	_network_target_velocity = Vector2.ZERO
	_network_aim_world_position = global_position + Vector2.LEFT * 80.0
	_has_network_target = false
	_apply_control_mode()
	_apply_player_palette()


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_aim: Variant = snapshot.get("aim", _network_aim_world_position)
	var snapshot_facing: Variant = snapshot.get("facing", last_dir)
	var had_network_target := _has_network_target

	if snapshot_position is Vector2:
		_network_target_position = snapshot_position
	if snapshot_velocity is Vector2:
		_network_target_velocity = snapshot_velocity
	if snapshot_aim is Vector2:
		_network_aim_world_position = snapshot_aim
		var aim_vector: Vector2 = snapshot_aim - _network_target_position
		if aim_vector.length_squared() > 0.0001:
			var gun: Node = get_node_or_null("Gun")
			if gun != null and gun.has_method("set_aim_direction"):
				gun.call("set_aim_direction", aim_vector.normalized())
	if (snapshot_facing is float or snapshot_facing is int) and absf(float(snapshot_facing)) > 0.0:
		last_dir = signf(float(snapshot_facing))

	_has_network_target = true
	if not had_network_target:
		global_position = _network_target_position
		velocity = _network_target_velocity


func get_move_direction() -> float:
	if control_mode != CONTROL_LOCAL:
		return 0.0
	return clampf(Input.get_action_strength(move_right_action) - Input.get_action_strength(move_left_action), -1.0, 1.0)


func is_jump_pressed() -> bool:
	if control_mode != CONTROL_LOCAL:
		return false
	return Input.is_action_just_pressed(jump_action)


func is_jump_held() -> bool:
	if control_mode != CONTROL_LOCAL:
		return false
	return Input.is_action_pressed(jump_action)


func is_shoot_pressed() -> bool:
	if control_mode != CONTROL_LOCAL or not shooting_enabled:
		return false
	return Input.is_action_just_pressed(shoot_action)


func is_shoot_down() -> bool:
	if control_mode != CONTROL_LOCAL or not shooting_enabled:
		return false
	return Input.is_action_pressed(shoot_action)


func get_aim_world_position() -> Vector2:
	if control_mode == CONTROL_REMOTE:
		return _network_aim_world_position
	return get_global_mouse_position()


func _apply_control_mode() -> void:
	if _state_machine == null:
		return

	if control_mode == CONTROL_REMOTE:
		_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_state_machine.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process_remote(delta: float) -> void:
	if not _has_network_target:
		return

	var interpolation_weight := clampf(delta * remote_interpolation_speed, 0.0, 1.0)
	global_position = global_position.lerp(_network_target_position, interpolation_weight)
	velocity = _network_target_velocity
	if absf(velocity.x) > 1.0:
		last_dir = signf(velocity.x)
	update_visual_movement(delta)


func update_grounded() -> bool:
	if is_on_floor():
		return true
	if velocity.y < 0.0:
		return false
	return _is_floor_ray(_ray_l) or _is_floor_ray(_ray_r)


func can_jump() -> bool:
	return _coyote_timer > 0.0


func has_buffered_jump() -> bool:
	return _jump_buffer_timer > 0.0


func consume_jump_buffer() -> void:
	_jump_buffer_timer = 0.0


func update_wall_coyote(delta: float) -> void:
	if is_on_wall():
		_wall_coyote_timer = wall_coyote_time
		var wall_x := get_wall_normal().x
		_wall_coyote_dir = signf(wall_x) if absf(wall_x) > 0.0 else -last_dir
	else:
		_wall_coyote_timer = maxf(_wall_coyote_timer - delta, 0.0)


func can_wall_jump() -> bool:
	return _wall_coyote_timer > 0.0 and has_buffered_jump()


func wall_jump() -> void:
	var dir := _wall_coyote_dir
	if dir == 0.0:
		dir = -last_dir
	var input_dir := get_move_direction()
	if input_dir != 0.0:
		dir = -signf(input_dir)
	velocity.x = -dir * wall_jump_velocity.x
	velocity.y = wall_jump_velocity.y
	_wall_coyote_timer = 0.0
	consume_jump_buffer()
	_coyote_timer = 0.0


func jump() -> void:
	velocity.y = -jump_velocity
	_coyote_timer = 0.0
	consume_jump_buffer()


func apply_horizontal_movement(delta: float, max_speed: float, acceleration: float, friction: float) -> float:
	var direction := get_move_direction()
	if direction != 0.0:
		last_dir = signf(direction)
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	return direction


func apply_gravity(delta: float, multiplier := 1.0) -> void:
	velocity.y = minf(velocity.y + gravity * multiplier * delta, max_fall_speed)


func apply_better_jump_gravity(delta: float) -> void:
	var multiplier := 1.0
	if velocity.y > 0.0:
		multiplier = fall_gravity_multiplier
	elif velocity.y < 0.0 and not is_jump_held():
		multiplier = low_jump_gravity_multiplier
	apply_gravity(delta, multiplier)


func maintain_hover_height(delta: float) -> void:
	if not update_grounded():
		return

	var floor_y := global_position.y + hover_dist
	if _is_floor_ray(_ray_l):
		floor_y = minf(floor_y, _ray_l.get_collision_point().y)
	if _is_floor_ray(_ray_r):
		floor_y = minf(floor_y, _ray_r.get_collision_point().y)

	var target_y := floor_y - hover_dist
	global_position.y = lerpf(global_position.y, target_y, clampf(delta * hover_snap_speed, 0.0, 1.0))
	if velocity.y > 0.0:
		velocity.y = 0.0


func update_visual_movement(delta: float) -> void:
	var speed_ratio := clampf(absf(velocity.x) / maxf(speed, 1.0), 0.0, 1.0)
	var grounded: bool = update_grounded()
	if grounded:
		var look := velocity.x * look_ahead
		var floor_y := global_position.y + hover_dist
		if _is_floor_ray(_ray_l):
			floor_y = minf(floor_y, _ray_l.get_collision_point().y)
		if _is_floor_ray(_ray_r):
			floor_y = minf(floor_y, _ray_r.get_collision_point().y)

		var ideal_l := Vector2(global_position.x - foot_spread + look, floor_y)
		var ideal_r := Vector2(global_position.x + foot_spread + look, floor_y)
		var floor_l: bool = _is_floor_ray(_ray_l)
		var floor_r: bool = _is_floor_ray(_ray_r)
		if floor_l != floor_r:
			var edge_gap: float = foot_spread * 1.25
			if floor_l:
				ideal_l.x = minf(ideal_l.x, _ray_l.get_collision_point().x)
				ideal_r.x = minf(ideal_r.x, ideal_l.x + edge_gap)
			else:
				ideal_r.x = maxf(ideal_r.x, _ray_r.get_collision_point().x)
				ideal_l.x = maxf(ideal_l.x, ideal_r.x - edge_gap)
		var move_dir: float = _get_visual_move_direction()
		var changed_direction: bool = (
			move_dir != 0.0
			and _last_visual_move_dir != 0.0
			and move_dir != _last_visual_move_dir
		)

		if not _was_visual_grounded:
			_set_feet(ideal_l, ideal_r)

		if _step_t_l < 1.0:
			_step_t_l = minf(_step_t_l + delta / step_duration, 1.0)
			foot_pos_l = _arc(_step_from_l, _step_to_l, _step_t_l, step_arc_h)
		if _step_t_r < 1.0:
			_step_t_r = minf(_step_t_r + delta / step_duration, 1.0)
			foot_pos_r = _arc(_step_from_r, _step_to_r, _step_t_r, step_arc_h)

		if changed_direction:
			_set_feet(ideal_l, ideal_r)
		elif _step_t_l >= 1.0 and _step_t_r >= 1.0:
			var dl := foot_pos_l.distance_to(ideal_l)
			var dr := foot_pos_r.distance_to(ideal_r)
			var l_ready := (_step_clock - _last_step_time_l) >= stride_min_interval
			var r_ready := (_step_clock - _last_step_time_r) >= stride_min_interval

			var prefer_left := _last_stepped == 1
			if prefer_left:
				if dl > step_trigger and l_ready:
					_begin_step(true, ideal_l)
				elif dr > step_trigger and r_ready:
					_begin_step(false, ideal_r)
			else:
				if dr > step_trigger and r_ready:
					_begin_step(false, ideal_r)
				elif dl > step_trigger and l_ready:
					_begin_step(true, ideal_l)

		bounce_t += delta * 8.0 * speed_ratio
		_was_visual_grounded = true
		if move_dir != 0.0:
			_last_visual_move_dir = move_dir
	else:
		_was_visual_grounded = false
		_last_visual_move_dir = 0.0
		_step_t_l = 1.0
		_step_t_r = 1.0
		var hip := global_position + Vector2(0.0, hip_y_offset).rotated(rotation)
		foot_pos_l = foot_pos_l.lerp(hip + Vector2(-air_foot_tuck_x, hover_dist * 0.7 - air_foot_tuck_y), delta * 10.0)
		foot_pos_r = foot_pos_r.lerp(hip + Vector2(air_foot_tuck_x, hover_dist * 0.7 - air_foot_tuck_y), delta * 10.0)
		bounce_t = lerp(bounce_t, 0.0, delta * 8.0)

	var visual_direction := get_move_direction()
	if control_mode == CONTROL_REMOTE:
		visual_direction = clampf(velocity.x / maxf(speed, 1.0), -1.0, 1.0)
	rotation = lerp_angle(rotation, visual_direction * 0.08, delta * 10.0)
	_update_body_sprite_direction()


func _update_movement_timers(delta: float) -> void:
	if is_jump_pressed():
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if update_grounded():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _initialize_feet() -> void:
	_set_feet(
		global_position + Vector2(-foot_spread, hover_dist),
		global_position + Vector2(foot_spread, hover_dist)
	)


func _update_ground_rays() -> void:
	var target_len := maxf(hover_dist, 8.0)
	_ray_l.target_position.y = target_len
	_ray_r.target_position.y = target_len


func _is_floor_ray(ray: RayCast2D) -> bool:
	if not ray.is_colliding():
		return false
	return ray.get_collision_normal().y <= FLOOR_NORMAL_Y_THRESHOLD


func _get_visual_move_direction() -> float:
	var input_direction: float = get_move_direction()
	if input_direction != 0.0:
		return signf(input_direction)
	if absf(velocity.x) > 20.0:
		return signf(velocity.x)
	return 0.0


func _set_feet(left: Vector2, right: Vector2) -> void:
	foot_pos_l = left
	foot_pos_r = right
	_step_from_l = foot_pos_l
	_step_to_l = foot_pos_l
	_step_from_r = foot_pos_r
	_step_to_r = foot_pos_r
	_step_t_l = 1.0
	_step_t_r = 1.0


func _arc(a: Vector2, b: Vector2, t: float, h: float) -> Vector2:
	var p := a.lerp(b, t)
	p.y -= sin(t * PI) * h
	return p


func _apply_player_palette() -> void:
	var limb_color := BLUE_LIMB_COLOR if _is_blue_player() else RED_LIMB_COLOR
	if _leg_renderer != null:
		_leg_renderer.col_leg = limb_color
	if _arm_renderer != null:
		_arm_renderer.col_arm = limb_color
	if _glove != null:
		_glove.modulate = limb_color
	_update_body_sprite_direction()


func _update_body_sprite_direction() -> void:
	if _body_sprite == null:
		return
	var facing_dir := signf(last_dir)
	if facing_dir == 0.0:
		facing_dir = 1.0
	var facing_left := facing_dir < 0.0
	var next_texture: Texture2D
	if _is_blue_player():
		next_texture = BLUE_BODY_TEXTURE_MIRRORED if facing_left else BLUE_BODY_TEXTURE
	else:
		next_texture = RED_BODY_TEXTURE_MIRRORED if facing_left else RED_BODY_TEXTURE
	if _body_sprite.texture != next_texture:
		_body_sprite.texture = next_texture
	_body_sprite.flip_h = false


func _is_blue_player() -> bool:
	return player_slot != 2


func _begin_step(is_left: bool, target: Vector2) -> void:
	if is_left:
		_step_from_l = foot_pos_l
		_step_to_l = target
		_step_t_l = 0.0
		_last_stepped = 0
		_last_step_time_l = _step_clock
	else:
		_step_from_r = foot_pos_r
		_step_to_r = target
		_step_t_r = 0.0
		_last_stepped = 1
		_last_step_time_r = _step_clock
