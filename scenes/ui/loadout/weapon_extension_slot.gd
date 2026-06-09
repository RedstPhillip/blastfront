extends Button
class_name WeaponExtensionSlot

signal extension_hovered(item: WeaponExtensionItem)
signal extension_dropped(item: WeaponExtensionItem)
signal extension_cleared(slot: StringName)

@export var slot: StringName = WeaponExtensionDefinition.SLOT_MIDDLE

var item: WeaponExtensionItem = null
var _is_hovered: bool = false
var _mark_label: Label = null

@onready var _background: TextureRect = %Background
@onready var _swatch: ColorRect = %Swatch
@onready var _visual_preview: WeaponExtensionVisualPreview = %VisualPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(42, 42)
	text = ""
	_ensure_mark_label()
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
		"source": &"slot",
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
		_update_mark_label(0)
		tooltip_text = ""
		return

	_swatch.color = item.definition.icon_color
	_visual_preview.visible = _visual_preview.set_extension(item)
	_swatch.visible = false
	_preview_frame.visible = false
	_preview_frame.set_condition_color(item.get_condition_color() if _visual_preview.visible else item.definition.icon_color)
	_apply_background_gradient(item.get_condition_color(), 0.82)
	_update_mark_label(item.mark)
	tooltip_text = ""


func _apply_background_gradient(base_color: Color, alpha: float) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(42, 42, base_color, alpha, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


func _clear_button_chrome() -> void:
	flat = true
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style_name, empty_style)


func _ensure_mark_label() -> void:
	if _mark_label != null:
		return
	_mark_label = Label.new()
	_mark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mark_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_mark_label.add_theme_font_size_override("font_size", 9)
	_mark_label.add_theme_color_override("font_color", Color8(255, 225, 92, 255))
	_mark_label.add_theme_color_override("font_shadow_color", Color8(0, 0, 0, 220))
	_mark_label.add_theme_constant_override("shadow_offset_x", 1)
	_mark_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_mark_label)
	_mark_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mark_label.offset_left = -32.0
	_mark_label.offset_top = 1.0
	_mark_label.offset_right = -2.0
	_mark_label.offset_bottom = 14.0


func _update_mark_label(item_mark: int) -> void:
	_ensure_mark_label()
	_mark_label.visible = item_mark > 0
	_mark_label.text = _stars_for_mark(item_mark)


func _stars_for_mark(item_mark: int) -> String:
	var filled: int = clampi(item_mark, 1, GameSettings.EXTENSION_MAX_MARK)
	var result: String = ""
	for star_index in range(GameSettings.EXTENSION_MAX_MARK):
		result += "★" if star_index < filled else "☆"
	return result


func _on_mouse_entered() -> void:
	_is_hovered = true
	if item == null or item.definition == null:
		_apply_background_gradient(Color8(46, 54, 61, 210), 0.46)
	else:
		_apply_background_gradient(item.get_condition_color(), 0.82)
		extension_hovered.emit(item)


func _on_mouse_exited() -> void:
	_is_hovered = false
	if item == null or item.definition == null:
		_apply_background_gradient(Color8(46, 54, 61, 210), 0.46)
	else:
		_apply_background_gradient(item.get_condition_color(), 0.82)


func _on_pressed() -> void:
	if item != null:
		extension_cleared.emit(slot)
