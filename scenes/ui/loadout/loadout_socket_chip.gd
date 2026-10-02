class_name LoadoutSocketChip
extends Control

## Callout for one socket on the bench (weapon barrel / optic / ammo, operator shield / vest / boots):
## a short tick, the slot name and what is fitted. The stage draws a leader from the tick to the part.
## No box around it; the tick and type do the work. Accepts drops on behalf of its stage, can be dragged
## off to take the part out, right click removes, left click shows the matching parts in the locker.

signal inspected(chip: LoadoutSocketChip)
signal remove_requested(slot: StringName)
signal selected(slot: StringName)

const CHIP_SIZE: Vector2 = Vector2(156.0, 36.0)
const TICK_WIDTH: float = 2.0
const TEXT_INSET: float = 10.0
## What a socket holds when nothing is fitted: the carbine always has a barrel, sights and rounds.
const STOCK_NAMES: Dictionary = {
	&"front": "Stock barrel", &"middle": "Iron sights", &"ammo": "Standard rounds",
	&"shield": "None", &"vest": "None", &"boots": "None",
}

var slot: StringName = &""
var item: Variant = null
var drop_owner: Control = null
var align_right: bool = false
var highlight: float = 0.0
var target_active: bool = false
var compatible_drag: bool = false
var linked: bool = false

var _hover: float = 0.0
var _hovered: bool = false
var _pop: float = 0.0
var _time: float = 0.0
var _drag_source: bool = false


func _init() -> void:
	custom_minimum_size = CHIP_SIZE
	size = CHIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hovered = true; set_process(true); inspected.emit(self))
	mouse_exited.connect(func() -> void: _hovered = false; set_process(true))
	set_process(false)


func set_item(next_item: Variant, animate: bool = false) -> void:
	var changed: bool = next_item != item
	item = next_item
	if changed and animate:
		_pop = 1.0
	set_process(true)
	queue_redraw()


func set_drag_state(active: bool, compatible: bool) -> void:
	target_active = active
	compatible_drag = compatible
	set_process(true)


func set_linked(value: bool) -> void:
	if linked != value:
		linked = value
		queue_redraw()


func is_hot() -> bool:
	return _hovered or (target_active and compatible_drag) or linked


## Where the stage's leader line meets this callout (local coordinates).
func tick_point() -> Vector2:
	return Vector2(size.x if align_right else 0.0, size.y * 0.5)


## Colour of the tick and leader for the current state.
func accent_color() -> Color:
	var pulse: float = 0.5 + 0.5 * sin(_time * 6.5)
	if target_active and compatible_drag:
		return LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.65 + 0.35 * pulse)
	if linked:
		return LoadoutStyle.ACCENT
	if target_active:
		return Color(1, 1, 1, 0.12)
	var base: Color = LoadoutStyle.TEXT if item != null else LoadoutStyle.TEXT_MUTED
	return base.lerp(Color.WHITE, _hover * 0.4).lerp(LoadoutStyle.ACCENT, highlight)


# --- Input & drag ----------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and item != null:
		remove_requested.emit(slot)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(slot)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	set_drag_preview(LoadoutDragGhost.create_for_item(item, get_global_mouse_position() - LoadoutItemTile.TILE_SIZE * 0.5, get_global_mouse_position()))
	_drag_source = true
	AudioDirector.play(&"loadout_pickup")
	queue_redraw()
	var type: StringName = &"weapon_extension_item" if item is WeaponExtensionItem else &"armor_item"
	return {"type": type, "source": &"slot", "item": item, "slot": slot}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if drop_owner == null:
		return false
	return drop_owner._can_drop_data(at_position + position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drop_owner != null:
		drop_owner._drop_data(at_position + position, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_source:
		_drag_source = false
		queue_redraw()
		if not get_viewport().gui_is_drag_successful() and drop_owner != null:
			var stage_rect: Rect2 = drop_owner.get_global_rect()
			if not stage_rect.has_point(drop_owner.get_global_mouse_position()):
				remove_requested.emit(slot)


# --- Drawing ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_hover = move_toward(_hover, 1.0 if _hovered else 0.0, delta * 12.0)
	_pop = move_toward(_pop, 0.0, delta * 3.0)
	highlight = move_toward(highlight, 0.0, delta * 2.0)
	queue_redraw()
	if not target_active and _pop <= 0.0 and highlight <= 0.0 and (_hover == 0.0 or _hover == 1.0):
		set_process(false)


func _draw() -> void:
	var dimmed: bool = target_active and not compatible_drag
	var alpha: float = 0.35 if dimmed else 1.0
	var accent: Color = accent_color()
	var tick_x: float = size.x - TICK_WIDTH if align_right else 0.0
	var pop: float = sin(_pop * PI)
	draw_rect(Rect2(tick_x, 2.0 - pop * 2.0, TICK_WIDTH, size.y - 4.0 + pop * 4.0), LoadoutStyle.with_alpha(accent, accent.a * alpha))

	var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
	var text_x: float = 0.0 if align_right else TEXT_INSET
	var text_width: float = size.x - TEXT_INSET
	var caption_color: Color = LoadoutStyle.TEXT_MUTED.lerp(LoadoutStyle.TEXT_SECONDARY, _hover)
	if (target_active and compatible_drag) or linked:
		caption_color = LoadoutStyle.ACCENT
	var caption: String = LoadoutStyle.slot_label(slot)
	var info: Dictionary = LoadoutStyle.item_info(item)
	if not info.is_empty() and int(info["mark"]) >= 2:
		caption += "  " + LoadoutStyle.roman(int(info["mark"]))
	draw_string(UiStyle.FONT_BOLD, Vector2(text_x, 12.0), caption, alignment, text_width, 10, LoadoutStyle.with_alpha(caption_color, caption_color.a * alpha))

	var name_text: String = str(STOCK_NAMES.get(slot, "None")) if info.is_empty() else str(info["name"])
	var name_color: Color = LoadoutStyle.TEXT_MUTED if info.is_empty() else LoadoutStyle.TEXT
	if _drag_source:
		name_color = LoadoutStyle.TEXT_MUTED
	var font_size: int = 15
	while font_size > 11 and UiStyle.FONT_UI.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width - 12.0:
		font_size -= 1
	draw_string(UiStyle.FONT_UI, Vector2(text_x, 30.0), name_text, alignment, text_width, font_size, LoadoutStyle.with_alpha(name_color, name_color.a * alpha))
	if not info.is_empty():
		# Grade dot after (or before, when right aligned) the name.
		var name_width: float = minf(UiStyle.FONT_UI.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, text_width)
		var dot_x: float = (size.x - TEXT_INSET - name_width - 8.0) if align_right else (text_x + name_width + 8.0)
		draw_circle(Vector2(dot_x, 25.0), 2.5, LoadoutStyle.with_alpha(info["color"], alpha), true, -1.0, true)
