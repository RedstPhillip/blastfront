extends Control
class_name SettingsMenu

## Tabbed settings screen bound to UserSettings. Every change applies immediately and persists.

signal back_pressed

const PARTICLE_LEVELS: Array[float] = [0.0, 0.33, 0.66, 1.0]
const PARTICLE_NAMES: Array[String] = ["Off", "Low", "Medium", "High"]
const WINDOW_MODE_NAMES: Array[String] = ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const KEY_CHIP_WIDTH: float = 132.0
## Action, keyboard & mouse, gamepad. Key names match the on-screen prompts (InputDevice.prompt).
const CONTROL_ROWS: Array[Array] = [
	["Move", "A / D", "L STICK"],
	["Jump  ·  Wall jump", "SPACE / W", "A"],
	["Aim", "MOUSE", "R STICK"],
	["Shoot", "LMB", "RT / RB"],
	["Block", "RMB", "LT / LB"],
	["Reload", "R", "X"],
	["Time Control", "Q", "Y"],
	["Orders", "TAB", "BACK"],
	["Pause", "ESC", "START"],
]

var _tabs: TabContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"modal_ui")
	_build()
	GameJuice.attach_button_feedback(self)
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()


func _build() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 560.0)
	panel.add_theme_stylebox_override("panel", UiStyle.with_shadow(UiStyle.with_margins(UiStyle.panel(UiStyle.PANEL_SOLID, UiStyle.LINE_STRONG, 10, 1), 34, 26), 30, Vector2(0, 14)))
	center.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var title: Label = Label.new()
	UiStyle.style_label(title, UiStyle.FONT_DISPLAY, 34, UiStyle.TEXT)
	title.text = "SETTINGS"
	header.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_tab: int) -> void: AudioDirector.play(&"ui_toggle"))
	box.add_child(_tabs)
	_build_tabs()

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	box.add_child(footer)
	var reset: Button = Button.new()
	reset.text = "RESET DEFAULTS"
	reset.custom_minimum_size = Vector2(210.0, 48.0)
	UiStyle.style_button(reset, false, 16)
	reset.pressed.connect(_on_reset_pressed)
	footer.add_child(reset)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back: Button = Button.new()
	back.text = "DONE"
	back.custom_minimum_size = Vector2(180.0, 48.0)
	UiStyle.style_button(back, true, 18)
	back.pressed.connect(func() -> void: back_pressed.emit())
	footer.add_child(back)
	back.grab_focus.call_deferred()


