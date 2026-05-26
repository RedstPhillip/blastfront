extends CharacterBody2D

signal despawn_requested(projectile: Node, reason: StringName, collider)

@export var muzzle_speed: float = GameSettings.PROJECTILE_MUZZLE_SPEED
@export var gravity: float = GameSettings.PROJECTILE_GRAVITY
@export var max_distance: float = GameSettings.PROJECTILE_MAX_DISTANCE
@export var linear_damping: float = GameSettings.PROJECTILE_LINEAR_DAMPING
@export var rotate_to_velocity: bool = GameSettings.PROJECTILE_ROTATE_TO_VELOCITY

var net_id: int = 0
var owner_slot: int = 0
var is_network_authority: bool = true
var direction: Vector2 = Vector2.LEFT
var initial_velocity: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _despawn_requested: bool = false


func _ready() -> void:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		direction = Vector2.LEFT
	direction = direction.normalized()

	velocity = initial_velocity if initial_velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else direction * muzzle_speed
	_update_rotation()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if linear_damping > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, linear_damping * delta)
	_update_rotation()

	var motion := velocity * delta
	var collision := move_and_collide(motion)
	if collision != null:
		_on_collision(collision)
		return

	_distance_travelled += motion.length()
	if _distance_travelled >= max_distance:
		_request_despawn(&"max_distance", null)


func apply_network_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_rotation: Variant = snapshot.get("rotation", rotation)

	if snapshot_position is Vector2:
		global_position = global_position.lerp(snapshot_position, GameSettings.PROJECTILE_SNAPSHOT_INTERPOLATION)
	if snapshot_velocity is Vector2:
		velocity = snapshot_velocity
	if snapshot_rotation is float or snapshot_rotation is int:
		rotation = float(snapshot_rotation)


func _update_rotation() -> void:
	if rotate_to_velocity and velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		rotation = velocity.angle()


func _on_collision(collision: KinematicCollision2D) -> void:
	var collider: Object = collision.get_collider()
	_play_collision_feedback(collision, collider)
	if net_id == 0:
		_apply_local_collision_damage(collider)
	_request_despawn(&"collision", collider)


func _apply_local_collision_damage(collider: Object) -> void:
	var player: Player = collider as Player
	if player != null:
		player.apply_hit_feedback(global_position, GameSettings.PROJECTILE_DAMAGE)
		player.health_component.damage(GameSettings.PROJECTILE_DAMAGE)


func _request_despawn(reason: StringName, collider: Object) -> void:
	if _despawn_requested:
		return

	_despawn_requested = true
	if is_network_authority:
		despawn_requested.emit(self, reason, collider)
	queue_free()


func _play_collision_feedback(collision: KinematicCollision2D, collider: Object) -> void:
	var collision_position: Vector2 = collision.get_position()
	var impact_direction: Vector2 = collision.get_normal()
	if impact_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED and velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		impact_direction = -velocity.normalized()

	var hit_player: Player = collider as Player
	if hit_player != null:
		return

	GameJuice.spawn_burst(&"impact", collision_position, impact_direction, Color(0.98, 0.55, 0.18, 0.9))
	GameJuice.play_sound_2d(&"impact", collision_position, -7.0, 0.035)
	GameJuice.shake(GameSettings.PROJECTILE_IMPACT_SHAKE_STRENGTH, GameSettings.PROJECTILE_IMPACT_SHAKE_TIME)
