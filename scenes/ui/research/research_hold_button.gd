class_name ResearchHoldButton
extends Control

## The research action: a primary button you hold instead of click. While held a lighter fill sweeps across
## it and the label stays readable on top; letting go early drains it. When it cannot be used it turns
## into a plain dark plate that says why in a word or two ("NEED 4 RP", "LOCKED").

signal completed

const HOLD_SECONDS: float = 0.42

var enabled: bool = false
var label_text: String = ""
var cost: int = -1

var _hover: bool = false
var _holding: bool = false
var _hold: float = 0.0
var _flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, 48.0)


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; _holding = false; set_process(true))
	set_process(false)


func configure(is_enabled: bool, text: String, price: int = -1) -> void:
	enabled = is_enabled
	label_text = text
	cost = price
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	if not enabled:
		_holding = false
	queue_redraw()


func flash() -> void:
	_flash = 1.0
	set_process(true)


## Pads hold the same button from anywhere on the screen.
func set_holding(value: bool) -> void:
	_holding = value and enabled
	set_process(true)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if button.pressed and enabled:
		_holding = true
		AudioDirector.play(&"ui_click", -6.0, 0.9)
	elif not button.pressed:
		_holding = false
	set_process(true)


func _process(delta: float) -> void:
	if _holding:
		_hold = minf(_hold + delta / HOLD_SECONDS, 1.0)
		if _hold >= 1.0:
			_holding = false
			_hold = 0.0
			completed.emit()
	else:
		_hold = move_toward(_hold, 0.0, delta * 4.0)
	_flash = move_toward(_flash, 0.0, delta * 2.5)
	queue_redraw()
	if not _holding and _hold <= 0.0 and _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if not enabled:
		draw_style_box(UiStyle.panel(UiStyle.FILL_IDLE), rect)
		draw_string(UiStyle.FONT_BOLD, Vector2(0.0, size.y * 0.5 + 5.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, LoadoutStyle.TEXT_MUTED)
		return
	draw_style_box(UiStyle.panel(UiStyle.ACCENT_HOT if _hover else UiStyle.ACCENT), rect)
	if _hold > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _hold, size.y)), Color(1.0, 0.95, 0.82, 0.8))
	if _flash > 0.0:
		draw_rect(rect, Color(1.0, 1.0, 1.0, _flash * 0.5))
	var ink: Color = UiStyle.INK
	var text_width: float = UiStyle.FONT_BOLD.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var cost_text: String = str(cost) if cost >= 0 else ""
	var cost_width: float = UiStyle.FONT_BOLD.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22.0 if cost >= 0 else 0.0
	var x: float = (size.x - text_width - cost_width) * 0.5
	draw_string(UiStyle.FONT_BOLD, Vector2(x, size.y * 0.5 + 6.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
	if cost >= 0:
		var cx: float = x + text_width + 16.0
		ResearchNodeButton.draw_rp_glyph(self, Vector2(cx, size.y * 0.5), 5.0, ink)
		draw_string(UiStyle.FONT_BOLD, Vector2(cx + 9.0, size.y * 0.5 + 6.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
