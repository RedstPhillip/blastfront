extends LoadoutItemCardBase
class_name ArmorItemCard

signal armor_hovered(item: ArmorItemData)
signal armor_selected(item: ArmorItemData)
signal armor_merge_requested(source_item: ArmorItemData, target_item: ArmorItemData)

var item: ArmorItemData = null

@onready var _icon_rect: TextureRect = %IconRect
@onready var _visual_preview: ArmorVisualPreview = %ArmorPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func setup(armor_item: ArmorItemData) -> void:
	item = armor_item
	if is_node_ready():
		_refresh()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if item == null or not (data is Dictionary):
		return false
	var drop_data: Dictionary = data
	if drop_data.get("type", &"") != &"armor_item":
		return false
	if drop_data.get("source", &"") != &"inventory":
		return false
	var dropped_item: ArmorItemData = drop_data.get("item", null) as ArmorItemData
	return ArmorInventory.can_merge_items(dropped_item, item)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var drop_data: Dictionary = data
	var dropped_item: ArmorItemData = drop_data.get("item", null) as ArmorItemData
	if ArmorInventory.can_merge_items(dropped_item, item):
		armor_merge_requested.emit(dropped_item, item)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	_create_drag_preview()
	return {
		"type": &"armor_item",
		"source": &"inventory",
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
		_set_card_frame(EMPTY_CARD_COLOR, 0)
		tooltip_text = ""
		return

	_visual_preview.visible = _visual_preview.set_armor_item(item)
	_icon_rect.visible = not _visual_preview.visible
	_icon_rect.texture = _get_fallback_texture(item)
	_preview_frame.set_condition_color(item.get_condition_color())
	_set_card_frame(item.get_condition_color(), item.get_mark())
	tooltip_text = ""


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


func _get_fallback_texture(_armor_item: ArmorItemData) -> Texture2D:
	return _create_icon_texture(_armor_item.get_condition_color())


func _emit_hovered() -> void:
	if item != null:
		armor_hovered.emit(item)


func _emit_pressed() -> void:
	if item != null:
		armor_selected.emit(item)


func _mark_text(item_mark: int) -> String:
	return _stars_for_mark(item_mark, ArmorItemData.MAX_MARK)
