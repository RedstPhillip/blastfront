extends Control
class_name LoadoutMergeDialog

signal confirmed
signal cancelled

@onready var _panel: PanelContainer = %DialogPanel
@onready var _source_tile: PanelContainer = %SourceTile
@onready var _target_tile: PanelContainer = %TargetTile
@onready var _result_tile: PanelContainer = %ResultTile
@onready var _condition_panel: PanelContainer = %ConditionPanel
@onready var _cost_badge: PanelContainer = %CostBadge
@onready var _balance_badge: PanelContainer = %BalanceBadge
@onready var _accent_bar: ColorRect = %AccentBar
@onready var _kind_label: Label = %KindLabel
@onready var _title_label: Label = %TitleLabel
@onready var _source_name_label: Label = %SourceNameLabel
@onready var _source_meta_label: Label = %SourceMetaLabel
@onready var _target_name_label: Label = %TargetNameLabel
@onready var _target_meta_label: Label = %TargetMetaLabel
@onready var _result_name_label: Label = %ResultNameLabel
@onready var _result_meta_label: Label = %ResultMetaLabel
@onready var _condition_label: Label = %ConditionLabel
@onready var _cost_label: Label = %CostLabel
@onready var _balance_label: Label = %BalanceLabel
@onready var _hint_label: Label = %HintLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _warning_dialog: AcceptDialog = %MergeWarningDialog


func _ready() -> void:
	hide()
	_panel.add_theme_stylebox_override(
		"panel",
		_create_style(Color8(14, 15, 16, 250), Color8(138, 151, 138, 220), 4, 20, 9)
	)
	_source_tile.add_theme_stylebox_override("panel", _create_style(Color8(30, 34, 36, 238), Color8(84, 96, 98, 185), 4, 0, 0))
	_target_tile.add_theme_stylebox_override("panel", _create_style(Color8(30, 34, 36, 238), Color8(84, 96, 98, 185), 4, 0, 0))
	_result_tile.add_theme_stylebox_override("panel", _create_style(Color8(36, 34, 22, 242), Color8(218, 172, 78, 210), 4, 0, 0))
	_condition_panel.add_theme_stylebox_override("panel", _create_style(Color8(8, 10, 11, 214), Color8(86, 96, 92, 150), 3, 0, 0))
	_cost_badge.add_theme_stylebox_override("panel", _create_style(Color8(80, 58, 22, 220), Color8(214, 158, 64, 180), 2, 0, 0))
	_balance_badge.add_theme_stylebox_override("panel", _create_style(Color8(18, 52, 45, 218), Color8(88, 184, 150, 170), 2, 0, 0))
	_warning_dialog.add_theme_stylebox_override(
		"panel",
		_create_style(Color8(22, 15, 14, 248), Color8(225, 82, 72, 220), 3, 16, 7)
	)
	_warning_dialog.ok_button_text = "OK"
	_warning_dialog.min_size = Vector2i(420, 0)
	_style_button(_warning_dialog.get_ok_button(), true, Color8(225, 82, 72, 255))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func show_merge(
	kind_text: String,
	title_text: String,
	source_name: String,
	target_name: String,
	source_mark: int,
	target_mark: int,
	next_mark: int,
	source_condition: float,
	target_condition: float,
	merge_cost: int,
	balance: int,
	accent: Color
) -> void:
	var result_condition: float = (source_condition + target_condition) * 0.5
	visible = true
	move_to_front()

	_accent_bar.color = accent
	_kind_label.text = kind_text
	_kind_label.add_theme_color_override("font_color", accent)
	_title_label.text = title_text if not title_text.is_empty() else "Forge MK%d Upgrade" % next_mark
	_source_name_label.text = _trim_item_name(source_name)
	_source_meta_label.text = "MK%d  |  %.0f%%" % [source_mark, source_condition]
	_target_name_label.text = _trim_item_name(target_name)
	_target_meta_label.text = "MK%d  |  %.0f%%" % [target_mark, target_condition]
	_result_name_label.text = _trim_item_name(source_name)
	_result_meta_label.text = "MK%d  |  %.0f%%" % [next_mark, result_condition]
	_result_meta_label.add_theme_color_override("font_color", accent)
	_condition_label.text = "Condition %.0f%% + %.0f%% -> %.0f%%" % [
		source_condition,
		target_condition,
		result_condition,
	]
	_cost_label.text = "Cost\n%d coins" % merge_cost
	_balance_label.text = "Balance\n%d coins" % balance
	_balance_label.add_theme_color_override(
		"font_color",
		Color8(180, 230, 210, 255) if balance >= merge_cost else Color8(255, 120, 100, 255)
	)
	_hint_label.text = "The two matching MK%d items are consumed." % source_mark
	_confirm_button.text = "FORGE MK%d  -%d C" % [next_mark, merge_cost]
	_cancel_button.text = "CANCEL"

	_style_button(_confirm_button, true, accent)
	_style_button(_cancel_button, false, accent)


func show_coin_warning(body: String, item_label: String) -> void:
	_warning_dialog.title = "Not Enough Coins"
	_warning_dialog.dialog_text = "%s\n\nEarn more coins before merging these %s." % [body, item_label]
	_warning_dialog.popup_centered()


func hide_dialog() -> void:
	hide()


func _on_confirm_pressed() -> void:
	hide()
	confirmed.emit()


func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()


func _trim_item_name(item_name: String) -> String:
	var trimmed: String = item_name.strip_edges()
	if trimmed.length() <= 30:
		return trimmed
	return trimmed.substr(0, 27) + "..."


func _style_button(button: Button, is_primary: bool, accent: Color) -> void:
	button.custom_minimum_size = Vector2(128, 38)
	button.add_theme_font_size_override("font_size", 16 if is_primary else 14)
	button.add_theme_color_override("font_color", Color8(18, 18, 16, 255) if is_primary else Color8(218, 220, 212, 255))
	button.add_theme_color_override("font_hover_color", Color8(12, 14, 14, 255) if is_primary else Color8(248, 250, 240, 255))
	button.add_theme_color_override("font_pressed_color", Color8(245, 248, 238, 255))
	var normal_color: Color = accent if is_primary else Color8(42, 40, 35, 242)
	var hover_color: Color = accent.lightened(0.18) if is_primary else Color8(58, 55, 48, 248)
	var pressed_color: Color = accent.darkened(0.22) if is_primary else Color8(30, 29, 26, 250)
	button.add_theme_stylebox_override("normal", _create_style(normal_color, accent.lightened(0.18), 3, 0, 0))
	button.add_theme_stylebox_override("hover", _create_style(hover_color, accent.lightened(0.35), 3, 0, 0))
	button.add_theme_stylebox_override("pressed", _create_style(pressed_color, accent.darkened(0.1), 3, 0, 0))
	button.add_theme_stylebox_override("focus", _create_style(hover_color, accent.lightened(0.35), 3, 0, 0))


func _create_style(bg_color: Color, border_color: Color, radius: int, shadow_size: int, shadow_y: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	if shadow_size > 0:
		style.shadow_color = Color(0, 0, 0, 0.48)
		style.shadow_size = shadow_size
		style.shadow_offset = Vector2(0, shadow_y)
	return style
