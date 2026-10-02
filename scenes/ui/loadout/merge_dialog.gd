extends Control
class_name LoadoutMergeDialog

## Confirms a merge: two cards of the same part and mark become one card of the next mark. Shows the real
## cards (A + B -> result), what the result keeps (the averaged condition), the price against the balance,
## and one primary action. Lives on the loadout's ink surfaces; Escape or a click on the scrim cancels.

signal confirmed
signal cancelled

const PANEL_SIZE: Vector2 = Vector2(520.0, 300.0)
const CARD: float = 76.0

var _panel: Control = null
var _source_card: LoadoutItemTile = null
var _target_card: LoadoutItemTile = null
var _result_card: LoadoutItemTile = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _title: String = ""
var _subtitle: String = ""
var _lines: Array = []
var _next_mark: int = 2
var _cost: int = 0
var _balance: int = 0
var _tween: Tween = null


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = Control.new()
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_source_card = _card()
	_target_card = _card()
	_result_card = _card()
	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.custom_minimum_size = Vector2(120.0, 40.0)
	UiStyle.style_button(_cancel_button, false, 15)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_panel.add_child(_cancel_button)
	_confirm_button = Button.new()
	_confirm_button.custom_minimum_size = Vector2(170.0, 40.0)
	UiStyle.style_button(_confirm_button, true, 16)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_panel.add_child(_confirm_button)
	GameJuice.attach_button_feedback(self)
	resized.connect(_layout)
	_layout()


func _card() -> LoadoutItemTile:
	var card: LoadoutItemTile = LoadoutItemTile.new()
	card.set_tile_size(Vector2(CARD, CARD))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	_panel.add_child(card)
	return card


func _layout() -> void:
	if _panel == null:
		return
	_panel.position = ((size - PANEL_SIZE) * 0.5).round()
	var row_y: float = 92.0
	var gap: float = 56.0
	var row_width: float = CARD * 3.0 + gap * 2.0
	var x: float = (PANEL_SIZE.x - row_width) * 0.5
	_source_card.position = Vector2(x, row_y)
	_target_card.position = Vector2(x + CARD + gap, row_y)
	_result_card.position = Vector2(x + (CARD + gap) * 2.0, row_y)
	_confirm_button.position = Vector2(PANEL_SIZE.x - 28.0 - _confirm_button.custom_minimum_size.x, PANEL_SIZE.y - 28.0 - 40.0)
	_confirm_button.size = _confirm_button.custom_minimum_size
	_cancel_button.position = Vector2(_confirm_button.position.x - 12.0 - _cancel_button.custom_minimum_size.x, _confirm_button.position.y)
	_cancel_button.size = _cancel_button.custom_minimum_size


func show_merge(kind_text: String, title_text: String, source_item: Variant, target_item: Variant, next_mark: int, merge_cost: int, balance: int) -> void:
	_title = title_text
	_subtitle = "%s  ·  %s" % [kind_text, str(LoadoutStyle.item_info(source_item).get("name", "")).to_upper()]
	_next_mark = next_mark
	_cost = merge_cost
	_balance = balance
	_source_card.setup(source_item)
	_target_card.setup(target_item)
	_result_card.setup(_preview_result(source_item, target_item, next_mark))
	_result_card.equipped = false
	_confirm_button.text = "MERGE"
	_confirm_button.disabled = balance < merge_cost
	visible = true
	move_to_front()
	_panel.queue_redraw()
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE * 0.96
	_panel.pivot_offset = PANEL_SIZE * 0.5
	modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.16)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	AudioDirector.play(&"ui_open")
	_confirm_button.grab_focus.call_deferred()


## The item the merge would produce, for the preview card only (nothing is added to any inventory).
func _preview_result(source_item: Variant, target_item: Variant, next_mark: int) -> Variant:
	if source_item is WeaponExtensionItem:
		var extension: WeaponExtensionItem = source_item
		return WeaponExtensionItem.create(extension.definition, (extension.condition + (target_item as WeaponExtensionItem).condition) * 0.5, next_mark)
	if source_item is ArmorItemData:
		return ArmorInventory._create_merged_item(source_item, target_item)
	return source_item


func show_coin_warning(_body: String, _item_label: String) -> void:
	pass


func hide_dialog() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.1)
	_tween.tween_callback(hide)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_cancel_pressed()


