extends Button
class_name ArmorSlot

signal armor_hovered(item: ArmorItemData)
signal armor_dropped(item: ArmorItemData)
signal armor_cleared(category: StringName)

@export var category: StringName = ArmorItemData.CATEGORY_BOOTS
@export var compact: bool = false

var item: ArmorItemData = null

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _title_label: Label = %TitleLabel
@onready var _condition_label: Label = %ConditionLabel
@onready var _margin: MarginContainer = $Margin


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
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
	else:
		_icon_rect.custom_minimum_size = Vector2(34, 30)
	if item == null:
		_condition_label.text = "Empty"
		_icon_rect.texture = null
		_apply_background_gradient(Color8(48, 54, 63, 225))
		tooltip_text = "Drop %s armor here" % ArmorItemData.category_display_name(category)
		return

	_condition_label.text = "%s - %d%%" % [item.get_condition_name(), int(round(item.condition))]
	_icon_rect.texture = item.icon
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = item.get_hover_text()


func _apply_background_gradient(base_color: Color) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	gradient.colors = PackedColorArray([
		_color_with_alpha(base_color.darkened(0.7), 0.58),
		_color_with_alpha(base_color, 0.72),
		Color(1.0, 1.0, 1.0, 0.18),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 96
	texture.height = 96
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.gradient = gradient
	_background.texture = texture


func _color_with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _on_mouse_entered() -> void:
	if item != null:
		armor_hovered.emit(item)


func _on_pressed() -> void:
	if item != null:
		armor_cleared.emit(category)
