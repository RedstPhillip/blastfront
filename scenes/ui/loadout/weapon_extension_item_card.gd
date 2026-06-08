extends Button
class_name WeaponExtensionItemCard

signal extension_hovered(item: WeaponExtensionItem)
signal extension_selected(item: WeaponExtensionItem)

var item: WeaponExtensionItem = null
var _is_hovered: bool = false

@onready var _background: TextureRect = %Background
@onready var _swatch: ColorRect = %Swatch
@onready var _visual_preview: WeaponExtensionVisualPreview = %VisualPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(54, 54)
	_clear_button_chrome()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	_refresh()


func setup(extension_item: WeaponExtensionItem) -> void:
	item = extension_item
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
		"type": &"weapon_extension_item",
		"item": item,
	}


func _refresh() -> void:
	if _swatch == null:
		return
	if item == null or item.definition == null:
		_swatch.color = Color(0.3, 0.34, 0.38, 1.0)
		_swatch.visible = false
		_visual_preview.clear()
		_visual_preview.visible = false
		_preview_frame.visible = false
		_preview_frame.set_condition_color(Color8(70, 78, 88, 210), false)
		_apply_background_gradient(Color8(70, 78, 88, 210))
		return

	_swatch.color = item.definition.icon_color
	_visual_preview.visible = _visual_preview.set_extension(item)
	_swatch.visible = false
	_preview_frame.visible = false
	_preview_frame.set_condition_color(item.get_condition_color() if _visual_preview.visible else item.definition.icon_color)
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = ""


func _apply_background_gradient(base_color: Color) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(54, 54, base_color, 0.82, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _clear_button_chrome() -> void:
	flat = true
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style_name, empty_style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	if item != null and item.definition != null:
		_apply_background_gradient(item.get_condition_color())


func _on_mouse_exited() -> void:
	_is_hovered = false
	if item != null and item.definition != null:
		_apply_background_gradient(item.get_condition_color())


func _on_pressed() -> void:
	if item != null:
		extension_selected.emit(item)
