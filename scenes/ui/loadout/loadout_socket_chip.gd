class_name LoadoutSocketChip
extends Control

## Labelled socket on a stage (weapon barrel/optic/ammo, operator boots/vest/shield). Shows what is
## installed, accepts drops on behalf of its stage, can be dragged off to remove the part and offers a
## small remove button on hover. Fixed size, so nothing around it moves when its content changes.

signal inspected(chip: LoadoutSocketChip)
signal remove_requested(slot: StringName)
signal selected(slot: StringName)

const CHIP_SIZE: Vector2 = Vector2(180.0, 46.0)
const ICON_BOX: Rect2 = Rect2(4.0, 4.0, 38.0, 38.0)

var slot: StringName = &""
var item: Variant = null
var drop_owner: Control = null
var highlight: float = 0.0
var target_active: bool = false
var compatible_drag: bool = false
var drop_armed: bool = false
var merge_mark: int = 0

var _hover: float = 0.0
var _hovered: bool = false
var _pop: float = 0.0
var _time: float = 0.0
var _remove_hovered: bool = false
var _drag_source: bool = false
var _armor_icon: ArmorVisualPreview = null
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = CHIP_SIZE
	size = CHIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	_style.set_corner_radius_all(6)
	_style.anti_aliasing = true


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hovered = true; set_process(true); inspected.emit(self))
	mouse_exited.connect(func() -> void: _hovered = false; _remove_hovered = false; set_process(true))
	set_process(false)


func set_item(next_item: Variant, animate: bool = false) -> void:
	var changed: bool = next_item != item
	item = next_item
	if changed and animate:
		_pop = 1.0
	_sync_armor_icon()
	set_process(true)
	queue_redraw()


## active: a drag is on; compatible: it can land in this socket; next_merge_mark: when it is the twin of
## the installed part, the mark that dropping it here merges into (0 = it would be installed instead).
func set_drag_state(active: bool, compatible: bool, next_merge_mark: int = 0) -> void:
	target_active = active
	compatible_drag = compatible
	merge_mark = next_merge_mark if compatible else 0
	drop_armed = false
	set_process(true)


## The cursor is over this socket's stage with a compatible part: releasing now drops it here.
func set_armed(armed: bool) -> void:
	drop_armed = armed and target_active and compatible_drag
	queue_redraw()


func get_anchor_global() -> Vector2:
	return global_position + Vector2(size.x * 0.5, size.y * 0.5)


func _remove_rect() -> Rect2:
	return Rect2(size.x - 20.0, 4.0, 16.0, 16.0)


# --- Input & drag ----------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var over_remove: bool = item != null and _remove_rect().has_point(motion.position)
		if over_remove != _remove_hovered:
			_remove_hovered = over_remove
			queue_redraw()
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and item != null:
		remove_requested.emit(slot)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if item != null and _remove_rect().has_point(button.position):
			remove_requested.emit(slot)
		else:
			selected.emit(slot)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	set_drag_preview(LoadoutDragGhost.create_for_item(item, global_position + ICON_BOX.position, get_global_mouse_position()))
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
	highlight = move_toward(highlight, 0.0, delta * 2.5)
	if _armor_icon != null:
		_armor_icon.scale = Vector2.ONE * (1.0 + sin(_pop * PI) * 0.18)
	queue_redraw()
	if not target_active and _pop <= 0.0 and highlight <= 0.0 and (_hover == 0.0 or _hover == 1.0):
		set_process(false)


