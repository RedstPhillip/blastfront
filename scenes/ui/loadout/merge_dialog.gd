class_name LoadoutMergeDialog
extends Control

## Merge confirmation: a feathered ink band across the loadout that reads as an equation — both copies,
## then the result one mark up with the condition it will really have — plus what the upgrade changes and
## one amber button. Enter / A merges, Esc / B or a click outside the band cancels. On confirm the copies
## slide into the result, it flashes, and the band lets go.

signal confirmed
signal cancelled

const SOURCE_ICON: Vector2 = Vector2(84.0, 62.0)
const RESULT_ICON: Vector2 = Vector2(118.0, 86.0)
const COLUMN_WIDTH: float = 520.0
const ROW_LIMIT: int = 3
const FUSE_SECONDS: float = 0.24
const HOLD_SECONDS: float = 0.5

var _source: Variant = null
var _target: Variant = null
var _result: Variant = null
var _rows: Array = []
var _cost: int = 0
var _balance: int = 0
var _interactive: bool = false
var _reveal: float = 0.0
var _result_in: float = 0.0
var _fuse: float = 0.0
var _flash: float = 0.0
var _tween: Tween = null
var _previous_focus: Control = null
var _merge_button: Button = null
var _cancel_button: Button = null


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cancel_button = _make_button("CANCEL", false)
	_cancel_button.pressed.connect(cancel)
	_merge_button = _make_button("MERGE", true)
	_merge_button.pressed.connect(confirm)
	set_process(false)


func _ready() -> void:
	_merge_button.focus_neighbor_left = _merge_button.get_path_to(_cancel_button)
	_cancel_button.focus_neighbor_right = _cancel_button.get_path_to(_merge_button)


## source / target are the two copies, result is the item the merge will produce (not yet in the inventory),
## rows are stat changes ({name, value, color}) from installing the result instead of the better copy.
func open(source: Variant, target: Variant, result: Variant, rows: Array, cost: int, balance: int) -> void:
	_source = source
	_target = target
	_result = result
	_rows = rows.slice(0, ROW_LIMIT)
	_cost = cost
	_balance = balance
	_fuse = 0.0
	_flash = 0.0
	_interactive = true
	visible = true
	move_to_front()
	_layout_buttons()
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	_previous_focus = focus_owner if focus_owner != null and not is_ancestor_of(focus_owner) else null
	_merge_button.grab_focus()
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "_reveal", 1.0, 0.2).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_result_in", 1.0, 0.24).from(0.0).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_process(true)


## True while the band is up (including its short outro), so the page underneath stays put.
func is_open() -> bool:
	return visible


func confirm() -> void:
	if not _interactive:
		return
	_interactive = false
	_release_focus()
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "_fuse", 1.0, FUSE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		_flash = 1.0
		confirmed.emit())
	_tween.tween_property(self, "_flash", 0.0, HOLD_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_reveal", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_close)


func cancel() -> void:
	if not _interactive:
		return
	_interactive = false
	_release_focus()
	cancelled.emit()
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "_reveal", 0.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_close)


func _close() -> void:
	visible = false
	set_process(false)
	_source = null
	_target = null
	_result = null


func _release_focus() -> void:
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	elif get_viewport().gui_get_focus_owner() != null and is_ancestor_of(get_viewport().gui_get_focus_owner()):
		get_viewport().gui_release_focus()
	_previous_focus = null


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _process(_delta: float) -> void:
	_merge_button.modulate.a = _reveal * (1.0 - _fuse)
	_cancel_button.modulate.a = _merge_button.modulate.a
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _interactive and (event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE)):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton:
		# Everything else stays with the band (Enter / A press the focused button), never the page below.
		if not (event.is_action(&"ui_accept") or event.is_action(&"ui_left") or event.is_action(&"ui_right")):
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and not _band_rect().has_point(click.position):
		cancel()
	accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _merge_button != null:
		_layout_buttons()


# --- Layout ----------------------------------------------------------------------------------------------

func _make_button(text_value: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	UiStyle.style_button(button, primary, 15)
	if primary:
		# The band opens with focus on MERGE; keep it plain amber so hovering still brightens it.
		button.add_theme_stylebox_override("focus", button.get_theme_stylebox(&"normal"))
	button.custom_minimum_size = Vector2(150.0 if primary else 112.0, 36.0)
	button.size = button.custom_minimum_size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)
	return button


func _band_rect() -> Rect2:
	var center_y: float = size.y * 0.5
	return Rect2(0.0, center_y - 168.0, size.x, 340.0)


func _layout_buttons() -> void:
	var center: Vector2 = size * 0.5
	var right: float = center.x + COLUMN_WIDTH * 0.5
	var y: float = center.y + 118.0
	_merge_button.position = Vector2(right - _merge_button.size.x, y)
	_cancel_button.position = Vector2(_merge_button.position.x - 10.0 - _cancel_button.size.x, y)


