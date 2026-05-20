extends Node2D

@onready var _flash: Polygon2D = $Flash
@onready var _core: Polygon2D = $Core
@onready var _smoke: CPUParticles2D = $Smoke
@onready var _sparks: CPUParticles2D = $Sparks

var _direction: Vector2 = Vector2.LEFT
var _tint: Color = Color(1.0, 0.82, 0.38, 1.0)


func configure(direction: Vector2, tint: Color = Color(1.0, 0.82, 0.38, 1.0)) -> void:
	_direction = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.LEFT
	_tint = tint
	if is_node_ready():
		_apply_settings()


func _ready() -> void:
	_apply_settings()
	await get_tree().create_timer(0.18).timeout
	queue_free()


func _apply_settings() -> void:
	global_rotation = _direction.angle()
	_flash.modulate = _tint
	_core.modulate = Color(1.0, 0.96, 0.78, 1.0)

	_smoke.direction = Vector2.LEFT
	_sparks.direction = Vector2.RIGHT
	_smoke.restart()
	_sparks.restart()
	_smoke.emitting = true
	_sparks.emitting = true

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_flash, "modulate:a", 0.0, 0.070).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_flash, "scale", Vector2(1.32, 1.18), 0.070).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_core, "modulate:a", 0.0, 0.052).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_core, "scale", Vector2(1.18, 1.12), 0.052).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
