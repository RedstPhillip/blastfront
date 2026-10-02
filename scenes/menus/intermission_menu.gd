extends Control

@onready var _title_label: Label = %TitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _local_ready_label: Label = %LocalReadyLabel
@onready var _remote_ready_label: Label = %RemoteReadyLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _status_page: Control = %StatusPage
@onready var _loadout_page: Control = %LoadoutPage
@onready var _research_page: Control = %ResearchPage
@onready var _left_page_button: Button = %LeftPageButton
@onready var _right_page_button: Button = %RightPageButton
@onready var _damage_earnings_label: Label = %DamageEarningsLabel
@onready var _damage_coins_label: Label = %DamageCoinsLabel
@onready var _survival_earnings_label: Label = %SurvivalEarningsLabel
@onready var _survival_coins_label: Label = %SurvivalCoinsLabel
@onready var _blocking_earnings_label: Label = %BlockingEarningsLabel
@onready var _blocking_coins_label: Label = %BlockingCoinsLabel
@onready var _first_hit_earnings_label: Label = %FirstHitEarningsLabel
@onready var _first_hit_coins_label: Label = %FirstHitCoinsLabel
@onready var _earned_total_label: Label = %EarnedTotalLabel
@onready var _coin_balance_label: Label = %CoinBalanceLabel

const TAB_NAMES: Array[String] = ["LOADOUT", "SUMMARY", "RESEARCH"]
const URGENT_SECONDS: int = 5

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _page_index: int = 0
var _tab_buttons: Array[Button] = []
var _earnings_animating: bool = false
var _last_countdown: int = -1
var _countdown_tween: Tween = null
var _spend_button: Button = null


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	var completed_sets: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	completed_sets += int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	RoundRewardInventory.prepare_for_round(completed_sets)
	_ready_button.pressed.connect(_on_ready_pressed)
	_left_page_button.pressed.connect(_on_previous_page_pressed)
	_right_page_button.pressed.connect(_on_next_page_pressed)
	_build_tab_bar()
	_build_spend_button()
	_replace_quest_panel()
	_left_page_button.get_parent().visible = false
	if _loadout_page.has_method(&"set_top_inset"):
		_loadout_page.set_top_inset(66.0)
	if _research_page.has_method(&"set_top_inset"):
		_research_page.set_top_inset(66.0)
	_status_page.offset_top = 58.0
	UiStyle.style_button(_ready_button, true, 20)
	GameJuice.attach_button_feedback(self)
	OnlineMatch.state_changed.connect(_refresh)
	OnlineMatch.countdown_changed.connect(_on_countdown_changed)
	_set_page(0)
	_refresh()
	_play_earnings_reveal()
	_ready_button.grab_focus.call_deferred()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if OnlineMatch.countdown_changed.is_connected(_on_countdown_changed):
		OnlineMatch.countdown_changed.disconnect(_on_countdown_changed)


func _on_ready_pressed() -> void:
	OnlineMatch.set_local_intermission_ready(true)
	AudioDirector.play(&"ui_confirm")
	_refresh()