func _on_confirm_pressed() -> void:
	hide_dialog()
	confirmed.emit()


func _on_cancel_pressed() -> void:
	AudioDirector.play(&"ui_back")
	hide_dialog()
	cancelled.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.012, 0.62))


func _draw_panel() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, PANEL_SIZE)
	var style: StyleBoxFlat = LoadoutStyle.flat(Color(0.04, 0.062, 0.066, 0.98), 4)
	style.border_color = LoadoutStyle.HAIRLINE
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 10)
	_panel.draw_style_box(style, rect)
	_panel.draw_rect(Rect2(0.0, 0.0, PANEL_SIZE.x, 2.0), LoadoutStyle.ACCENT)
	_panel.draw_string(UiStyle.FONT_DISPLAY, Vector2(28.0, 46.0), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, LoadoutStyle.TEXT)
	_panel.draw_string(UiStyle.FONT_BOLD, Vector2(28.0, 68.0), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, PANEL_SIZE.x - 56.0, 11, LoadoutStyle.TEXT_MUTED)

	var plus_center: Vector2 = Vector2((_source_card.position.x + CARD + _target_card.position.x) * 0.5, _source_card.position.y + CARD * 0.5)
	_panel.draw_line(plus_center + Vector2(-6, 0), plus_center + Vector2(6, 0), LoadoutStyle.TEXT_SECONDARY, 2.0)
	_panel.draw_line(plus_center + Vector2(0, -6), plus_center + Vector2(0, 6), LoadoutStyle.TEXT_SECONDARY, 2.0)
	var arrow_center: Vector2 = Vector2((_target_card.position.x + CARD + _result_card.position.x) * 0.5, plus_center.y)
	_panel.draw_line(arrow_center + Vector2(-10, 0), arrow_center + Vector2(8, 0), LoadoutStyle.ACCENT, 2.0, true)
	_panel.draw_polyline(PackedVector2Array([arrow_center + Vector2(2, -6), arrow_center + Vector2(9, 0), arrow_center + Vector2(2, 6)]), LoadoutStyle.ACCENT, 2.0, true)
	var result_rect: Rect2 = Rect2(_result_card.position, Vector2(CARD, CARD)).grow(4.0)
	LoadoutStyle.draw_brackets(_panel, result_rect, LoadoutStyle.ACCENT, 10.0, 2.0)

	for card in [_source_card, _target_card, _result_card]:
		var info: Dictionary = LoadoutStyle.item_info(card.item)
		if info.is_empty():
			continue
		var is_result: bool = card == _result_card
		var mark_text: String = "MK " + LoadoutStyle.roman(_next_mark if is_result else int(info["mark"]))
		var below: float = card.position.y + CARD + 18.0
		_panel.draw_string(UiStyle.FONT_BOLD, Vector2(card.position.x - 20.0, below), mark_text, HORIZONTAL_ALIGNMENT_CENTER, CARD + 40.0, 12, LoadoutStyle.ACCENT if is_result else LoadoutStyle.TEXT)
		_panel.draw_string(UiStyle.FONT_BOLD, Vector2(card.position.x - 20.0, below + 15.0), "%d%%" % int(roundf(float(info["condition"]))), HORIZONTAL_ALIGNMENT_CENTER, CARD + 40.0, 11, info["color"])

	var price_y: float = PANEL_SIZE.y - 42.0
	var affordable: bool = _balance >= _cost
	LoadoutStyle.draw_coin(_panel, Vector2(34.0, price_y - 5.0), 6.0, LoadoutStyle.COIN if affordable else LoadoutStyle.NEGATIVE)
	_panel.draw_string(UiStyle.FONT_DISPLAY, Vector2(46.0, price_y + 2.0), str(_cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LoadoutStyle.COIN if affordable else LoadoutStyle.NEGATIVE)
	var cost_width: float = UiStyle.FONT_DISPLAY.get_string_size(str(_cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_panel.draw_string(UiStyle.FONT_BOLD, Vector2(52.0 + cost_width, price_y + 1.0), "YOU HAVE %d" % _balance, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LoadoutStyle.TEXT_MUTED)
	_panel.draw_string(UiStyle.FONT_BODY, Vector2(28.0, price_y + 22.0), "Both copies are used up.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LoadoutStyle.TEXT_MUTED)
