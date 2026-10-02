class_name HudQuestTracker
extends Control

## In-match orders: up to three quests with tier colour, animated progress bar, progress readout and
## reward chip. Progress ticks flash the row, completion turns it green with a reward pop and toast,
## failure strikes it through. Shows a clear hint while no orders are assigned yet.

const WIDTH: float = 300.0
const HEADER_HEIGHT: float = 30.0
const ROW_HEIGHT: float = 42.0
const ROW_GAP: float = 4.0
const BAR_HEIGHT: float = 4.0
const COMPLETE_COLOR: Color = Color(0.49, 0.92, 0.58)
const FAILED_COLOR: Color = Color(1.0, 0.38, 0.3)

var _rows: Array[Dictionary] = []
var _states: Dictionary = {}
var _header: Control = null
var _title: Label = null
var _points: Label = null
var _empty: Label = null
var _background: Control = null
var _reserved_points: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(HudRewardFlight.COUNTER_GROUP)
	_background = Control.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.draw.connect(_draw_background)
	add_child(_background)
	_title = _label(UiStyle.FONT_DISPLAY, 15, UiStyle.ACCENT, Vector2(14.0, 7.0), Vector2(150.0, 20.0))
	_title.text = "ORDERS"
	_points = _label(UiStyle.FONT_BOLD, 13, UiStyle.TEXT, Vector2(WIDTH - 124.0, 9.0), Vector2(110.0, 18.0))
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points.pivot_offset = Vector2(110.0, 9.0)
	_empty = _label(UiStyle.FONT_BODY, 13, UiStyle.TEXT_DIM, Vector2(14.0, HEADER_HEIGHT + 4.0), Vector2(WIDTH - 28.0, 36.0))
	_empty.text = "Orders arrive after the first set.\nComplete them to earn research points."
	for index in range(3):
		_rows.append(_build_row(index))
	if not ResearchQuestManager.quests_changed.is_connected(_refresh):
		ResearchQuestManager.quests_changed.connect(_refresh)
	if not ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.connect(_on_points_changed)
	_on_points_changed(ResearchManager.research_points, false)
	_refresh()


func _exit_tree() -> void:
	if ResearchQuestManager.quests_changed.is_connected(_refresh):
		ResearchQuestManager.quests_changed.disconnect(_refresh)
	if ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.disconnect(_on_points_changed)


func _label(font: Font, font_size: int, color: Color, at: Vector2, label_size: Vector2, parent: Node = null) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.style_label(label, font, font_size, color)
	label.position = at
	label.size = label_size
	label.clip_text = true
	(parent if parent != null else self).add_child(label)
	return label


func _build_row(index: int) -> Dictionary:
	var row: Control = Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size = Vector2(WIDTH - 16.0, ROW_HEIGHT)
	row.position = Vector2(8.0, HEADER_HEIGHT + float(index) * (ROW_HEIGHT + ROW_GAP))
	row.pivot_offset = row.size * 0.5
	add_child(row)
	var entry: Dictionary = {"node": row, "fill": 0.0, "fill_target": 0.0, "flash": 0.0, "color": UiStyle.TEXT_DIM, "status": &"open", "key": ""}
	row.draw.connect(_draw_row.bind(entry))
	entry["title"] = _label(UiStyle.FONT_UI, 14, UiStyle.TEXT, Vector2(12.0, 4.0), Vector2(row.size.x - 70.0, 20.0), row)
	var progress: Label = _label(UiStyle.FONT_BOLD, 12, UiStyle.TEXT_DIM, Vector2(row.size.x - 62.0, 23.0), Vector2(56.0, 16.0), row)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.pivot_offset = Vector2(56.0, 8.0)
	entry["progress"] = progress
	var reward: Label = _label(UiStyle.FONT_BOLD, 11, UiStyle.ACCENT, Vector2(row.size.x - 52.0, 5.0), Vector2(46.0, 16.0), row)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.pivot_offset = Vector2(23.0, 8.0)
	entry["reward"] = reward
	return entry


