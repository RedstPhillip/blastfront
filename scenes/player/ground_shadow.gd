class_name GroundShadow
extends Sprite2D

## Soft contact shadow projected onto the floor below the owner; fades and shrinks with height.

const TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const MAX_HEIGHT: float = 260.0
const WORLD_MASK: int = 1

@export var base_width: float = 34.0
@export var base_alpha: float = 0.42

var _owner_body: Node2D = null


func _ready() -> void:
	_owner_body = get_parent() as Node2D
	texture = TEXTURE
	top_level = true
	z_index = -2
	modulate = Color(0.0, 0.02, 0.01, 0.0)


func _physics_process(_delta: float) -> void:
	if _owner_body == null or not _owner_body.visible:
		visible = false
		return
	var origin: Vector2 = _owner_body.global_position
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, origin + Vector2(0.0, MAX_HEIGHT), WORLD_MASK)
	if _owner_body is CollisionObject2D:
		query.exclude = [(_owner_body as CollisionObject2D).get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		visible = false
		return
	visible = true
	var floor_point: Vector2 = hit["position"]
	var height_ratio: float = clampf((floor_point.y - origin.y) / MAX_HEIGHT, 0.0, 1.0)
	global_position = floor_point + Vector2(0.0, 1.0)
	var width: float = base_width * lerpf(1.0, 0.45, height_ratio)
	var texture_size: float = float(TEXTURE.get_width())
	scale = Vector2(width / texture_size, width * 0.26 / texture_size)
	modulate.a = base_alpha * (1.0 - height_ratio) * (1.0 - height_ratio)
