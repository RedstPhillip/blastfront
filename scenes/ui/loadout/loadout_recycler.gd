class_name LoadoutRecycler
extends Control

## Sell zone under the shop. Owned parts and armor (from the inventory or straight off the gun / operator)
## always sell for part of their value; offered and saved blueprints can only be recycled once the
## Recycling research is done. While something is dragged the zone shows what it would pay.

signal sold(refund: int, title: String)

var _hot: bool = false
var _drag_value: int = -1
var _drag_blocked: bool = false
var _time: float = 0.0
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 40.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(2)
	_style.anti_aliasing = true


func refresh() -> void:
	var ratio: int = int(roundf(RoundRewardInventory.get_sell_ratio() * 100.0))
	tooltip_text = "Drop a part or armor piece here to sell it for %d%% of its value." % ratio
	if ResearchManager.get_recycling_refund_ratio() > 0.0:
		tooltip_text += " Shop blueprints can be recycled too."
	queue_redraw()


## Coins this payload would bring; -1 when it cannot be sold here.
func _value_of(data: Variant) -> int:
	if not (data is Dictionary):
		return -1
	var payload: Dictionary = data
	var type: StringName = StringName(str(payload.get("type", "")))
	if type == &"weapon_extension_item" or type == &"armor_item":
		var value: int = RoundRewardInventory.sell_value(payload.get("item"))
		return value if value > 0 else -1
	if type == &"round_reward":
		var kind: StringName = StringName(str(payload.get("source_kind", "")))
		var index: int = int(payload.get("source_index", -1))
		if not RoundRewardInventory.has_reward(kind, index):
			return -1
		var refund: int = RoundRewardInventory.recycle_value(kind, index)
		return refund if refund > 0 else -1
	return -1


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = _value_of(data) > 0
	_set_hot(ok)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_hot(false)
	var payload: Dictionary = data
	var type: StringName = StringName(str(payload.get("type", "")))
	var refund: int = 0
	var title: String = ""
	if type == &"round_reward":
		refund = RoundRewardInventory.recycle_reward(StringName(str(payload.get("source_kind", ""))), int(payload.get("source_index", -1)))
		title = "Blueprint recycled"
	else:
		var item: Variant = payload.get("item")
		var info: Dictionary = LoadoutStyle.item_info(item)
		refund = RoundRewardInventory.sell_item(item)
		title = "%s sold" % str(info.get("name", "Item"))
	if refund > 0:
		sold.emit(refund, title)


func _set_hot(hot: bool) -> void:
	if _hot != hot:
		_hot = hot
		set_process(true)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		_drag_value = _value_of(data)
		_drag_blocked = data is Dictionary and StringName(str((data as Dictionary).get("type", ""))) == &"round_reward" and _drag_value <= 0
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		_drag_value = -1
		_drag_blocked = false
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
	var armed: bool = _drag_value > 0
	var fill: Color = LoadoutStyle.SLOT
	if _hot:
		fill = LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.9)
	elif armed:
		fill = LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.14)
	_style.bg_color = fill
	_style.set_border_width_all(0)
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if armed and not _hot:
		LoadoutStyle.draw_dashed_rect(self, Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.7), 4.0)
	var ink: Color = UiStyle.INK if _hot else (LoadoutStyle.TEXT if armed else LoadoutStyle.TEXT_MUTED)
	var mid_y: float = size.y * 0.5
	var label: String = "SELL"
	if _drag_blocked:
		label = "NEEDS RECYCLING"
		ink = LoadoutStyle.with_alpha(LoadoutStyle.NEGATIVE, 0.85)
	var font: Font = UiStyle.FONT_BOLD
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var x: float = 16.0
	_draw_bin(Vector2(x + 7.0, mid_y), ink)
	x += 24.0
	draw_string(font, Vector2(x, mid_y + 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	x += text_width + 12.0
	if armed:
		var amount: String = "+%d" % _drag_value
		var amount_width: float = UiStyle.FONT_DISPLAY.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var right: float = size.x - 14.0
		draw_string(UiStyle.FONT_DISPLAY, Vector2(right - amount_width, mid_y + 7.0), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
		LoadoutStyle.draw_coin(self, Vector2(right - amount_width - 11.0, mid_y + 0.5), 5.5, LoadoutStyle.COIN if not _hot else UiStyle.INK)
	elif not _drag_blocked:
		var ratio: String = "%d%% OF VALUE" % int(roundf(RoundRewardInventory.get_sell_ratio() * 100.0))
		draw_string(font, Vector2(0.0, mid_y + 5.0), ratio, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0, 11, LoadoutStyle.TEXT_MUTED)


func _draw_bin(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center + Vector2(-5.5, -4.0), Vector2(11.0, 12.0)), color, false, 1.5)
	draw_line(center + Vector2(-7.5, -5.5), center + Vector2(7.5, -5.5), color, 1.5, true)
	draw_line(center + Vector2(-2.0, -8.0), center + Vector2(2.0, -8.0), color, 1.5, true)
	for offset in [-2.5, 0.0, 2.5]:
		draw_line(center + Vector2(offset, -1.5), center + Vector2(offset, 5.5), color, 1.0)
