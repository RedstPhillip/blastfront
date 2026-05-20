extends CharacterBody2D
class_name Player

const BLUE_BODY_TEXTURE: Texture2D = preload("res://assets/Player/blue_ball.png")
const BLUE_BODY_TEXTURE_MIRRORED: Texture2D = preload("res://assets/Player/blue_ball_mirrored.png")
const RED_BODY_TEXTURE: Texture2D = preload("res://assets/Player/red_ball.png")
const RED_BODY_TEXTURE_MIRRORED: Texture2D = preload("res://assets/Player/red_ball_mirrored.png")

@export var gravity: float = GameSettings.PLAYER_GRAVITY
@export var wall_slide_speed: float = GameSettings.PLAYER_WALL_SLIDE_SPEED
@export var air_speed: float = GameSettings.PLAYER_AIR_SPEED
@export var speed: float = GameSettings.PLAYER_SPEED
@export var ground_acceleration: float = GameSettings.PLAYER_GROUND_ACCELERATION
@export var ground_friction: float = GameSettings.PLAYER_GROUND_FRICTION
@export var air_acceleration: float = GameSettings.PLAYER_AIR_ACCELERATION
@export var air_friction: float = GameSettings.PLAYER_AIR_FRICTION
@export var fall_gravity_multiplier: float = GameSettings.PLAYER_FALL_GRAVITY_MULTIPLIER
@export var low_jump_gravity_multiplier: float = GameSettings.PLAYER_LOW_JUMP_GRAVITY_MULTIPLIER
@export var jump_velocity: float = GameSettings.PLAYER_JUMP_VELOCITY
@export var coyote_time: float = GameSettings.PLAYER_COYOTE_TIME
@export var jump_buffer_time: float = GameSettings.PLAYER_JUMP_BUFFER_TIME
@export var wall_coyote_time: float = GameSettings.PLAYER_WALL_COYOTE_TIME
@export var max_fall_speed: float = GameSettings.PLAYER_MAX_FALL_SPEED
@export var wall_jump_velocity: Vector2 = GameSettings.PLAYER_WALL_JUMP_VELOCITY
@export var hover_dist: float = GameSettings.PLAYER_HOVER_DISTANCE
@export var hover_snap_speed: float = GameSettings.PLAYER_HOVER_SNAP_SPEED
@export var foot_spread: float = GameSettings.PLAYER_FOOT_SPREAD
@export var hip_y_offset: float = GameSettings.PLAYER_HIP_Y_OFFSET
@export var bounce_amp: float = GameSettings.PLAYER_BOUNCE_AMPLITUDE

@export var look_ahead: float = GameSettings.PLAYER_LOOK_AHEAD
@export var step_trigger: float = GameSettings.PLAYER_STEP_TRIGGER
@export var step_duration: float = GameSettings.PLAYER_STEP_DURATION
@export var step_arc_h: float = GameSettings.PLAYER_STEP_ARC_HEIGHT
@export var stride_min_interval: float = GameSettings.PLAYER_STRIDE_MIN_INTERVAL

@export var air_foot_tuck_x: float = GameSettings.PLAYER_AIR_FOOT_TUCK_X
@export var air_foot_tuck_y: float = GameSettings.PLAYER_AIR_FOOT_TUCK_Y

@export var remote_interpolation_speed: float = GameSettings.PLAYER_REMOTE_INTERPOLATION_SPEED

var player_slot: int = 0
var control_mode: StringName = GameSettings.CONTROL_LOCAL
var move_left_action: StringName = GameSettings.INPUT_P1_MOVE_LEFT
var move_right_action: StringName = GameSettings.INPUT_P1_MOVE_RIGHT
var jump_action: StringName = GameSettings.INPUT_P1_JUMP
var shoot_action: StringName = GameSettings.INPUT_P1_SHOOT
var shooting_enabled: bool = true
var movement_enabled: bool = true
var player_color_id: StringName = &""

var foot_pos_l: Vector2
var foot_pos_r: Vector2
var bounce_t: float = 0.0
var last_dir: float = 1.0
var _last_visual_move_dir: float = 0.0
var _was_visual_grounded: bool = false

