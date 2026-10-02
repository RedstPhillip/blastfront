class_name LoadoutNameplate
extends Control

## The readout under a stage: what you are looking at, in four short lines. A display-font title, a meta
## line of small caps segments (slot, mark, grade in its colour, price...), one sentence of description and
## the effects the stat strip does not cover ("Spread −2°  ·  Freeze resist +30%") in green or red.
## Normally it names the weapon or the operator; hovering a part or a socket swaps the content in place
## with a quick rise-and-fade, so the eye never has to travel to a separate details panel.

const HEIGHT: float = 96.0
const TITLE_SIZE: int = 22
const META_SIZE: int = 11
const BODY_SIZE: int = 13
const EFFECT_SIZE: int = 12

var _title: String = ""
var _title_color: Color = LoadoutStyle.TEXT
var _segments: Array = []
var _effects: Array = []
var _description: String = ""
var _signature: String = ""
var _enter: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, HEIGHT)
	set_process(false)


## segments: [[text, color(, "coin")], ...] joined with dots on the meta line.
## effects: [[text, color], ...] on the last line.
func show_content(title: String, segments: Array, description: String = "", effects: Array = [], title_color: Color = LoadoutStyle.TEXT) -> void:
	var signature: String = "%s|%s|%s|%s|%s" % [title, str(segments), description, str(effects), title_color.to_html()]
	if signature == _signature:
		return
	var animate: bool = _signature != ""
	_signature = signature
	_title = title
	_title_color = title_color
	_segments = segments
	_description = description
	_effects = effects
	if animate:
		_enter = 0.0
		set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_enter = move_toward(_enter, 1.0, delta / 0.16)
	queue_redraw()
	if _enter >= 1.0:
		set_process(false)


func _draw() -> void:
	var eased: float = 1.0 - pow(1.0 - _enter, 3.0)
	var lift: float = (1.0 - eased) * 4.0
	var title_size: int = TITLE_SIZE
	while title_size > 15 and UiStyle.FONT_DISPLAY.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > size.x:
		title_size -= 1
	draw_string(UiStyle.FONT_DISPLAY, Vector2(0.0, 22.0 + lift), _title, HORIZONTAL_ALIGNMENT_LEFT, size.x, title_size, LoadoutStyle.with_alpha(_title_color, _title_color.a * eased))
	_draw_segments(_segments, 41.0 + lift, UiStyle.FONT_BOLD, META_SIZE, eased, true)
	if _description != "":
		var body: String = _fit(_description, UiStyle.FONT_BODY, BODY_SIZE)
		draw_string(UiStyle.FONT_BODY, Vector2(0.0, 62.0 + lift), body, HORIZONTAL_ALIGNMENT_LEFT, size.x, BODY_SIZE, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_SECONDARY, LoadoutStyle.TEXT_SECONDARY.a * eased))
	_draw_segments(_effects, (82.0 if _description != "" else 62.0) + lift, UiStyle.FONT_BOLD, EFFECT_SIZE, eased, false)


func _draw_segments(segments: Array, y: float, font: Font, font_size: int, eased: float, caps_dots: bool) -> void:
	var x: float = 0.0
	for segment in segments:
		var text: String = str(segment[0])
		if text == "":
			continue
		var color: Color = segment[1]
		var is_coin: bool = segment.size() > 2 and str(segment[2]) == "coin"
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + (11.0 if is_coin else 0.0)
		if x > 0.0:
			if x + 13.0 + width > size.x:
				return
			draw_circle(Vector2(x + 6.0, y - (4.0 if caps_dots else 4.5)), 1.3, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, LoadoutStyle.TEXT_MUTED.a * eased), true, -1.0, true)
			x += 13.0
		if is_coin:
			LoadoutStyle.draw_coin(self, Vector2(x + 4.0, y - 4.0), 3.6, LoadoutStyle.with_alpha(color, eased))
			x += 11.0
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LoadoutStyle.with_alpha(color, color.a * eased))
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Shortens a sentence to the plate's width with an ellipsis.
func _fit(text: String, font: Font, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= size.x:
		return text
	var words: PackedStringArray = text.split(" ")
	var result: String = ""
	for word in words:
		var candidate: String = word if result == "" else result + " " + word
		if font.get_string_size(candidate + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
			break
		result = candidate
	return result.trim_suffix(",").trim_suffix(".") + "…"