# --- Drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	if _result == null:
		return
	var reveal: float = _reveal
	var center: Vector2 = size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.6 * reveal))
	_draw_band(reveal)

	var lift: float = (1.0 - reveal) * 10.0
	var info: Dictionary = LoadoutStyle.item_info(_result)
	var column_left: float = center.x - COLUMN_WIDTH * 0.5
	var content_alpha: float = reveal
	_draw_text_centered("MERGE  ·  %s" % LoadoutStyle.slot_label(info.get("slot", &"")), UiStyle.FONT_BOLD, 11,
		center.y - 134.0 + lift, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, LoadoutStyle.TEXT_MUTED.a * content_alpha))
	_draw_text_centered(str(info.get("name", "")), UiStyle.FONT_DISPLAY, 24, center.y - 106.0 + lift,
		LoadoutStyle.with_alpha(LoadoutStyle.TEXT, content_alpha))

	# The equation: copy + copy › result. On confirm the copies travel into the result.
	var icon_y: float = center.y - 34.0 + lift
	var result_center: Vector2 = Vector2(center.x + 150.0, icon_y)
	var fuse: float = _fuse
	var copies_alpha: float = content_alpha * (1.0 - fuse)
	var source_center: Vector2 = Vector2(center.x - 196.0, icon_y).lerp(result_center, fuse)
	var target_center: Vector2 = Vector2(center.x - 76.0, icon_y).lerp(result_center, fuse)
	var operator_color: Color = LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, LoadoutStyle.TEXT_MUTED.a * copies_alpha)
	_draw_plus(Vector2(center.x - 136.0, icon_y), operator_color)
	_draw_chevron(Vector2(center.x + 36.0, icon_y), LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.8 * copies_alpha))
	_draw_item(_source, source_center, SOURCE_ICON * lerpf(1.0, 0.7, fuse), copies_alpha, false)
	_draw_item(_target, target_center, SOURCE_ICON * lerpf(1.0, 0.7, fuse), copies_alpha, false)
	var pop: float = 1.0 + sin(clampf(_flash, 0.0, 1.0) * PI) * 0.08
	_draw_item(_result, result_center, RESULT_ICON * lerpf(0.86, 1.0, _result_in) * pop, content_alpha * clampf(_result_in, 0.0, 1.0), true)

	# What the upgrade changes on the weapon / operator, in the inspector's words.
	var rows_alpha: float = content_alpha * (1.0 - fuse)
	var row_y: float = center.y + 54.0 + lift
	for row in _rows:
		var entry: Dictionary = row
		var name_color: Color = entry.get("name_color", LoadoutStyle.TEXT_SECONDARY)
		var value_color: Color = entry.get("color", LoadoutStyle.TEXT)
		draw_string(UiStyle.FONT_BODY, Vector2(center.x - 150.0, row_y), str(entry.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 170.0, 13,
			LoadoutStyle.with_alpha(name_color, name_color.a * rows_alpha))
		draw_string(UiStyle.FONT_BOLD, Vector2(center.x + 20.0, row_y), str(entry.get("value", "")), HORIZONTAL_ALIGNMENT_RIGHT, 130.0, 13,
			LoadoutStyle.with_alpha(value_color, value_color.a * rows_alpha))
		row_y += 20.0

	# Footer: price and what is left, then the buttons (children, laid out on the right).
	var footer_alpha: float = content_alpha * (1.0 - fuse)
	var footer_y: float = center.y + 136.0
	LoadoutStyle.draw_coin(self, Vector2(column_left + 7.0, footer_y), 6.5, LoadoutStyle.with_alpha(LoadoutStyle.COIN, footer_alpha))
	var cost_text: String = str(_cost)
	draw_string(UiStyle.FONT_DISPLAY, Vector2(column_left + 20.0, footer_y + 7.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		LoadoutStyle.with_alpha(LoadoutStyle.COIN, footer_alpha))
	var cost_width: float = UiStyle.FONT_DISPLAY.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(UiStyle.FONT_BOLD, Vector2(column_left + 28.0 + cost_width, footer_y + 5.0), "%d  ›  %d LEFT" % [_balance, _balance - _cost],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, LoadoutStyle.TEXT_MUTED.a * footer_alpha))


## Full-width ink band feathered at top and bottom, like the round banners.
func _draw_band(alpha: float) -> void:
	var band: Rect2 = _band_rect()
	var feather: float = 46.0
	var ink: Color = Color(0.02, 0.02, 0.019, 0.985 * alpha)
	var clear: Color = Color(ink.r, ink.g, ink.b, 0.0)
	LoadoutStyle.draw_gradient_rect(self, Rect2(band.position.x, band.position.y - feather, band.size.x, feather), clear, ink)
	draw_rect(band, ink)
	LoadoutStyle.draw_gradient_rect(self, Rect2(band.position.x, band.end.y, band.size.x, feather), ink, clear)
	if _flash > 0.0:
		var glow: Color = LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, 0.16 * _flash * alpha)
		LoadoutStyle.draw_glow(self, Vector2(size.x * 0.5 + 150.0, band.get_center().y - 34.0), Vector2(220.0, 120.0), glow)


