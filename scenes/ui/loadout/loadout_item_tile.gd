class_name LoadoutItemTile
extends Button

## Locker card for a weapon part or an armor piece. The art carries the card; around it only what the
## player needs at a glance: the mark (II / III, MK I is the default and stays quiet), a condition bar
## whose length is the wear and whose colour is the grade, and an amber frame while the piece is equipped.
## Cards never change size, so the grid never moves.

signal inspected(tile: LoadoutItemTile)
signal activated(tile: LoadoutItemTile)
signal secondary_activated(tile: LoadoutItemTile)
signal merge_requested(source_item: Variant, target_item: Variant)

const TILE_SIZE: Vector2 = Vector2(68.0, 68.0)
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
var _mouse_over: bool = false
var _focused: bool = false
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
	_style.set_corner_radius_all(3)
	_style.anti_aliasing = true


func _ready() -> void:
	mouse_entered.connect(_on_mouse_changed.bind(true))
	mouse_exited.connect(_on_mouse_changed.bind(false))
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	pressed.connect(_on_pressed)
	button_down.connect(func() -> void: _press = 1.0; set_process(true))
	set_process(false)
	_sync_icon()


func set_tile_size(tile_size: Vector2) -> void:
	custom_minimum_size = tile_size
	size = tile_size
	if _armor_icon != null:
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


func is_hovered_tile() -> bool:
	return _hovered


func get_mark() -> int:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).mark
	if item is ArmorItemData:
		return (item as ArmorItemData).get_mark()
	return 0


func get_grade_color() -> Color:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).get_condition_color()
	if item is ArmorItemData:
		return (item as ArmorItemData).get_condition_color()
	return LoadoutStyle.HAIRLINE


func get_condition() -> float:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).condition
	if item is ArmorItemData:
		return (item as ArmorItemData).condition
	return 0.0


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
	if item == null or equipped or not (data is Dictionary):
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


func _on_mouse_changed(entered: bool) -> void:
	_mouse_over = entered
	_update_hovered(entered)


## Keyboard focus only counts as hover for pad players; a mouse click also focuses the card, and that must
## not leave it lit (or inspected) after the pointer has moved on.
func _on_focus_changed(entered: bool) -> void:
	_focused = entered
	_update_hovered(entered and InputDevice.using_gamepad)


func _update_hovered(announce: bool) -> void:
	_hovered = _mouse_over or (_focused and InputDevice.using_gamepad)
	set_process(true)
	if announce and _hovered and item != null:
		inspected.emit(self)


func _on_pressed() -> void:
	if item != null:
		activated.emit(self)


# --- Drawing ---------------------------------------------------------------------------------------------

## The card itself; shop tiles are taller than their card and print the price underneath.
func _card_size() -> Vector2:
	return size


func _art_rect() -> Rect2:
	return Rect2(Vector2(9.0, 8.0), _card_size() - Vector2(18.0, 20.0))


