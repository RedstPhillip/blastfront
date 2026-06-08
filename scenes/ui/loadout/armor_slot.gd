extends Button
class_name ArmorSlot

signal armor_hovered(item: ArmorItemData)
signal armor_dropped(item: ArmorItemData)
signal armor_cleared(category: StringName)

@export var category: StringName = ArmorItemData.CATEGORY_BOOTS
@export var compact: bool = false

var item: ArmorItemData = null
var _is_hovered: bool = false

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _visual_preview: ArmorVisualPreview = %ArmorPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame
@onready var _title_label: Label = %TitleLabel
@onready var _condition_label: Label = %ConditionLabel
@onready var _margin: MarginContainer = $Margin


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	_refresh()


func setup(slot_category: StringName, armor_item: ArmorItemData) -> void:
	category = slot_category
	item = armor_item
	if is_node_ready():
		_refresh()


func set_item(armor_item: ArmorItemData) -> void:
	item = armor_item
	if is_node_ready():
		_refresh()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var drop_data: Dictionary = data
	if drop_data.get("type", &"") != &"armor_item":
		return false
	var dropped_item: ArmorItemData = drop_data.get("item", null) as ArmorItemData
	return dropped_item != null and dropped_item.category == category


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var drop_data: Dictionary = data
	var dropped_item: ArmorItemData = drop_data.get("item", null) as ArmorItemData
	if dropped_item != null:
		armor_dropped.emit(dropped_item)


func _refresh() -> void:
	if _title_label == null or _condition_label == null:
		return

	_title_label.text = ArmorItemData.category_display_name(category)
	_title_label.visible = not compact
	_condition_label.visible = not compact
	text = ""
	if compact:
		custom_minimum_size = Vector2(42, 42)
		size = Vector2(42, 42)
		_margin.add_theme_constant_override("margin_left", 5)
		_margin.add_theme_constant_override("margin_top", 5)
		_margin.add_theme_constant_override("margin_right", 5)
		_margin.add_theme_constant_override("margin_bottom", 5)
		_icon_rect.custom_minimum_size = Vector2(28, 28)
		_visual_preview.custom_minimum_size = Vector2(30, 30)
		_preview_frame.custom_minimum_size = Vector2(34, 34)
	else:
		_icon_rect.custom_minimum_size = Vector2(34, 30)
		_visual_preview.custom_minimum_size = Vector2(40, 34)
		_preview_frame.custom_minimum_size = Vector2(44, 44)
	if item == null:
		_condition_label.text = "Empty"
		_icon_rect.texture = null
		_icon_rect.visible = false
		_visual_preview.clear()
		_visual_preview.visible = false
		_preview_frame.set_condition_color(Color8(48, 54, 63, 225), false)
		_apply_background_gradient(Color8(48, 54, 63, 225))
		tooltip_text = "Drop %s armor here" % ArmorItemData.category_display_name(category)
		return

	_condition_label.text = "%s - %d%%" % [item.get_condition_name(), int(round(item.condition))]
	_visual_preview.visible = _visual_preview.set_armor_item(item)
	_icon_rect.visible = not _visual_preview.visible
	_icon_rect.texture = _get_fallback_texture(item)
	_preview_frame.set_condition_color(item.get_condition_color())
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = item.get_hover_text()


func _apply_background_gradient(base_color: Color) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(96, 96, base_color, 0.72, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _get_fallback_texture(armor_item: ArmorItemData) -> Texture2D:
	if armor_item.icon != null:
		return armor_item.icon
	return null


func _on_mouse_entered() -> void:
	_is_hovered = true
	_refresh()
	if item != null:
		armor_hovered.emit(item)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh()


func _on_pressed() -> void:
	if item != null:
		armor_cleared.emit(category)