func _process(delta: float) -> void:
	for entry in _rows:
		var row: Control = entry["node"]
		if not row.visible:
			continue
		var dirty: bool = false
		var fill: float = entry["fill"]
		var target: float = entry["fill_target"]
		if not is_equal_approx(fill, target):
			fill = move_toward(fill, target, delta * 1.6)
			entry["fill"] = fill
			dirty = true
		var flash: float = entry["flash"]
		if flash > 0.0:
			entry["flash"] = maxf(flash - delta * 2.4, 0.0)
			dirty = true
		if dirty:
			row.queue_redraw()


func _refresh() -> void:
	var quests: Array[Dictionary] = ResearchQuestManager.get_local_quests()
	_empty.visible = quests.is_empty()
	for index in range(_rows.size()):
		var entry: Dictionary = _rows[index]
		var row: Control = entry["node"]
		if index >= quests.size():
			row.visible = false
			entry["key"] = ""
			continue
		row.visible = true
		_apply_quest(entry, quests[index])
	var visible_rows: int = mini(quests.size(), _rows.size())
	var body_height: float = 40.0 if quests.is_empty() else float(visible_rows) * (ROW_HEIGHT + ROW_GAP)
	size = Vector2(WIDTH, HEADER_HEIGHT + body_height + 6.0)
	custom_minimum_size = size
	_background.size = size
	_background.queue_redraw()


func _apply_quest(entry: Dictionary, quest: Dictionary) -> void:
	var key: String = "%s|%s" % [str(quest.get("id", "")), str(quest.get("title", ""))]
	var progress: float = float(quest.get("progress", 0.0))
	var target: float = maxf(float(quest.get("target", 1.0)), 1.0)
	var completed: bool = quest.get("completed", false) == true
	var failed: bool = quest.get("failed", false) == true
	var status: StringName = &"done" if completed else (&"failed" if failed else &"open")
	var is_new: bool = key != entry["key"]
	var previous: Dictionary = _states.get(key, {})
	var tier_color: Color = _tier_color(StringName(str(quest.get("tier", ""))))
	entry["key"] = key
	entry["color"] = tier_color
	var title: Label = entry["title"]
	var progress_label: Label = entry["progress"]
	var reward_label: Label = entry["reward"]
	title.text = str(quest.get("title", ""))
	reward_label.text = "+%d RP" % int(quest.get("reward", 0))
	var no_hit: bool = StringName(str(quest.get("event", ""))) == &"no_hit"
	var ratio: float = 1.0 if completed or (no_hit and not failed) else clampf(progress / target, 0.0, 1.0)
	entry["fill_target"] = ratio
	if is_new:
		entry["fill"] = ratio
	match status:
		&"done":
			progress_label.text = "DONE"
			progress_label.add_theme_color_override("font_color", COMPLETE_COLOR)
			title.add_theme_color_override("font_color", COMPLETE_COLOR.lightened(0.3))
		&"failed":
			progress_label.text = "FAILED"
			progress_label.add_theme_color_override("font_color", FAILED_COLOR)
			title.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
		_:
			progress_label.text = "SAFE" if no_hit else "%d/%d" % [int(floor(progress)), int(target)]
			progress_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
			title.add_theme_color_override("font_color", UiStyle.TEXT)
	if not is_new and not previous.is_empty():
		if status == &"done" and previous.get("status") != &"done":
			_celebrate(entry, quest)
		elif status == &"failed" and previous.get("status") != &"failed":
			entry["flash"] = 0.6
			AudioDirector.play(&"ui_error", -6.0)
		elif progress > float(previous.get("progress", 0.0)) and status == &"open":
			entry["flash"] = 0.7
			_pop(progress_label, 1.35)
			AudioDirector.play(&"ui_toggle", -10.0, 1.3)
	entry["status"] = status
	_states[key] = {"status": status, "progress": progress}
	(entry["node"] as Control).queue_redraw()


