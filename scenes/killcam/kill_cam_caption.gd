class_name KillCamCaption
extends Control

## The kill cam on screen: soft ink washes along the top and bottom edges (the point banner tucks into the
## top one) and, in the bottom one, the replay's single line: a REPLAY eyebrow with the pace, the kill's name
## ("Ricochet · Bouncy Bullets MK III") after a tick in the killer's colour, a hairline that fills as the clip
## plays, and the key that skips it. No panels: washes, type and hairlines only (see LoadoutStyle).

const TOP_WASH: float = 150.0
const BOTTOM_WASH: float = 190.0
## The line sits in the middle of the bottom edge, clear of the HUD's player cards in both corners.
const LINE_WIDTH: float = 560.0
const CARD_CLEARANCE: float = 340.0
const KILL_FONT_SIZE: int = 30

var _label_head: String = ""
var _label_tail: String = ""
var _accent: Color = Color.WHITE
var _skip_key: String = ""
var _progress: float = 0.0
var _pace: float = 1.0
var _shown: float = 0.0
var _punch: float = 0.0
var _skippable: bool = true
var _tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


## A replay starts: label is "Head · rest" (the head reads brighter), accent the killer's colour.
func play(label: String, accent: Color, skip_key: String) -> void:
	var split: int = label.find(" · ")
	_label_head = label if split < 0 else label.substr(0, split)
	_label_tail = "" if split < 0 else label.substr(split)
	_accent = accent
	_skip_key = skip_key
	_progress = 0.0
	_pace = 1.0
	_punch = 0.0
	_skippable = true
	visible = true
	set_process(true)
	_fade_to(1.0, 0.16)


## Past the banner (a match-winning replay behind the results) it can no longer be skipped: the key goes.
func set_skippable(skippable: bool) -> void:
	_skippable = skippable


func set_progress(ratio: float, pace: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	_pace = pace


## The knockout lands in the replay: the line kicks once.
func punch() -> void:
	_punch = 1.0


func dismiss() -> void:
	if not visible:
		return
	_fade_to(0.0, 0.2)


func _fade_to(target: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_property(self, "_shown", target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if target <= 0.0:
		_tween.tween_callback(func() -> void:
			visible = false
			set_process(false))


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
	_punch = maxf(_punch - real_delta * 3.5, 0.0)
	modulate.a = clampf(_shown * 1.4 - 0.2, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.001:
		return
	var w: float = size.x
	var h: float = size.y
	var ink: Color = Color(0.0, 0.006, 0.008, 1.0)
	# The washes slide in from the edges as the replay cuts in.
	var top: float = TOP_WASH * _shown
	var bottom: float = BOTTOM_WASH * _shown
	LoadoutStyle.draw_gradient_rect(self, Rect2(0.0, 0.0, w, top), Color(ink, 0.7), Color(ink, 0.0))
	LoadoutStyle.draw_gradient_rect(self, Rect2(0.0, h - bottom, w, bottom), Color(ink, 0.0), Color(ink, 0.82))
	var line_width: float = clampf(w - CARD_CLEARANCE * 2.0, 320.0, LINE_WIDTH)
	var x: float = (w - line_width) * 0.5
	var eyebrow_y: float = h - 94.0
	var pace_text: String = "%.1f×" % _pace if _pace < 0.95 else ""
	LoadoutStyle.draw_eyebrow(self, x, eyebrow_y, line_width, "REPLAY", pace_text, LoadoutStyle.TEXT_MUTED)
	# The kill's name: a tick in the killer's colour, the head in full white, the rest a step quieter.
	var font: Font = UiStyle.FONT_DISPLAY
	var baseline: float = h - 54.0 - 4.0 * _punch
	var size_now: int = KILL_FONT_SIZE
	draw_rect(Rect2(x, baseline - 23.0, 3.0, 24.0), _accent)
	var text_x: float = x + 14.0
	var head_width: float = font.get_string_size(_label_head, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x
	draw_string_outline(font, Vector2(text_x, baseline), _label_head, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, 6, Color(0.0, 0.0, 0.0, 0.55))
	draw_string(font, Vector2(text_x, baseline), _label_head, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, LoadoutStyle.TEXT)
	if _label_tail != "":
		var tail: String = LoadoutStyle.fit_text(_label_tail, font, size_now, maxf(line_width - head_width - 14.0, 40.0))
		draw_string_outline(font, Vector2(text_x + head_width, baseline), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, 6, Color(0.0, 0.0, 0.0, 0.55))
		draw_string(font, Vector2(text_x + head_width, baseline), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, LoadoutStyle.TEXT_SECONDARY)
	# How far the clip has played.
	var bar_y: float = h - 36.0
	draw_line(Vector2(x, bar_y), Vector2(x + line_width, bar_y), LoadoutStyle.HAIRLINE, 1.0)
	draw_line(Vector2(x, bar_y), Vector2(x + line_width * _progress, bar_y), Color(LoadoutStyle.TEXT, 0.55), 1.0)
	if _skip_key != "" and _skippable:
		var label_font: Font = UiStyle.FONT_BOLD
		var skip_width: float = label_font.get_string_size("SKIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var chip_x: float = x + line_width - skip_width - 8.0 - maxf(label_font.get_string_size(_skip_key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0, 18.0)
		var chip_width: float = LoadoutStyle.draw_key_chip(self, Vector2(chip_x, bar_y + 8.0), _skip_key, 18.0)
		draw_string(label_font, Vector2(chip_x + chip_width + 8.0, bar_y + 21.0), "SKIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LoadoutStyle.TEXT_MUTED)
