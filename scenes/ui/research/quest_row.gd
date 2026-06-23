extends PanelContainer
class_name ResearchQuestRow

@onready var _tier_label: Label = %TierLabel
@onready var _title_label: Label = %TitleLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _margin: MarginContainer = %Margin
@onready var _compact_progress_label: Label = %CompactProgressLabel
@onready var _progress_row: HBoxContainer = %ProgressRow
@onready var _tier_stripe: ColorRect = %TierStripe


func set_quest(quest: Dictionary) -> void:
	if quest.is_empty():
		hide()
		return
	show()
	var tier: StringName = StringName(str(quest["tier"]))
	var progress: float = float(quest["progress"])
	var target: float = maxf(float(quest["target"]), 1.0)
	var completed: bool = quest["completed"] == true
	var failed: bool = quest["failed"] == true
	var progress_text: String = ""
	var progress_color: Color = Color(0.82, 0.82, 0.76, 1.0)
	_tier_label.text = str(tier).to_upper()
	var tier_color: Color = _tier_color(tier)
	_tier_label.add_theme_color_override("font_color", tier_color)
	_tier_stripe.color = tier_color
	_title_label.text = str(quest["title"])
	_reward_label.text = "+%d RP" % int(quest["reward"])
	_progress_bar.max_value = target
	_progress_bar.value = progress
	if completed:
		progress_text = "DONE"
		progress_color = Color(0.55, 1.0, 0.62, 1.0)
	elif failed:
		progress_text = "FAILED"
		progress_color = Color(1.0, 0.38, 0.28, 1.0)
	elif StringName(str(quest["event"])) == &"no_hit":
		progress_text = "SAFE"
		progress_color = Color(0.86, 0.79, 0.62, 1.0)
	else:
		progress_text = "%d/%d" % [int(floor(progress)), int(target)]
	_progress_label.text = progress_text
	_progress_label.add_theme_color_override("font_color", progress_color)
	_compact_progress_label.text = progress_text
	_compact_progress_label.add_theme_color_override("font_color", progress_color)
	tooltip_text = ""


func set_compact(compact: bool) -> void:
	if not compact:
		return
	custom_minimum_size = Vector2(210.0, 21.0)
	_tier_label.hide()
	_tier_stripe.show()
	_progress_row.hide()
	_compact_progress_label.show()
	_margin.add_theme_constant_override("margin_left", 4)
	_margin.add_theme_constant_override("margin_top", 1)
	_margin.add_theme_constant_override("margin_right", 4)
	_margin.add_theme_constant_override("margin_bottom", 1)
	_title_label.add_theme_font_size_override("font_size", 10)
	_reward_label.add_theme_font_size_override("font_size", 9)
	_compact_progress_label.add_theme_font_size_override("font_size", 9)
	var compact_style := StyleBoxFlat.new()
	compact_style.bg_color = Color(0.035, 0.032, 0.026, 0.16)
	add_theme_stylebox_override("panel", compact_style)


func _tier_color(tier: StringName) -> Color:
	if tier == ResearchQuestManager.TIER_HARD:
		return Color(0.94, 0.36, 0.25, 1.0)
	if tier == ResearchQuestManager.TIER_MEDIUM:
		return Color(0.94, 0.68, 0.26, 1.0)
	return Color(0.56, 0.82, 0.52, 1.0)