var _network_target_position: Vector2 = Vector2.ZERO
var _network_target_velocity: Vector2 = Vector2.ZERO
var _network_aim_world_position: Vector2 = Vector2.ZERO
var _has_network_target: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _wall_coyote_timer: float = 0.0
var _wall_coyote_dir: float = 0.0
var _step_clock: float = 0.0
var _last_stepped: int = 1
var _last_step_time_l: float = GameSettings.PLAYER_INITIAL_STEP_TIME
var _last_step_time_r: float = GameSettings.PLAYER_INITIAL_STEP_TIME
var _step_from_l: Vector2 = Vector2.ZERO
var _step_to_l: Vector2 = Vector2.ZERO
var _step_t_l: float = 1.0
var _step_from_r: Vector2 = Vector2.ZERO
var _step_to_r: Vector2 = Vector2.ZERO
var _step_t_r: float = 1.0
var _can_shoot_when_controls_enabled: bool = true
var _body_base_scale: Vector2 = Vector2.ONE
var _body_motion_scale: Vector2 = Vector2.ONE
var _body_punch_scale: Vector2 = Vector2.ONE
var _hit_flash_timer: float = 0.0
var _hit_feedback_guard_timer: float = 0.0
var _run_dust_timer: float = 0.0
var _step_sound_timer: float = 0.0
var _last_feedback_grounded: bool = false
var _last_feedback_velocity_y: float = 0.0
var _idle_visual_time: float = 0.0

@onready var _body_sprite: Sprite2D = $Sprite2D
@onready var _glove: Sprite2D = $ArmRenderer/Glove

var _leg_renderer: Node = null
var _arm_renderer: Node = null

@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR
@onready var _state_machine: StateMachine = $State
@onready var health_component: HealthComponent = $HealthComponent


func _ready() -> void:
	_leg_renderer = get_node_or_null("LegRenderer")
	_arm_renderer = get_node_or_null("ArmRenderer")
	_body_base_scale = _body_sprite.scale
	_update_ground_rays()
	_initialize_feet()
	_network_target_position = global_position
	_network_aim_world_position = global_position + Vector2.LEFT * GameSettings.PLAYER_REMOTE_AIM_DISTANCE
	_apply_control_mode()
	_apply_player_palette()
	_last_feedback_grounded = update_grounded()
	_last_feedback_velocity_y = velocity.y
	if not health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.connect(_on_health_changed)
	if not health_component.health_depleted.is_connected(_on_health_depleted):
		health_component.health_depleted.connect(_on_health_depleted)


func _process(delta: float) -> void:
	_update_feedback_visuals(delta)


func _physics_process(delta: float) -> void:
	_update_ground_rays()
	_step_clock += delta
	if control_mode == GameSettings.CONTROL_REMOTE:
		_physics_process_remote(delta)
		return
	_update_movement_timers(delta)
	update_wall_coyote(delta)


func configure_local_control(slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, allow_shoot: bool) -> void:
	player_slot = slot
	control_mode = GameSettings.CONTROL_LOCAL
	move_left_action = move_left
	move_right_action = move_right
	jump_action = jump
	shoot_action = shoot
	_can_shoot_when_controls_enabled = allow_shoot
	shooting_enabled = movement_enabled and _can_shoot_when_controls_enabled
	_apply_control_mode()
	_apply_player_palette()


func configure_remote_control(slot: int) -> void:
	player_slot = slot
	control_mode = GameSettings.CONTROL_REMOTE
	_can_shoot_when_controls_enabled = false
	shooting_enabled = false
	_network_target_position = global_position
	_network_target_velocity = Vector2.ZERO
	_network_aim_world_position = global_position + Vector2.LEFT * GameSettings.PLAYER_REMOTE_AIM_DISTANCE
	_has_network_target = false
	_apply_control_mode()
	_apply_player_palette()


func set_controls_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	shooting_enabled = enabled and _can_shoot_when_controls_enabled


func set_player_color(color_id: StringName) -> void:
	if not GameSettings.is_valid_player_color(color_id):
		return
	player_color_id = color_id
	_apply_player_palette()


func get_visual_tint() -> Color:
	return GameSettings.player_color_value(_get_effective_color_id())


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
		if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
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
	if control_mode != GameSettings.CONTROL_LOCAL or not movement_enabled:
		return 0.0
	return clampf(Input.get_action_strength(move_right_action) - Input.get_action_strength(move_left_action), -1.0, 1.0)


func is_jump_pressed() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL or not movement_enabled:
		return false
	return Input.is_action_just_pressed(jump_action)


func is_jump_held() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL or not movement_enabled:
		return false
	return Input.is_action_pressed(jump_action)


func is_shoot_pressed() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL or not shooting_enabled:
		return false
	return Input.is_action_just_pressed(shoot_action)


