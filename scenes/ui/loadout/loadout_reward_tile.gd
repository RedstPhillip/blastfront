class_name LoadoutRewardTile
extends LoadoutItemTile

## Shop offer or saved blueprint. Same card as the inventory, plus a price tag; click buys, dragging onto
## the weapon or operator buys and installs, and blueprints can be swapped between offer and saved slots.

signal reward_claimed(source_kind: StringName, source_index: int)
signal reward_moved(payload: Dictionary, target_kind: StringName, target_index: int)

var source_kind: StringName = RoundRewardInventory.SOURCE_OFFER
var source_index: int = -1
var reward: Dictionary = {}


func setup_reward(kind: StringName, index: int, next_reward: Dictionary) -> void:
	source_kind = kind
	source_index = index
	reward = next_reward
	price = int(reward.get("price", 0)) if not reward.is_empty() else -1
	affordable = price >= 0 and OnlineMatch.get_local_coin_balance() >= price
	setup(reward.get("item", null) if not reward.is_empty() else null)


func refresh_affordability() -> void:
	affordable = price >= 0 and OnlineMatch.get_local_coin_balance() >= price
	queue_redraw()


func _build_payload() -> Dictionary:
	if reward.is_empty():
		return {}
	return {
		"type": &"round_reward",
		"reward_type": StringName(str(reward.get("type", ""))),
		"source_kind": source_kind,
		"source_index": source_index,
		"item": reward.get("item", null),
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if payload.get("type", &"") != &"round_reward":
		return false
	if StringName(str(payload.get("source_kind", ""))) == source_kind and int(payload.get("source_index", -1)) == source_index:
		return false
	if source_kind == RoundRewardInventory.SOURCE_SAVED:
		return true
	if StringName(str(payload.get("source_kind", ""))) != RoundRewardInventory.SOURCE_SAVED:
		return false
	return RoundRewardInventory.can_place_reward_in_offer_slot(source_index, StringName(str(payload.get("reward_type", ""))))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	reward_moved.emit(data, source_kind, source_index)


func _on_pressed() -> void:
	if not reward.is_empty():
		reward_claimed.emit(source_kind, source_index)


func _draw() -> void:
	if item == null and source_kind == RoundRewardInventory.SOURCE_SAVED:
		_style.bg_color = LoadoutStyle.TILE_EMPTY
		_style.border_color = LoadoutStyle.EDGE_SOFT
		_style.set_border_width_all(1)
		_style.shadow_size = 0
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var color: Color = Color(1, 1, 1, 0.12)
		if drop_highlight:
			color = Color(LoadoutStyle.TARGET.r, LoadoutStyle.TARGET.g, LoadoutStyle.TARGET.b, 0.7)
		var corners: Array[Vector2] = [Vector2(6, 6), Vector2(size.x - 6, 6), size - Vector2(6, 6), Vector2(6, size.y - 6)]
		for index in range(4):
			draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.0, 3.0)
		return
	super._draw()
