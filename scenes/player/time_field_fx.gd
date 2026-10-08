class_name TimeFieldFx
extends Node2D

## The clock face around a slowed player (Time Control): a ring of hour ticks turning slowly backwards with
## a bright sweep on it, closing in when the slow starts and opening out as it wears off. Drawn once; the
## turn, the size and the fade all run on the transform and modulate.

const RADIUS: float = 46.0
const TICKS: int = 12
## Radians per second the face turns (backwards: time running out for the one inside).
const TURN_SPEED: float = -0.9

var _player: Player = null


func _ready() -> void:
	_player = get_parent() as Player
	material = FxLib.additive_material()
	top_level = true
	z_index = 4
	visible = false


func _process(delta: float) -> void:
	if _player == null:
		return
	var strength: float = TimeFlow.strength_of(_player.time_scale) if not _player.is_eliminated() else 0.0
	visible = strength > 0.001
	if not visible:
		return
	global_position = _player.global_position
	rotation = wrapf(rotation + TURN_SPEED * delta, -PI, PI)
	scale = Vector2.ONE * lerpf(1.6, 1.0, strength)
	modulate.a = strength


func _draw() -> void:
	var color: Color = TimeFlow.COLOR
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color(color, 0.35), 1.5, true)
	draw_arc(Vector2.ZERO, RADIUS + 9.0, 0.0, TAU, 64, Color(color, 0.12), 5.0, true)
	for index in range(TICKS):
		var angle: float = TAU * float(index) / float(TICKS)
		var outward: Vector2 = Vector2(cos(angle), sin(angle))
		var major: bool = index % 3 == 0
		var inner: float = RADIUS - (8.0 if major else 4.5)
		draw_line(outward * inner, outward * (RADIUS - 1.0), Color(color.lightened(0.35), 0.9 if major else 0.6), 2.4 if major else 1.4, true)
	# The sweep: a bright arc trailing off behind its head, like a second hand's afterimage.
	var steps: int = 10
	for step in range(steps):
		var t: float = float(step) / float(steps)
		var from_angle: float = -PI * 0.5 + t * 1.1
		var to_angle: float = from_angle + 1.1 / float(steps)
		draw_arc(Vector2.ZERO, RADIUS, from_angle, to_angle, 4, Color(1.0, 0.97, 1.0, 0.9 * (1.0 - t)), 3.0, true)
