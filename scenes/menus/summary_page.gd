extends Control
class_name SummaryPage

## The set summary between sets, in the frame the loadout and research pages share (see LoadoutStyle): the
## score and the coin ledger of the last set on the left, the dock on the right with the countdown, who is
## ready, the orders and the Ready Up button where the research page has Hold to Research. The ledger counts
## up line by line with coin ticks when the page opens; once the balance buys something, a Spend button
## points to the shop.

signal spend_requested

const URGENT_SECONDS: int = 5
const LEFT: float = 48.0
const ROW_HEIGHT: float = 38.0
const SCORE_TOP: float = 30.0
const LEDGER_TOP: float = 198.0
const DOCK_WIDTH: float = LoadoutStyle.DOCK_WIDTH
const DOCK_PAD: float = LoadoutStyle.DOCK_PAD

var _top_inset: float = 0.0
var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _content: Control = null
var _dock: Control = null
var _ready_button: Button = null
var _spend_button: Button = null
var _tracker: HudQuestTracker = null
var _prompt_bar: UiPromptBar = null
## Ledger lines: {"label", "detail", "coins", "shown", "pop"}; "shown" counts up during the reveal.
var _rows: Array[Dictionary] = []
var _earned: int = 0
var _shown_earned: float = 0.0
var _earned_pop: float = 0.0
var _shown_balance: float = 0.0
var _revealing: bool = false
var _last_countdown: int = -1
var _countdown_pop: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_build()
	resized.connect(_layout)
	OnlineMatch.state_changed.connect(_refresh)
	OnlineMatch.countdown_changed.connect(_on_countdown_changed)
	InputDevice.device_changed.connect(func(_pad: bool) -> void: _prompt_bar.set_prompts(_prompts()))
	_layout()
	_load_ledger()
	_refresh()
	_play_reveal()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if OnlineMatch.countdown_changed.is_connected(_on_countdown_changed):
		OnlineMatch.countdown_changed.disconnect(_on_countdown_changed)


## Leaves room above the page for the intermission tab bar.
func set_top_inset(pixels: float) -> void:
	_top_inset = pixels
	_layout()


func focus_default() -> void:
	if _ready_button != null and not _ready_button.disabled:
		_ready_button.grab_focus()


func _build() -> void:
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	add_child(_content)

	_spend_button = Button.new()
	_spend_button.text = "SPEND COINS  ·  Q"
	_spend_button.custom_minimum_size = Vector2(0.0, 40.0)
	UiStyle.style_button(_spend_button, false, 15)
	_spend_button.pressed.connect(func() -> void: spend_requested.emit())
	_spend_button.visible = false
	_content.add_child(_spend_button)

	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.draw.connect(_draw_dock)
	add_child(_dock)
	# Same orders widget as in the match HUD, so orders read identically everywhere.
	_tracker = HudQuestTracker.new()
	_tracker.always_open = true
	_dock.add_child(_tracker)
	_ready_button = Button.new()
	_ready_button.text = "READY UP"
	UiStyle.style_button(_ready_button, true, 18)
	# Focus is how a pad reaches the button, not a state: it keeps the same amber as Hold to Research.
	_ready_button.add_theme_stylebox_override("focus", _ready_button.get_theme_stylebox("normal"))
	_ready_button.pressed.connect(_on_ready_pressed)
	_dock.add_child(_ready_button)

	_prompt_bar = UiPromptBar.new()
	add_child(_prompt_bar)
	_prompt_bar.set_prompts(_prompts())


func _layout() -> void:
	if _content == null:
		return
	var top: float = _top_inset
	_content.position = Vector2(0.0, top)
	_content.size = Vector2(size.x - DOCK_WIDTH, size.y - top)
	_dock.position = Vector2(size.x - DOCK_WIDTH, top)
	_dock.size = Vector2(DOCK_WIDTH, size.y - top)
	# The tracker insets its own rows by 10 px (HUD layout); pull it back onto the dock's text edge.
	_tracker.position = Vector2(DOCK_PAD - 10.0, 222.0)
	_ready_button.position = Vector2(DOCK_PAD, _dock.size.y - 96.0)
	_ready_button.size = Vector2(DOCK_WIDTH - DOCK_PAD * 2.0, 48.0)
	_spend_button.size = Vector2(210.0, 40.0)
	_spend_button.position = Vector2(_content.size.x - LEFT - _spend_button.size.x, _balance_top() + 12.0)
	_prompt_bar.position = Vector2(LEFT, size.y - 42.0)
	_prompt_bar.size = Vector2(size.x - DOCK_WIDTH - 72.0, 22.0)
	_content.queue_redraw()
	_dock.queue_redraw()


