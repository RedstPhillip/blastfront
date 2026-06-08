extends VBoxContainer
class_name StatComparisonRow

@onready var _name_label: Label = %StatName
@onready var _value_label: Label = %StatValue
@onready var _before_bar: ProgressBar = %BeforeBar
@onready var _after_bar: ProgressBar = %AfterBar


func setup(
	display_name: String,
	before_value: float,
	after_value: float,
	value_suffix: String,
	decimals: int,
	lower_is_better: bool
) -> void:
	var maximum: float = maxf(maxf(absf(before_value), absf(after_value)) * 1.2, 1.0)
	_before_bar.max_value = maximum
	_after_bar.max_value = maximum
	_before_bar.value = maxf(before_value, 0.0)
	_after_bar.value = maxf(after_value, 0.0)

	var difference: float = after_value - before_value
	var improved: bool = difference < 0.0 if lower_is_better else difference > 0.0
	var changed_color: Color = Color8(72, 190, 111, 255) if improved else Color8(224, 92, 82, 255)
	var after_style: StyleBoxFlat = StyleBoxFlat.new()
	after_style.bg_color = changed_color
	after_style.corner_radius_top_left = 2
	after_style.corner_radius_top_right = 2
	after_style.corner_radius_bottom_right = 2
	after_style.corner_radius_bottom_left = 2
	_after_bar.add_theme_stylebox_override("fill", after_style)

	_name_label.text = display_name
	_value_label.text = "%s  >  %s" % [
		_format_value(before_value, value_suffix, decimals),
		_format_value(after_value, value_suffix, decimals),
	]
	_value_label.add_theme_color_override("font_color", changed_color)


func _format_value(value: float, suffix: String, decimals: int) -> String:
	var number_text: String = str(int(round(value)))
	if decimals == 1:
		number_text = "%.1f" % value
	elif decimals >= 2:
		number_text = "%.2f" % value
	return "%s%s" % [number_text, suffix]