func _draw() -> void:
	var drop_ready: bool = target_active and compatible_drag
	var drop_color: Color = LoadoutStyle.drop_color(drop_armed, _time)
	var fill: Color = Color(0.13, 0.14, 0.158, 0.92).lerp(LoadoutStyle.CARD_HOVER, _hover)
	_style.set_border_width_all(0)
	if drop_ready:
		fill = fill.lerp(Color(0.24, 0.18, 0.08, 0.95), 0.65 if drop_armed else 0.4)
		_style.border_color = drop_color
		_style.set_border_width_all(2)
	elif target_active:
		fill = Color(fill.r, fill.g, fill.b, fill.a * 0.5)
	elif _hover > 0.0 or highlight > 0.0:
		_style.border_color = Color(1, 1, 1, maxf(0.35 * _hover, highlight * 0.8))
		_style.set_border_width_all(1)
	_style.bg_color = fill
	_style.shadow_size = 0
	var pop_scale: float = 1.0 + sin(_pop * PI) * 0.06
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * pop_scale)
	draw_style_box(_style, Rect2(-size * 0.5, size))
	draw_set_transform(Vector2.ZERO)

	var box: Rect2 = ICON_BOX
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.28))
	if item == null:
		var dash_color: Color = Color(1, 1, 1, 0.18)
		if drop_ready:
			dash_color = drop_color
		var c: Vector2 = box.get_center()
		draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), dash_color, 1.5)
		draw_line(c + Vector2(0, -5), c + Vector2(0, 5), dash_color, 1.5)
	elif item is WeaponExtensionItem:
		WeaponArt.draw_part_icon(self, box.grow(-3.0), (item as WeaponExtensionItem).get_definition_id(), {
			"alpha": 0.3 if _drag_source else 1.0,
			"accent": LoadoutStyle.local_accent(),
			"flash": highlight * 0.5,
		})
	if item != null:
		var grade: Color = _grade_color()
		draw_rect(Rect2(box.position.x, box.end.y - 2.0, box.size.x, 2.0), grade)

	var text_x: float = box.end.x + 7.0
	var merging: bool = drop_ready and merge_mark > 0 and item != null
	var caption_color: Color = LoadoutStyle.ACCENT if drop_ready else LoadoutStyle.TEXT_MUTED
	var caption_text: String = "MERGE" if merging else LoadoutStyle.slot_label(slot)
	draw_string(UiStyle.FONT_BOLD, Vector2(text_x, 18.0), caption_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, caption_color)
	var name_width: float = size.x - text_x - 8.0
	var name_size: int = 12 if size.x > 160.0 else 11
	if item == null:
		draw_string(UiStyle.FONT_BOLD, Vector2(text_x, 35.0), "—", HORIZONTAL_ALIGNMENT_LEFT, name_width, 13, LoadoutStyle.TEXT_MUTED)
		return
	if merging:
		# Dropping the twin here merges: say so in place of the label and name, with the tiles' badge.
		LoadoutStyle.draw_merge_badge(self, Vector2(box.end.x - 5.0, box.position.y + 5.0), 5.0, drop_color)
		var marks: String = "MK %s  ›  MK %s" % [LoadoutStyle.roman(merge_mark - 1), LoadoutStyle.roman(merge_mark)]
		if UiStyle.FONT_BOLD.get_string_size(marks, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > name_width:
			marks = "›  MK %s" % LoadoutStyle.roman(merge_mark)
		draw_string(UiStyle.FONT_BOLD, Vector2(text_x, 35.0), marks, HORIZONTAL_ALIGNMENT_LEFT, name_width, name_size, drop_color)
		return
	draw_string(UiStyle.FONT_BOLD, Vector2(text_x, 35.0), _item_name(), HORIZONTAL_ALIGNMENT_LEFT, name_width, name_size, LoadoutStyle.TEXT)
	var label_width: float = UiStyle.FONT_BOLD.get_string_size(LoadoutStyle.slot_label(slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	LoadoutStyle.draw_pips(self, Vector2(text_x + label_width + 7.0, 11.0), _item_mark(), 3, 1.4, 1.4)
	if _hover <= 0.01:
		return
	var cross_rect: Rect2 = _remove_rect()
	var cross_color: Color = LoadoutStyle.NEGATIVE if _remove_hovered else Color(1, 1, 1, 0.25 + 0.4 * _hover)
	var cc: Vector2 = cross_rect.get_center()
	draw_line(cc + Vector2(-3.2, -3.2), cc + Vector2(3.2, 3.2), cross_color, 1.5, true)
	draw_line(cc + Vector2(3.2, -3.2), cc + Vector2(-3.2, 3.2), cross_color, 1.5, true)


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.0, 3.0, true)


func _item_name() -> String:
	if item is WeaponExtensionItem:
		var full: String = (item as WeaponExtensionItem).get_display_name()
		return full.substr(0, full.rfind(" MK")) if full.rfind(" MK") > 0 else full
	if item is ArmorItemData:
		var title: String = (item as ArmorItemData).get_hover_title()
		return title.substr(0, title.rfind(" MK")) if title.rfind(" MK") > 0 else title
	return ""


func _item_mark() -> int:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).mark
	if item is ArmorItemData:
		return (item as ArmorItemData).get_mark()
	return 0


func _grade_color() -> Color:
	if item is WeaponExtensionItem:
		return (item as WeaponExtensionItem).get_condition_color()
	if item is ArmorItemData:
		return (item as ArmorItemData).get_condition_color()
	return LoadoutStyle.EDGE


func _sync_armor_icon() -> void:
	if item is ArmorItemData:
		if _armor_icon == null:
			_armor_icon = ArmorVisualPreview.new()
			_armor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_armor_icon)
		_armor_icon.position = ICON_BOX.position + Vector2(3.0, 3.0)
		_armor_icon.size = ICON_BOX.size - Vector2(6.0, 6.0)
		_armor_icon.pivot_offset = _armor_icon.size * 0.5
		_armor_icon.visible = true
		_armor_icon.set_armor_item(item)
	elif _armor_icon != null:
		_armor_icon.clear()
		_armor_icon.visible = false
