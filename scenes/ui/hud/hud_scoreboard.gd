class_name HudScoreboard
extends Control

## Top-centre score plate: two angled team plates with big score digits and win pips around a centre
## emblem, plus a pulsing MATCH POINT tag. Plates redraw only when their content changes; score pops
## animate the digit labels' scale and a glow overlay's alpha.

const BOARD_SIZE: Vector2 = Vector2(420.0, 78.0)
const EMBLEM_RADIUS: float = 27.0
const DIGIT_WIDTH: float = 80.0

var left_color: Color = Color(0.31, 0.67, 1.0)
var right_color: Color = Color(0.92, 0.31, 0.31)
var left_name: String = "YOU"
var right_name: String = "CPU"
var center_label: String = "R1"

var _left_score: int = -1
var _right_score: int = -1
var _left_pips: int = 0
var _right_pips: int = 0
var _pip_target: int = 2
var _time: float = 0.0
var _initialized: bool = false
var _drawn_signature: String = ""
var _match_point: bool = false

var _plates: Control = null
var _left_glow: Control = null
var _right_glow: Control = null
var _left_digit: Label = null
var _right_digit: Label = null
var _left_name_label: Label = null
var _right_name_label: Label = null
var _center: Label = null
var _match_point_tag: Label = null
var _left_tween: Tween = null
var _right_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = BOARD_SIZE
	size = BOARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plates = _layer(_draw_plates)
	_left_glow = _layer(_draw_glow.bind(false))
	_right_glow = _layer(_draw_glow.bind(true))
	_left_glow.modulate.a = 0.0
	_right_glow.modulate.a = 0.0
	_left_digit = _digit_label(false)
	_right_digit = _digit_label(true)
	_left_name_label = _name_label(false)
	_right_name_label = _name_label(true)
	_center = Label.new()
	UiStyle.style_label(_center, UiStyle.FONT_DISPLAY, 18, UiStyle.ACCENT_HOT)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.size = Vector2(60.0, 30.0)
	_center.position = Vector2(BOARD_SIZE.x * 0.5 - 30.0, 19.0)
	add_child(_center)
	_match_point_tag = Label.new()
	UiStyle.style_label(_match_point_tag, UiStyle.FONT_DISPLAY, 13, UiStyle.ACCENT, 5)
	_match_point_tag.text = "MATCH POINT"
	_match_point_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_point_tag.size = Vector2(160.0, 20.0)
	_match_point_tag.position = Vector2(BOARD_SIZE.x * 0.5 - 80.0, 62.0)
	_match_point_tag.pivot_offset = Vector2(80.0, 10.0)
	_match_point_tag.visible = false
	add_child(_match_point_tag)


func _layer(painter: Callable) -> Control:
	var layer: Control = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = BOARD_SIZE
	layer.draw.connect(painter.bind(layer))
	add_child(layer)
	return layer


func _digit_label(right: bool) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_DISPLAY, 40, Color.WHITE, 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(DIGIT_WIDTH, 50.0)
	var center_x: float = BOARD_SIZE.x * 0.5 + (62.0 if right else -62.0)
	label.position = Vector2(center_x - DIGIT_WIDTH * 0.5, 9.0)
	label.pivot_offset = label.size * 0.5
	add_child(label)
	return label


