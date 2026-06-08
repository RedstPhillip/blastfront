extends VBoxContainer
class_name StatComparisonRow

@onready var _name_label: Label = %StatName
@onready var _value_label: Label = %StatValue
@onready var _base_fill: ColorRect = %BaseFill
@onready var _delta_fill: ColorRect = %DeltaFill


func setup(
	display_name: String,
	before_value: float,
	after_value: float,
	value_suffix: String,
	decimals: int,
	lower_is_better: bool
) -> void:
	var before_score: float = _display_score(before_value, lower_is_better)
	var after_score: float = _display_score(after_value, lower_is_better)
	var maximum: float = maxf(maxf(before_score, after_score) * 1.2, 0.001)
	var before_ratio: float = clampf(before_score / maximum, 0.0, 1.0)
	var after_ratio: float = clampf(after_score / maximum, 0.0, 1.0)
	var score_difference: float = after_score - before_score
	_base_fill.anchor_left = 0.0
	_base_fill.anchor_right = before_ratio
	_delta_fill.visible = not is_zero_approx(score_difference)
	if score_difference > 0.0:
		_delta_fill.anchor_left = before_ratio
		_delta_fill.anchor_right = after_ratio
		_delta_fill.color = Color8(62, 142, 235, 255)
	elif score_difference < 0.0:
		_delta_fill.anchor_left = after_ratio
		_delta_fill.anchor_right = before_ratio
		_delta_fill.color = Color8(224, 82, 76, 255)

	_name_label.text = display_name
	if is_zero_approx(score_difference):
		_value_label.text = _format_value(before_value, value_suffix, decimals)
		_value_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.87, 0.94))
	else:
		_value_label.text = "%s  >  %s" % [
			_format_value(before_value, value_suffix, decimals),
			_format_value(after_value, value_suffix, decimals),
		]
		_value_label.add_theme_color_override(
			"font_color",
			Color8(62, 142, 235, 255) if score_difference > 0.0 else Color8(224, 82, 76, 255)
		)


func _display_score(value: float, lower_is_better: bool) -> float:
	if lower_is_better:
		return 1.0 / maxf(absf(value), 0.01)
	return maxf(value, 0.0)


func _format_value(value: float, suffix: String, decimals: int) -> String:
	var number_text: String = str(int(round(value)))
	if decimals == 1:
		number_text = "%.1f" % value
	elif decimals >= 2:
		number_text = "%.2f" % value
	return "%s%s" % [number_text, suffix]
