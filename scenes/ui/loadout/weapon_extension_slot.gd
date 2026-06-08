extends Button
class_name WeaponExtensionSlot

signal extension_hovered(item: WeaponExtensionItem)
signal extension_dropped(item: WeaponExtensionItem)
signal extension_cleared(slot: StringName)

@export var slot: StringName = WeaponExtensionDefinition.SLOT_MIDDLE

var item: WeaponExtensionItem = null
var _is_hovered: bool = false

@onready var _background: TextureRect = %Background
@onready var _swatch: ColorRect = %Swatch
@onready var _visual_preview: WeaponExtensionVisualPreview = %VisualPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(42, 42)
	text = ""
	_clear_button_chrome()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	_refresh()


func setup(extension_slot: StringName, extension_item: WeaponExtensionItem) -> void:
	slot = extension_slot
	item = extension_item
	if is_node_ready():
		_refresh()


func set_item(extension_item: WeaponExtensionItem) -> void:
	item = extension_item
	if is_node_ready():
		_refresh()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var drop_data: Dictionary = data
	if drop_data.get("type", &"") != &"weapon_extension_item":
		return false
	var dropped_item: WeaponExtensionItem = drop_data.get("item", null) as WeaponExtensionItem
	return dropped_item != null and dropped_item.get_slot() == slot


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var drop_data: Dictionary = data
	var dropped_item: WeaponExtensionItem = drop_data.get("item", null) as WeaponExtensionItem
	if dropped_item != null:
		extension_dropped.emit(dropped_item)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	var preview: Control = duplicate() as Control
	if preview != null:
		preview.modulate.a = 0.85
		set_drag_preview(preview)
	var dragged_item: WeaponExtensionItem = item
	extension_cleared.emit(slot)
	return {
		"type": &"weapon_extension_item",
		"item": dragged_item,
	}


func _refresh() -> void:
	if item == null or item.definition == null:
		_swatch.visible = false
		_visual_preview.clear()
		_visual_preview.visible = false
		_preview_frame.visible = false
		_preview_frame.set_condition_color(Color8(46, 54, 61, 210), false)
		_apply_background_gradient(Color8(46, 54, 61, 210), 0.46)
		tooltip_text = ""
		return

	_swatch.color = item.definition.icon_color
	_visual_preview.visible = _visual_preview.set_extension(item)
	_swatch.visible = false
	_preview_frame.visible = false
	_preview_frame.set_condition_color(item.get_condition_color() if _visual_preview.visible else item.definition.icon_color)
	_apply_background_gradient(Color8(74, 78, 82, 230), 0.64)
	tooltip_text = ""


func _apply_background_gradient(base_color: Color, alpha: float) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(42, 42, base_color, alpha, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _clear_button_chrome() -> void:
	flat = true
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style_name, empty_style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_refresh()
	if item != null:
		extension_hovered.emit(item)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh()


func _on_pressed() -> void:
	if item != null:
		extension_cleared.emit(slot)
