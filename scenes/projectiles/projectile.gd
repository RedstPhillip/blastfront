extends CharacterBody2D

signal despawn_requested(projectile: Node, reason: StringName, collider)

@export var muzzle_speed := 1200.0
@export var gravity := 980.0
@export var linear_damping := 0.0
@export var max_distance := 1400.0
@export var rotate_to_velocity := true

var net_id := 0
var owner_slot := 0
var is_network_authority := true
var direction := Vector2.LEFT
var initial_velocity := Vector2.ZERO
var _distance_travelled := 0.0
var _despawn_requested := false


func _ready() -> void:
	if direction.length_squared() <= 0.0001:
		direction = Vector2.LEFT

	direction = direction.normalized()
	velocity = initial_velocity if initial_velocity.length_squared() > 0.0001 else direction * muzzle_speed
	if rotate_to_velocity and velocity.length_squared() > 0.0001:
		rotation = velocity.angle()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if linear_damping > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, linear_damping * delta)

	if rotate_to_velocity and velocity.length_squared() > 0.0001:
		rotation = velocity.angle()

	var motion := velocity * delta
	var collision := move_and_collide(motion)
	if collision != null:
		_request_despawn(&"collision", collision.get_collider())
		return

	_distance_travelled += motion.length()
	if _distance_travelled >= max_distance:
		_request_despawn(&"max_distance", null)


func apply_network_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_rotation: Variant = snapshot.get("rotation", rotation)

	if snapshot_position is Vector2:
		global_position = global_position.lerp(snapshot_position, 0.6)
	if snapshot_velocity is Vector2:
		velocity = snapshot_velocity
	if snapshot_rotation is float or snapshot_rotation is int:
		rotation = float(snapshot_rotation)


func _request_despawn(reason: StringName, collider) -> void:
	if _despawn_requested:
		return

	_despawn_requested = true
	if is_network_authority:
		despawn_requested.emit(self, reason, collider)
	queue_free()
