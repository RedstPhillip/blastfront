extends Node2D

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

@export var orbit_radius := 30.0
@export var aim_angle_offset_degrees := 180.0
@export var fire_interval := 0.12
@export var automatic_fire := false
@export var projectile_speed := 1200.0
@export var projectile_gravity := 2500.0
@export var projectile_linear_damping := 0.0
@export var projectile_max_distance := 1400.0

var _aim_direction := Vector2.LEFT
var _pointing_right := false
var _fire_cooldown := 0.0

@onready var _player: Player = get_parent() as Player
@onready var _visual_root: Node2D = $VisualRoot
@onready var _muzzle: Marker2D = $VisualRoot/Muzzle


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	var aim_position: Vector2 = _player.get_aim_world_position()
	var aim_vector: Vector2 = aim_position - _player.global_position
	if aim_vector.length_squared() > 0.0001:
		_aim_direction = aim_vector.normalized()
		_pointing_right = _aim_direction.x > 0.0

	global_position = _player.global_position + _aim_direction * orbit_radius
	global_rotation = _aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees)

	_visual_root.scale.y = -1.0 if _pointing_right else 1.0

	var wants_shot: bool = _player.is_shoot_down() if automatic_fire else _player.is_shoot_pressed()
	if wants_shot and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = fire_interval


func _shoot() -> void:
	var world: Node = get_tree().get_first_node_in_group("game_world")
	if world == null:
		world = _player.get_parent()
	if world != null and world.has_method("request_shot"):
		var direction: Vector2 = get_shot_direction()
		world.request_shot(_player, get_muzzle_global_position(), direction, _build_projectile_data(direction))
		return

	if world == null or not world.has_method("spawn_projectile"):
		return

	var direction: Vector2 = get_shot_direction()
	var projectile := PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", projectile_speed)
	projectile.set("gravity", projectile_gravity)
	projectile.set("linear_damping", projectile_linear_damping)
	projectile.set("max_distance", projectile_max_distance)
	projectile.set("initial_velocity", direction * projectile_speed)
	world.spawn_projectile(projectile, get_muzzle_global_position())


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
	if _aim_direction.length_squared() <= 0.0001:
		return Vector2.LEFT
	return _aim_direction.normalized()


func set_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		_aim_direction = direction.normalized()
		_pointing_right = _aim_direction.x > 0.0
		global_rotation = _aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees)
		_visual_root.scale.y = -1.0 if _pointing_right else 1.0


func _build_projectile_data(direction: Vector2) -> Dictionary:
	return {
		"muzzle_speed": projectile_speed,
		"gravity": projectile_gravity,
		"linear_damping": projectile_linear_damping,
		"max_distance": projectile_max_distance,
		"initial_velocity": direction * projectile_speed,
	}