func _draw_item(item: Variant, center: Vector2, icon_size: Vector2, alpha: float, is_result: bool) -> void:
	if item == null or alpha <= 0.01:
		return
	var info: Dictionary = LoadoutStyle.item_info(item)
	var mark: int = int(info.get("mark", 1))
	var condition: float = clampf(float(info.get("condition", 100.0)) / 100.0, 0.0, 1.0)
	var icon_rect: Rect2 = Rect2(center - icon_size * 0.5, icon_size)
	if is_result:
		LoadoutStyle.draw_brackets(self, icon_rect.grow(8.0), LoadoutStyle.with_alpha(LoadoutStyle.ACCENT, alpha), 10.0, 2.0)
		if _flash > 0.0:
			draw_rect(icon_rect.grow(8.0), LoadoutStyle.with_alpha(UiStyle.ACCENT_HOT, 0.25 * _flash * alpha))
	if item is WeaponExtensionItem:
		WeaponArt.draw_part_icon(self, icon_rect, (item as WeaponExtensionItem).get_definition_id(), {
			"alpha": alpha,
			"accent": LoadoutStyle.local_accent(),
			"max_scale": 3.4,
			"flash": _flash * 0.6 if is_result else 0.0,
		})
	elif item is ArmorItemData:
		var armor: ArmorItemData = item
		var fit: Vector2 = icon_size * 0.92
		ArmorArt.draw_icon(self, Rect2(center - fit * 0.5, fit), ArmorArt.art_id_for(armor), armor.get_mark(), {
			"team": LoadoutStyle.local_accent(),
			"max_scale": 3.4,
			"alpha": alpha,
			"flash": _flash * 0.6 if is_result else 0.0,
		})
		draw_set_transform_matrix(Transform2D.IDENTITY)

	# Mark, condition value and the durability bar under the art.
	var label_y: float = icon_rect.end.y + (22.0 if is_result else 18.0)
	var bar_width: float = icon_size.x * (0.9 if is_result else 0.8)
	var left: float = center.x - bar_width * 0.5
	var mark_text: String = "MK %s" % LoadoutStyle.roman(mark)
	var mark_color: Color = LoadoutStyle.ACCENT if is_result else LoadoutStyle.TEXT_SECONDARY
	var font_size: int = 13 if is_result else 11
	draw_string(UiStyle.FONT_BOLD, Vector2(left, label_y), mark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		LoadoutStyle.with_alpha(mark_color, mark_color.a * alpha))
	var percent: String = "%d%%" % roundi(condition * 100.0)
	var percent_color: Color = LoadoutStyle.TEXT if is_result else LoadoutStyle.TEXT_SECONDARY
	draw_string(UiStyle.FONT_BOLD, Vector2(left, label_y), percent, HORIZONTAL_ALIGNMENT_RIGHT, bar_width, font_size,
		LoadoutStyle.with_alpha(percent_color, percent_color.a * alpha))
	var bar_y: float = label_y + 6.0
	var wear: Color = LoadoutStyle.wear_color(condition)
	if is_result and condition >= 0.6:
		wear = LoadoutStyle.TEXT
	draw_rect(Rect2(left, bar_y, bar_width, 2.0), Color(1.0, 1.0, 1.0, 0.08 * alpha))
	draw_rect(Rect2(left, bar_y, bar_width * condition, 2.0), LoadoutStyle.with_alpha(wear, wear.a * alpha))


func _draw_plus(at: Vector2, color: Color) -> void:
	draw_line(at + Vector2(-6.0, 0.0), at + Vector2(6.0, 0.0), color, 2.0, true)
	draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0), color, 2.0, true)


func _draw_chevron(at: Vector2, color: Color) -> void:
	draw_line(at + Vector2(-22.0, 0.0), at + Vector2(10.0, 0.0), LoadoutStyle.with_alpha(color, color.a * 0.45), 2.0, true)
	draw_polyline(PackedVector2Array([at + Vector2(4.0, -7.0), at + Vector2(12.0, 0.0), at + Vector2(4.0, 7.0)]), color, 2.0, true)


func _draw_text_centered(text_value: String, font: Font, font_size: int, baseline: float, color: Color) -> void:
	draw_string(font, Vector2(0.0, baseline), text_value, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
