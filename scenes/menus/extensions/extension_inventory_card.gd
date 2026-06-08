class_name ExtensionInventoryCard
extends PanelContainer

const DRAG_KIND: String = "weapon_extension_item"

var _item: WeaponExtensionItem = null

@onready var _name_label: Label = %NameLabel
@onready var _slot_label: Label = %SlotLabel
@onready var _condition_label: Label = %ConditionLabel
@onready var _color_swatch: ColorRect = %ColorSwatch


func setup(item: WeaponExtensionItem) -> void:
	_item = item
	_refresh()


func get_item() -> WeaponExtensionItem:
	return _item


func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item == null:
		return null

	var preview_label: Label = Label.new()
	preview_label.text = _item.get_display_name()
	preview_label.add_theme_color_override("font_color", _item.get_condition_color())
	set_drag_preview(preview_label)

	return {
		"kind": DRAG_KIND,
		"item": _item,
	}


func _refresh() -> void:
	if _item == null:
		_name_label.text = "Empty"
		_slot_label.text = ""
		_condition_label.text = ""
		if _color_swatch != null:
			_color_swatch.color = Color(0.3, 0.3, 0.3, 0.5)
		return

	var tier_color: Color = _item.get_condition_color()
	_name_label.text = _item.get_display_name()
	_name_label.add_theme_color_override("font_color", tier_color)
	_slot_label.text = _item.get_slot_display_name().to_upper()
	_condition_label.text = "%s  %.1f" % [_item.get_condition_tier_name(), _item.condition]
	_condition_label.add_theme_color_override("font_color", tier_color)
	if _color_swatch != null and _item.definition != null:
		_color_swatch.color = _item.definition.icon_color
