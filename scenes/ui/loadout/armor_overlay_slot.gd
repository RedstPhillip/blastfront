extends Button
class_name ArmorOverlaySlot

signal armor_hovered(item: ArmorItemData)
signal armor_dropped(item: ArmorItemData)
signal armor_cleared(category: StringName)

@export var category: StringName = ArmorItemData.CATEGORY_BOOTS

var item: ArmorItemData = null

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect


func _ready() -> void:
	custom_minimum_size = Vector2(42, 42)
	text = ""
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
	if item == null:
		_icon_rect.texture = null
		_apply_background_gradient(Color8(46, 54, 61, 210), 0.46)
		tooltip_text = "Drop %s armor here" % ArmorItemData.category_display_name(category)
		return

	_icon_rect.texture = item.icon
	_apply_background_gradient(Color8(74, 78, 82, 230), 0.64)
	tooltip_text = item.get_hover_text()


func _apply_background_gradient(base_color: Color, alpha: float) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(base_color.r * 0.35, base_color.g * 0.35, base_color.b * 0.35, alpha),
		Color(base_color.r, base_color.g, base_color.b, alpha),
		Color(1.0, 1.0, 1.0, 0.14),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 42
	texture.height = 42
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.gradient = gradient
	_background.texture = texture


func _on_mouse_entered() -> void:
	if item != null:
		armor_hovered.emit(item)


func _on_pressed() -> void:
	if item != null:
		armor_cleared.emit(category)
