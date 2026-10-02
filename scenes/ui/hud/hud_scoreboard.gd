class_name HudScoreboard
extends Control

## The score, top centre, as small as it can be while still reading at a glance: two digits around a
## round / set tag, the names outside them with a short team-coloured underline, and (in set play) pips
## for the rounds inside the current set. No plates: a soft shadow keeps it legible over the sky. A point
## pops its digit and flashes its underline; match point adds a quiet amber tag underneath.

const BOARD_SIZE: Vector2 = Vector2(320.0, 52.0)
const DIGIT_GAP: float = 30.0

var left_color: Color = Color(0.31, 0.67, 1.0)
var right_color: Color = Color(0.92, 0.31, 0.31)
var left_name: String = "YOU"
var right_name: String = "CPU"
var center_label: String = "R1"
## Set play shows the rounds inside the current set as pips under the names.
var pips_enabled: bool = false

var _left_score: int = -1
var _right_score: int = -1
var _left_pips: int = 0
var _right_pips: int = 0
var _pip_target: int = 2
var _show_pips: bool = false
var _time: float = 0.0
var _initialized: bool = false
var _drawn_signature: String = ""
var _match_point: bool = false
var _left_flash: float = 0.0
var _right_flash: float = 0.0

var _layer_node: Control = null
var _left_digit: Label = null
var _right_digit: Label = null
var _left_tween: Tween = null
var _right_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = BOARD_SIZE
	size = BOARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_node = Control.new()
	_layer_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_node.size = BOARD_SIZE
	_layer_node.draw.connect(_draw_board)
	add_child(_layer_node)
	_left_digit = _digit_label(false)
	_right_digit = _digit_label(true)


func _digit_label(right: bool) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_DISPLAY, 30, Color.WHITE, 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(44.0, 36.0)
	var center_x: float = BOARD_SIZE.x * 0.5 + (DIGIT_GAP if right else -DIGIT_GAP)
	label.position = Vector2(center_x - 22.0, 2.0)
	label.pivot_offset = label.size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## pips are the rounds inside the current set (drawn when pips_enabled).
func set_state(left_score: int, right_score: int, left_pips: int, right_pips: int, pip_target: int) -> void:
	var left_up: bool = _initialized and (left_score > _left_score or left_pips > _left_pips)
	var right_up: bool = _initialized and (right_score > _right_score or right_pips > _right_pips)
	_show_pips = pips_enabled
	var changed: bool = left_score != _left_score or right_score != _right_score
	_left_score = left_score
	_right_score = right_score
	_left_pips = left_pips
	_right_pips = right_pips
	_pip_target = maxi(pip_target, 0)
	if changed or not _initialized:
		_left_digit.text = str(left_score)
		_right_digit.text = str(right_score)
	_initialized = true
	if left_up:
		_left_tween = _pop(_left_digit, _left_tween)
		_left_flash = 1.0
	if right_up:
		_right_tween = _pop(_right_digit, _right_tween)
		_right_flash = 1.0
	_match_point = _pip_target > 1 and (left_pips == _pip_target - 1 or right_pips == _pip_target - 1)
	var signature: String = "%s|%s|%s|%s|%s|%d|%d|%d|%s|%s" % [left_color.to_html(), right_color.to_html(), left_name, right_name, center_label, _left_pips, _right_pips, _pip_target, _show_pips, _match_point]
	if signature != _drawn_signature:
		_drawn_signature = signature
		_left_digit.add_theme_color_override("font_color", left_color.lightened(0.35))
		_right_digit.add_theme_color_override("font_color", right_color.lightened(0.35))
		_layer_node.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var busy: bool = _match_point or _left_flash > 0.0 or _right_flash > 0.0
	_left_flash = maxf(_left_flash - delta * 1.6, 0.0)
	_right_flash = maxf(_right_flash - delta * 1.6, 0.0)
	if busy:
		_layer_node.queue_redraw()


func _pop(digit: Label, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	digit.scale = Vector2(1.5, 1.5)
	digit.modulate = Color(2.0, 2.0, 2.0)
	var tween: Tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	tween.tween_property(digit, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(digit, "modulate", Color.WHITE, 0.5)
	return tween


func _draw_board() -> void:
	var mid: float = BOARD_SIZE.x * 0.5
	LoadoutStyle.draw_glow(_layer_node, Vector2(mid, 20.0), Vector2(170.0, 34.0), Color(0.0, 0.012, 0.016, 0.45), 40)
	_layer_node.draw_string_outline(UiStyle.FONT_BOLD, Vector2(mid - 30.0, 25.0), center_label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, 4, Color(0, 0, 0, 0.6))
	_layer_node.draw_string(UiStyle.FONT_BOLD, Vector2(mid - 30.0, 25.0), center_label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, UiStyle.TEXT_DIM)
	for right in [false, true]:
		var sign_value: float = 1.0 if right else -1.0
		var color: Color = right_color if right else left_color
		var flash: float = _right_flash if right else _left_flash
		var digit_x: float = mid + sign_value * DIGIT_GAP
		var underline: Rect2 = Rect2(digit_x - 11.0, 38.0, 22.0, 3.0)
		_layer_node.draw_rect(underline, color.lerp(Color.WHITE, flash * 0.7))
		var name_text: String = right_name if right else left_name
		var name_width: float = UiStyle.FONT_BOLD.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var name_x: float = digit_x + sign_value * 36.0 - (0.0 if right else name_width)
		_layer_node.draw_string_outline(UiStyle.FONT_BOLD, Vector2(name_x, 25.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
		_layer_node.draw_string(UiStyle.FONT_BOLD, Vector2(name_x, 25.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.TEXT)
		if _show_pips and _pip_target > 0:
			var pips: int = _right_pips if right else _left_pips
			for index in range(_pip_target):
				var px: float = digit_x + sign_value * (40.0 + float(index) * 11.0)
				var center: Vector2 = Vector2(px, 36.0)
				var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -3.5), center + Vector2(3.5, 0), center + Vector2(0, 3.5), center + Vector2(-3.5, 0)])
				_layer_node.draw_colored_polygon(diamond, color.lightened(0.25) if index < pips else Color(1, 1, 1, 0.16))
	if _match_point:
		var alpha: float = 0.7 + 0.3 * sin(_time * 4.0)
		var tag: String = "SET POINT" if pips_enabled else "MATCH POINT"
		_layer_node.draw_string_outline(UiStyle.FONT_BOLD, Vector2(mid - 60.0, 52.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 10, 4, Color(0, 0, 0, 0.6 * alpha))
		_layer_node.draw_string(UiStyle.FONT_BOLD, Vector2(mid - 60.0, 52.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 10, LoadoutStyle.with_alpha(UiStyle.ACCENT, alpha))
