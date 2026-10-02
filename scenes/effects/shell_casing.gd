class_name ShellCasing
extends Sprite2D

## Ejected brass casing with lightweight ballistic motion, bounces off level geometry with a tink.

const TEXTURE: Texture2D = preload("res://assets/fx/casing.png")
const GRAVITY: float = 1500.0
const LIFETIME: float = 2.6
const BOUNCE_DAMPING: float = 0.42
const WORLD_MASK: int = 1

var size_factor: float = 1.0
var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _age: float = 0.0
var _bounces: int = 0
var _resting: bool = false


func launch(eject_direction: Vector2) -> void:
	var direction: Vector2 = eject_direction.normalized() if eject_direction.length_squared() > 0.0001 else Vector2.UP
	_velocity = direction * randf_range(170.0, 260.0) + Vector2(0.0, -randf_range(140.0, 220.0))
	_spin = randf_range(14.0, 26.0) * (1.0 if randf() > 0.5 else -1.0)
	rotation = randf_range(0.0, TAU)


func _ready() -> void:
	texture = TEXTURE
	scale = Vector2.ONE * 0.62 * size_factor
	z_index = 4


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		modulate.a = maxf(0.0, modulate.a - delta * 3.0)
		if modulate.a <= 0.0:
			queue_free()
		return
	if _resting:
		return
	_velocity.y += GRAVITY * delta
	var motion: Vector2 = _velocity * delta
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, global_position + motion, WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		global_position += motion
		rotation += _spin * delta
		return
	var normal: Vector2 = hit["normal"]
	global_position = (hit["position"] as Vector2) + normal * 1.5
	_velocity = _velocity.bounce(normal) * BOUNCE_DAMPING
	_velocity.x *= 0.8
	_spin *= -0.6
	_bounces += 1
	if _bounces <= 2:
		AudioDirector.play_at(&"casing", global_position, -3.0 * float(_bounces - 1))
	if _velocity.length() < 50.0 or _bounces > 4:
		_resting = true
		rotation = snappedf(rotation, PI)
