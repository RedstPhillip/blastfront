extends PanelContainer
class_name RewardInventoryDropTarget

signal reward_dropped(payload: Dictionary)

@export var accepted_reward_type: StringName = RoundRewardInventory.REWARD_EXTENSION


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if payload.get("type", &"") != &"round_reward":
		return false
	return StringName(str(payload.get("reward_type", ""))) == accepted_reward_type


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	reward_dropped.emit(payload)
