extends PanelContainer
class_name RecyclerDropTarget

signal reward_recycled(refund: int)

@onready var _refund_label: Label = %RefundLabel


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	refresh()


func refresh() -> void:
	var ratio: float = ResearchManager.get_recycling_refund_ratio()
	visible = ratio > 0.0
	_refund_label.text = "%d%% REFUND" % int(roundf(ratio * 100.0))
	tooltip_text = "Drop an offered or saved blueprint here to recycle it for coins."


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not visible or not (data is Dictionary):
		return false
	var payload: Dictionary = data
	return payload.get("type", &"") == &"round_reward"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var refund: int = RoundRewardInventory.recycle_reward(source_kind, source_index)
	if refund > 0:
		reward_recycled.emit(refund)