func is_shoot_down() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL or not shooting_enabled:
		return false
	return Input.is_action_pressed(shoot_action)


func get_aim_world_position() -> Vector2:
	if control_mode == GameSettings.CONTROL_REMOTE:
		return _network_aim_world_position
	return get_global_mouse_position()


func _apply_control_mode() -> void:
	if _state_machine == null:
		return

	if control_mode == GameSettings.CONTROL_REMOTE:
		_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_state_machine.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process_remote(delta: float) -> void:
	if not _has_network_target:
		return

	var interpolation_weight := clampf(delta * remote_interpolation_speed, 0.0, 1.0)
	global_position = global_position.lerp(_network_target_position, interpolation_weight)
	velocity = _network_target_velocity
	if absf(velocity.x) > GameSettings.PLAYER_REMOTE_FACING_SPEED_THRESHOLD:
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
	_emit_jump_feedback(Vector2(dir, 0.35))


func jump() -> void:
	velocity.y = -jump_velocity
	_coyote_timer = 0.0
	consume_jump_buffer()
	_emit_jump_feedback(Vector2.DOWN)


func apply_horizontal_movement(delta: float, max_speed: float, acceleration: float, friction: float) -> float:
	var direction := get_move_direction()
	if direction != 0.0:
		last_dir = signf(direction)
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	return direction


func apply_gravity(delta: float, multiplier: float = 1.0) -> void:
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
	_update_surface_feedback(delta, grounded, speed_ratio)
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
			var edge_gap: float = foot_spread * GameSettings.PLAYER_EDGE_GAP_MULTIPLIER
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

		bounce_t += delta * GameSettings.PLAYER_BOUNCE_SPEED * speed_ratio
		_was_visual_grounded = true
		if move_dir != 0.0:
			_last_visual_move_dir = move_dir
	else:
		_was_visual_grounded = false
		_last_visual_move_dir = 0.0
		_step_t_l = 1.0
		_step_t_r = 1.0
		var hip := global_position + Vector2(0.0, hip_y_offset).rotated(rotation)
		var tuck_y: float = hover_dist * GameSettings.PLAYER_AIR_FOOT_HOVER_MULTIPLIER - air_foot_tuck_y
		foot_pos_l = foot_pos_l.lerp(
			hip + Vector2(-air_foot_tuck_x, tuck_y),
			delta * GameSettings.PLAYER_AIR_FOOT_LERP_SPEED
		)
		foot_pos_r = foot_pos_r.lerp(
			hip + Vector2(air_foot_tuck_x, tuck_y),
			delta * GameSettings.PLAYER_AIR_FOOT_LERP_SPEED
		)
		bounce_t = lerp(bounce_t, 0.0, delta * GameSettings.PLAYER_BOUNCE_SPEED)

	var visual_direction := get_move_direction()
	if control_mode == GameSettings.CONTROL_REMOTE:
		visual_direction = clampf(velocity.x / maxf(speed, 1.0), -1.0, 1.0)
	rotation = lerp_angle(
		rotation,
		visual_direction * GameSettings.PLAYER_VISUAL_ROTATION_SCALE,
		delta * GameSettings.PLAYER_VISUAL_ROTATION_LERP_SPEED
	)
	_update_body_sprite_direction()


func apply_hit_feedback(source_position: Vector2, damage: int = GameSettings.PROJECTILE_DAMAGE) -> void:
	var away_from_source: Vector2 = global_position - source_position
	if away_from_source.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		away_from_source = Vector2(-last_dir, -0.25)
	var hit_direction: Vector2 = away_from_source.normalized()
	var tint: Color = GameSettings.player_color_value(_get_effective_color_id())
	var damage_ratio: float = clampf(float(damage) / maxf(float(GameSettings.PROJECTILE_DAMAGE), 1.0), 0.75, 1.8)

	_hit_flash_timer = GameSettings.PLAYER_HIT_FLASH_TIME
	_hit_feedback_guard_timer = 0.09
	_body_punch_scale = Vector2(1.18, 0.84)

	if control_mode == GameSettings.CONTROL_LOCAL and movement_enabled:
		velocity.x += hit_direction.x * GameSettings.PLAYER_HIT_KNOCKBACK_X * damage_ratio
		velocity.y -= GameSettings.PLAYER_HIT_KNOCKBACK_Y * damage_ratio

	GameJuice.spawn_burst(&"hit", global_position, hit_direction, tint)
	GameJuice.play_sound_2d(&"hit", global_position, -5.0, 0.08)
	GameJuice.shake(GameSettings.PLAYER_HIT_SHAKE_STRENGTH * damage_ratio, GameSettings.PLAYER_HIT_SHAKE_TIME)


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
	var target_len := maxf(hover_dist, GameSettings.PLAYER_FLOOR_RAY_MIN_LENGTH)
	_ray_l.target_position.y = target_len
	_ray_r.target_position.y = target_len


