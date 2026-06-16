extends LoadoutItemCardBase
class_name WeaponExtensionItemCard

signal extension_hovered(item: WeaponExtensionItem)
signal extension_selected(item: WeaponExtensionItem)
signal extension_merge_requested(source_item: WeaponExtensionItem, target_item: WeaponExtensionItem)

var item: WeaponExtensionItem = null

@onready var _swatch: ColorRect = %Swatch
@onready var _visual_preview: WeaponExtensionVisualPreview = %VisualPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func setup(extension_item: WeaponExtensionItem) -> void:
	item = extension_item
	if is_node_ready():
		_refresh()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if item == null or not (data is Dictionary):
		return false
	var drop_data: Dictionary = data
	if drop_data.get("type", &"") != &"weapon_extension_item":
		return false
	if drop_data.get("source", &"") != &"inventory":
		return false
	var dropped_item: WeaponExtensionItem = drop_data.get("item", null) as WeaponExtensionItem
	return ExtensionInventory.can_merge_items(dropped_item, item)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var drop_data: Dictionary = data
	var dropped_item: WeaponExtensionItem = drop_data.get("item", null) as WeaponExtensionItem
	if ExtensionInventory.can_merge_items(dropped_item, item):
		extension_merge_requested.emit(dropped_item, item)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	_create_drag_preview()
	return {
		"type": &"weapon_extension_item",
		"source": &"inventory",
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
		_set_card_frame(EMPTY_CARD_COLOR, 0)
		return

	_swatch.color = item.definition.icon_color
	_visual_preview.visible = _visual_preview.set_extension(item)
	_swatch.visible = false
	_preview_frame.visible = false
	_preview_frame.set_condition_color(item.get_condition_color() if _visual_preview.visible else item.definition.icon_color)
	_set_card_frame(item.get_condition_color(), item.mark)
	tooltip_text = ""


func _emit_hovered() -> void:
	if item != null:
		extension_hovered.emit(item)


func _emit_pressed() -> void:
	if item != null:
		extension_selected.emit(item)


func _mark_text(item_mark: int) -> String:
	return _stars_for_mark(item_mark, GameSettings.EXTENSION_MAX_MARK)
