extends Node2D

@export var orbit_radius := 30.0
@export var aim_angle_offset_degrees := 180.0

var _pointing_right := false

@onready var _player: Node2D = get_parent() as Node2D
@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
	if _player == null:
		return

	var aim_vector := get_global_mouse_position() - _player.global_position
	if aim_vector.length_squared() <= 0.0001:
		return

	var aim_direction := aim_vector.normalized()
	if aim_direction.x > 0.0:
		_pointing_right = true
	elif aim_direction.x < 0.0:
		_pointing_right = false

	global_position = _player.global_position + aim_direction * orbit_radius
	global_rotation = aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees)
	_sprite.flip_v = _pointing_right
