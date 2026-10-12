extends Control
class_name SettingsMenu

## Tabbed settings screen bound to UserSettings. Every change applies immediately and persists.

signal back_pressed

const PARTICLE_LEVELS: Array[float] = [0.0, 0.33, 0.66, 1.0]
const PARTICLE_NAMES: Array[String] = ["Off", "Low", "Medium", "High"]
const WINDOW_MODE_NAMES: Array[String] = ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const LISTENING_TEXT: String = "PRESS…"
## While a chip is listening the menu must swallow the next key, including ESC (cancel) and the
## ui_accept press that would otherwise re-trigger the very button under the cursor.
const LISTEN_TIMEOUT: float = 8.0
## Controls tab grid: label column, two key columns of equal width, the undo slot.
const CONTROL_LABEL_WIDTH: float = 200.0
const CONTROL_COLUMN_WIDTH: float = 172.0
const CONTROL_ROW_HEIGHT: float = 24.0
const UNDO_SLOT_WIDTH: float = 58.0

var _tabs: TabContainer = null
var _listening: Dictionary = {}
var _listen_deadline: float = 0.0
var _chips: Array[Button] = []
var _row_reset: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"modal_ui")
	_build()
	GameJuice.attach_button_feedback(self)
	InputDevice.bindings_changed.connect(_on_bindings_changed)
	set_process(false)
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)


func _process(delta: float) -> void:
	# A chip left listening (walked away from the menu) would eat input forever.
	if not _listening.is_empty() and float(Time.get_ticks_msec()) > _listen_deadline:
		_stop_listening()


