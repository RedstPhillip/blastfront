extends Button
class_name ArmorItemCard

signal armor_hovered(item: ArmorItemData)
signal armor_selected(item: ArmorItemData)

var item: ArmorItemData = null
var _is_hovered: bool = false
var _mark_label: Label = null

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _visual_preview: ArmorVisualPreview = %ArmorPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(54, 54)
	_ensure_mark_label()
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
		_update_mark_label(0)
		tooltip_text = ""
		return

	_visual_preview.visible = _visual_preview.set_armor_item(item)
	_icon_rect.visible = not _visual_preview.visible
	_icon_rect.texture = _get_fallback_texture(item)
	_preview_frame.set_condition_color(item.get_condition_color())
	_apply_background_gradient(item.get_condition_color())
	_update_mark_label(item.get_mark())
	tooltip_text = ""


func _apply_background_gradient(base_color: Color) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(54, 54, base_color, 0.82, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _ensure_mark_label() -> void:
	if _mark_label != null:
		return
	_mark_label = Label.new()
	_mark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mark_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_mark_label.add_theme_font_size_override("font_size", 11)
	_mark_label.add_theme_color_override("font_color", Color8(255, 225, 92, 255))
	_mark_label.add_theme_color_override("font_shadow_color", Color8(0, 0, 0, 220))
	_mark_label.add_theme_constant_override("shadow_offset_x", 1)
	_mark_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_mark_label)
	_mark_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mark_label.offset_left = -38.0
	_mark_label.offset_top = 2.0
	_mark_label.offset_right = -3.0
	_mark_label.offset_bottom = 18.0


func _update_mark_label(item_mark: int) -> void:
	_ensure_mark_label()
	_mark_label.visible = item_mark > 0
	_mark_label.text = _stars_for_mark(item_mark)


func _stars_for_mark(item_mark: int) -> String:
	var filled: int = clampi(item_mark, 1, ArmorItemData.MAX_MARK)
	var result: String = ""
	for star_index in range(ArmorItemData.MAX_MARK):
		result += "★" if star_index < filled else "☆"
	return result


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