## Page tabs across the top on a thin ink header: text tabs with an amber underline for the open page,
## flanked by the keys that switch them (Q / E, LB / RB on a pad).
func _build_tab_bar() -> void:
	var header: Control = Control.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 58.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.draw.connect(func() -> void:
		header.draw_rect(Rect2(Vector2.ZERO, header.size), Color(0.0, 0.01, 0.012, 0.55))
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


## Same orders widget as in the match HUD, so quests read identically everywhere.
func _replace_quest_panel() -> void:
	var old_panel: Control = find_child("QuestPanel", true, false) as Control
	if old_panel == null:
		return
	var tracker: HudQuestTracker = HudQuestTracker.new()
	tracker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	old_panel.add_sibling(tracker)
	old_panel.queue_free()


func _key_hint(text: String) -> Control:
	var chip: Control = Control.new()
	chip.custom_minimum_size = Vector2(26.0, 40.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.draw.connect(func() -> void: LoadoutStyle.draw_key_chip(chip, Vector2(3.0, 11.0), "LB" if InputDevice.using_gamepad and text == "Q" else ("RB" if InputDevice.using_gamepad else text), 20.0))
	InputDevice.device_changed.connect(func(_pad: bool) -> void: chip.queue_redraw())
	return chip


## Counts each earnings line up in turn with coin ticks, then the total and the balance.
func _play_earnings_reveal() -> void:
	var earnings: Dictionary = OnlineMatch.get_last_set_earnings(_local_slot)
	var steps: Array = [
		[_damage_coins_label, int(earnings.get("damage_coins", 0))],
		[_survival_coins_label, int(earnings.get("survival_coins", 0))],
		[_blocking_coins_label, int(earnings.get("block_coins", 0))],
		[_first_hit_coins_label, int(earnings.get("first_hit_coins", 0))],
	]
	var earned: int = int(earnings.get("earned", 0))
	var balance: int = OnlineMatch.get_local_coin_balance()
	var start_balance: int = maxi(balance - earned, 0)
	_earnings_animating = true
	_spend_button.visible = false
	for step in steps:
		(step[0] as Label).text = "+0"
	_earned_total_label.text = "EARNED  +0"
	_coin_balance_label.text = "BALANCE  %d COINS" % start_balance
	var tween: Tween = create_tween()
	tween.tween_interval(0.35)
	for step in steps:
		var label: Label = step[0]
		var value: int = step[1]
		tween.tween_method(_set_coin_text.bind(label, "+%d"), 0.0, float(value), 0.28 if value > 0 else 0.08)
		tween.tween_callback(_tick_reward.bind(label, value > 0, false))
	tween.tween_interval(0.15)
	tween.tween_method(_set_coin_text.bind(_earned_total_label, "EARNED  +%d"), 0.0, float(earned), 0.45)
	tween.tween_callback(_tick_reward.bind(_earned_total_label, earned > 0, true))
	tween.tween_method(_set_coin_text.bind(_coin_balance_label, "BALANCE  %d COINS"), float(start_balance), float(balance), 0.45)
	tween.tween_callback(_finish_earnings_reveal)


func _set_coin_text(value: float, label: Label, format: String) -> void:
	label.text = format % int(round(value))


func _finish_earnings_reveal() -> void:
	_earnings_animating = false
	_update_spend_button(true)
	_refresh_earnings()


## Call to action under the earnings once the balance buys something, so the shop is never overlooked.
func _build_spend_button() -> void:
	_spend_button = Button.new()
	_spend_button.text = "SPEND COINS  ·  Q"
	_spend_button.custom_minimum_size = Vector2(260.0, 46.0)
	_spend_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.style_button(_spend_button, false, 17)
	_spend_button.pressed.connect(_set_page.bind(-1))
	_spend_button.visible = false
	_coin_balance_label.add_sibling(_spend_button)


func _update_spend_button(animate: bool) -> void:
	if _spend_button == null:
		return
	var affordable: bool = OnlineMatch.get_local_coin_balance() >= GameSettings.SHOP_MIN_PRICE
	var was_visible: bool = _spend_button.visible
	_spend_button.visible = affordable
	if affordable and animate and not was_visible:
		_spend_button.modulate.a = 0.0
		_spend_button.create_tween().tween_property(_spend_button, "modulate:a", 1.0, 0.3)


func _tick_reward(label: Label, rewarded: bool, big: bool) -> void:
	if not rewarded:
		return
	AudioDirector.play(&"reward" if big else &"coins", -6.0 if big else -10.0)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.25, 1.25) if big else Vector2(1.15, 1.15)
	label.create_tween().tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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


func _on_countdown_changed(_seconds_left: int) -> void:
	_refresh()


func _on_previous_page_pressed() -> void:
	_set_page(_page_index - 1)


func _on_next_page_pressed() -> void:
	_set_page(_page_index + 1)


func _refresh() -> void:
	var local_name: String = OnlineMatch.get_player_color_name(_local_slot)
	var remote_name: String = OnlineMatch.get_player_color_name(_remote_slot)
	if NetworkSession.is_bot_shop_duel():
		local_name = UiStyle.player_name(_local_slot)
		remote_name = UiStyle.player_name(_remote_slot)
	_title_label.text = "NEXT SET"
	_score_label.text = "%s %d - %d %s" % [
		local_name.to_upper(),
		int(OnlineMatch.match_points.get(_local_slot, 0)),
		int(OnlineMatch.match_points.get(_remote_slot, 0)),
		remote_name.to_upper(),
	]
	var seconds: int = int(ceil(OnlineMatch.intermission_remaining))
	if NetworkSession.is_bot_shop_duel():
		_countdown_label.text = "READY?"
		var ready_title: Label = find_child("ReadyTitle", true, false) as Label
		if ready_title != null:
			ready_title.text = "NO TIME LIMIT"
	else:
		_countdown_label.text = "%dS" % seconds
		_update_countdown_urgency(seconds)

	var local_ready: bool = OnlineMatch.intermission_ready.get(_local_slot, false) == true
	var remote_ready: bool = OnlineMatch.intermission_ready.get(_remote_slot, false) == true
	_style_ready_label(_local_ready_label, "YOU", local_ready)
	_style_ready_label(_remote_ready_label, remote_name.to_upper() if remote_name != "" else "OPPONENT", remote_ready)
	_ready_button.disabled = local_ready
	if local_ready and remote_ready:
		_ready_button.text = "STARTING"
	elif local_ready:
		_ready_button.text = "WAITING FOR OPPONENT"
	else:
		_ready_button.text = "READY UP"
	_refresh_earnings()


func _style_ready_label(label: Label, who: String, ready: bool) -> void:
	label.text = "%s   %s" % [who, "READY" if ready else "NOT READY"]
	label.add_theme_color_override("font_color", UiStyle.SUCCESS if ready else UiStyle.TEXT_DIM)


## The last seconds tick audibly and pulse red so nobody is surprised by the next set starting.
func _update_countdown_urgency(seconds: int) -> void:
	if seconds == _last_countdown:
		return
	_last_countdown = seconds
	var urgent: bool = seconds <= URGENT_SECONDS and seconds > 0
	_countdown_label.add_theme_color_override("font_color", UiStyle.DANGER.lightened(0.2) if urgent else Color(0.996, 0.976, 0.927))
	if not urgent:
		return
	AudioDirector.play(&"count_tick", -8.0)
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_label.pivot_offset = _countdown_label.size * 0.5
	_countdown_label.scale = Vector2(1.2, 1.2)
	_countdown_tween = create_tween()
	_countdown_tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_earnings() -> void:
	var earnings: Dictionary = OnlineMatch.get_last_set_earnings(_local_slot)
	var damage: int = int(earnings.get("damage", 0))
	var survival_seconds: int = int(earnings.get("survival_seconds", 0))
	var blocked_damage: int = int(earnings.get("blocked_damage", 0))
	var first_hit: bool = earnings.get("first_hit", false) == true
	_damage_earnings_label.text = "%d DAMAGE" % damage
	_survival_earnings_label.text = "%dS ALIVE" % survival_seconds
	_blocking_earnings_label.text = "%d BLOCKED" % blocked_damage
	_first_hit_earnings_label.text = "FIRST HIT" if first_hit else "NO FIRST HIT"
	if _earnings_animating:
		return
	_damage_coins_label.text = "+%d" % int(earnings.get("damage_coins", 0))
	_survival_coins_label.text = "+%d" % int(earnings.get("survival_coins", 0))
	_blocking_coins_label.text = "+%d" % int(earnings.get("block_coins", 0))
	_first_hit_coins_label.text = "+%d" % int(earnings.get("first_hit_coins", 0))
	_earned_total_label.text = "EARNED  +%d" % int(earnings.get("earned", 0))
	_coin_balance_label.text = "BALANCE  %d COINS" % OnlineMatch.get_local_coin_balance()
	_update_spend_button(false)


func _set_page(next_page: int) -> void:
	var previous: int = _page_index
	_page_index = clampi(next_page, -1, 1)
	_loadout_page.visible = _page_index == -1
	_status_page.visible = _page_index == 0
	_research_page.visible = _page_index == 1
	_left_page_button.visible = _page_index > -1
	_right_page_button.visible = _page_index < 1
	for index in range(_tab_buttons.size()):
		_tab_buttons[index].set_pressed_no_signal(index - 1 == _page_index)
	if previous == _page_index or not is_inside_tree():
		return
	AudioDirector.play(&"ui_whoosh", -8.0)
	var page: Control = [_loadout_page, _status_page, _research_page][_page_index + 1]
	page.modulate.a = 0.0
	page.position.x = 40.0 * signf(float(_page_index - previous))
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(page, "modulate:a", 1.0, 0.18)
	tween.tween_property(page, "position:x", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)



func _is_page_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
