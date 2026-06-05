extends Button
class_name ArmorItemCard

signal armor_hovered(item: ArmorItemData)
signal armor_selected(item: ArmorItemData)

var item: ArmorItemData = null

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _name_label: Label = %NameLabel
@onready var _meta_label: Label = %MetaLabel


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	pressed.connect(_on_pressed)
	_refresh()


func setup(armor_item: ArmorItemData) -> void:
	item = armor_item
	if is_node_ready():
		_refresh()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	var preview: Control = duplicate() as Control
	if preview != null:
		preview.modulate.a = 0.85
		set_drag_preview(preview)
	return {
		"type": &"armor_item",
		"item": item,
	}


func _refresh() -> void:
	if _name_label == null or _meta_label == null:
		return
	if item == null:
		_name_label.text = "Empty"
		_meta_label.text = ""
		_icon_rect.texture = null
		_apply_background_gradient(Color8(70, 78, 88, 210))
		return

	_name_label.text = item.get_hover_title()
	_meta_label.text = "%s - %d%%" % [item.get_category_display_name(), int(round(item.condition))]
	_icon_rect.texture = item.icon
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = item.get_hover_text()


func _apply_background_gradient(base_color: Color) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		base_color.darkened(0.62),
		_color_with_alpha(base_color, 0.82),
		Color(1.0, 1.0, 1.0, 0.18),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 128
	texture.height = 86
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
		armor_selected.emit(item)
