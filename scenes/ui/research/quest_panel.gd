extends PanelContainer
class_name ResearchQuestPanel

@export var compact: bool = false

@onready var _title_label: Label = %TitleLabel
@onready var _last_reward_label: Label = %LastRewardLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _vbox: VBoxContainer = %VBox
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
	_apply_layout()
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
	_last_reward_label.text = "+%d RP" % amount if compact else "+%d RP  %s" % [amount, reason.to_upper()]
	var tween: Tween = create_tween()
	_last_reward_label.modulate = Color(1.0, 0.85, 0.35, 1.0)
	tween.tween_property(_last_reward_label, "modulate", Color.WHITE, 0.5)


func _apply_layout() -> void:
	_title_label.text = "OBJECTIVES" if compact else "NEXT SET ORDERS"
	for row in _rows:
		row.set_compact(compact)
	if not compact:
		return
	custom_minimum_size = Vector2(246.0, 0.0)
	_vbox.add_theme_constant_override("separation", 2)
	_title_label.add_theme_font_size_override("font_size", 10)
	_last_reward_label.add_theme_font_size_override("font_size", 8)
	_empty_label.add_theme_font_size_override("font_size", 9)
	var base_style: StyleBox = get_theme_stylebox("panel")
	var compact_style: StyleBoxFlat = base_style.duplicate() as StyleBoxFlat
	if compact_style != null:
		compact_style.bg_color = Color(0.055, 0.047, 0.035, 0.78)
		compact_style.border_color = Color(0.48, 0.37, 0.24, 0.5)
		compact_style.content_margin_left = 5.0
		compact_style.content_margin_top = 4.0
		compact_style.content_margin_right = 5.0
		compact_style.content_margin_bottom = 5.0
		compact_style.shadow_size = 3
		add_theme_stylebox_override("panel", compact_style)
