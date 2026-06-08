extends Button
class_name ArmorItemCard

signal armor_hovered(item: ArmorItemData)
signal armor_selected(item: ArmorItemData)

var item: ArmorItemData = null
var _is_hovered: bool = false

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _visual_preview: ArmorVisualPreview = %ArmorPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(54, 54)
	_clear_button_chrome()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
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
	if _icon_rect == null:
		return
	if item == null:
		_icon_rect.texture = null
		_icon_rect.visible = false
		_visual_preview.clear()
		_visual_preview.visible = false
		_preview_frame.set_condition_color(Color8(70, 78, 88, 210), false)
		_apply_background_gradient(Color8(70, 78, 88, 210))
		return

	_visual_preview.visible = _visual_preview.set_armor_item(item)
	_icon_rect.visible = not _visual_preview.visible
	_icon_rect.texture = _get_fallback_texture(item)
	_preview_frame.set_condition_color(item.get_condition_color())
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = item.get_hover_text()


func _apply_background_gradient(base_color: Color) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(54, 54, base_color, 0.82, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _create_icon_texture(base_color: Color) -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.68, 1.0])
	gradient.colors = PackedColorArray([
		base_color.darkened(0.45),
		base_color,
		Color(1.0, 1.0, 1.0, 0.28),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 34
	texture.height = 34
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.gradient = gradient
	return texture


func _get_fallback_texture(armor_item: ArmorItemData) -> Texture2D:
	if armor_item.icon != null:
		return armor_item.icon
	return _create_icon_texture(armor_item.get_condition_color())


func _clear_button_chrome() -> void:
	flat = true
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style_name, empty_style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_apply_background_gradient(item.get_condition_color() if item != null else Color8(70, 78, 88, 210))
	if item != null:
		armor_hovered.emit(item)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_apply_background_gradient(item.get_condition_color() if item != null else Color8(70, 78, 88, 210))


func _on_pressed() -> void:
	if item != null:
		armor_selected.emit(item)
