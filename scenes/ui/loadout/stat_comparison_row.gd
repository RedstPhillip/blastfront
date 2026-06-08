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
	_lower_is_better: bool
) -> void:
	var maximum: float = maxf(maxf(absf(before_value), absf(after_value)) * 1.2, 1.0)
	var before_ratio: float = clampf(maxf(before_value, 0.0) / maximum, 0.0, 1.0)
	var after_ratio: float = clampf(maxf(after_value, 0.0) / maximum, 0.0, 1.0)
	var difference: float = after_value - before_value
	_base_fill.anchor_left = 0.0
	_base_fill.anchor_right = before_ratio
	_delta_fill.visible = not is_zero_approx(difference)
	if difference > 0.0:
		_delta_fill.anchor_left = before_ratio
		_delta_fill.anchor_right = after_ratio
		_delta_fill.color = Color8(62, 142, 235, 255)
	elif difference < 0.0:
		_delta_fill.anchor_left = after_ratio
		_delta_fill.anchor_right = before_ratio
		_delta_fill.color = Color8(224, 82, 76, 255)

	_name_label.text = display_name
	if is_zero_approx(difference):
		_value_label.text = _format_value(before_value, value_suffix, decimals)
		_value_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.87, 0.94))
	else:
		_value_label.text = "%s  >  %s" % [
			_format_value(before_value, value_suffix, decimals),
			_format_value(after_value, value_suffix, decimals),
		]
		_value_label.add_theme_color_override(
			"font_color",
			Color8(62, 142, 235, 255) if difference > 0.0 else Color8(224, 82, 76, 255)
		)


func _format_value(value: float, suffix: String, decimals: int) -> String:
	var number_text: String = str(int(round(value)))
	if decimals == 1:
		number_text = "%.1f" % value
	elif decimals >= 2:
		number_text = "%.2f" % value
	return "%s%s" % [number_text, suffix]