func _celebrate(entry: Dictionary, quest: Dictionary) -> void:
	entry["flash"] = 1.0
	var row: Control = entry["node"]
	row.scale = Vector2(1.06, 1.06)
	row.create_tween().set_ignore_time_scale(true).tween_property(row, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop(entry["reward"], 1.6)
	AudioDirector.play(&"coins", -4.0)
	HudToasts.notify("ORDER COMPLETE", "%s  ·  +%d RP" % [str(quest.get("title", "")), int(quest.get("reward", 0))], COMPLETE_COLOR, &"")


func _pop(label: Label, amount: float) -> void:
	label.scale = Vector2(amount, amount)
	label.create_tween().set_ignore_time_scale(true).tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_points_changed(points: int, animate: bool = true) -> void:
	_points.text = "%d RP" % maxi(points - _reserved_points, 0)
	if animate and _reserved_points == 0:
		_pop(_points, 1.3)


## Points that are still flying in (HudRewardFlight) are held back from the shown total.
func reserve_points(amount: int) -> void:
	_reserved_points += amount
	_on_points_changed(ResearchManager.research_points, false)


func release_points(amount: int) -> void:
	_reserved_points = maxi(_reserved_points - amount, 0)
	_on_points_changed(ResearchManager.research_points, false)
	_pop(_points, 1.25)


func get_points_target() -> Vector2:
	return _points.get_global_rect().get_center()


func _draw_background() -> void:
	var w: float = size.x
	var h: float = size.y
	_background.draw_rect(Rect2(0.0, 0.0, w, h), Color(UiStyle.PANEL.r, UiStyle.PANEL.g, UiStyle.PANEL.b, 0.78))
	_background.draw_rect(Rect2(0.0, 0.0, w, 2.0), UiStyle.ACCENT)
	_background.draw_rect(Rect2(0.0, 0.0, w, h), UiStyle.LINE, false, 1.0)


func _draw_row(entry: Dictionary) -> void:
	var row: Control = entry["node"]
	var w: float = row.size.x
	var color: Color = entry["color"]
	var status: StringName = entry["status"]
	var accent: Color = COMPLETE_COLOR if status == &"done" else (FAILED_COLOR if status == &"failed" else color)
	var base_alpha: float = 0.16 if status == &"done" else 0.07
	row.draw_rect(Rect2(0.0, 0.0, w, ROW_HEIGHT), Color(accent.r, accent.g, accent.b, base_alpha + float(entry["flash"]) * 0.3))
	row.draw_rect(Rect2(0.0, 0.0, 4.0, ROW_HEIGHT), accent)
	var bar: Rect2 = Rect2(12.0, ROW_HEIGHT - 11.0, w - 84.0, BAR_HEIGHT)
	row.draw_rect(bar, Color(0.0, 0.03, 0.03, 0.85))
	var fill: float = clampf(float(entry["fill"]), 0.0, 1.0)
	if fill > 0.0:
		row.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), accent)
	var chip: Rect2 = Rect2(w - 52.0, 4.0, 46.0, 18.0)
	row.draw_rect(chip, Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.12))
	row.draw_rect(chip, Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.45), false, 1.0)
	if status == &"failed":
		row.draw_line(Vector2(12.0, 14.0), Vector2(w - 64.0, 14.0), Color(FAILED_COLOR.r, FAILED_COLOR.g, FAILED_COLOR.b, 0.7), 1.5)
	elif status == &"done":
		var check: PackedVector2Array = PackedVector2Array([Vector2(w - 66.0, 30.0), Vector2(w - 62.0, 34.0), Vector2(w - 55.0, 26.0)])
		row.draw_polyline(check, COMPLETE_COLOR, 2.2, true)


func _tier_color(tier: StringName) -> Color:
	if tier == ResearchQuestManager.TIER_HARD:
		return Color(0.94, 0.36, 0.25, 1.0)
	if tier == ResearchQuestManager.TIER_MEDIUM:
		return Color(0.94, 0.68, 0.26, 1.0)
	return Color(0.56, 0.82, 0.52, 1.0)
