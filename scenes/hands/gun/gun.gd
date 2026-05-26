extends Node2D

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

@export var orbit_radius: float = GameSettings.GUN_ORBIT_RADIUS
@export var aim_angle_offset_degrees: float = GameSettings.GUN_AIM_ANGLE_OFFSET_DEGREES
@export var fire_interval: float = GameSettings.GUN_FIRE_INTERVAL
@export var automatic_fire: bool = GameSettings.GUN_AUTOMATIC_FIRE
@export var projectile_speed: float = GameSettings.GUN_PROJECTILE_SPEED
@export var projectile_gravity: float = GameSettings.GUN_PROJECTILE_GRAVITY
@export var projectile_linear_damping: float = GameSettings.GUN_PROJECTILE_LINEAR_DAMPING
@export var projectile_max_distance: float = GameSettings.GUN_PROJECTILE_MAX_DISTANCE

var _aim_direction: Vector2 = Vector2.LEFT
var _pointing_right: bool = false
var _fire_cooldown: float = 0.0
var _recoil_offset: float = 0.0
var _recoil_rotation: float = 0.0

@onready var _player: Player = get_parent() as Player
@onready var _visual_root: Node2D = $VisualRoot
@onready var _muzzle: Marker2D = $VisualRoot/Muzzle


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_recoil_offset = move_toward(_recoil_offset, 0.0, GameSettings.GUN_RECOIL_RETURN_SPEED * delta)
	_recoil_rotation = lerp_angle(_recoil_rotation, 0.0, clampf(delta * 18.0, 0.0, 1.0))

	var aim_position: Vector2 = _player.get_aim_world_position()
	var aim_vector: Vector2 = aim_position - _player.global_position
	if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		_set_aim_direction(aim_vector)

	_update_visual_transform()

	var wants_shot: bool = _player.is_shoot_down() if automatic_fire else _player.is_shoot_pressed()
	if wants_shot and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = fire_interval


func _shoot() -> void:
	var direction: Vector2 = get_shot_direction()
	var muzzle_position: Vector2 = get_muzzle_global_position()
	_play_fire_feedback(direction, muzzle_position)

	var world: Node = get_tree().get_first_node_in_group("game_world")
	if world == null:
		world = _player.get_parent()
	if world != null and world.has_method("request_shot"):
		world.request_shot(_player, muzzle_position, direction, _build_projectile_data(direction))
		return

	if world == null or not world.has_method("spawn_projectile"):
		return

	var projectile: Node2D = PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", projectile_speed)
	projectile.set("gravity", projectile_gravity)
	projectile.set("linear_damping", projectile_linear_damping)
	projectile.set("max_distance", projectile_max_distance)
	projectile.set("initial_velocity", direction * projectile_speed)
	world.spawn_projectile(projectile, muzzle_position)


func build_shot_data() -> Dictionary:
	var direction: Vector2 = get_shot_direction()
	return {
		"spawn_position": get_muzzle_global_position(),
		"direction": direction,
		"fire_interval": fire_interval,
		"projectile": _build_projectile_data(direction),
	}


func get_muzzle_global_position() -> Vector2:
	if _muzzle == null:
		return global_position
	return _muzzle.global_position


func get_shot_direction() -> Vector2:
	if _aim_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return Vector2.LEFT
	return _aim_direction.normalized()


func set_aim_direction(direction: Vector2) -> void:
	if _set_aim_direction(direction):
		_update_visual_transform()


func _set_aim_direction(direction: Vector2) -> bool:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return false

	_aim_direction = direction.normalized()
	_pointing_right = _aim_direction.x > 0.0
	return true


func _update_visual_transform() -> void:
	if _player == null or _visual_root == null:
		return

	var current_radius: float = maxf(orbit_radius - _recoil_offset, orbit_radius * 0.58)
	global_position = _player.global_position + _aim_direction * current_radius
	global_rotation = _aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees) + _recoil_rotation
	_visual_root.scale.x = 1.0 + _recoil_offset * 0.008
	_visual_root.scale.y = (-1.0 if _pointing_right else 1.0) * (1.0 - _recoil_offset * 0.004)


func _build_projectile_data(direction: Vector2) -> Dictionary:
	return {
		"muzzle_speed": projectile_speed,
		"gravity": projectile_gravity,
		"linear_damping": projectile_linear_damping,
		"max_distance": projectile_max_distance,
		"initial_velocity": direction * projectile_speed,
	}


func _play_fire_feedback(direction: Vector2, muzzle_position: Vector2) -> void:
	_recoil_offset = GameSettings.GUN_RECOIL_DISTANCE
	var recoil_side: float = -1.0 if _pointing_right else 1.0
	_recoil_rotation = deg_to_rad(GameSettings.GUN_RECOIL_ROTATION_DEGREES) * recoil_side
	GameJuice.spawn_muzzle(muzzle_position, direction)
	GameJuice.play_sound_2d(&"shoot", muzzle_position, -12.0, 0.06)
	GameJuice.shake(GameSettings.GUN_FIRE_SHAKE_STRENGTH, GameSettings.GUN_FIRE_SHAKE_TIME)
