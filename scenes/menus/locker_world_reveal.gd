class_name LockerWorldReveal
extends Control

## The locker countdown's world reveal: under the big number the worlds roll through a one-line window,
## slow down and settle on the one this match is fought on, a beat before the set starts. Text on a soft
## shadow pool, no plate; the landed name turns amber with a hairline beneath it.

const ROLL_SECONDS: float = 1.8
## Full passes through the catalogue before it settles, so even two worlds read as a roll.
const PASSES: int = 3
const CAPTION_BASELINE: float = 30.0
const CAPTION_SIZE: int = 13
## The window the names slide through; one row tall so only the caption sits above it.
const WINDOW_TOP: float = 40.0
const WINDOW_HEIGHT: float = 60.0
const NAME_BASELINE: float = 44.0
const NAME_SIZE: int = 40

var _names: Array[String] = []
var _target: int = 0
var _elapsed: float = -1.0
var _last_row: int = 0
var _landed: bool = false
var _punch: float = 0.0
var _rule: float = 0.0
var _window: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for world_id in WorldCatalog.ids():
		_names.append(WorldCatalog.display_name(world_id).to_upper())
	_window = Control.new()
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.clip_contents = true
	_window.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_window.offset_top = WINDOW_TOP
	_window.offset_bottom = WINDOW_TOP + WINDOW_HEIGHT
	_window.draw.connect(_draw_names)
	add_child(_window)


func play(world_id: StringName) -> void:
	_target = maxi(WorldCatalog.ids().find(world_id), 0)
	_elapsed = 0.0
	_last_row = 0
	_landed = false
	_punch = 0.0
	_rule = 0.0
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)


func stop() -> void:
	_elapsed = -1.0
	visible = false


func is_playing() -> bool:
	return _elapsed >= 0.0


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	var row: int = int(floor(_row_position()))
	if row != _last_row and not _landed:
		_last_row = row
		# Ticks climb in pitch as the reel slows, like a wheel finding its notch.
		AudioDirector.play(&"ui_hover", -4.0, lerpf(0.9, 1.25, clampf(_elapsed / ROLL_SECONDS, 0.0, 1.0)))
	if not _landed and _elapsed >= ROLL_SECONDS:
		_landed = true
		_punch = 1.0
		AudioDirector.play(&"ui_confirm")
	_punch = move_toward(_punch, 0.0, delta * 3.5)
	if _landed:
		_rule = move_toward(_rule, 1.0, delta * 5.0)
	queue_redraw()
	_window.queue_redraw()


## Rows travelled so far; ease-out so the roll starts fast and creeps into place.
func _row_position() -> float:
	var total: float = float(PASSES * _names.size() + _target)
	var t: float = clampf(_elapsed / ROLL_SECONDS, 0.0, 1.0)
	return total * (1.0 - pow(1.0 - t, 3.0))


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var center_x: float = size.x * 0.5
	LoadoutStyle.draw_glow(self, Vector2(center_x, WINDOW_TOP + 20.0), Vector2(160.0, 80.0), Color(0.0, 0.0, 0.0, 0.7))
	_draw_centered(self, UiStyle.FONT_BOLD, "WORLD", CAPTION_BASELINE, CAPTION_SIZE, UiStyle.TEXT_MUTED, 4)
	if _rule > 0.0:
		var half: float = 70.0 * _rule
		draw_rect(Rect2(center_x - half, WINDOW_TOP + WINDOW_HEIGHT - 2.0, half * 2.0, 2.0), Color(UiStyle.ACCENT, 0.85 * _rule))


## The incoming name rises into the window from below while the last one leaves through the top.
func _draw_names() -> void:
	if _elapsed < 0.0 or _names.is_empty():
		return
	var position_rows: float = _row_position()
	var base_row: int = int(floor(position_rows))
	var fraction: float = position_rows - float(base_row)
	var color: Color = UiStyle.ACCENT if _landed else UiStyle.TEXT
	var pivot: Vector2 = Vector2(_window.size.x * 0.5, NAME_BASELINE - 14.0)
	var scale_factor: float = 1.0 + 0.14 * _punch
	_window.draw_set_transform(pivot * (1.0 - scale_factor), 0.0, Vector2.ONE * scale_factor)
	for offset in [0, 1]:
		var row_offset: float = (float(offset) - fraction) * WINDOW_HEIGHT
		var alpha: float = clampf(1.0 - absf(row_offset) / WINDOW_HEIGHT, 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var text: String = _names[(base_row + offset) % _names.size()]
		_draw_centered(_window, UiStyle.FONT_DISPLAY, text, NAME_BASELINE + row_offset, NAME_SIZE, Color(color, alpha), 8)
	_window.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_centered(canvas: Control, font: Font, text: String, baseline: float, font_size: int, color: Color, outline: int) -> void:
	var origin: Vector2 = Vector2(0.0, baseline)
	var outline_color: Color = Color(UiStyle.INK, 0.85 * color.a)
	canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, canvas.size.x, font_size, outline, outline_color)
	canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, canvas.size.x, font_size, color)