func _name_label(right: bool) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_BOLD, 13, UiStyle.TEXT_DIM)
	label.size = Vector2(85.0, 18.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if right else HORIZONTAL_ALIGNMENT_RIGHT
	var name_x: float = BOARD_SIZE.x * 0.5 + (105.0 if right else -105.0 - 85.0)
	label.position = Vector2(name_x, 17.0)
	add_child(label)
	return label


func set_state(left_score: int, right_score: int, left_pips: int, right_pips: int, pip_target: int) -> void:
	var left_up: bool = _initialized and (left_score > _left_score or left_pips > _left_pips)
	var right_up: bool = _initialized and (right_score > _right_score or right_pips > _right_pips)
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
		_left_tween = _pop(_left_digit, _left_glow, left_color, _left_tween)
	if right_up:
		_right_tween = _pop(_right_digit, _right_glow, right_color, _right_tween)
	_match_point = _pip_target > 1 and (left_pips == _pip_target - 1 or right_pips == _pip_target - 1)
	_refresh_static()


func _process(delta: float) -> void:
	_time += delta
	if _match_point_tag.visible != _match_point:
		_match_point_tag.visible = _match_point
		if _match_point:
			_match_point_tag.scale = Vector2(1.6, 1.6)
			create_tween().tween_property(_match_point_tag, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _match_point:
		_match_point_tag.modulate.a = 0.65 + 0.35 * sin(_time * 5.0)


func _refresh_static() -> void:
	var signature: String = "%s|%s|%s|%s|%s|%d|%d|%d" % [left_color.to_html(), right_color.to_html(), left_name, right_name, center_label, _left_pips, _right_pips, _pip_target]
	if signature == _drawn_signature:
		return
	_drawn_signature = signature
	_left_name_label.text = left_name
	_right_name_label.text = right_name
	_center.text = center_label
	_left_digit.add_theme_color_override("font_color", left_color.lightened(0.25))
	_right_digit.add_theme_color_override("font_color", right_color.lightened(0.25))
	_plates.queue_redraw()
	_left_glow.queue_redraw()
	_right_glow.queue_redraw()


func _pop(digit: Label, glow: Control, color: Color, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	digit.scale = Vector2(1.45, 1.45)
	digit.modulate = Color(2.0, 2.0, 2.0)
	glow.modulate.a = 1.0
	var tween: Tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	tween.tween_property(digit, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(digit, "modulate", Color.WHITE, 0.5)
	tween.tween_property(glow, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


func _plate_shape(right: bool) -> PackedVector2Array:
	var mid: float = BOARD_SIZE.x * 0.5
	var sign_value: float = 1.0 if right else -1.0
	var inner: float = mid + sign_value * (EMBLEM_RADIUS - 2.0)
	var outer: float = mid + sign_value * (mid - 6.0)
	return PackedVector2Array([Vector2(inner, 10.0), Vector2(outer, 10.0), Vector2(outer - sign_value * 22.0, 58.0), Vector2(inner, 58.0)])


func _draw_plates(layer: Control) -> void:
	var mid: float = BOARD_SIZE.x * 0.5
	for right in [false, true]:
		var color: Color = right_color if right else left_color
		var plate: PackedVector2Array = _plate_shape(right)
		layer.draw_colored_polygon(plate, UiStyle.PANEL)
		layer.draw_colored_polygon(plate, Color(color.r, color.g, color.b, 0.12))
		layer.draw_polyline(PackedVector2Array([plate[0], plate[1]]), color, 3.0, true)
		var outline: PackedVector2Array = plate.duplicate()
		outline.append(plate[0])
		layer.draw_polyline(outline, UiStyle.LINE, 1.0, true)
		_draw_pips(layer, right, color)
	var emblem: PackedVector2Array = PackedVector2Array()
	for index in range(6):
		var angle: float = TAU * float(index) / 6.0 + PI / 6.0
		emblem.append(Vector2(mid, 34.0) + Vector2(cos(angle), sin(angle)) * EMBLEM_RADIUS)
	layer.draw_colored_polygon(emblem, UiStyle.PANEL_SOLID)
	var emblem_outline: PackedVector2Array = emblem.duplicate()
	emblem_outline.append(emblem[0])
	layer.draw_polyline(emblem_outline, UiStyle.ACCENT, 2.0, true)


func _draw_pips(layer: Control, right: bool, color: Color) -> void:
	if _pip_target <= 0:
		return
	var mid: float = BOARD_SIZE.x * 0.5
	var sign_value: float = 1.0 if right else -1.0
	var pips: int = _right_pips if right else _left_pips
	for index in range(_pip_target):
		var center: Vector2 = Vector2(mid + sign_value * (110.0 + float(index) * 15.0), 45.0)
		var filled: bool = index < pips
		var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -5.5), center + Vector2(5.5, 0), center + Vector2(0, 5.5), center + Vector2(-5.5, 0)])
		layer.draw_colored_polygon(diamond, color.lightened(0.2) if filled else Color(0.12, 0.17, 0.17, 1.0))
		var diamond_outline: PackedVector2Array = diamond.duplicate()
		diamond_outline.append(diamond[0])
		layer.draw_polyline(diamond_outline, Color(color.r, color.g, color.b, 0.7 if filled else 0.25), 1.2, true)


func _draw_glow(layer: Control, right: bool) -> void:
	var color: Color = right_color if right else left_color
	layer.draw_colored_polygon(_plate_shape(right), Color(color.r, color.g, color.b, 0.45))
