extends Button
class_name RoundRewardSlot

signal reward_hovered(reward: Dictionary)
signal reward_claimed(source_kind: StringName, source_index: int)
signal reward_dropped(payload: Dictionary, target_index: int)

var source_kind: StringName = RoundRewardInventory.SOURCE_OFFER
var source_index: int = -1
@export var is_saved_slot: bool = false
var reward: Dictionary = {}
var _is_hovered: bool = false
var _mark_label: Label = null

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _swatch: ColorRect = %Swatch
@onready var _price_label: Label = %PriceLabel
@onready var _visual_preview: WeaponExtensionVisualPreview = %VisualPreview
@onready var _armor_preview: ArmorVisualPreview = %ArmorPreview
@onready var _preview_frame: LoadoutPreviewFrame = %PreviewFrame


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	text = ""
	_ensure_mark_label()
	_clear_button_chrome()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	_refresh()


func setup(slot_source_kind: StringName, slot_index: int, saved_slot: bool) -> void:
	source_kind = slot_source_kind
	source_index = slot_index
	is_saved_slot = saved_slot
	if is_node_ready():
		custom_minimum_size = Vector2(64, 64)
		_refresh()


func set_reward(next_reward: Dictionary) -> void:
	reward = next_reward
	if is_node_ready():
		_refresh()


func refresh_affordability() -> void:
	if is_node_ready():
		_refresh_price(false)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if reward.is_empty():
		return null
	var preview: Control = duplicate() as Control
	if preview != null:
		preview.modulate.a = 0.88
		set_drag_preview(preview)
	return {
		"type": &"round_reward",
		"reward_type": StringName(str(reward.get("type", ""))),
		"source_kind": source_kind,
		"source_index": source_index,
		"item": reward.get("item", null),
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if payload.get("type", &"") != &"round_reward":
		return false
	if is_saved_slot:
		return true
	if source_kind != RoundRewardInventory.SOURCE_OFFER:
		return false
	if StringName(str(payload.get("source_kind", ""))) != RoundRewardInventory.SOURCE_SAVED:
		return false
	var reward_type: StringName = StringName(str(payload.get("reward_type", "")))
	return RoundRewardInventory.can_place_reward_in_offer_slot(source_index, reward_type)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	reward_dropped.emit(payload, source_index)


func _refresh() -> void:
	if _background == null or _icon_rect == null or _swatch == null or _price_label == null or _visual_preview == null or _armor_preview == null or _preview_frame == null:
		return
	if reward.is_empty():
		_icon_rect.texture = null
		_icon_rect.visible = false
		_swatch.visible = false
		_price_label.visible = false
		_visual_preview.clear()
		_visual_preview.visible = false
		_armor_preview.clear()
		_armor_preview.visible = false
		_preview_frame.visible = false
		_preview_frame.set_condition_color(Color8(35, 37, 42, 240) if is_saved_slot else Color8(32, 38, 44, 210), false)
		var empty_color: Color = Color8(35, 37, 42, 240) if is_saved_slot else Color8(32, 38, 44, 210)
		_apply_background_gradient(empty_color, 0.72 if is_saved_slot else 0.38)
		_update_mark_label(0)
		tooltip_text = "Drop an item here to save it for the next round." if is_saved_slot else "Reward already claimed or saved."
		return

	var reward_type: StringName = StringName(str(reward.get("type", "")))
	var item_variant: Variant = reward.get("item", null)
	var condition_color: Color = Color8(139, 145, 154, 255)
	_icon_rect.visible = false
	_swatch.visible = false
	_visual_preview.clear()
	_visual_preview.visible = false
	_armor_preview.clear()
	_armor_preview.visible = false
	_preview_frame.visible = true
	_update_mark_label(0)

	if reward_type == RoundRewardInventory.REWARD_EXTENSION:
		var extension_item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if extension_item != null and extension_item.definition != null:
			condition_color = extension_item.get_condition_color()
			_swatch.color = extension_item.definition.icon_color
			_visual_preview.visible = _visual_preview.set_extension(extension_item)
			_swatch.visible = false
			_preview_frame.visible = false
			_preview_frame.set_condition_color(condition_color if _visual_preview.visible else extension_item.definition.icon_color)
			_update_mark_label(extension_item.mark)
			tooltip_text = ""
	elif reward_type == RoundRewardInventory.REWARD_ARMOR:
		var armor_item: ArmorItemData = item_variant as ArmorItemData
		if armor_item != null:
			_update_mark_label(armor_item.get_mark())
			condition_color = armor_item.get_condition_color()
			_armor_preview.visible = _armor_preview.set_armor_item(armor_item)
			_icon_rect.texture = _get_armor_fallback_texture(armor_item)
			_icon_rect.visible = not _armor_preview.visible
			_preview_frame.visible = true
			_preview_frame.set_condition_color(condition_color)
			tooltip_text = ""

	_apply_background_gradient(condition_color, 0.82)
	_refresh_price(true)


func _refresh_price(update_tooltip: bool) -> void:
	if _price_label == null:
		return
	if reward.is_empty():
		_price_label.visible = false
		return
	var price: int = int(reward.get("price", 0))
	var can_afford: bool = OnlineMatch.get_local_coin_balance() >= price
	_price_label.text = "%d C" % price
	_price_label.add_theme_color_override(
		"font_color",
		Color8(255, 219, 92, 255) if can_afford else Color8(245, 105, 92, 255)
	)
	_price_label.visible = true
	if update_tooltip and not tooltip_text.is_empty():
		tooltip_text += "\nPrice: %d coins" % price


func _apply_background_gradient(base_color: Color, alpha: float) -> void:
	_background.texture = LoadoutPreviewFrame.create_condition_texture(64, 64, base_color, alpha, LoadoutPreviewFrame.DEFAULT_CORNER_RADIUS, _is_hovered)


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
	_mark_label.offset_left = -40.0
	_mark_label.offset_top = 2.0
	_mark_label.offset_right = -4.0
	_mark_label.offset_bottom = 18.0


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


func _create_icon_texture(base_color: Color) -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		base_color.darkened(0.5),
		base_color,
		Color(1.0, 1.0, 1.0, 0.32),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 36
	texture.height = 36
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.gradient = gradient
	return texture


func _get_armor_fallback_texture(armor_item: ArmorItemData) -> Texture2D:
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
	_refresh_background_only()
	if not reward.is_empty():
		reward_hovered.emit(reward)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh_background_only()


func _on_pressed() -> void:
	if not reward.is_empty():
		reward_claimed.emit(source_kind, source_index)


func _refresh_background_only() -> void:
	if reward.is_empty():
		var empty_color: Color = Color8(35, 37, 42, 240) if is_saved_slot else Color8(32, 38, 44, 210)
		_apply_background_gradient(empty_color, 0.72 if is_saved_slot else 0.38)
		return

	var reward_type: StringName = StringName(str(reward.get("type", "")))
	var item_variant: Variant = reward.get("item", null)
	if reward_type == RoundRewardInventory.REWARD_EXTENSION:
		var extension_item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		_apply_background_gradient(extension_item.get_condition_color() if extension_item != null else Color8(139, 145, 154, 255), 0.82)
	elif reward_type == RoundRewardInventory.REWARD_ARMOR:
		var armor_item: ArmorItemData = item_variant as ArmorItemData
		_apply_background_gradient(armor_item.get_condition_color() if armor_item != null else Color8(139, 145, 154, 255), 0.82)
	else:
		_apply_background_gradient(Color8(139, 145, 154, 255), 0.82)