func _make_page(page_name: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var page: VBoxContainer = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
	return page


func _row(page: VBoxContainer, label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 40.0)
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_UI, 18, UiStyle.TEXT)
	label.text = label_text
	label.custom_minimum_size = Vector2(250.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row


func _section(page: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_BOLD, 13, UiStyle.ACCENT)
	label.text = text
	page.add_child(label)


func _slider(page: VBoxContainer, label_text: String, key: StringName, max_value: float = 1.0) -> void:
	var row: HBoxContainer = _row(page, label_text)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = max_value
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(300.0, 24.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = UserSettings.get_float(key)
	row.add_child(slider)
	var value_label: Label = Label.new()
	UiStyle.style_label(value_label, UiStyle.FONT_BOLD, 16, UiStyle.ACCENT_HOT)
	value_label.custom_minimum_size = Vector2(60.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.text = "%d%%" % int(round(slider.value * 100.0))
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		UserSettings.set_value(key, value)
		value_label.text = "%d%%" % int(round(value * 100.0))
		AudioDirector.play(&"ui_slider")
	)


func _toggle(page: VBoxContainer, label_text: String, key: StringName) -> void:
	var row: HBoxContainer = _row(page, label_text)
	var toggle: CheckButton = CheckButton.new()
	toggle.button_pressed = UserSettings.get_bool(key)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(func(pressed: bool) -> void:
		UserSettings.set_value(key, pressed)
		AudioDirector.play(&"ui_toggle")
	)
	row.add_child(toggle)


func _options(page: VBoxContainer, label_text: String, items: Array, selected: int, on_selected: Callable) -> OptionButton:
	var row: HBoxContainer = _row(page, label_text)
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size = Vector2(300.0, 40.0)
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for item in items:
		option.add_item(str(item))
	option.select(clampi(selected, 0, items.size() - 1))
	option.item_selected.connect(func(index: int) -> void:
		on_selected.call(index)
		AudioDirector.play(&"ui_select" if AudioDirector.has_event(&"ui_select") else &"ui_click")
	)
	row.add_child(option)
	return option


func _build_audio_tab() -> void:
	var page: VBoxContainer = _make_page("AUDIO")
	_section(page, "VOLUME")
	_slider(page, "Master", UserSettings.MASTER_VOLUME)
	_slider(page, "Music", UserSettings.MUSIC_VOLUME)
	_slider(page, "Effects", UserSettings.SFX_VOLUME)
	_slider(page, "Interface", UserSettings.UI_VOLUME)


func _build_video_tab() -> void:
	var page: VBoxContainer = _make_page("VIDEO")
	_section(page, "DISPLAY")
	_options(page, "Display mode", WINDOW_MODE_NAMES, UserSettings.get_int(UserSettings.WINDOW_MODE), func(index: int) -> void:
		UserSettings.set_value(UserSettings.WINDOW_MODE, index)
	)
	var resolutions: Array = []
	var current: Vector2i = UserSettings.get_value(UserSettings.RESOLUTION)
	var selected: int = 0
	for index in range(UserSettings.RESOLUTIONS.size()):
		var resolution: Vector2i = UserSettings.RESOLUTIONS[index]
		resolutions.append("%d × %d" % [resolution.x, resolution.y])
		if resolution == current:
			selected = index
	_options(page, "Window size", resolutions, selected, func(index: int) -> void:
		UserSettings.set_value(UserSettings.RESOLUTION, UserSettings.RESOLUTIONS[index])
	)
	_toggle(page, "VSync", UserSettings.VSYNC)
	var fps_names: Array = []
	for limit in UserSettings.FPS_LIMITS:
		fps_names.append("Unlimited" if limit == 0 else "%d FPS" % limit)
	_options(page, "Frame rate limit", fps_names, maxi(UserSettings.FPS_LIMITS.find(UserSettings.get_int(UserSettings.FPS_LIMIT)), 0), func(index: int) -> void:
		UserSettings.set_value(UserSettings.FPS_LIMIT, UserSettings.FPS_LIMITS[index])
	)
	_section(page, "EFFECTS")
	_slider(page, "Post-processing", UserSettings.POST_PROCESSING)
	_slider(page, "Screen flashes", UserSettings.SCREEN_FLASH)


func _build_gameplay_tab() -> void:
	var page: VBoxContainer = _make_page("GAMEPLAY")
	_section(page, "FEEL")
	_slider(page, "Screen shake", UserSettings.SCREEN_SHAKE, 1.5)
	_toggle(page, "Hit-stop on impacts", UserSettings.HITSTOP)
	_toggle(page, "Damage numbers", UserSettings.DAMAGE_NUMBERS)
	var particle_index: int = 3
	for index in range(PARTICLE_LEVELS.size()):
		if is_equal_approx(PARTICLE_LEVELS[index], UserSettings.get_float(UserSettings.PARTICLES)):
			particle_index = index
	_options(page, "Particle detail", PARTICLE_NAMES, particle_index, func(index: int) -> void:
		UserSettings.set_value(UserSettings.PARTICLES, PARTICLE_LEVELS[index])
	)


func _build_controls_tab() -> void:
	var page: VBoxContainer = _make_page("CONTROLS")
	page.add_theme_constant_override("separation", 4)
	# Column heads sit over the key columns, in the same section style as the other tabs.
	var heads: HBoxContainer = _row(page, "")
	heads.custom_minimum_size.y = 20.0
	for text in ["KEYBOARD", "GAMEPAD"]:
		var head: Label = Label.new()
		UiStyle.style_label(head, UiStyle.FONT_BOLD, 13, UiStyle.ACCENT)
		head.text = text
		head.custom_minimum_size = Vector2(KEY_CHIP_WIDTH, 0.0)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heads.add_child(head)
	for entry in CONTROL_ROWS:
		var row: HBoxContainer = _row(page, str(entry[0]))
		row.custom_minimum_size.y = 28.0
		row.add_child(_key_chip(str(entry[1])))
		row.add_child(_key_chip(str(entry[2])))


func _key_chip(text: String) -> PanelContainer:
	var key: Label = Label.new()
	UiStyle.style_label(key, UiStyle.FONT_BOLD, 14, UiStyle.TEXT)
	key.text = text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chip: PanelContainer = PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiStyle.with_margins(UiStyle.panel(UiStyle.PANEL_RAISED), 10, 3))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.custom_minimum_size = Vector2(KEY_CHIP_WIDTH, 0.0)
	chip.add_child(key)
	return chip


func _build_tabs() -> void:
	_build_audio_tab()
	_build_video_tab()
	_build_gameplay_tab()
	_build_controls_tab()


## Rebuilds every page from the defaults. The old pages leave the container at once (not at the end of the
## frame), otherwise the new pages could not take their names and the tabs would show generated ones.
func _on_reset_pressed() -> void:
	UserSettings.reset_to_defaults()
	AudioDirector.play(&"ui_confirm")
	var current_tab: int = _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_build_tabs()
	_tabs.current_tab = clampi(current_tab, 0, _tabs.get_tab_count() - 1)
