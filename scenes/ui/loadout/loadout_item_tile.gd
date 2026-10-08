class_name LoadoutItemTile
extends Button

## Inventory card for a weapon part or an armor piece: graphite card, the part art, a quality stripe and
## tier pips. Installed cards dim and carry a check; hover brightens; dragging leaves an outline behind.
## Cards never change size, so the grid never moves.

signal inspected(tile: LoadoutItemTile)
signal activated(tile: LoadoutItemTile)
signal secondary_activated(tile: LoadoutItemTile)
signal merge_requested(source_item: Variant, target_item: Variant)

const TILE_SIZE: Vector2 = Vector2(62.0, 62.0)
const HOVER_SPEED: float = 14.0

var item: Variant = null
var equipped: bool = false
var merge_ready: bool = false
var price: int = -1
var affordable: bool = true
var drop_highlight: bool = false

var _hover: float = 0.0
var _press: float = 0.0
var _pop: float = 0.0
var _hovered: bool = false
var _drag_source: bool = false
var _armor_icon: ArmorVisualPreview = null
var _style: StyleBoxFlat = StyleBoxFlat.new()
var _pulse_time: float = 0.0


func _init() -> void:
	custom_minimum_size = TILE_SIZE
	size = TILE_SIZE
	focus_mode = Control.FOCUS_ALL
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_meta("juice_feedback_connected", true)
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		add_theme_stylebox_override(style_name, empty)
	_style.set_corner_radius_all(4)
	_style.anti_aliasing = true


func _ready() -> void:
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	focus_entered.connect(_on_hover_changed.bind(true))
	focus_exited.connect(_on_hover_changed.bind(false))
	pressed.connect(_on_pressed)
	button_down.connect(func() -> void: _press = 1.0; set_process(true))
	set_process(false)
	_sync_icon()


func setup(next_item: Variant, is_equipped: bool = false, has_merge_partner: bool = false) -> void:
	var item_changed: bool = next_item != item
	item = next_item
	equipped = is_equipped
	merge_ready = has_merge_partner and not is_equipped
	disabled = item == null
	focus_mode = Control.FOCUS_NONE if item == null else Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW if item == null else Control.CURSOR_POINTING_HAND
	if item_changed and is_node_ready():
		_sync_icon()
	_sync_armor_tint()
	queue_redraw()


func set_drop_highlight(enabled: bool) -> void:
	if drop_highlight == enabled:
		return
	drop_highlight = enabled
	set_process(true)
	queue_redraw()


func pop() -> void:
	_pop = 1.0
	set_process(true)


func get_mark() -> int:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).mark
	if item is ArmorItemData:
		return (item as ArmorItemData).get_mark()
	return 0


func get_slot() -> StringName:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).get_slot()
	if item is ArmorItemData:
		return (item as ArmorItemData).category
	return &""


# --- Drag & drop -----------------------------------------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	var payload: Dictionary = _build_payload()
	if payload.is_empty():
		return null
	set_drag_preview(LoadoutDragGhost.create(self))
	_drag_source = true
	_sync_armor_tint()
	AudioDirector.play(&"loadout_pickup")
	queue_redraw()
	return payload


func _build_payload() -> Dictionary:
	if item is WeaponExtensionItem:
		return {"type": &"weapon_extension_item", "source": &"inventory", "item": item}
	if item is ArmorItemData:
		return {"type": &"armor_item", "source": &"inventory", "item": item}
	return {}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if item == null or not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if payload.get("source", &"") != &"inventory" or payload.get("item", null) == item:
		return false
	var dropped: Variant = payload.get("item", null)
	if item is WeaponExtensionItem and dropped is WeaponExtensionItem:
		return ExtensionInventory.can_merge_items(dropped, item)
	if item is ArmorItemData and dropped is ArmorItemData:
		return ArmorInventory.can_merge_items(dropped, item)
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	merge_requested.emit(payload.get("item", null), item)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if _drag_source:
			_drag_source = false
			_sync_armor_tint()
			queue_redraw()
		if drop_highlight:
			set_drop_highlight(false)
	elif what == NOTIFICATION_DRAG_BEGIN:
		set_drop_highlight(_can_drop_data(Vector2.ZERO, get_viewport().gui_get_drag_data()))


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and item != null:
		secondary_activated.emit(self)
		accept_event()


# --- Animation -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var target: float = 1.0 if (_hovered and item != null) else 0.0
	_hover = move_toward(_hover, target, delta * HOVER_SPEED)
	_press = move_toward(_press, 0.0, delta * 7.0)
	_pop = move_toward(_pop, 0.0, delta * 3.2)
	_pulse_time += delta
	_layout_armor_icon()
	queue_redraw()
	if is_equal_approx(_hover, target) and _press <= 0.0 and _pop <= 0.0 and not drop_highlight:
		set_process(false)


func _on_hover_changed(entered: bool) -> void:
	_hovered = entered
	set_process(true)
	if entered and item != null:
		inspected.emit(self)


func _on_pressed() -> void:
	if item != null:
		activated.emit(self)


