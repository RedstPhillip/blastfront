class_name LoadoutInspector
extends PanelContainer

## Details panel: a large preview of whatever is under the cursor (the whole carbine when nothing is),
## its name and quality, and the stat changes it would cause. Every section has a fixed height so moving
## across the inventory never makes anything jump.

const ROW_COUNT: int = 6

var preview_height: float = 112.0
var row_count: int = ROW_COUNT

var _preview: Control = null
var _armor_icon: ArmorVisualPreview = null
var _title: Label = null
var _subtitle: Label = null
var _grade: Label = null
var _condition_track: Control = null
var _condition_value: float = -1.0
var _condition_color: Color = Color.WHITE
var _description: Label = null
var _rows_caption: Label = null
var _rows: Array[Dictionary] = []
var _hint: Label = null
var _kind: StringName = &""
var _id: StringName = &""
var _mark: int = 0
var _config: Dictionary = {}
var _accent_color: Color = Color.WHITE
var _flash: float = 0.0
var _reveal: float = 1.0


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0.0, preview_height)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.clip_contents = true
	_preview.draw.connect(_draw_preview)
	column.add_child(_preview)
	_armor_icon = ArmorVisualPreview.new()
	_armor_icon.visible = false
	_preview.add_child(_armor_icon)
	_preview.resized.connect(_layout_armor_preview)

	_subtitle = _label(UiStyle.FONT_BOLD, 10, LoadoutStyle.TEXT_MUTED)
	column.add_child(_subtitle)
	_title = _label(UiStyle.FONT_DISPLAY, 19, LoadoutStyle.TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size = Vector2(10.0, 24.0)
	column.add_child(_title)
	_grade = _label(UiStyle.FONT_BOLD, 10, LoadoutStyle.TEXT_SECONDARY)
	_grade.custom_minimum_size = Vector2(10.0, 14.0)
	column.add_child(_grade)
	_condition_track = Control.new()
	_condition_track.custom_minimum_size = Vector2(0.0, 3.0)
	_condition_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_condition_track.draw.connect(_draw_condition)
	column.add_child(_condition_track)
	_description = _label(UiStyle.FONT_BODY, 13, LoadoutStyle.TEXT_SECONDARY)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(10.0, 34.0)
	_description.max_lines_visible = 4
	_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	column.add_child(_description)
	_rows_caption = _label(UiStyle.FONT_BOLD, 10, LoadoutStyle.TEXT_MUTED)
	column.add_child(_rows_caption)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rows)
	for index in range(row_count):
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 21.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label: Label = _label(UiStyle.FONT_BODY, 13, LoadoutStyle.TEXT_SECONDARY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var value_label: Label = _label(UiStyle.FONT_BOLD, 13, LoadoutStyle.TEXT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_label)
		row.add_child(value_label)
		rows.add_child(row)
		_rows.append({"row": row, "name": name_label, "value": value_label})
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_hint = _label(UiStyle.FONT_BOLD, 10, LoadoutStyle.TEXT_MUTED)
	_hint.custom_minimum_size = Vector2(10.0, 14.0)
	column.add_child(_hint)
	set_process(false)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.5, 0.0)
	_reveal = minf(_reveal + delta * 9.0, 1.0)
	add_theme_stylebox_override("panel", _panel_style())
	_preview.queue_redraw()
	_armor_icon.modulate.a = _reveal
	if _flash <= 0.0 and _reveal >= 1.0:
		set_process(false)


## Brief tint, e.g. after a purchase or a merge.
func flash(color: Color) -> void:
	_accent_color = color
	_flash = 1.0
	set_process(true)


func show_overview(subtitle: String, config: Dictionary, rows: Array) -> void:
	_set_preview(&"weapon", &"", 0, config)
	_subtitle.text = subtitle
	_title.text = "Build"
	_grade.text = ""
	_set_condition(-1.0, Color.WHITE)
	_description.text = ""
	_set_rows("", rows)
	_hint.text = ""


func show_extension(item: WeaponExtensionItem, description: String, caption: String, rows: Array, hint: String) -> void:
	_set_preview(&"extension", item.get_definition_id(), item.mark, {})
	_subtitle.text = LoadoutStyle.slot_label(item.get_slot())
	_title.text = _strip_mark(item.get_display_name())
	_set_grade(item.mark, item.condition, item.get_condition_tier_name(), item.get_condition_color())
	_description.text = description
	_set_rows(caption, rows)
	_hint.text = hint


func show_armor(item: ArmorItemData, description: String, caption: String, rows: Array, hint: String) -> void:
	_set_preview(&"armor", item.item_id, item.get_mark(), {}, item)
	_subtitle.text = LoadoutStyle.slot_label(item.category)
	_title.text = _strip_mark(item.get_hover_title())
	_set_grade(item.get_mark(), item.condition, item.get_condition_name(), item.get_condition_color())
	_description.text = description
	_set_rows(caption, rows)
	_hint.text = hint


func show_slot(slot: StringName, description: String, rows: Array, hint: String) -> void:
	_set_preview(&"empty", slot, 0, {})
	_subtitle.text = LoadoutStyle.slot_label(slot)
	_title.text = "Empty"
	_grade.text = ""
	_set_condition(-1.0, Color.WHITE)
	_description.text = description
	_set_rows("", rows)
	_hint.text = hint


