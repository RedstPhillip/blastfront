class_name LoadoutRecycler
extends Control

## Drop zone that turns an unwanted blueprint back into coins (unlocked through research).

signal recycled(refund: int)

var _hot: bool = false
var _armed: bool = false
var _time: float = 0.0
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = Vector2(56.0, 56.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(3)
	_style.anti_aliasing = true


func refresh() -> void:
	var ratio: float = ResearchManager.get_recycling_refund_ratio()
	visible = ratio > 0.0
	tooltip_text = "Drop a blueprint here to recycle it for %d%% of its price." % int(roundf(ratio * 100.0))
	queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not visible or not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if StringName(str(payload.get("type", ""))) != &"round_reward":
		return false
	var ok: bool = RoundRewardInventory.has_reward(StringName(str(payload.get("source_kind", ""))), int(payload.get("source_index", -1)))
	_set_hot(ok)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_hot(false)
	var payload: Dictionary = data
	var refund: int = RoundRewardInventory.recycle_reward(StringName(str(payload.get("source_kind", ""))), int(payload.get("source_index", -1)))
	if refund > 0:
		recycled.emit(refund)


func _set_hot(hot: bool) -> void:
	if _hot != hot:
		_hot = hot
		set_process(true)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		_armed = data is Dictionary and StringName(str((data as Dictionary).get("type", ""))) == &"round_reward"
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		_armed = false
		_set_hot(false)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_set_hot(false)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not _hot:
		set_process(false)


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 8.0)
	_style.bg_color = LoadoutStyle.CARD_EMPTY.lerp(Color(0.32, 0.09, 0.07, 0.9), (0.45 + pulse * 0.25) if _hot else 0.0)
	_style.set_border_width_all(0)
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var color: Color = LoadoutStyle.NEGATIVE if _hot else (LoadoutStyle.TEXT_SECONDARY if _armed else LoadoutStyle.TEXT_MUTED)
	if _armed:
		LoadoutStyle.draw_dashed_rect(self, Rect2(Vector2.ZERO, size).grow(-1.0), LoadoutStyle.with_alpha(color, 0.7), 4.0)
	var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.42)
	# Bin: lid, handle and body with three ribs.
	draw_line(c + Vector2(-9, -7), c + Vector2(9, -7), color, 1.6, true)
	draw_line(c + Vector2(-3, -10), c + Vector2(3, -10), color, 1.6, true)
	draw_polyline(PackedVector2Array([c + Vector2(-7, -4), c + Vector2(-6, 9), c + Vector2(6, 9), c + Vector2(7, -4)]), color, 1.6, true)
	for x in [-2.5, 0.0, 2.5]:
		draw_line(c + Vector2(x, -1), c + Vector2(x, 6), color, 1.0)
	var ratio: int = int(roundf(ResearchManager.get_recycling_refund_ratio() * 100.0))
	draw_string(UiStyle.FONT_BOLD, Vector2(0.0, size.y - 6.0), "%d%%" % ratio, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, color)