# --- Drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	var w: float = size.x
	if item == null:
		_style.bg_color = LoadoutStyle.CARD_EMPTY
		_style.set_border_width_all(0)
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		return
	var ease_hover: float = _hover * _hover * (3.0 - 2.0 * _hover)
	var card_scale: float = (1.0 + sin(_pop * PI) * 0.07) * (1.0 - _press * 0.04)
	var center: Vector2 = size * 0.5
	var base: Transform2D = Transform2D(0.0, Vector2.ONE * card_scale, 0.0, center + Vector2(0.0, -ease_hover))
	draw_set_transform_matrix(base)
	var rect: Rect2 = Rect2(-center, size)

	_style.bg_color = LoadoutStyle.CARD.lerp(LoadoutStyle.CARD_HOVER, ease_hover)
	_style.set_border_width_all(0)
	var armed: bool = drop_highlight and _drop_armed()
	if drop_highlight:
		_style.border_color = LoadoutStyle.drop_color(armed, _pulse_time)
		_style.set_border_width_all(2)
	elif has_focus() and InputDevice.using_gamepad:
		# The pad cursor: the same accent frame as focused options elsewhere.
		_style.border_color = UiStyle.ACCENT
		_style.set_border_width_all(2)
	elif ease_hover > 0.0:
		_style.border_color = Color(1, 1, 1, 0.4 * ease_hover)
		_style.set_border_width_all(1)
	draw_style_box(_style, rect)
	var dim: bool = equipped or _drag_source
	# Durability along the bottom edge: the bar's length is the condition; it only takes a colour once the
	# part is worn (amber) or nearly broken (red), so a shelf of fresh parts stays calm.
	var condition: float = clampf(float(LoadoutStyle.item_info(item).get("condition", 100.0)) / 100.0, 0.0, 1.0)
	var wear: Color = LoadoutStyle.wear_color(condition)
	if dim:
		wear.a *= 0.45
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, w, 2.0), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, w * condition, 2.0), wear)

	if item is WeaponExtensionItem:
		var icon_rect: Rect2 = Rect2(rect.position + Vector2(9.0, 9.0), size - Vector2(18.0, 21.0)).grow(ease_hover * 1.5)
		WeaponArt.draw_part_icon(self, icon_rect, (item as WeaponExtensionItem).get_definition_id(), {
			"desaturate": 0.85 if dim else 0.0,
			"alpha": 0.22 if _drag_source else (0.4 if equipped else 1.0),
			"accent": LoadoutStyle.local_accent(),
			"base": base,
		})
		draw_set_transform_matrix(base)

	LoadoutStyle.draw_pips(self, rect.position + Vector2(6.0, 6.0), get_mark(), 3, 1.4, 1.4)
	var corner: Vector2 = Vector2(rect.end.x - 9.5, rect.position.y + 9.5)
	if drop_highlight:
		# Every tile that accepts this drop is a merge target, installed or not.
		LoadoutStyle.draw_merge_badge(self, corner, 6.5 if armed else 5.5, LoadoutStyle.drop_color(armed, _pulse_time))
	elif equipped:
		LoadoutStyle.draw_check(self, corner, 6.0, LoadoutStyle.TEXT, LoadoutStyle.BG_BOTTOM)
	elif merge_ready:
		LoadoutStyle.draw_merge_badge(self, corner, 5.5, LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.6 + 0.4 * sin(_pulse_time * 4.0)))
	if price >= 0:
		_draw_price(rect)
	if _drag_source:
		LoadoutStyle.draw_dashed_rect(self, rect.grow(-1.0), Color(1, 1, 1, 0.35), 4.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _drop_armed() -> bool:
	return is_inside_tree() and get_viewport().gui_is_dragging() and get_global_rect().has_point(get_global_mouse_position())


func _draw_price(rect: Rect2) -> void:
	var font: Font = UiStyle.FONT_BOLD
	var text_value: String = str(price)
	var width: float = font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	var origin: Vector2 = Vector2(rect.end.x - width - 3.0, rect.end.y - 18.0)
	var color: Color = WeaponArt.GOLD if affordable else LoadoutStyle.NEGATIVE
	draw_rect(Rect2(origin, Vector2(width, 13.0)), Color(0.0, 0.0, 0.0, 0.65))
	var diamond: Vector2 = origin + Vector2(5.0, 6.5)
	draw_colored_polygon(PackedVector2Array([diamond + Vector2(0, -2.6), diamond + Vector2(2.6, 0), diamond + Vector2(0, 2.6), diamond + Vector2(-2.6, 0)]), color)
	draw_string(font, origin + Vector2(10.0, 10.5), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _sync_icon() -> void:
	if item is ArmorItemData:
		if _armor_icon == null:
			_armor_icon = ArmorVisualPreview.new()
			_armor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_armor_icon)
		_armor_icon.size = size - Vector2(18.0, 21.0)
		_armor_icon.pivot_offset = _armor_icon.size * 0.5
		_layout_armor_icon()
		_armor_icon.visible = true
		_armor_icon.set_armor_item(item)
	elif _armor_icon != null:
		_armor_icon.clear()
		_armor_icon.visible = false
	_sync_armor_tint()


func _layout_armor_icon() -> void:
	if _armor_icon == null:
		return
	var ease_hover: float = _hover * _hover * (3.0 - 2.0 * _hover)
	_armor_icon.position = Vector2(9.0, 9.0 - ease_hover)
	_armor_icon.scale = Vector2.ONE * (1.0 + sin(_pop * PI) * 0.07) * (1.0 - _press * 0.04) * (1.0 + ease_hover * 0.05)


func _sync_armor_tint() -> void:
	if _armor_icon == null:
		return
	if _drag_source:
		_armor_icon.modulate = Color(0.6, 0.6, 0.6, 0.22)
	elif equipped:
		_armor_icon.modulate = Color(0.55, 0.55, 0.55, 0.42)
	else:
		_armor_icon.modulate = Color.WHITE
