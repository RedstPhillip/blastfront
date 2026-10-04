class_name HudVictoryScreen
extends Control

## End-of-match results on the same feathered ink band as the point banner (no box): VICTORY / DEFEAT,
## the final score, stat counters that count up, and the two actions.

signal rematch_pressed
signal menu_pressed

var _dim: ColorRect = null
var _panel: VBoxContainer = null
var _band: Control = null
var _title: Label = null
var _score: Label = null
var _stats_row: HBoxContainer = null
var _rematch_button: Button = null
var _menu_button: Button = null
var _confetti: CPUParticles2D = null
var _shown: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group(&"modal_ui")
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_dim)

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.amount = 90
	_confetti.lifetime = 3.2
	_confetti.texture = FxLib.TEX_DEBRIS
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 20.0
	_confetti.gravity = Vector2(0, 160)
	_confetti.initial_velocity_min = 40.0
	_confetti.initial_velocity_max = 140.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.scale_amount_min = 0.25
	_confetti.scale_amount_max = 0.5
	_confetti.color_ramp = FxLib.fade_ramp(&"late")
	add_child(_confetti)

	_band = Control.new()
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.draw.connect(_draw_band)
	_band.modulate.a = 0.0
	add_child(_band)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size = Vector2(640, 0)
	_panel.add_theme_constant_override("separation", 10)
	center.add_child(_panel)
	var box: VBoxContainer = _panel
	_title = _label(UiStyle.FONT_DISPLAY, 86, UiStyle.TEXT, "VICTORY")
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	box.add_child(_title)
	_score = _label(UiStyle.FONT_BOLD, 20, UiStyle.TEXT, "")
	_score.add_theme_constant_override("outline_size", 4)
	_score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	box.add_child(_score)
	var separator: ColorRect = ColorRect.new()
	separator.custom_minimum_size = Vector2(280, 1)
	separator.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	separator.color = LoadoutStyle.HAIRLINE
	box.add_child(separator)
	_stats_row = HBoxContainer.new()
	_stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats_row.add_theme_constant_override("separation", 34)
	box.add_child(_stats_row)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 22)
	box.add_child(buttons)
	_rematch_button = Button.new()
	_rematch_button.text = "REMATCH"
	_rematch_button.custom_minimum_size = Vector2(220, 52)
	UiStyle.style_button(_rematch_button, true)
	_rematch_button.pressed.connect(func() -> void: rematch_pressed.emit())
	buttons.add_child(_rematch_button)
	_menu_button = Button.new()
	_menu_button.text = "MAIN MENU"
	_menu_button.custom_minimum_size = Vector2(220, 52)
	UiStyle.style_button(_menu_button, false)
	_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu_button)
	GameJuice.attach_button_feedback(self)


func _label(font: Font, font_size: int, color: Color, text: String) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, font, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	return label


func is_shown() -> bool:
	return _shown


func show_result(won: bool, headline_color: Color, score_text: String, stats: Array[Dictionary], can_rematch: bool, rematch_text: String) -> void:
	if _shown:
		return
	_shown = true
	visible = true
	_title.text = "VICTORY" if won else "DEFEAT"
	_title.add_theme_color_override("font_color", UiStyle.ACCENT if won else UiStyle.DANGER)
	_score.text = score_text
	_rematch_button.disabled = not can_rematch
	_rematch_button.text = rematch_text
	for child in _stats_row.get_children():
		child.queue_free()
	var counters: Array[Label] = []
	var targets: Array[float] = []
	var formats: Array[String] = []
	for stat in stats:
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		var value_label: Label = _label(UiStyle.FONT_DISPLAY, 30, UiStyle.TEXT, "0")
		var name_label: Label = _label(UiStyle.FONT_BOLD, 11, UiStyle.TEXT_DIM, str(stat.get("label", "")))
		column.add_child(value_label)
		column.add_child(name_label)
		_stats_row.add_child(column)
		counters.append(value_label)
		targets.append(float(stat.get("value", 0.0)))
		formats.append(str(stat.get("format", "%d")))

	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.35, 0.5)
	tween.tween_property(_band, "modulate:a", 1.0, 0.4)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	for index in range(counters.size()):
		var label: Label = counters[index]
		var target: float = targets[index]
		var format: String = formats[index]
		tween.tween_method(func(value: float) -> void: label.text = format % (int(round(value)) if format.contains("%d") else value), 0.0, target, 0.9).set_delay(0.5 + index * 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	AudioDirector.play(&"match_victory" if won else &"match_defeat")
	AudioDirector.duck_music(-14.0, 2.5, 2.0)
	if won:
		_confetti.position = Vector2(size.x * 0.5, -20.0)
		_confetti.emission_rect_extents = Vector2(size.x * 0.5, 10.0)
		_confetti.color = headline_color
		_confetti.color_initial_ramp = _confetti_colors(headline_color)
		_confetti.emitting = true
	_rematch_button.grab_focus.call_deferred()


func hide_result() -> void:
	_band.modulate.a = 0.0
	_shown = false
	visible = false
	_confetti.emitting = false


func _confetti_colors(base: Color) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	gradient.colors = PackedColorArray([base, UiStyle.ACCENT, Color.WHITE, base.lightened(0.3)])
	return gradient


## A wide ink band behind the result, feathered at its top and bottom like the point banner.
func _draw_band() -> void:
	var mid: float = size.y * 0.5
	var half: float = 190.0
	var feather: float = 90.0
	var ink: Color = Color(0.0, 0.012, 0.016, 0.82)
	var clear: Color = Color(ink.r, ink.g, ink.b, 0.0)
	LoadoutStyle.draw_gradient_rect(_band, Rect2(0.0, mid - half - feather, size.x, feather), clear, ink)
	_band.draw_rect(Rect2(0.0, mid - half, size.x, half * 2.0), ink)
	LoadoutStyle.draw_gradient_rect(_band, Rect2(0.0, mid + half, size.x, feather), ink, clear)
