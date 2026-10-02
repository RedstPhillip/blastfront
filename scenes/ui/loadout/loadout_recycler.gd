class_name LoadoutRecycler
extends Control

## Drop zone that turns an unwanted blueprint back into coins (unlocked through research).

signal recycled(refund: int)

var _hot: bool = false
var _time: float = 0.0
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = Vector2(62.0, 62.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(6)
	_style.anti_aliasing = true


func refresh() -> void:
	var ratio: float = ResearchManager.get_recycling_refund_ratio()
	visible = ratio > 0.0
	tooltip_text = "Drop an offered or saved blueprint here to recycle it for %d%% of its price." % int(roundf(ratio * 100.0))
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
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_set_hot(false)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not _hot:
		set_process(false)


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 8.0)
	_style.bg_color = LoadoutStyle.TILE_EMPTY.lerp(Color(0.3, 0.1, 0.08), (0.4 + pulse * 0.3) if _hot else 0.0)
	_style.border_color = LoadoutStyle.DANGER if _hot else LoadoutStyle.EDGE_SOFT
	_style.set_border_width_all(2 if _hot else 1)
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.42)
	var color: Color = LoadoutStyle.DANGER if _hot else Color(1, 1, 1, 0.35)
	draw_rect(Rect2(c + Vector2(-8, -6), Vector2(16, 17)), color, false, 1.6)
	draw_line(c + Vector2(-11, -8), c + Vector2(11, -8), color, 1.6, true)
	draw_line(c + Vector2(-3, -11), c + Vector2(3, -11), color, 1.6, true)
	for x in [-3.5, 0.0, 3.5]:
		draw_line(c + Vector2(x, -2), c + Vector2(x, 8), color, 1.1)
	var ratio: int = int(roundf(ResearchManager.get_recycling_refund_ratio() * 100.0))
	draw_string(UiStyle.FONT_BOLD, Vector2(0.0, size.y - 6.0), "%d%%" % ratio, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, color)
