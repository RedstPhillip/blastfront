extends CharacterBody2D
class_name Player

const PlayerMovementLogic = preload("res://scenes/player/player_movement_logic.gd")
const CONTROL_LOCAL: StringName = &"local"
const CONTROL_REMOTE: StringName = &"remote"

@export var gravity := 1000;
@export var wall_slide_speed := 100;
@export var move_force := 600.0;
@export var air_speed := 120;
@export var speed := 210.0
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
@export var speed_step_boost := 0.55
@export var fast_step_duration_scale := 0.725
@export var fast_step_arc_scale := 1.35
@export var remote_interpolation_speed := 18.0


const BASE_LEG_LENGTH := 25.0

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

var _movement_logic: PlayerMovementLogic
var _network_target_position := Vector2.ZERO
var _network_target_velocity := Vector2.ZERO
var _network_aim_world_position := Vector2.ZERO
var _has_network_target := false

@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR
@onready var _state_machine: StateMachine = $State


func _ready() -> void:
	_movement_logic = PlayerMovementLogic.new()
	_movement_logic.setup(self)
	_network_target_position = global_position
	_network_aim_world_position = global_position + Vector2.LEFT * 80.0
	_apply_control_mode()


func _physics_process(delta: float) -> void:
	if control_mode == CONTROL_REMOTE and _has_network_target:
		var interpolation_weight := clampf(delta * remote_interpolation_speed, 0.0, 1.0)
		global_position = global_position.lerp(_network_target_position, interpolation_weight)
		velocity = _network_target_velocity
	#_movement_logic.physics_process(self, delta)


func configure_local_control(slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, allow_shoot: bool) -> void:
	player_slot = slot
	control_mode = CONTROL_LOCAL
	move_left_action = move_left
	move_right_action = move_right
	jump_action = jump
	shoot_action = shoot
	shooting_enabled = allow_shoot
	_apply_control_mode()


func configure_remote_control(slot: int) -> void:
	player_slot = slot
	control_mode = CONTROL_REMOTE
	shooting_enabled = false
	_network_target_position = global_position
	_network_target_velocity = Vector2.ZERO
	_network_aim_world_position = global_position + Vector2.LEFT * 80.0
	_has_network_target = false
	_apply_control_mode()


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_aim: Variant = snapshot.get("aim", _network_aim_world_position)

	if snapshot_position is Vector2:
		_network_target_position = snapshot_position
	if snapshot_velocity is Vector2:
		_network_target_velocity = snapshot_velocity
	if snapshot_aim is Vector2:
		_network_aim_world_position = snapshot_aim

	_has_network_target = true


func get_move_direction() -> float:
	if control_mode != CONTROL_LOCAL:
		return 0.0
	return clampf(Input.get_action_strength(move_right_action) - Input.get_action_strength(move_left_action), -1.0, 1.0)


func is_jump_pressed() -> bool:
	if control_mode != CONTROL_LOCAL:
		return false
	return Input.is_action_just_pressed(jump_action)


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