func _input(event: InputEvent) -> void:
	if _process_listen(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# While a chip listens, ESC cancels the capture instead of closing the menu.
	if not _listening.is_empty():
		return
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
	page.add_theme_constant_override("separation", 2)
	_chips.clear()
	_row_reset.clear()
	# Column heads over the key columns (same widths as the cells below, and the undo slot); the label
	# column carries the one-line how-to.
	var heads: HBoxContainer = _row(page, "CLICK TO REBIND  ·  ESC CANCELS")
	heads.custom_minimum_size.y = 20.0
	var how_to: Label = heads.get_child(0) as Label
	UiStyle.style_label(how_to, UiStyle.FONT_BOLD, 11, UiStyle.TEXT_MUTED)
	how_to.custom_minimum_size.x = CONTROL_LABEL_WIDTH
	for text in ["KEYBOARD & MOUSE", "GAMEPAD"]:
		var head: Label = Label.new()
		UiStyle.style_label(head, UiStyle.FONT_BOLD, 13, UiStyle.ACCENT)
		head.text = text
		head.custom_minimum_size.x = CONTROL_COLUMN_WIDTH
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heads.add_child(head)
	heads.add_child(_undo_slot(null))
	for row in InputDevice.CONTROL_ROWS:
		var actions: Array = row["actions"]
		var line: HBoxContainer = _row(page, str(row["label"]))
		line.custom_minimum_size.y = CONTROL_ROW_HEIGHT
		var label: Label = line.get_child(0) as Label
		label.add_theme_font_size_override(&"font_size", 16)
		label.custom_minimum_size.x = CONTROL_LABEL_WIDTH
		line.add_child(_chip_cell(actions, InputDevice.KEYBOARD, row))
		line.add_child(_chip_cell(actions, InputDevice.GAMEPAD, row))
		line.add_child(_undo_slot(_row_reset_button(actions)))
	_refresh_chips()


## A fixed-width slot at the end of a row, so a row's cells keep their width whether UNDO shows or not.
func _undo_slot(undo: Button) -> Control:
	var slot: CenterContainer = CenterContainer.new()
	slot.custom_minimum_size = Vector2(UNDO_SLOT_WIDTH, 0.0)
	if undo != null:
		slot.add_child(undo)
	return slot


## Puts one row's bindings back to the project's own; only visible while that row is off-default.
func _row_reset_button(actions: Array) -> Button:
	var undo: Button = Button.new()
	undo.text = "UNDO"
	undo.tooltip_text = "Back to the default bindings"
	undo.custom_minimum_size = Vector2(UNDO_SLOT_WIDTH - 4.0, CONTROL_ROW_HEIGHT - 2.0)
	undo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStyle.style_button(undo, false, 11)
	_compact(undo)
	undo.add_theme_stylebox_override("focus", UiStyle.focus_frame())
	undo.visible = false
	undo.pressed.connect(func() -> void:
		_stop_listening()
		for action in actions:
			InputDevice.reset_action(action)
		AudioDirector.play(&"ui_toggle"))
	_row_reset.append(undo)
	return undo


## One cell of a row: a clickable chip per action (a row like Move binds two keys), or a fixed chip
## when the row has no InputMap action to rebind.
func _chip_cell(actions: Array, kind: StringName, row: Dictionary) -> Control:
	var cell: HBoxContainer = HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	cell.custom_minimum_size.x = CONTROL_COLUMN_WIDTH
	if actions.is_empty():
		cell.add_child(_fixed_chip(str(row.get(str(kind), ""))))
		return cell
	for action in actions:
		cell.add_child(_binding_chip(action, kind))
	return cell


## Small padding for the grid's buttons, so the text decides nothing about a column's width.
static func _compact(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = button.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0


## Each chip knows the binding it shows (action + column), so labels and captures never depend on the
## order the chips were built in (a row like Move holds two actions per column).
func _binding_chip(action: StringName, kind: StringName) -> Button:
	var chip: Button = Button.new()
	chip.custom_minimum_size = Vector2(0.0, CONTROL_ROW_HEIGHT - 2.0)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(chip, false, 13)
	_compact(chip)
	chip.add_theme_stylebox_override("focus", UiStyle.focus_frame())
	chip.set_meta(&"action", action)
	chip.set_meta(&"kind", kind)
	chip.pressed.connect(_on_chip_pressed.bind(action, kind))
	_chips.append(chip)
	return chip


func _fixed_chip(text: String) -> PanelContainer:
	var key: Label = Label.new()
	UiStyle.style_label(key, UiStyle.FONT_BOLD, 13, UiStyle.TEXT_MUTED)
	key.text = text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chip: PanelContainer = PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiStyle.with_margins(UiStyle.panel(UiStyle.PANEL_RAISED), 10, 2))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_child(key)
	return chip


## Repaints every chip from the InputMap: the label, a red tint where the binding clashes with another
## action, and the amber "listening" state for the chip waiting for a press.
func _refresh_chips() -> void:
	# A row reads as changed (amber, UNDO shown) as soon as one of its actions is off its default.
	var touched_rows: Dictionary = {}
	for row_index in range(InputDevice.CONTROL_ROWS.size()):
		var actions: Array = InputDevice.CONTROL_ROWS[row_index]["actions"]
		var touched: bool = false
		for action in actions:
			touched = touched or InputDevice.is_modified(action)
		for action in actions:
			touched_rows[action] = touched
		if row_index < _row_reset.size():
			_row_reset[row_index].visible = touched
	for chip in _chips:
		var action: StringName = chip.get_meta(&"action")
		var kind: StringName = chip.get_meta(&"kind")
		if _listening.get("chip") == chip:
			chip.text = LISTENING_TEXT
			chip.add_theme_color_override("font_color", UiStyle.ACCENT_HOT)
			chip.add_theme_color_override("font_hover_color", UiStyle.ACCENT_HOT)
			continue
		var event: InputEvent = InputDevice.binding_for(action, kind)
		chip.text = InputDevice.describe_event(event)
		var clash: bool = InputDevice.conflicts_with(action, event)
		var color: Color = UiStyle.DANGER if clash else (UiStyle.ACCENT if touched_rows.get(action, false) else UiStyle.TEXT_DIM)
		chip.add_theme_color_override("font_color", color)
		chip.add_theme_color_override("font_hover_color", UiStyle.TEXT)
		chip.tooltip_text = "Also bound to another action" if clash else ""


func _on_chip_pressed(action: StringName, kind: StringName) -> void:
	# A second chip while one is listening: swap the listener instead of stacking them.
	_listening = {"action": action, "chip": _chip_for(action, kind)}
	_listen_deadline = float(Time.get_ticks_msec()) + LISTEN_TIMEOUT * 1000.0
	AudioDirector.play(&"ui_click")
	_refresh_chips()
	set_process(true)
	get_viewport().set_input_as_handled()


func _chip_for(action: StringName, kind: StringName) -> Button:
	for chip in _chips:
		if chip.get_meta(&"action") == action and chip.get_meta(&"kind") == kind:
			return chip
	return null


## Captures the next key, mouse button or pad input while a chip listens. Returns true when the event
## belonged to the capture, so the caller can swallow it before anything else reacts. A capture is
## modal: stick drift and stray clicks below the deadzone are ignored rather than ending it, so only a
## real press, ESC or the timeout leaves the chip.
func _process_listen(event: InputEvent) -> bool:
	if _listening.is_empty():
		return false
	var action: StringName = _listening["action"]
	if event is InputEventKey and not event.is_pressed():
		return false
	if event is InputEventMouseButton and not event.is_pressed():
		return false
	# ESC backs out without changing anything, so the menu can never be locked out.
	if event is InputEventKey and _is_escape(event as InputEventKey):
		_stop_listening()
		return true
	var captured: InputEvent = _capturable(event)
	if captured != null:
		InputDevice.rebind(action, captured)
		AudioDirector.play(&"ui_confirm")
		_stop_listening()
	return true


static func _is_escape(key: InputEventKey) -> bool:
	return key.physical_keycode == KEY_ESCAPE or (key.physical_keycode == 0 and key.keycode == KEY_ESCAPE)


## Keeps only what makes a binding: strips the pressed state and any text/click noise, and rejects
## sticks pushed only past the deadzone.
func _capturable(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key: InputEventKey = (event as InputEventKey).duplicate() as InputEventKey
		key.pressed = false
		key.echo = false
		key.alt_pressed = false
		key.shift_pressed = false
		key.ctrl_pressed = false
		key.meta_pressed = false
		key.unicode = 0
		return key
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			return null
		var mouse: InputEventMouseButton = (event as InputEventMouseButton).duplicate() as InputEventMouseButton
		mouse.pressed = false
		return mouse
	if event is InputEventJoypadButton and event.is_pressed():
		var pad: InputEventJoypadButton = (event as InputEventJoypadButton).duplicate() as InputEventJoypadButton
		pad.pressed = false
		pad.pressure = 0.0
		return pad
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		var deadzone: float = InputDevice.TRIGGER_DEADZONE if motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT else InputDevice.STICK_DEADZONE
		if absf(motion.axis_value) < deadzone:
			return null
		var axis: InputEventJoypadMotion = motion.duplicate() as InputEventJoypadMotion
		axis.axis_value = 1.0 if motion.axis_value > 0.0 else -1.0
		return axis
	return null


func _stop_listening() -> void:
	if _listening.is_empty():
		return
	_listening = {}
	set_process(false)
	_refresh_chips()


func _on_bindings_changed() -> void:
	_refresh_chips()


func _build_tabs() -> void:
	_build_audio_tab()
	_build_video_tab()
	_build_gameplay_tab()
	_build_controls_tab()


## Rebuilds every page from the defaults. The old pages leave the container at once (not at the end of the
## frame), otherwise the new pages could not take their names and the tabs would show generated ones.
func _on_reset_pressed() -> void:
	_stop_listening()
	UserSettings.reset_to_defaults()
	AudioDirector.play(&"ui_confirm")
	var current_tab: int = _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_build_tabs()
	_tabs.current_tab = clampi(current_tab, 0, _tabs.get_tab_count() - 1)
