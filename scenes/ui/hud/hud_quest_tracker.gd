class_name HudQuestTracker
extends Control

## Orders and research points, top left. In a match it stays one line: the research counter and a small
## progress bar per order in its tier colour. It opens into the full list only when there is something to
## read - when a set starts and when an order is completed or failed - then folds away again, so it never
## sits on the arena. TAB / Back pins it open (and folds it again); the pin outlasts the match. Completed orders send their points hopping into the
## counter. Outside a match (the intermission) it is always open.

const WIDTH: float = 284.0
const LINE_HEIGHT: float = 26.0
const ROW_HEIGHT: float = 26.0
const MINI_BAR: Vector2 = Vector2(30.0, 4.0)
const OPEN_ON_SET_START: float = 5.0
const OPEN_ON_RESULT: float = 3.2
const COMPLETE_COLOR: Color = UiStyle.SUCCESS
const FAILED_COLOR: Color = UiStyle.DANGER

## Shared by every tracker, so a list pinned open stays open into the next match.
static var pinned: bool = false

var always_open: bool = false

var _quests: Array[Dictionary] = []
var _states: Dictionary = {}
var _fills: Dictionary = {}
var _flashes: Dictionary = {}
var _open: float = 0.0
var _open_timer: float = 0.0
var _time: float = 0.0
var _reserved_points: int = 0
var _shown_points: int = 0
var _points_pop: float = 0.0
var _canvas: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(HudRewardFlight.COUNTER_GROUP)
	# Children are ready before the game joins its group, so look for the game among the ancestors.
	always_open = always_open or not _inside_match()
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tracker)
	add_child(_canvas)
	ResearchQuestManager.quests_changed.connect(_refresh)
	ResearchQuestManager.research_reward_awarded.connect(_on_reward_awarded)
	ResearchManager.research_points_changed.connect(_on_points_changed)
	_shown_points = ResearchManager.research_points
	_open = 1.0 if (always_open or pinned) else 0.0
	_refresh()
	if not always_open and not _quests.is_empty():
		_open_timer = OPEN_ON_SET_START


func _exit_tree() -> void:
	if ResearchQuestManager.quests_changed.is_connected(_refresh):
		ResearchQuestManager.quests_changed.disconnect(_refresh)
	if ResearchQuestManager.research_reward_awarded.is_connected(_on_reward_awarded):
		ResearchQuestManager.research_reward_awarded.disconnect(_on_reward_awarded)
	if ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.disconnect(_on_points_changed)


func _input(event: InputEvent) -> void:
	if always_open or not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var key: InputEventKey = event as InputEventKey
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if (key != null and key.keycode == KEY_TAB) or (pad != null and pad.button_index == JOY_BUTTON_BACK):
		pinned = not pinned
		# Folding by hand also drops a pending auto-open, otherwise the list would stay up.
		if not pinned:
			_open_timer = 0.0
		AudioDirector.play(&"ui_toggle", -10.0)
		get_viewport().set_input_as_handled()
		set_process(true)


func _refresh() -> void:
	var quests: Array[Dictionary] = ResearchQuestManager.get_local_quests()
	var was_empty: bool = _quests.is_empty()
	_quests = quests
	for quest in quests:
		var key: String = _key(quest)
		var progress: float = float(quest.get("progress", 0.0))
		var completed: bool = quest.get("completed", false) == true
		var failed: bool = quest.get("failed", false) == true
		var status: StringName = &"done" if completed else (&"failed" if failed else &"open")
		var previous: Dictionary = _states.get(key, {})
		if not previous.is_empty():
			if status == &"done" and previous.get("status") != &"done":
				_flashes[key] = 1.0
				_open_timer = maxf(_open_timer, OPEN_ON_RESULT)
				AudioDirector.play(&"coins", -6.0)
			elif status == &"failed" and previous.get("status") != &"failed":
				_flashes[key] = 0.8
				_open_timer = maxf(_open_timer, OPEN_ON_RESULT)
				AudioDirector.play(&"ui_error", -8.0)
			elif progress > float(previous.get("progress", 0.0)) and status == &"open":
				_flashes[key] = 0.6
		if not _fills.has(key):
			_fills[key] = _ratio(quest)
		_states[key] = {"status": status, "progress": progress}
	if was_empty and not quests.is_empty() and not always_open:
		_open_timer = OPEN_ON_SET_START
	_update_size()
	set_process(true)


