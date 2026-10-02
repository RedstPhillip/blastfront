class_name LoadoutRewardTile
extends LoadoutItemTile

## Shop offer or saved blueprint. Same card as the locker, plus a price tag; click buys, dragging onto
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


const PRICE_LINE: float = 18.0


## Offers are a square card with the price printed underneath, so the price never covers the art.
func set_tile_size(tile_size: Vector2) -> void:
	super.set_tile_size(Vector2(tile_size.x, tile_size.x + PRICE_LINE))


func _card_size() -> Vector2:
	return Vector2(size.x, size.x)


func _draw() -> void:
	var card: Rect2 = Rect2(Vector2.ZERO, _card_size())
	if item == null:
		_style.bg_color = LoadoutStyle.CARD_EMPTY
		_style.set_border_width_all(0)
		draw_style_box(_style, card)
		if drop_highlight:
			var pulse: float = 0.55 + 0.45 * sin(_pulse_time * 7.0)
			LoadoutStyle.draw_brackets(self, card.grow(-2.0), LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, pulse), 9.0, 1.5)
		elif source_kind == RoundRewardInventory.SOURCE_OFFER:
			# A bought-out offer: a quiet dash where the item was.
			draw_line(card.get_center() + Vector2(-6.0, 0.0), card.get_center() + Vector2(6.0, 0.0), Color(1, 1, 1, 0.12), 1.5)
		return
	super._draw()
	if price < 0:
		return
	var color: Color = LoadoutStyle.COIN if affordable else LoadoutStyle.NEGATIVE
	var text_value: String = str(price)
	var text_width: float = UiStyle.FONT_BOLD.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var start: float = (size.x - text_width - 11.0) * 0.5
	LoadoutStyle.draw_coin(self, Vector2(start + 3.5, card.end.y + 10.0), 3.5, color)
	draw_string(UiStyle.FONT_BOLD, Vector2(start + 11.0, card.end.y + 14.5), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
