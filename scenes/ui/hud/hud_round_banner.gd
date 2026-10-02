class_name HudRoundBanner
extends Control

## Centre-screen announcer: round intros with a 3-2-1-FIGHT countdown and point banners with sweeping
## diagonal bars in the scoring player's colour.

const BAR_SLANT: float = -0.07

var _title: Label = null
var _subtitle: Label = null
var _count: Label = null
var _flash: ColorRect = null
var _bar_top: Polygon2D = null
var _bar_bottom: Polygon2D = null
var _bar_stripe: Polygon2D = null
var _sequence: Tween = null
var _bars_tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_bar_top = Polygon2D.new()
	_bar_bottom = Polygon2D.new()
	_bar_stripe = Polygon2D.new()
	for bar in [_bar_top, _bar_bottom, _bar_stripe]:
		bar.visible = false
		add_child(bar)
	_title = _make_label(UiStyle.FONT_DISPLAY, 78, UiStyle.TEXT, 12)
	_subtitle = _make_label(UiStyle.FONT_BOLD, 22, UiStyle.TEXT_DIM, 6)
	_count = _make_label(UiStyle.FONT_DISPLAY, 130, UiStyle.ACCENT_HOT, 14)
	resized.connect(_layout)
	_layout()


func _make_label(font: Font, font_size: int, color: Color, outline: int) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, font, font_size, color, outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	add_child(label)
	return label


func _layout() -> void:
	var w: float = size.x
	var h: float = size.y
	_title.size = Vector2(w, 110.0)
	_title.position = Vector2(0.0, h * 0.5 - 115.0)
	_title.pivot_offset = _title.size * 0.5
	_subtitle.size = Vector2(w, 40.0)
	_subtitle.position = Vector2(0.0, h * 0.5 - 12.0)
	_subtitle.pivot_offset = _subtitle.size * 0.5
	_count.size = Vector2(w, 170.0)
	_count.position = Vector2(0.0, h * 0.5 + 10.0)
	_count.pivot_offset = _count.size * 0.5


