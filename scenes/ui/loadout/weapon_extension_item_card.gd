extends Button
class_name WeaponExtensionItemCard

signal extension_hovered(item: WeaponExtensionItem)
signal extension_selected(item: WeaponExtensionItem)

var item: WeaponExtensionItem = null

@onready var _background: TextureRect = %Background
@onready var _swatch: ColorRect = %Swatch
@onready var _name_label: Label = %NameLabel
@onready var _meta_label: Label = %MetaLabel


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
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
	if _name_label == null or _meta_label == null:
		return
	if item == null or item.definition == null:
		_name_label.text = "Empty"
		_meta_label.text = ""
		_swatch.color = Color(0.3, 0.34, 0.38, 1.0)
		_apply_background_gradient(Color8(70, 78, 88, 210))
		return

	_name_label.text = item.get_display_name()
	_meta_label.text = "%s - %d%%" % [item.get_slot_display_name(), int(round(item.condition))]
	_swatch.color = item.definition.icon_color
	_apply_background_gradient(item.get_condition_color())
	tooltip_text = _get_hover_text()


func _get_hover_text() -> String:
	if item == null or item.definition == null:
		return ""
	var lines: Array[String] = []
	lines.append("%s | Mark %d | %s" % [item.get_slot_display_name(), item.definition.mark, item.get_condition_tier_name()])
	lines.append("Condition: %d / 100" % int(round(item.condition)))
	if not item.definition.description.is_empty():
		lines.append(item.definition.description)
	return "\n".join(lines)


func _apply_background_gradient(base_color: Color) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		base_color.darkened(0.62),
		Color(base_color.r, base_color.g, base_color.b, 0.82),
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


func _on_mouse_entered() -> void:
	if item != null:
		extension_hovered.emit(item)


func _on_pressed() -> void:
	if item != null:
		extension_selected.emit(item)
