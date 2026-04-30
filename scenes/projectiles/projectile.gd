extends CharacterBody2D

@export var muzzle_speed := 1200.0
@export var gravity := 980.0
@export var linear_damping := 0.0
@export var max_distance := 1400.0
@export var rotate_to_velocity := true

var direction := Vector2.LEFT
var initial_velocity := Vector2.ZERO
var _distance_travelled := 0.0


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
		queue_free()
		return

	_distance_travelled += motion.length()
	if _distance_travelled >= max_distance:
		queue_free()
