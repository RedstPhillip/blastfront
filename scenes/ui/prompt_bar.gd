class_name UiPromptBar
extends Control

## The line along the bottom of the loadout and research screens: key chips with what they do right now
## on the left, and a short-lived status message on the right ("BOUGHT EXTENDED BARREL · −12").
## Prompts are [[key, action], ...]; the screen swaps them as the pointer moves.

const STATUS_SECONDS: float = 2.6

## Narrow columns (the loadout's centre) pack the prompts tighter.
var compact: bool = false

var _prompts: Array = []
var _status_text: String = ""
var _status_color: Color = LoadoutStyle.TEXT
var _status_time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 22.0)
	set_process(false)


func set_prompts(prompts: Array) -> void:
	if prompts == _prompts:
		return
	_prompts = prompts
	queue_redraw()


func notify(text: String, color: Color) -> void:
	_status_text = text
	_status_color = color
	_status_time = STATUS_SECONDS
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_status_time = maxf(_status_time - delta, 0.0)
	queue_redraw()
	if _status_time <= 0.0:
		set_process(false)


func _draw() -> void:
	var x: float = 0.0
	for prompt in _prompts:
		x += LoadoutStyle.draw_key_chip(self, Vector2(x, 2.0), str(prompt[0]), 18.0) + 7.0
		draw_string(UiStyle.FONT_UI, Vector2(x, 16.0), str(prompt[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LoadoutStyle.TEXT_SECONDARY)
		x += UiStyle.FONT_UI.get_string_size(str(prompt[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + (12.0 if compact else 22.0)
	if _status_time <= 0.0 or _status_text == "":
		return
	var alpha: float = clampf(_status_time / 0.4, 0.0, 1.0) * clampf((STATUS_SECONDS - _status_time) / 0.12, 0.0, 1.0)
	var width: float = UiStyle.FONT_BOLD.get_string_size(_status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_circle(Vector2(size.x - width - 12.0, 11.0), 3.0, LoadoutStyle.with_alpha(_status_color, alpha), true, -1.0, true)
	draw_string(UiStyle.FONT_BOLD, Vector2(size.x - width, 16.0), _status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LoadoutStyle.with_alpha(_status_color, alpha))