func _key(quest: Dictionary) -> String:
	return "%s|%s" % [str(quest.get("id", "")), str(quest.get("title", ""))]


func _ratio(quest: Dictionary) -> float:
	var completed: bool = quest.get("completed", false) == true
	var failed: bool = quest.get("failed", false) == true
	var no_hit: bool = StringName(str(quest.get("event", ""))) == &"no_hit"
	if completed or (no_hit and not failed):
		return 1.0
	return clampf(float(quest.get("progress", 0.0)) / maxf(float(quest.get("target", 1.0)), 1.0), 0.0, 1.0)


func _update_size() -> void:
	var rows: int = maxi(_quests.size(), 1)
	var height: float = LINE_HEIGHT + 8.0 + float(rows) * ROW_HEIGHT
	custom_minimum_size = Vector2(WIDTH, height if always_open else LINE_HEIGHT)
	size = Vector2(WIDTH, height)
	_canvas.size = size


func _process(delta: float) -> void:
	_time += delta
	if not always_open:
		_open_timer = maxf(_open_timer - delta, 0.0)
		var target: float = 1.0 if (_open_timer > 0.0 or pinned) else 0.0
		_open = move_toward(_open, target, delta * (6.0 if target > 0.0 else 3.5))
	var busy: bool = _open > 0.0 and _open < 1.0
	for quest in _quests:
		var key: String = _key(quest)
		var fill: float = float(_fills.get(key, 0.0))
		var target_fill: float = _ratio(quest)
		if not is_equal_approx(fill, target_fill):
			_fills[key] = move_toward(fill, target_fill, delta * 1.6)
			busy = true
		if float(_flashes.get(key, 0.0)) > 0.0:
			_flashes[key] = maxf(float(_flashes[key]) - delta * 2.0, 0.0)
			busy = true
	_points_pop = move_toward(_points_pop, 0.0, delta * 3.0)
	_canvas.queue_redraw()
	if not busy and _points_pop <= 0.0 and _open_timer <= 0.0 and (_open == 0.0 or _open == 1.0):
		set_process(false)


# --- Research counter (target of HudRewardFlight) ---------------------------------------------------

func _on_points_changed(points: int) -> void:
	_shown_points = maxi(points - _reserved_points, 0)
	if _reserved_points == 0:
		_points_pop = 1.0
	set_process(true)


## Points that are still flying in are held back from the shown total.
func reserve_points(amount: int) -> void:
	_reserved_points += amount
	_on_points_changed(ResearchManager.research_points)


func release_points(amount: int) -> void:
	_reserved_points = maxi(_reserved_points - amount, 0)
	_shown_points = maxi(ResearchManager.research_points - _reserved_points, 0)
	_points_pop = 1.0
	set_process(true)


func get_points_target() -> Vector2:
	return get_global_transform_with_canvas() * Vector2(10.0, LINE_HEIGHT * 0.5)


## An order's reward hops from its row into the counter.
func _on_reward_awarded(amount: int, reason: String) -> void:
	for index in range(_quests.size()):
		if str(_quests[index].get("title", "")) != reason:
			continue
		var row_y: float = LINE_HEIGHT + 8.0 + float(index) * ROW_HEIGHT + ROW_HEIGHT * 0.45
		var from: Vector2 = get_global_transform_with_canvas() * Vector2(WIDTH - 18.0, row_y)
		HudRewardFlight.launch_from_screen(from, amount)
		return


# --- Drawing -----------------------------------------------------------------------------------------

