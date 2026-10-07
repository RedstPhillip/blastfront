class_name HudControlsHint
extends Control

## A row of key chips ("A D  MOVE", "LMB  SHOOT", ...) that eases in under the round banner for a
## player's first few matches, then gets out of the way. Labels follow the active input device.

const SHOW_COUNT: int = 3
const HOLD_SECONDS: float = 6.5
const CHIP_HEIGHT: float = 34.0
const CHIP_GAP: float = 22.0

var _row: HBoxContainer = null
var _tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	InputDevice.device_changed.connect(_on_device_changed)


static func should_show() -> bool:
	return UserSettings.get_int(UserSettings.CONTROLS_HINTS_SEEN) < SHOW_COUNT


func play(delay: float = 0.6) -> void:
	UserSettings.set_value(UserSettings.CONTROLS_HINTS_SEEN, UserSettings.get_int(UserSettings.CONTROLS_HINTS_SEEN) + 1)
	_rebuild()
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_row.position.y = _row_y() + 18.0
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_interval(delay)
	_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	_tween.parallel().tween_property(_row, "position:y", _row_y(), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_tween.tween_callback(hide)


func _row_y() -> float:
	return size.y - 54.0


func _on_device_changed(_using_gamepad: bool) -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	if _row != null:
		_row.queue_free()
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(CHIP_GAP))
	add_child(_row)
	var gamepad: bool = InputDevice.using_gamepad
	var entries: Array = [
		["L STICK" if gamepad else "A  D", "MOVE"],
		["A" if gamepad else "SPACE", "JUMP"],
		[InputDevice.prompt(&"p1_shoot"), "SHOOT"],
		[InputDevice.prompt(&"p1_block"), "BLOCK"],
		[InputDevice.prompt(&"p1_reload"), "RELOAD"],
	]
	if gamepad:
		entries.insert(1, ["R STICK", "AIM"])
	for entry in entries:
		_row.add_child(_chip(str(entry[0]), str(entry[1])))
	_row.reset_size()
	_row.position = Vector2((size.x - _row.size.x) * 0.5, _row_y())


func _chip(key_text: String, action_text: String) -> Control:
	var chip: Control = Control.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_width: float = maxf(UiStyle.FONT_BOLD.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0, 20.0)
	var action_width: float = UiStyle.FONT_BOLD.get_string_size(action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	chip.custom_minimum_size = Vector2(key_width + 8.0 + action_width, 22.0)
	chip.draw.connect(func() -> void:
		LoadoutStyle.draw_glow(chip, Vector2(chip.size.x * 0.5, 11.0), Vector2(chip.size.x * 0.7, 18.0), Color(0.0, 0.012, 0.016, 0.5), 24)
		LoadoutStyle.draw_key_chip(chip, Vector2(0.0, 1.0), key_text, 20.0, UiStyle.TEXT)
		chip.draw_string_outline(UiStyle.FONT_BOLD, Vector2(key_width + 8.0, 16.0), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
		chip.draw_string(UiStyle.FONT_BOLD, Vector2(key_width + 8.0, 16.0), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.TEXT))
	return chip