func _draw() -> void:
	if item == null:
		_style.bg_color = LoadoutStyle.CARD_EMPTY
		_style.set_border_width_all(0)
		draw_style_box(_style, Rect2(Vector2.ZERO, _card_size()))
		return
	var ease_hover: float = _hover * _hover * (3.0 - 2.0 * _hover)
	var card_scale: float = (1.0 + sin(_pop * PI) * 0.08) * (1.0 - _press * 0.04)
	var card: Vector2 = _card_size()
	var center: Vector2 = card * 0.5
	var base: Transform2D = Transform2D(0.0, Vector2.ONE * card_scale, 0.0, center + Vector2(0.0, -ease_hover * 1.5))
	draw_set_transform_matrix(base)
	var rect: Rect2 = Rect2(-center, card)

	_style.bg_color = LoadoutStyle.CARD.lerp(LoadoutStyle.CARD_HOVER, ease_hover)
	_style.set_border_width_all(0)
	draw_style_box(_style, rect)
	# A hairline of light along the top edge gives the card a little thickness.
	draw_line(rect.position + Vector2(3.0, 0.5), Vector2(rect.end.x - 3.0, rect.position.y + 0.5), Color(1, 1, 1, 0.05 + 0.05 * ease_hover), 1.0)

	if item is WeaponExtensionItem:
		var art: Rect2 = Rect2(rect.position + _art_rect().position, _art_rect().size).grow(ease_hover * 1.5)
		WeaponArt.draw_part_icon(self, art, (item as WeaponExtensionItem).get_definition_id(), {
			"alpha": 0.25 if _drag_source else 1.0,
			"accent": LoadoutStyle.local_accent(),
			"base": base,
		})
		draw_set_transform_matrix(base)

	_draw_condition(rect)
	var mark: int = get_mark()
	if mark >= 2:
		draw_string(UiStyle.FONT_BOLD, rect.position + Vector2(6.0, 13.0), LoadoutStyle.roman(mark), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LoadoutStyle.ACCENT if mark >= 3 else LoadoutStyle.TEXT_SECONDARY)

	if equipped:
		_style.bg_color = Color(0, 0, 0, 0)
		_style.border_color = LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.9)
		_style.set_border_width_all(2)
		draw_style_box(_style, rect)
		var tab: Vector2 = Vector2(rect.end.x - 8.0, rect.position.y + 8.0)
		LoadoutStyle.draw_check(self, tab, 6.0, LoadoutStyle.ACCENT, LoadoutStyle.SURFACE_DEEP)
	elif drop_highlight:
		var pulse: float = 0.55 + 0.45 * sin(_pulse_time * 7.0)
		_style.bg_color = Color(0, 0, 0, 0)
		_style.border_color = LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, pulse)
		_style.set_border_width_all(2)
		draw_style_box(_style, rect)
	elif ease_hover > 0.0:
		_style.bg_color = Color(0, 0, 0, 0)
		_style.border_color = Color(1, 1, 1, 0.32 * ease_hover)
		_style.set_border_width_all(1)
		draw_style_box(_style, rect)
	if merge_ready and not equipped:
		_draw_merge_badge(Vector2(rect.end.x - 8.0, rect.position.y + 8.0))
	if price >= 0 and _card_size().y >= size.y:
		_draw_price(rect)
	if _drag_source:
		LoadoutStyle.draw_dashed_rect(self, rect.grow(-1.0), Color(1, 1, 1, 0.3), 4.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Condition bar along the bottom: track plus a fill as long as the remaining condition.
func _draw_condition(rect: Rect2) -> void:
	var grade: Color = get_grade_color()
	var track: Rect2 = Rect2(rect.position.x + 8.0, rect.end.y - 7.0, rect.size.x - 16.0, 2.0)
	draw_rect(track, Color(1, 1, 1, 0.07))
	var ratio: float = clampf(get_condition() / 100.0, 0.06, 1.0)
	var alpha: float = 0.35 if _drag_source else 0.95
	draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, track.size.y)), LoadoutStyle.with_alpha(grade, alpha))


func _draw_merge_badge(center: Vector2) -> void:
	draw_circle(center, 5.5, LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.18), true, -1.0, true)
	draw_arc(center, 5.5, 0.0, TAU, 16, LoadoutStyle.ACCENT, 1.2, true)
	draw_line(center + Vector2(-2.6, 0.0), center + Vector2(2.6, 0.0), LoadoutStyle.ACCENT, 1.4)
	draw_line(center + Vector2(0.0, -2.6), center + Vector2(0.0, 2.6), LoadoutStyle.ACCENT, 1.4)


func _draw_price(rect: Rect2) -> void:
	var font: Font = UiStyle.FONT_BOLD
	var text_value: String = str(price)
	var text_width: float = font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var width: float = text_width + 17.0
	var origin: Vector2 = Vector2(rect.end.x - width - 3.0, rect.position.y + 3.0)
	var color: Color = LoadoutStyle.COIN if affordable else LoadoutStyle.NEGATIVE
	var plate: StyleBoxFlat = LoadoutStyle.flat(Color(0.0, 0.0, 0.0, 0.62), 2)
	draw_style_box(plate, Rect2(origin, Vector2(width, 14.0)))
	LoadoutStyle.draw_coin(self, origin + Vector2(6.5, 7.0), 3.4, color)
	draw_string(font, origin + Vector2(12.0, 11.0), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _sync_icon() -> void:
	if item is ArmorItemData:
		if _armor_icon == null:
			_armor_icon = ArmorVisualPreview.new()
			_armor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_armor_icon)
		_armor_icon.size = _art_rect().size
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
	_armor_icon.position = _art_rect().position + Vector2(0.0, -ease_hover * 1.5)
	_armor_icon.scale = Vector2.ONE * (1.0 + sin(_pop * PI) * 0.08) * (1.0 - _press * 0.04) * (1.0 + ease_hover * 0.05)


func _sync_armor_tint() -> void:
	if _armor_icon == null:
		return
	_armor_icon.modulate = Color(0.6, 0.6, 0.6, 0.25) if _drag_source else Color.WHITE
