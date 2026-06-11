extends PanelContainer
class_name ResearchQuestRow

@onready var _tier_label: Label = %TierLabel
@onready var _title_label: Label = %TitleLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _progress_bar: ProgressBar = %ProgressBar


func set_quest(quest: Dictionary) -> void:
	if quest.is_empty():
		hide()
		return
	show()
	var tier: StringName = StringName(str(quest.get("tier", "")))
	var progress: float = float(quest.get("progress", 0.0))
	var target: float = maxf(float(quest.get("target", 1.0)), 1.0)
	var completed: bool = quest.get("completed", false) == true
	var failed: bool = quest.get("failed", false) == true
	_tier_label.text = str(tier).to_upper()
	_tier_label.add_theme_color_override("font_color", _tier_color(tier))
	_title_label.text = str(quest.get("title", "Quest"))
	_reward_label.text = "+%d RP" % int(quest.get("reward", 0))
	_progress_bar.max_value = target
	_progress_bar.value = progress
	if completed:
		_progress_label.text = "COMPLETE"
		_progress_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.62, 1.0))
	elif failed:
		_progress_label.text = "FAILED"
		_progress_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.28, 1.0))
	elif StringName(str(quest.get("event", ""))) == &"no_hit":
		_progress_label.text = "UNTOUCHED"
		_progress_label.add_theme_color_override("font_color", Color(0.86, 0.79, 0.62, 1.0))
	else:
		_progress_label.text = "%d / %d" % [int(floor(progress)), int(target)]
		_progress_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.76, 1.0))
	tooltip_text = str(quest.get("description", ""))


func _tier_color(tier: StringName) -> Color:
	if tier == ResearchQuestManager.TIER_HARD:
		return Color(0.94, 0.36, 0.25, 1.0)
	if tier == ResearchQuestManager.TIER_MEDIUM:
		return Color(0.94, 0.68, 0.26, 1.0)
	return Color(0.56, 0.82, 0.52, 1.0)