func _prompts() -> Array:
	if InputDevice.using_gamepad:
		return [["A", "Ready"], ["LB RB", "Pages"]]
	return [["ENTER", "Ready"], ["Q E", "Pages"]]


# --- State -----------------------------------------------------------------------------------------------

func _load_ledger() -> void:
	var earnings: Dictionary = OnlineMatch.get_last_set_earnings(_local_slot)
	var first_hit: bool = earnings.get("first_hit", false) == true
	_rows = [
		_row("Damage dealt", str(int(earnings.get("damage", 0))), int(earnings.get("damage_coins", 0))),
		_row("Time alive", "%ds" % int(earnings.get("survival_seconds", 0)), int(earnings.get("survival_coins", 0))),
		_row("Damage blocked", str(int(earnings.get("blocked_damage", 0))), int(earnings.get("block_coins", 0))),
		_row("First hit", "Yes" if first_hit else "—", int(earnings.get("first_hit_coins", 0))),
	]
	var interest: int = int(earnings.get("interest_bonus", 0))
	if interest > 0:
		_rows.append(_row("Interest", "Research", interest))
	_earned = int(earnings.get("earned", 0))


func _row(label: String, detail: String, coins: int) -> Dictionary:
	return {"label": label, "detail": detail, "coins": coins, "shown": float(coins), "pop": 0.0}


func _refresh() -> void:
	var local_ready: bool = OnlineMatch.intermission_ready.get(_local_slot, false) == true
	var remote_ready: bool = OnlineMatch.intermission_ready.get(_remote_slot, false) == true
	_ready_button.disabled = local_ready
	if local_ready and remote_ready:
		_ready_button.text = "STARTING"
	elif local_ready:
		_ready_button.text = "WAITING FOR %s" % _name(_remote_slot)
	else:
		_ready_button.text = "READY UP"
	if not NetworkSession.is_bot_shop_duel():
		_update_countdown_urgency(int(ceil(OnlineMatch.intermission_remaining)))
	if not _revealing:
		_shown_balance = float(OnlineMatch.get_local_coin_balance())
		_update_spend_button(false)
	_content.queue_redraw()
	_dock.queue_redraw()


func _on_countdown_changed(_seconds_left: int) -> void:
	_refresh()


func _on_ready_pressed() -> void:
	OnlineMatch.set_local_intermission_ready(true)
	AudioDirector.play(&"ui_confirm")
	_refresh()


func _name(slot: int) -> String:
	if NetworkSession.is_bot_shop_duel():
		return UiStyle.player_name(slot)
	var color_name: String = OnlineMatch.get_player_color_name(slot)
	return color_name.to_upper() if color_name != "" else ("YOU" if slot == _local_slot else "OPPONENT")


## The last seconds tick audibly and pulse red so nobody is surprised by the next set starting.
func _update_countdown_urgency(seconds: int) -> void:
	if seconds == _last_countdown:
		return
	_last_countdown = seconds
	if seconds > URGENT_SECONDS or seconds <= 0:
		return
	AudioDirector.play(&"count_tick", -8.0)
	_countdown_pop = 1.0
	set_process(true)


func _update_spend_button(animate: bool) -> void:
	var affordable: bool = OnlineMatch.get_local_coin_balance() >= GameSettings.SHOP_MIN_PRICE
	var was_visible: bool = _spend_button.visible
	_spend_button.visible = affordable
	if affordable and animate and not was_visible:
		_spend_button.modulate.a = 0.0
		_spend_button.create_tween().tween_property(_spend_button, "modulate:a", 1.0, 0.3)


# --- Reveal ----------------------------------------------------------------------------------------------

