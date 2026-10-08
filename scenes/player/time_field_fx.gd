class_name TimeFieldFx
extends Node2D

## The clock face around a slowed player (Time Control): a ring of hour ticks turning slowly backwards with
## a bright sweep on it, closing in when the slow starts and opening out as it wears off. Frozen (Mk III),
## the clock stops dead and hardens. A countdown floats above the player and a ticking drone loops while it
## lasts. The face is drawn once; turning, size and fade run on the transform and modulate.

const RADIUS: float = 46.0
const TICKS: int = 12
## Radians per second the face turns (backwards: time running out for the one inside).
const TURN_SPEED: float = -0.9
const LOOP_STREAM: AudioStream = preload("res://assets/audio/sfx/time_loop.wav")
const LOOP_VOLUME_DB: float = -9.0
const COUNTER_FONT_SIZE: int = 18

var _player: Player = null
var _counter: Node2D = null
var _counter_text: String = ""
var _loop: AudioStreamPlayer2D = null


func _ready() -> void:
	_player = get_parent() as Player
	material = FxLib.additive_material()
	top_level = true
	z_index = 4
	visible = false
	_counter = Node2D.new()
	_counter.name = "Counter"
	_counter.top_level = true
	_counter.z_index = 60
	_counter.visible = false
	_counter.draw.connect(_draw_counter)
	add_child(_counter)
	_loop = AudioStreamPlayer2D.new()
	_loop.name = "Loop"
	_loop.stream = LOOP_STREAM
	_loop.bus = &"SFX"
	_loop.volume_db = -60.0
	# The WAV imports as a one-shot; replaying on finish makes it loop whatever its import settings.
	_loop.finished.connect(func() -> void:
		if _counter.visible:
			_loop.play())
	_counter.add_child(_loop)


func _process(delta: float) -> void:
	if _player == null:
		return
	var strength: float = TimeFlow.strength_of(_player.time_scale) if not _player.is_eliminated() else 0.0
	var active: bool = strength > 0.001 and _player.is_time_slowed()
	visible = strength > 0.001
	_update_counter(active)
	_update_loop(active, strength, delta)
	if not visible:
		return
	global_position = _player.global_position
	var frozen: bool = _player.is_time_frozen()
	rotation = wrapf(rotation + TURN_SPEED * _player.time_scale * delta, -PI, PI)
	scale = Vector2.ONE * lerpf(1.6, 1.0, strength) * (0.92 if frozen else 1.0)
	modulate = Color(1.35, 1.35, 1.5, strength) if frozen else Color(1.0, 1.0, 1.0, strength)


## Tenths of a second left, over the player's head; redrawn only when the number changes.
func _update_counter(active: bool) -> void:
	_counter.visible = active
	if not active:
		_counter_text = ""
		return
	_counter.global_position = _player.global_position + Vector2(0.0, -RADIUS - 26.0)
	var text: String = "%.1f" % _player.get_time_slow_left()
	if _player.is_time_frozen():
		text = "FROZEN " + text
	if text != _counter_text:
		_counter_text = text
		_counter.queue_redraw()


func _update_loop(active: bool, strength: float, delta: float) -> void:
	if active and not _loop.playing:
		_loop.volume_db = -40.0
		_loop.play()
	if not _loop.playing:
		return
	var target_db: float = LOOP_VOLUME_DB if active else -60.0
	_loop.volume_db = move_toward(_loop.volume_db, target_db, delta * (60.0 if active else 90.0))
	# The drone sinks with the clock and nearly stops ticking when frozen.
	_loop.pitch_scale = lerpf(1.0, 0.7, strength) * (0.75 if _player.is_time_frozen() else 1.0)
	if not active and _loop.volume_db <= -59.0:
		_loop.stop()


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


func _draw_counter() -> void:
	if _counter_text == "":
		return
	var font: Font = UiStyle.FONT_DISPLAY
	var width: float = font.get_string_size(_counter_text, HORIZONTAL_ALIGNMENT_CENTER, -1, COUNTER_FONT_SIZE).x
	var origin: Vector2 = Vector2(-width * 0.5, 0.0)
	_counter.draw_string_outline(font, origin, _counter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTER_FONT_SIZE, 6, Color(0.03, 0.02, 0.06, 0.85))
	_counter.draw_string(font, origin, _counter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTER_FONT_SIZE, TimeFlow.COLOR.lightened(0.45))
