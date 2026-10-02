class_name LoadoutInventoryDrop
extends Control

## The inventory grid area as a drop target: dropping an installed part back here takes it off,
## dropping a shop offer here buys it into the inventory.

var kind: StringName = &"extension"
var page: LoadoutPage = null

var _active: bool = false
var _over: bool = false
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _accepts(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	var type: StringName = StringName(str(payload.get("type", "")))
	if type == &"round_reward":
		var wanted: StringName = RoundRewardInventory.REWARD_EXTENSION if kind == &"extension" else RoundRewardInventory.REWARD_ARMOR
		return StringName(str(payload.get("reward_type", ""))) == wanted
	if StringName(str(payload.get("source", ""))) != &"slot":
		return false
	return type == (&"weapon_extension_item" if kind == &"extension" else &"armor_item")


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = _accepts(data)
	if ok != _over:
		_over = ok
		queue_redraw()
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_over = false
	queue_redraw()
	if page != null:
		page.unequip_from_inventory_drop(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_active = _accepts(get_viewport().gui_get_drag_data())
		set_process(_active)
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		_active = false
		_over = false
		set_process(false)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _over:
		_over = false
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _over and not get_global_rect().has_point(get_global_mouse_position()):
		_over = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
	var alpha: float = (0.55 + pulse * 0.35) if _over else 0.22
	var color: Color = Color(LoadoutStyle.TARGET.r, LoadoutStyle.TARGET.g, LoadoutStyle.TARGET.b, alpha)
	if _over:
		draw_rect(Rect2(Vector2.ZERO, size), Color(LoadoutStyle.TARGET.r, LoadoutStyle.TARGET.g, LoadoutStyle.TARGET.b, 0.05))
	var rect: Rect2 = Rect2(Vector2.ZERO, size).grow(-1.0)
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.4, 6.0, true)
