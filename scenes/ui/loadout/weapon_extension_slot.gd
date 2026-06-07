extends Button
class_name WeaponExtensionSlot

signal extension_hovered(item: WeaponExtensionItem)
signal extension_dropped(item: WeaponExtensionItem)
signal extension_cleared(slot: StringName)

@export var slot: StringName = WeaponExtensionDefinition.SLOT_MIDDLE

var item: WeaponExtensionItem = null

@onready var _background: TextureRect = %Background
@onready var _swatch: ColorRect = %Swatch


func _ready() -> void:
	custom_minimum_size = Vector2(42, 42)
	text = ""
	mouse_entered.connect(_on_mouse_entered)
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
		_apply_background_gradient(Color8(46, 54, 61, 210), 0.46)
		tooltip_text = "Drop %s extension here" % WeaponExtensionDefinition.slot_display_name(slot)
		return

	_swatch.visible = true
	_swatch.color = item.definition.icon_color
	_apply_background_gradient(Color8(74, 78, 82, 230), 0.64)
	tooltip_text = _get_hover_text()


func _get_hover_text() -> String:
	if item == null or item.definition == null:
		return ""
	var lines: Array[String] = []
	lines.append("%s | %s" % [item.get_display_name(), item.get_condition_tier_name()])
	lines.append("%s slot | %d%%" % [item.get_slot_display_name(), int(round(item.condition))])
	if not item.definition.description.is_empty():
		lines.append(item.definition.description)
	return "\n".join(lines)


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
		extension_hovered.emit(item)


func _on_pressed() -> void:
	if item != null:
		extension_cleared.emit(slot)