## Counts each ledger line up in turn with coin ticks, then the total and the balance.
func _play_reveal() -> void:
	var balance: int = OnlineMatch.get_local_coin_balance()
	_shown_balance = float(maxi(balance - _earned, 0))
	_shown_earned = 0.0
	for row in _rows:
		row["shown"] = 0.0
	_revealing = true
	_spend_button.visible = false
	var tween: Tween = create_tween()
	tween.tween_interval(0.35)
	for index in range(_rows.size()):
		var coins: int = int(_rows[index]["coins"])
		tween.tween_method(func(value: float) -> void:
			_rows[index]["shown"] = value
			_content.queue_redraw(), 0.0, float(coins), 0.28 if coins > 0 else 0.08)
		tween.tween_callback(func() -> void:
			if coins > 0:
				_rows[index]["pop"] = 1.0
				AudioDirector.play(&"coins", -10.0)
				set_process(true))
	tween.tween_interval(0.15)
	tween.tween_method(func(value: float) -> void:
		_shown_earned = value
		_content.queue_redraw(), 0.0, float(_earned), 0.45)
	tween.tween_callback(func() -> void:
		if _earned > 0:
			_earned_pop = 1.0
			AudioDirector.play(&"reward", -6.0)
			set_process(true))
	tween.tween_method(func(value: float) -> void:
		_shown_balance = value
		_content.queue_redraw(), _shown_balance, float(balance), 0.45)
	tween.tween_callback(func() -> void:
		_revealing = false
		_update_spend_button(true)
		_refresh())


func _process(delta: float) -> void:
	var busy: bool = false
	for row in _rows:
		row["pop"] = move_toward(float(row["pop"]), 0.0, delta * 4.0)
		busy = busy or float(row["pop"]) > 0.0
	_earned_pop = move_toward(_earned_pop, 0.0, delta * 4.0)
	_countdown_pop = move_toward(_countdown_pop, 0.0, delta * 2.5)
	_content.queue_redraw()
	_dock.queue_redraw()
	if not busy and _earned_pop <= 0.0 and _countdown_pop <= 0.0:
		set_process(false)


# --- Drawing ---------------------------------------------------------------------------------------------

func _ledger_bottom() -> float:
	return LEDGER_TOP + 30.0 + float(maxi(_rows.size(), 4)) * ROW_HEIGHT


func _balance_top() -> float:
	return _ledger_bottom() + 78.0