func _draw_tracker() -> void:
	var open: float = _open * _open * (3.0 - 2.0 * _open)
	var rows_height: float = float(maxi(_quests.size(), 1)) * ROW_HEIGHT
	var shadow_height: float = LINE_HEIGHT + (8.0 + rows_height) * open
	LoadoutStyle.draw_glow(_canvas, Vector2(WIDTH * 0.32, shadow_height * 0.5), Vector2(WIDTH * 0.85, shadow_height * 0.5 + 26.0), Color(0.0, 0.012, 0.016, 0.42 + 0.12 * open), 40)
	_draw_counter()
	if open <= 0.01:
		return
	if _quests.is_empty():
		var hint_alpha: float = open
		_canvas.draw_string_outline(UiStyle.FONT_BODY, Vector2(0.0, LINE_HEIGHT + 22.0), "No orders yet", HORIZONTAL_ALIGNMENT_LEFT, WIDTH, 13, 3, Color(0, 0, 0, 0.6 * hint_alpha))
		_canvas.draw_string(UiStyle.FONT_BODY, Vector2(0.0, LINE_HEIGHT + 22.0), "No orders yet", HORIZONTAL_ALIGNMENT_LEFT, WIDTH, 13, LoadoutStyle.with_alpha(UiStyle.TEXT_DIM, hint_alpha))
		return
	for index in range(_quests.size()):
		var row_open: float = clampf(open * 1.6 - float(index) * 0.25, 0.0, 1.0)
		if row_open <= 0.0:
			continue
		_draw_row(_quests[index], LINE_HEIGHT + 8.0 + float(index) * ROW_HEIGHT - (1.0 - row_open) * 6.0, row_open)


## The always-visible line: research counter and one mini bar per order.
func _draw_counter() -> void:
	var pop: float = sin(_points_pop * PI) * 0.18
	var center: Vector2 = Vector2(10.0, LINE_HEIGHT * 0.5)
	ResearchNodeButton.draw_rp_glyph(_canvas, center, 9.0 * (1.0 + pop), Color(0.0, 0.0, 0.0, 0.6))
	ResearchNodeButton.draw_rp_glyph(_canvas, center, 7.0 * (1.0 + pop), UiStyle.INTEL)
	var text: String = str(_shown_points)
	var color: Color = UiStyle.INTEL.lerp(Color.WHITE, _points_pop * 0.6)
	_canvas.draw_string_outline(UiStyle.FONT_DISPLAY, Vector2(23.0, LINE_HEIGHT * 0.5 + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.65))
	_canvas.draw_string(UiStyle.FONT_DISPLAY, Vector2(23.0, LINE_HEIGHT * 0.5 + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
	var x: float = 23.0 + UiStyle.FONT_DISPLAY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 14.0
	for quest in _quests:
		var key: String = _key(quest)
		var status: StringName = _states.get(key, {}).get("status", &"open")
		var bar: Rect2 = Rect2(Vector2(x, LINE_HEIGHT * 0.5 - MINI_BAR.y * 0.5), MINI_BAR)
		var flash: float = float(_flashes.get(key, 0.0))
		_canvas.draw_rect(bar.grow(1.5), Color(0.0, 0.0, 0.0, 0.6))
		_canvas.draw_rect(bar, Color(1, 1, 1, 0.14))
		var fill_color: Color = COMPLETE_COLOR if status == &"done" else (FAILED_COLOR if status == &"failed" else UiStyle.TEXT)
		var fill: float = 1.0 if status == &"failed" else float(_fills.get(key, 0.0))
		_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), fill_color.lerp(Color.WHITE, flash * 0.6))
		x += MINI_BAR.x + 6.0
	if not always_open and not _quests.is_empty():
		LoadoutStyle.draw_key_chip(_canvas, Vector2(x + 6.0, LINE_HEIGHT * 0.5 - 8.0), "BACK" if InputDevice.using_gamepad else "TAB", 16.0, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, 0.5 + 0.5 * (1.0 - _open)))