## Round intro: title, optional subtitle and a countdown ending in FIGHT exactly at `duration`.
func play_intro(round_number: int, duration: float, subtitle: String, title_override: String = "") -> void:
	_kill_sequences()
	_title.text = title_override if title_override != "" else "ROUND %d" % round_number
	_title.add_theme_color_override("font_color", UiStyle.TEXT)
	_subtitle.text = subtitle
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_count.modulate.a = 0.0
	_title.scale = Vector2(1.25, 1.25)
	_sequence = create_tween().set_ignore_time_scale(true)
	_sequence.set_parallel(true)
	_sequence.tween_property(_title, "modulate:a", 1.0, 0.18)
	_sequence.tween_property(_title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sequence.tween_property(_subtitle, "modulate:a", 1.0, 0.25).set_delay(0.12)
	AudioDirector.play(&"ui_whoosh")
	var digits: Array[String] = ["3", "2", "1"]
	if duration >= 1.45:
		for index in range(digits.size()):
			var at: float = duration - 0.45 * float(digits.size() - index)
			_sequence.tween_callback(_pop_count.bind(digits[index], UiStyle.TEXT, false)).set_delay(maxf(at, 0.05))
	_sequence.tween_property(_title, "modulate:a", 0.0, 0.2).set_delay(maxf(duration - 0.2, 0.0))
	_sequence.tween_property(_subtitle, "modulate:a", 0.0, 0.2).set_delay(maxf(duration - 0.2, 0.0))
	_sequence.tween_callback(_pop_count.bind("FIGHT!", UiStyle.ACCENT, true)).set_delay(duration)


func _pop_count(text: String, color: Color, is_final: bool) -> void:
	_count.text = text
	_count.add_theme_color_override("font_color", color)
	_count.add_theme_font_size_override("font_size", 150 if is_final else 130)
	_count.modulate.a = 1.0
	_count.scale = Vector2.ONE * (1.8 if is_final else 1.5)
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(_count, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_count, "modulate:a", 0.0, 0.3).set_delay(0.55 if is_final else 0.3)
	if is_final:
		AudioDirector.play(&"count_go")
		_flash.color = Color(1.0, 0.85, 0.55, 0.28)
		tween.tween_property(_flash, "color:a", 0.0, 0.35)
		GameJuice.shake(4.0, 0.2)
	else:
		AudioDirector.play(&"count_tick", 0.0, 1.0 + (0.12 if text == "1" else 0.0))


## Point banner: a feathered ink band sweeps in behind the title with one thin stripe in the scorer's colour,
## so the moment lands without slabs of colour covering the arena.
func play_point(color: Color, title: String, subtitle: String, big: bool = false) -> void:
	_kill_sequences()
	_title.text = title
	_title.add_theme_color_override("font_color", color.lightened(0.35))
	_subtitle.text = subtitle
	_count.modulate.a = 0.0
	var w: float = size.x
	var h: float = size.y
	var sweep: float = w + 400.0
	var ink: Color = Color(0.0, 0.012, 0.016, 0.78)
	_setup_bar(_bar_top, ink, h * 0.5 - 150.0, 82.0, sweep, true)
	_setup_bar(_bar_bottom, ink, h * 0.5 - 68.0, 104.0, sweep, false)
	_setup_bar(_bar_stripe, Color(color.lightened(0.15), 0.95), h * 0.5 - 22.0, 3.0, sweep)
	_bar_top.position.x = -sweep
	_bar_stripe.position.x = w + 200.0
	_bar_bottom.position.x = w + 200.0
	_flash.color = Color(color.r, color.g, color.b, 0.3)
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_title.scale = Vector2(0.7, 0.7)
	AudioDirector.play(&"round_win_big" if big else &"round_win")
	AudioDirector.play(&"ui_whoosh")
	var hold: float = 1.15
	_bars_tween = create_tween().set_ignore_time_scale(true)
	_bars_tween.set_parallel(true)
	_bars_tween.tween_property(_flash, "color:a", 0.0, 0.6)
	_bars_tween.tween_property(_bar_top, "position:x", -200.0, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_bars_tween.tween_property(_bar_stripe, "position:x", -200.0, 0.36).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(0.03)
	_bars_tween.tween_property(_bar_bottom, "position:x", -200.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(0.05)
	_bars_tween.tween_property(_title, "modulate:a", 1.0, 0.15).set_delay(0.12)
	_bars_tween.tween_property(_title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	_bars_tween.tween_property(_subtitle, "modulate:a", 1.0, 0.2).set_delay(0.25)
	_bars_tween.tween_property(_bar_top, "position:x", w + 300.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN).set_delay(hold)
	_bars_tween.tween_property(_bar_stripe, "position:x", -sweep - 300.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN).set_delay(hold + 0.03)
	_bars_tween.tween_property(_bar_bottom, "position:x", -sweep - 300.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN).set_delay(hold + 0.05)
	_bars_tween.tween_property(_title, "modulate:a", 0.0, 0.25).set_delay(hold)
	_bars_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.25).set_delay(hold)


func hide_banner() -> void:
	_kill_sequences()
	for label in [_title, _subtitle, _count]:
		label.modulate.a = 0.0
	for bar in [_bar_top, _bar_bottom, _bar_stripe]:
		bar.visible = false


## A slanted band; fade_in feathers it from transparent at the top, fade_out towards the bottom.
func _setup_bar(bar: Polygon2D, color: Color, y: float, height: float, width: float, fade_in: Variant = null) -> void:
	bar.visible = true
	bar.color = Color.WHITE
	var slant: float = height * 0.25
	bar.polygon = PackedVector2Array([
		Vector2(slant, y),
		Vector2(width, y),
		Vector2(width - slant, y + height),
		Vector2(0.0, y + height),
	])
	var clear: Color = Color(color.r, color.g, color.b, 0.0)
	var top: Color = color
	var bottom: Color = color
	if fade_in == true:
		top = clear
	elif fade_in == false:
		bottom = clear
	bar.vertex_colors = PackedColorArray([top, top, bottom, bottom])


func _kill_sequences() -> void:
	for tween in [_sequence, _bars_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