func show_message(title: String, subtitle: String, body: String, color: Color) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_grade.text = ""
	_description.text = body
	_set_condition(-1.0, color)
	_set_rows("", [])
	_hint.text = ""
	flash(color)


func set_summary(text: String) -> void:
	_grade.text = text
	_grade.add_theme_color_override("font_color", LoadoutStyle.TEXT_MUTED)


func set_hint(text: String) -> void:
	_hint.text = text


func _set_rows(caption: String, rows: Array) -> void:
	_rows_caption.text = caption
	for index in range(row_count):
		var row: Dictionary = _rows[index]
		var name_label: Label = row["name"]
		var value_label: Label = row["value"]
		if index < rows.size():
			var entry: Dictionary = rows[index]
			name_label.text = str(entry.get("name", ""))
			value_label.text = str(entry.get("value", ""))
			value_label.add_theme_color_override("font_color", entry.get("color", LoadoutStyle.TEXT))
			name_label.add_theme_color_override("font_color", entry.get("name_color", LoadoutStyle.TEXT_SECONDARY))
		else:
			name_label.text = ""
			value_label.text = ""


func _set_grade(mark: int, condition: float, grade_name: String, color: Color) -> void:
	_grade.text = "MK %s   ·   %s   ·   %d%%" % [LoadoutStyle.roman(mark), grade_name.to_upper(), int(roundf(condition))]
	_grade.add_theme_color_override("font_color", color)
	var wear: Color = LoadoutStyle.wear_color(condition / 100.0)
	_set_condition(condition, Color(wear.r, wear.g, wear.b, maxf(wear.a, 0.55)))


func _set_condition(value: float, color: Color) -> void:
	_condition_value = value
	_condition_color = color
	_condition_track.queue_redraw()


func _set_preview(kind: StringName, id: StringName, mark: int, config: Dictionary, armor: ArmorItemData = null) -> void:
	var changed: bool = kind != _kind or id != _id or config != _config
	_kind = kind
	_id = id
	_mark = mark
	_config = config
	_armor_icon.visible = armor != null
	if armor != null:
		_armor_icon.set_armor_item(armor)
		_layout_armor_preview()
	else:
		_armor_icon.clear()
	if changed:
		_reveal = 0.0
		set_process(true)
	_preview.queue_redraw()


func _layout_armor_preview() -> void:
	var box: float = minf(_preview.size.y - 28.0, 140.0)
	_armor_icon.size = Vector2(box, box)
	_armor_icon.position = Vector2((_preview.size.x - box) * 0.5, (_preview.size.y - box) * 0.5)


func _draw_preview() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _preview.size)
	_preview.draw_style_box(LoadoutStyle.flat(Color(0, 0, 0, 0.22), 4), rect)
	LoadoutStyle.draw_glow(_preview, rect.get_center(), rect.size * Vector2(0.42, 0.55), Color(1, 1, 1, 0.06))
	var ease: float = 1.0 - pow(1.0 - _reveal, 3.0)
	var lift: Vector2 = Vector2(0.0, (1.0 - ease) * 6.0)
	match _kind:
		&"extension":
			WeaponArt.draw_part_icon(_preview, Rect2(rect.position + Vector2(rect.size.x * 0.22, 12.0) + lift, Vector2(rect.size.x * 0.56, rect.size.y - 24.0)), _id, {
				"accent": LoadoutStyle.local_accent(), "max_scale": 3.4, "alpha": ease,
			})
		&"weapon":
			var bounds: Rect2 = WeaponArt.weapon_bounds(_config)
			var fit: float = minf((rect.size.x - 24.0) / bounds.size.x, (rect.size.y - 18.0) / bounds.size.y)
			var xform: Transform2D = Transform2D(0.0, Vector2.ONE * fit, 0.0, rect.get_center() + lift) * Transform2D(0.0, -bounds.get_center())
			WeaponArt.draw_weapon(_preview, xform, _config, {"accent": LoadoutStyle.local_accent(), "alpha": ease})
		&"empty":
			var c: Vector2 = rect.get_center()
			var color: Color = Color(1, 1, 1, 0.16)
			_preview.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), color, 1.5)
			_preview.draw_line(c + Vector2(0, -10), c + Vector2(0, 10), color, 1.5)
	if _mark > 0:
		LoadoutStyle.draw_pips(_preview, Vector2(10.0, 10.0), _mark, 3, 1.8, 1.8)


func _draw_condition() -> void:
	if _condition_value < 0.0:
		return
	var track: Rect2 = Rect2(Vector2.ZERO, _condition_track.size)
	_condition_track.draw_rect(track, Color(1, 1, 1, 0.07))
	_condition_track.draw_rect(Rect2(Vector2.ZERO, Vector2(track.size.x * clampf(_condition_value / 100.0, 0.0, 1.0), track.size.y)), _condition_color)


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.03).lerp(Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.12), _flash), 6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 10.0
	return style


func _label(font: Font, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	UiStyle.style_label(label, font, font_size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _strip_mark(text: String) -> String:
	var index: int = text.rfind(" MK")
	return text.substr(0, index) if index > 0 else text
