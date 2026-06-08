extends Button
class_name RoundRewardSlot

signal reward_hovered(reward: Dictionary)
signal reward_claimed(source_kind: StringName, source_index: int)
signal reward_dropped(payload: Dictionary, target_index: int)

var source_kind: StringName = RoundRewardInventory.SOURCE_OFFER
var source_index: int = -1
@export var is_saved_slot: bool = false
var reward: Dictionary = {}

@onready var _background: TextureRect = %Background
@onready var _icon_rect: TextureRect = %IconRect
@onready var _swatch: ColorRect = %Swatch


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	text = ""
	mouse_entered.connect(_on_mouse_entered)
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
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not is_saved_slot or not (data is Dictionary):
		return false
	var payload: Dictionary = data
	return payload.get("type", &"") == &"round_reward"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	reward_dropped.emit(payload, source_index)


func _refresh() -> void:
	if _background == null or _icon_rect == null or _swatch == null:
		return
	if reward.is_empty():
		_icon_rect.texture = null
		_icon_rect.visible = false
		_swatch.visible = false
		var empty_color: Color = Color8(35, 37, 42, 240) if is_saved_slot else Color8(32, 38, 44, 210)
		_apply_background_gradient(empty_color, 0.72 if is_saved_slot else 0.38)
		tooltip_text = "Drop an item here to save it for the next round." if is_saved_slot else "Reward already claimed or saved."
		return

	var reward_type: StringName = StringName(str(reward.get("type", "")))
	var item_variant: Variant = reward.get("item", null)
	var condition_color: Color = Color8(139, 145, 154, 255)
	_icon_rect.visible = false
	_swatch.visible = false

	if reward_type == RoundRewardInventory.REWARD_EXTENSION:
		var extension_item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if extension_item != null and extension_item.definition != null:
			condition_color = extension_item.get_condition_color()
			_swatch.color = extension_item.definition.icon_color
			_swatch.visible = true
			tooltip_text = _extension_tooltip(extension_item)
	elif reward_type == RoundRewardInventory.REWARD_ARMOR:
		var armor_item: ArmorItemData = item_variant as ArmorItemData
		if armor_item != null:
			condition_color = armor_item.get_condition_color()
			_icon_rect.texture = armor_item.icon if armor_item.icon != null else _create_icon_texture(condition_color)
			_icon_rect.visible = true
			tooltip_text = armor_item.get_hover_text()

	_apply_background_gradient(condition_color, 0.82)


func _extension_tooltip(item: WeaponExtensionItem) -> String:
	var lines: Array[String] = []
	lines.append("%s | %s" % [item.get_display_name(), item.get_condition_tier_name()])
	lines.append("%s | Condition: %d / 100" % [item.get_slot_display_name(), int(round(item.condition))])
	if item.definition != null and not item.definition.description.is_empty():
		lines.append(item.definition.description)
	return "\n".join(lines)


func _apply_background_gradient(base_color: Color, alpha: float) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(base_color.r * 0.28, base_color.g * 0.28, base_color.b * 0.28, alpha),
		Color(base_color.r, base_color.g, base_color.b, alpha),
		Color(1.0, 1.0, 1.0, 0.18),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.gradient = gradient
	_background.texture = texture


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


func _on_mouse_entered() -> void:
	if not reward.is_empty():
		reward_hovered.emit(reward)


func _on_pressed() -> void:
	if not reward.is_empty():
		reward_claimed.emit(source_kind, source_index)