func _draw_row(quest: Dictionary, y: float, alpha: float) -> void:
	var key: String = _key(quest)
	var status: StringName = _states.get(key, {}).get("status", &"open")
	var flash: float = float(_flashes.get(key, 0.0))
	var accent: Color = COMPLETE_COLOR if status == &"done" else (FAILED_COLOR if status == &"failed" else UiStyle.TEXT)
	if flash > 0.0:
		_canvas.draw_rect(Rect2(-4.0, y - 2.0, WIDTH + 8.0, ROW_HEIGHT - 2.0), LoadoutStyle.with_alpha(accent, flash * 0.18 * alpha))
	var title: String = str(quest.get("title", ""))
	var title_color: Color = COMPLETE_COLOR.lightened(0.3) if status == &"done" else (UiStyle.TEXT_MUTED if status == &"failed" else UiStyle.TEXT)
	_canvas.draw_string_outline(UiStyle.FONT_UI, Vector2(10.0, y + 14.0), title, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 96.0, 13, 3, Color(0, 0, 0, 0.6 * alpha))
	_canvas.draw_string(UiStyle.FONT_UI, Vector2(10.0, y + 14.0), title, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 96.0, 13, LoadoutStyle.with_alpha(title_color, alpha))
	if status == &"failed":
		var width: float = minf(UiStyle.FONT_UI.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, WIDTH - 96.0)
		_canvas.draw_line(Vector2(10.0, y + 9.5), Vector2(10.0 + width, y + 9.5), LoadoutStyle.with_alpha(FAILED_COLOR, 0.7 * alpha), 1.5)
	var no_hit: bool = StringName(str(quest.get("event", ""))) == &"no_hit"
	var progress_text: String = "DONE" if status == &"done" else ("FAILED" if status == &"failed" else ("SAFE" if no_hit else "%d/%d" % [int(floor(float(quest.get("progress", 0.0)))), int(maxf(float(quest.get("target", 1.0)), 1.0))]))
	var progress_color: Color = COMPLETE_COLOR if status == &"done" else (FAILED_COLOR if status == &"failed" else UiStyle.TEXT_DIM)
	_canvas.draw_string_outline(UiStyle.FONT_BOLD, Vector2(WIDTH - 86.0, y + 14.0), progress_text, HORIZONTAL_ALIGNMENT_RIGHT, 44.0, 11, 3, Color(0, 0, 0, 0.6 * alpha))
	_canvas.draw_string(UiStyle.FONT_BOLD, Vector2(WIDTH - 86.0, y + 14.0), progress_text, HORIZONTAL_ALIGNMENT_RIGHT, 44.0, 11, LoadoutStyle.with_alpha(progress_color, alpha))
	var reward: String = "+%d" % int(quest.get("reward", 0))
	ResearchNodeButton.draw_rp_glyph(_canvas, Vector2(WIDTH - 30.0, y + 10.0), 4.5, LoadoutStyle.with_alpha(UiStyle.INTEL, alpha))
	_canvas.draw_string_outline(UiStyle.FONT_BOLD, Vector2(WIDTH - 22.0, y + 14.0), reward, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.6 * alpha))
	_canvas.draw_string(UiStyle.FONT_BOLD, Vector2(WIDTH - 22.0, y + 14.0), reward, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LoadoutStyle.with_alpha(UiStyle.INTEL, alpha))
	var bar: Rect2 = Rect2(10.0, y + 19.0, WIDTH - 96.0, 2.0)
	_canvas.draw_rect(bar, Color(1, 1, 1, 0.08 * alpha))
	var fill: float = 1.0 if status == &"failed" else float(_fills.get(key, 0.0))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), LoadoutStyle.with_alpha(accent, 0.9 * alpha))


func _inside_match() -> bool:
	var node: Node = get_parent()
	while node != null:
		if node is Game:
			return true
		node = node.get_parent()
	return false
