extends Control

## Between sets: three pages (loadout, summary, research) in one shared frame over the dimmed world, with
## the page tabs on top. The pages draw no backdrop of their own (see LoadoutStyle).

@onready var _status_page: SummaryPage = %StatusPage
@onready var _loadout_page: Control = %LoadoutPage
@onready var _research_page: Control = %ResearchPage

const TAB_NAMES: Array[String] = ["LOADOUT", "SUMMARY", "RESEARCH"]
const TOP_INSET: float = 66.0

var _page_index: int = 0
var _tab_buttons: Array[Button] = []


func _ready() -> void:
	var completed_sets: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	completed_sets += int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	RoundRewardInventory.prepare_for_round(completed_sets)
	_build_tab_bar()
	_status_page.spend_requested.connect(_set_page.bind(-1))
	_status_page.set_top_inset(TOP_INSET)
	if _loadout_page.has_method(&"set_top_inset"):
		_loadout_page.set_top_inset(TOP_INSET)
	if _loadout_page.has_method(&"set_backdrop"):
		_loadout_page.set_backdrop(false)
	if _research_page.has_method(&"set_top_inset"):
		_research_page.set_top_inset(TOP_INSET)
	GameJuice.attach_button_feedback(self)
	InputDevice.device_changed.connect(_on_device_changed)
	_set_page(0)
	_focus_page.call_deferred()


## Page tabs across the top on a thin ink header: text tabs with an amber underline for the open page,
## flanked by the keys that switch them (Q / E, LB / RB on a pad).
func _build_tab_bar() -> void:
	var header: Control = Control.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 58.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.draw.connect(func() -> void:
		header.draw_rect(Rect2(Vector2.ZERO, header.size), Color(0.0, 0.0, 0.0, 0.35))
		header.draw_line(Vector2(0.0, header.size.y - 0.5), Vector2(header.size.x, header.size.y - 0.5), LoadoutStyle.HAIRLINE, 1.0))
	add_child(header)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = 9.0
	add_child(bar)
	bar.add_child(_key_hint("Q"))
	for index in range(TAB_NAMES.size()):
		var tab: Button = Button.new()
		tab.text = TAB_NAMES[index]
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(132.0, 40.0)
		tab.focus_mode = Control.FOCUS_NONE
		tab.set_meta("juice_feedback_connected", true)
		tab.add_theme_font_override("font", UiStyle.FONT_BOLD)
		tab.add_theme_font_size_override("font_size", 16)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var style: StyleBoxFlat = LoadoutStyle.flat(Color(0, 0, 0, 0), 0)
			if state in ["pressed", "hover_pressed"]:
				style.border_color = UiStyle.ACCENT
				style.border_width_bottom = 2
			style.content_margin_bottom = 4.0
			tab.add_theme_stylebox_override(state, style)
		tab.add_theme_color_override("font_color", LoadoutStyle.TEXT_MUTED)
		tab.add_theme_color_override("font_hover_color", LoadoutStyle.TEXT_SECONDARY)
		tab.add_theme_color_override("font_pressed_color", LoadoutStyle.TEXT)
		tab.add_theme_color_override("font_hover_pressed_color", LoadoutStyle.TEXT)
		tab.pressed.connect(_set_page.bind(index - 1))
		tab.mouse_entered.connect(func() -> void: AudioDirector.play(&"ui_hover", -8.0))
		bar.add_child(tab)
		_tab_buttons.append(tab)
	bar.add_child(_key_hint("E"))


func _key_hint(text: String) -> Control:
	var chip: Control = Control.new()
	chip.custom_minimum_size = Vector2(26.0, 40.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.draw.connect(func() -> void: LoadoutStyle.draw_key_chip(chip, Vector2(3.0, 11.0), "LB" if InputDevice.using_gamepad and text == "Q" else ("RB" if InputDevice.using_gamepad else text), 20.0))
	InputDevice.device_changed.connect(func(_pad: bool) -> void: chip.queue_redraw())
	return chip


## Pages switch with Q / E (LB / RB). Arrow keys and the d-pad stay with the page itself: they move through
## the locker grid and the research tree.
func _input(event: InputEvent) -> void:
	if _loadout_page.visible and _loadout_page.has_method(&"is_modal_open") and _loadout_page.is_modal_open():
		return
	if _is_page_cancel_event(event) and _page_index != 0:
		_set_page(0)
		get_viewport().set_input_as_handled()
	elif _is_tab_event(event, KEY_Q, JOY_BUTTON_LEFT_SHOULDER):
		_set_page(_page_index - 1)
		get_viewport().set_input_as_handled()
	elif _is_tab_event(event, KEY_E, JOY_BUTTON_RIGHT_SHOULDER):
		_set_page(_page_index + 1)
		get_viewport().set_input_as_handled()


func _is_tab_event(event: InputEvent, key: Key, button: JoyButton) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		return key_event.pressed and not key_event.echo and key_event.keycode == key
	var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
	return joy_event != null and joy_event.pressed and joy_event.button_index == button


func _set_page(next_page: int) -> void:
	var previous: int = _page_index
	_page_index = clampi(next_page, -1, 1)
	_loadout_page.visible = _page_index == -1
	_status_page.visible = _page_index == 0
	_research_page.visible = _page_index == 1
	for index in range(_tab_buttons.size()):
		_tab_buttons[index].set_pressed_no_signal(index - 1 == _page_index)
	if previous == _page_index or not is_inside_tree():
		return
	_focus_page.call_deferred()
	AudioDirector.play(&"ui_whoosh", -8.0)
	var page: Control = [_loadout_page, _status_page, _research_page][_page_index + 1]
	page.modulate.a = 0.0
	page.position.x = 40.0 * signf(float(_page_index - previous))
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(page, "modulate:a", 1.0, 0.18)
	tween.tween_property(page, "position:x", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The open page takes the cursor (its default control), so a pad can always act after a page switch.
func _focus_page() -> void:
	var page: Control = [_loadout_page, _status_page, _research_page][_page_index + 1]
	if page.has_method(&"focus_default"):
		page.focus_default()


func _on_device_changed(using_gamepad: bool) -> void:
	if using_gamepad and get_viewport().gui_get_focus_owner() == null:
		_focus_page()


func _is_page_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
