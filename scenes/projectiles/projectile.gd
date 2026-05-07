extends CharacterBody2D

@export var muzzle_speed := 1200.0
@export var gravity := 980.0
@export var max_distance := 1400.0
@export var linear_damping := 0.0
@export var rotate_to_velocity := true

var direction := Vector2.LEFT
var _distance_travelled := 0.0


func _ready() -> void:
	if direction.length_squared() <= 0.0001:
		direction = Vector2.LEFT
	direction = direction.normalized()

	velocity = direction * muzzle_speed
	_update_rotation()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	velocity = velocity.move_toward(Vector2.ZERO, linear_damping * delta)
	_update_rotation()

	var motion := velocity * delta
	var collision := move_and_collide(motion)
	if collision != null:
		_on_collision(collision)
		return

	_distance_travelled += motion.length()
	if _distance_travelled >= max_distance:
		queue_free()


func _update_rotation() -> void:
	if rotate_to_velocity and velocity.length_squared() > 0.0001:
		rotation = velocity.angle()


func _on_collision(collision: KinematicCollision2D) -> void:
	var player := collision.get_collider() as Player
	if player != null:
		player.health_component.damage(1)
	queue_free()