func _is_floor_ray(ray: RayCast2D) -> bool:
	if not ray.is_colliding():
		return false
	return ray.get_collision_normal().y <= GameSettings.PLAYER_FLOOR_NORMAL_Y_THRESHOLD


func _get_visual_move_direction() -> float:
	var input_direction: float = get_move_direction()
	if input_direction != 0.0:
		return signf(input_direction)
	if absf(velocity.x) > GameSettings.PLAYER_VISUAL_SPEED_THRESHOLD:
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
	var effective_color_id: StringName = _get_effective_color_id()
	var limb_color: Color = GameSettings.player_color_value(effective_color_id)
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
	var effective_color_id: StringName = _get_effective_color_id()
	var next_texture: Texture2D = _get_body_texture(effective_color_id, facing_left)
	if _body_sprite.texture != next_texture:
		_body_sprite.texture = next_texture
	_body_sprite.modulate = _get_body_sprite_base_modulate(effective_color_id, facing_left)
	_body_sprite.flip_h = false


func _get_effective_color_id() -> StringName:
	if GameSettings.is_valid_player_color(player_color_id):
		return player_color_id
	if player_slot == GameSettings.PLAYER_TWO_SLOT:
		return GameSettings.ONLINE_DEFAULT_REMOTE_COLOR
	return GameSettings.ONLINE_DEFAULT_LOCAL_COLOR


func _get_body_texture(color_id: StringName, facing_left: bool) -> Texture2D:
	if _has_body_texture(color_id, facing_left):
		var texture_path: String = _get_body_texture_path(color_id, facing_left)
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			return texture

	if color_id == GameSettings.PLAYER_COLOR_RED:
		return RED_BODY_TEXTURE_MIRRORED if facing_left else RED_BODY_TEXTURE
	return BLUE_BODY_TEXTURE_MIRRORED if facing_left else BLUE_BODY_TEXTURE


func _has_body_texture(color_id: StringName, facing_left: bool) -> bool:
	return ResourceLoader.exists(_get_body_texture_path(color_id, facing_left))


func _get_body_texture_path(color_id: StringName, facing_left: bool) -> String:
	var mirrored_suffix: String = "_mirrored" if facing_left else ""
	return "res://assets/Player/%s_ball%s.png" % [str(color_id), mirrored_suffix]


func _get_body_sprite_base_modulate(color_id: StringName, facing_left: bool) -> Color:
	return Color.WHITE if _has_body_texture(color_id, facing_left) else GameSettings.player_color_value(color_id)


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


func _emit_jump_feedback(direction: Vector2) -> void:
	var dust_position: Vector2 = global_position + Vector2(0.0, hover_dist - 4.0)
	_body_punch_scale = Vector2(0.82, 1.16)
	GameJuice.spawn_burst(&"jump", dust_position, direction, Color(0.86, 0.78, 0.56, 0.65))
	GameJuice.play_sound_2d(&"jump", global_position, -9.0, 0.07)


func _update_surface_feedback(delta: float, grounded: bool, speed_ratio: float) -> void:
	if grounded and not _last_feedback_grounded:
		var land_speed: float = maxf(_last_feedback_velocity_y, 0.0)
		if land_speed >= GameSettings.PLAYER_LAND_EFFECT_MIN_SPEED:
			var land_ratio: float = clampf(
				land_speed / GameSettings.PLAYER_HEAVY_LAND_EFFECT_SPEED,
				0.35,
				1.35
			)
			_body_punch_scale = Vector2(1.12 + land_ratio * 0.07, 0.90 - land_ratio * 0.05)
			GameJuice.spawn_burst(&"land", global_position + Vector2(0.0, hover_dist - 3.0), Vector2.UP, Color(0.78, 0.70, 0.54, 0.7))
			GameJuice.play_sound_2d(&"land", global_position, -10.0 + land_ratio * 2.0, 0.06)
			GameJuice.shake(1.8 * land_ratio, 0.065)

	if grounded and speed_ratio > 0.34 and absf(velocity.x) > GameSettings.PLAYER_VISUAL_SPEED_THRESHOLD:
		_run_dust_timer -= delta
		_step_sound_timer -= delta
		if _run_dust_timer <= 0.0:
			var move_direction: Vector2 = Vector2(signf(velocity.x), 0.0)
			GameJuice.spawn_burst(&"run_dust", global_position + Vector2(0.0, hover_dist - 2.0), move_direction, Color(0.76, 0.68, 0.50, 0.5))
			_run_dust_timer = GameSettings.PLAYER_RUN_DUST_INTERVAL
		if _step_sound_timer <= 0.0:
			GameJuice.play_sound_2d(&"step", global_position, -18.0 + speed_ratio * 2.0, 0.10)
			_step_sound_timer = GameSettings.PLAYER_STEP_SOUND_INTERVAL
	else:
		_run_dust_timer = minf(_run_dust_timer, GameSettings.PLAYER_RUN_DUST_INTERVAL)
		_step_sound_timer = minf(_step_sound_timer, GameSettings.PLAYER_STEP_SOUND_INTERVAL)

	_last_feedback_grounded = grounded
	_last_feedback_velocity_y = velocity.y


