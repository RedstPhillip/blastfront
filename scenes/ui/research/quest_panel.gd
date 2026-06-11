extends PanelContainer
class_name ResearchQuestPanel

@export var compact: bool = false

@onready var _title_label: Label = %TitleLabel
@onready var _last_reward_label: Label = %LastRewardLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _rows: Array[ResearchQuestRow] = [
	%QuestRowEasy,
	%QuestRowMedium,
	%QuestRowHard,
]


func _ready() -> void:
	if not ResearchQuestManager.quests_changed.is_connected(_refresh):
		ResearchQuestManager.quests_changed.connect(_refresh)
	if not ResearchQuestManager.research_reward_awarded.is_connected(_on_reward_awarded):
		ResearchQuestManager.research_reward_awarded.connect(_on_reward_awarded)
	_title_label.text = "FIELD ORDERS" if compact else "NEXT SET ORDERS"
	_refresh()


func _exit_tree() -> void:
	if ResearchQuestManager.quests_changed.is_connected(_refresh):
		ResearchQuestManager.quests_changed.disconnect(_refresh)
	if ResearchQuestManager.research_reward_awarded.is_connected(_on_reward_awarded):
		ResearchQuestManager.research_reward_awarded.disconnect(_on_reward_awarded)


func _refresh() -> void:
	var quests: Array[Dictionary] = ResearchQuestManager.get_local_quests()
	_empty_label.visible = quests.is_empty()
	for row_index in range(_rows.size()):
		var quest: Dictionary = quests[row_index] if row_index < quests.size() else {}
		_rows[row_index].set_quest(quest)
	var last_awarded: int = ResearchQuestManager.get_last_awarded_points()
	_last_reward_label.visible = last_awarded > 0
	_last_reward_label.text = "LAST SET  +%d RP" % last_awarded


func _on_reward_awarded(amount: int, reason: String) -> void:
	_last_reward_label.visible = true
	_last_reward_label.text = "+%d RP  %s" % [amount, reason.to_upper()]
	var tween: Tween = create_tween()
	_last_reward_label.modulate = Color(1.0, 0.85, 0.35, 1.0)
	tween.tween_property(_last_reward_label, "modulate", Color.WHITE, 0.5)
