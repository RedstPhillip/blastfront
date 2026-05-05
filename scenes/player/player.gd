extends CharacterBody2D
class_name Player

const PlayerMovementLogic = preload("res://scenes/player/player_movement_logic.gd")

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


const BASE_LEG_LENGTH := 25.0

var foot_pos_l: Vector2
var foot_pos_r: Vector2
var bounce_t := 0.0
var last_dir := 1.0

var _movement_logic: PlayerMovementLogic

@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR


func _ready() -> void:
	_movement_logic = PlayerMovementLogic.new()
	_movement_logic.setup(self)


func _physics_process(delta: float) -> void:
	pass
	#_movement_logic.physics_process(self, delta)
