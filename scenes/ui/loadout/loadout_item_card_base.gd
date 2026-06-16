extends Button
class_name LoadoutItemCardBase

const CARD_SIZE: Vector2 = Vector2(54, 54)
const EMPTY_CARD_COLOR: Color = Color8(70, 78, 88, 210)
const MARK_FONT_COLOR: Color = Color8(255, 225, 92, 255)

var _is_hovered: bool = false
var _has_merge_partner: bool = false
var _mark_label: Label = null

@onready var _background: TextureRect = %Background


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	_ensure_mark_label()
	_clear_button_chrome()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	_refresh()


func set_merge_partner_available(is_available: bool) -> void:
	_has_merge_partner = is_available
	if is_node_ready():
		_refresh()


func _create_drag_preview() -> Control:
	var preview: Control = duplicate() as Control
	if preview != null:
		preview.modulate.a = 0.85
		set_drag_preview(preview)
	return preview


func _set_card_frame(base_color: Color, item_mark: int) -> void:
	var card_color: Color = base_color.lightened(0.22) if _has_merge_partner else base_color
	var alpha: float = 0.96 if _has_merge_partner else 0.82
	_background.texture = LoadoutPreviewFrame.create_condition_texture(
		int(CARD_SIZE.x),
		int(CARD_SIZE.y),
		card_color,
		alpha,
		LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS,
		_is_hovered
	)
	_update_mark_label(item_mark)


func _stars_for_mark(item_mark: int, max_mark: int) -> String:
	var filled: int = clampi(item_mark, 1, max_mark)
	var result: String = ""
	for star_index in range(max_mark):
		result += "★" if star_index < filled else "☆"
	return result


func _refresh() -> void:
	return


func _emit_hovered() -> void:
	return


func _emit_pressed() -> void:
	return


func _mark_text(_item_mark: int) -> String:
	return ""


func _ensure_mark_label() -> void:
	if _mark_label != null:
		return
	_mark_label = Label.new()
	_mark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mark_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_mark_label.add_theme_font_size_override("font_size", 11)
	_mark_label.add_theme_color_override("font_color", MARK_FONT_COLOR)
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
	_mark_label.text = _mark_text(item_mark)


func _clear_button_chrome() -> void:
	flat = true
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(style_name, empty_style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_refresh()
	_emit_hovered()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh()


func _on_pressed() -> void:
	_emit_pressed()