func _update_feedback_visuals(delta: float) -> void:
	if _body_sprite == null:
		return

	_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
	_hit_feedback_guard_timer = maxf(_hit_feedback_guard_timer - delta, 0.0)

	var horizontal_ratio: float = clampf(absf(velocity.x) / maxf(speed, 1.0), 0.0, 1.0)
	var target_scale: Vector2 = Vector2(1.0 + horizontal_ratio * 0.035, 1.0 - horizontal_ratio * 0.02)
	if _last_feedback_grounded and horizontal_ratio < 0.08:
		_idle_visual_time += delta
		var idle_pulse: float = sin(_idle_visual_time * 2.4) * 0.012
		target_scale = Vector2(1.0 + idle_pulse, 1.0 - idle_pulse)
	elif not _last_feedback_grounded:
		var vertical_ratio: float = clampf(absf(velocity.y) / maxf(max_fall_speed, 1.0), 0.0, 1.0)
		target_scale = Vector2(1.0 - vertical_ratio * 0.045, 1.0 + vertical_ratio * 0.075)
	else:
		_idle_visual_time = 0.0

	_body_motion_scale = _body_motion_scale.lerp(target_scale, clampf(delta * GameSettings.PLAYER_BODY_SCALE_LERP_SPEED, 0.0, 1.0))
	_body_punch_scale = _body_punch_scale.lerp(Vector2.ONE, clampf(delta * GameSettings.PLAYER_BODY_PUNCH_RETURN_SPEED, 0.0, 1.0))

	var combined_scale: Vector2 = Vector2(
		_body_motion_scale.x * _body_punch_scale.x,
		_body_motion_scale.y * _body_punch_scale.y
	)
	_body_sprite.scale = Vector2(
		_body_base_scale.x * combined_scale.x,
		_body_base_scale.y * combined_scale.y
	)

	var facing_dir: float = signf(last_dir)
	if facing_dir == 0.0:
		facing_dir = 1.0
	var facing_left: bool = facing_dir < 0.0
	var color_id: StringName = _get_effective_color_id()
	var base_modulate: Color = _get_body_sprite_base_modulate(color_id, facing_left)
	if _hit_flash_timer > 0.0:
		var hit_ratio: float = clampf(_hit_flash_timer / GameSettings.PLAYER_HIT_FLASH_TIME, 0.0, 1.0)
		_body_sprite.modulate = base_modulate.lerp(Color(1.0, 0.94, 0.70, 1.0), hit_ratio)
	else:
		_body_sprite.modulate = base_modulate


func _on_health_changed(old_health: int, new_health: int) -> void:
	if new_health >= old_health or _hit_feedback_guard_timer > 0.0:
		return
	var fallback_source: Vector2 = global_position - Vector2(last_dir * 64.0, 0.0)
	apply_hit_feedback(fallback_source, old_health - new_health)


func _on_health_depleted() -> void:
	var tint: Color = GameSettings.player_color_value(_get_effective_color_id())
	_hit_flash_timer = GameSettings.PLAYER_HIT_FLASH_TIME
	_body_punch_scale = Vector2(1.28, 0.72)
	GameJuice.spawn_burst(&"death", global_position, Vector2.UP, tint)
	GameJuice.play_sound_2d(&"death", global_position, -4.5, 0.06)
	GameJuice.shake(GameSettings.PLAYER_DEATH_SHAKE_STRENGTH, GameSettings.PLAYER_DEATH_SHAKE_TIME)