func _draw_content() -> void:
	var width: float = _content.size.x - LEFT * 2.0
	_draw_score(width)

	LoadoutStyle.draw_eyebrow(_content, LEFT, LEDGER_TOP, width, "SET EARNINGS")
	var y: float = LEDGER_TOP + 30.0
	for row in _rows:
		var coins: int = int(row["coins"])
		var center: float = y + ROW_HEIGHT * 0.5
		_content.draw_string(UiStyle.FONT_UI, Vector2(LEFT, center + 5.0), str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, LoadoutStyle.TEXT)
		_content.draw_string(UiStyle.FONT_BOLD, Vector2(LEFT + 210.0, center + 5.0), str(row["detail"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LoadoutStyle.TEXT_SECONDARY)
		_draw_coins(Vector2(LEFT + width, center), "+%d" % int(roundf(float(row["shown"]))), 17, 1.0 + 0.18 * sin(float(row["pop"]) * PI), coins > 0 and float(row["shown"]) > 0.5)
		_content.draw_line(Vector2(LEFT, y + ROW_HEIGHT), Vector2(LEFT + width, y + ROW_HEIGHT), LoadoutStyle.EDGE_SOFT, 1.0)
		y += ROW_HEIGHT
	var total_y: float = _ledger_bottom() + 28.0
	_content.draw_string(UiStyle.FONT_BOLD, Vector2(LEFT, total_y + 5.0), "EARNED THIS SET", HORIZONTAL_ALIGNMENT_LEFT, -1, LoadoutStyle.EYEBROW_SIZE, LoadoutStyle.TEXT_SECONDARY)
	_draw_coins(Vector2(LEFT + width, total_y), "+%d" % int(roundf(_shown_earned)), 22, 1.0 + 0.22 * sin(_earned_pop * PI), _earned > 0 and _shown_earned > 0.5)

	var balance_top: float = _balance_top()
	LoadoutStyle.draw_eyebrow(_content, LEFT, balance_top, width, "BALANCE")
	var balance_text: String = str(int(roundf(_shown_balance)))
	LoadoutStyle.draw_coin(_content, Vector2(LEFT + 13.0, balance_top + 38.0), 12.0)
	_content.draw_string(UiStyle.FONT_DISPLAY, Vector2(LEFT + 34.0, balance_top + 52.0), balance_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, LoadoutStyle.COIN)
	var number_width: float = UiStyle.FONT_DISPLAY.get_string_size(balance_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	_content.draw_string(UiStyle.FONT_BOLD, Vector2(LEFT + 42.0 + number_width, balance_top + 50.0), "COINS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LoadoutStyle.TEXT_SECONDARY)


## Sets won so far, each player under their own colour, with one pip per set up to the match target.
func _draw_score(width: float) -> void:
	var target: int = GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN
	LoadoutStyle.draw_eyebrow(_content, LEFT, SCORE_TOP, width, "SETS", "FIRST TO %d" % target)
	var sides: Array = [[_local_slot, LEFT], [_remote_slot, LEFT + 132.0]]
	for side in sides:
		var slot: int = side[0]
		var x: float = side[1]
		var points: int = int(OnlineMatch.match_points.get(slot, 0))
		var color: Color = UiStyle.player_color(slot)
		_content.draw_string(UiStyle.FONT_BOLD, Vector2(x, SCORE_TOP + 36.0), _name(slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
		_content.draw_string(UiStyle.FONT_DISPLAY, Vector2(x - 3.0, SCORE_TOP + 100.0), str(points), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, LoadoutStyle.TEXT)
		for pip in range(target):
			var rect: Rect2 = Rect2(Vector2(x + float(pip) * 18.0, SCORE_TOP + 114.0), Vector2(13.0, 4.0))
			_content.draw_rect(rect, color if pip < points else Color(1, 1, 1, 0.1))
	_content.draw_string(UiStyle.FONT_DISPLAY, Vector2(LEFT + 66.0, SCORE_TOP + 92.0), "–", HORIZONTAL_ALIGNMENT_CENTER, 52.0, 40, LoadoutStyle.TEXT_MUTED)


## A coin amount right-aligned at `anchor`, the coin glyph before it; muted when nothing was earned.
func _draw_coins(anchor: Vector2, text: String, font_size: int, scale_factor: float, earned: bool) -> void:
	var size_px: int = int(roundf(float(font_size) * scale_factor))
	var color: Color = LoadoutStyle.COIN if earned else LoadoutStyle.TEXT_MUTED
	var text_width: float = UiStyle.FONT_DISPLAY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_content.draw_string(UiStyle.FONT_DISPLAY, Vector2(anchor.x - text_width, anchor.y + float(size_px) * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
	LoadoutStyle.draw_coin(_content, Vector2(anchor.x - text_width - 12.0, anchor.y), float(size_px) * 0.3, color)


func _draw_dock() -> void:
	var w: float = _dock.size.x
	var x: float = DOCK_PAD
	var inner: float = w - DOCK_PAD * 2.0
	_dock.draw_rect(Rect2(Vector2.ZERO, _dock.size), LoadoutStyle.DOCK)
	_dock.draw_line(Vector2(0.5, 0.0), Vector2(0.5, _dock.size.y), LoadoutStyle.HAIRLINE, 1.0)

	var untimed: bool = NetworkSession.is_bot_shop_duel()
	LoadoutStyle.draw_eyebrow(_dock, x, 30.0, inner, "NEXT SET", "NO TIME LIMIT" if untimed else "")
	if untimed:
		_dock.draw_string(UiStyle.FONT_DISPLAY, Vector2(x, 82.0), "WHEN READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, LoadoutStyle.TEXT)
	else:
		var seconds: int = int(ceil(OnlineMatch.intermission_remaining))
		var urgent: bool = seconds <= URGENT_SECONDS and seconds > 0
		var size_px: int = int(roundf(52.0 * (1.0 + 0.2 * _countdown_pop)))
		var color: Color = UiStyle.DANGER.lightened(0.2) if urgent else LoadoutStyle.TEXT
		_dock.draw_string(UiStyle.FONT_DISPLAY, Vector2(x - 2.0, 94.0), str(seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
		var number_width: float = UiStyle.FONT_DISPLAY.get_string_size(str(seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x + number_width + 6.0, 92.0), "SEC", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LoadoutStyle.TEXT_SECONDARY)

	LoadoutStyle.draw_eyebrow(_dock, x, 128.0, inner, "READY CHECK")
	var y: float = 158.0
	for slot in [_local_slot, _remote_slot]:
		var ready: bool = OnlineMatch.intermission_ready.get(slot, false) == true
		_dock.draw_circle(Vector2(x + 4.0, y - 4.0), 4.0, UiStyle.player_color(slot), true, -1.0, true)
		_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x + 18.0, y), _name(slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LoadoutStyle.TEXT)
		_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, y), "READY" if ready else "NOT READY", HORIZONTAL_ALIGNMENT_RIGHT, inner, 12, UiStyle.SUCCESS if ready else LoadoutStyle.TEXT_MUTED)
		y += 26.0
	LoadoutStyle.draw_eyebrow(_dock, x, 212.0, inner, "ORDERS")
