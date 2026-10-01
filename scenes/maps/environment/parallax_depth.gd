class_name ParallaxDepth
extends Node2D

## Lightweight parallax layer. Content is authored around the origin and appears centred on
## `anchor` when the camera looks at it; `factor` < 1 makes the layer feel further away.

@export var factor: Vector2 = Vector2(0.3, 0.2)
@export var anchor: Vector2 = Vector2(1140.0, 360.0)
@export var drift_speed: Vector2 = Vector2.ZERO

var _drift: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_priority = 50
	_update_position()


func _process(delta: float) -> void:
	_drift += drift_speed * delta
	_update_position()


func _update_position() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	var focus: Vector2 = anchor
	if camera != null:
		focus = camera.global_position
	position = anchor + (focus - anchor) * (Vector2.ONE - factor) + _drift
