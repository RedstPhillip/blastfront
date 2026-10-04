extends Control
class_name ResearchNodeButton

## One research project on the tree: an icon badge whose ring is split into one segment per mark (filled
## in the intel colour as they are researched), the name underneath and the next price. The next segment is
## amber when the project can be researched right now. Click (or pad focus) selects; press and hold
## researches (the amber arc fills around the badge first, so nothing is ever bought by accident).
## Researching flashes the badge and charges the new segment; projects that become reachable fade in.

signal research_selected(research_id: StringName)
signal research_requested(research_id: StringName)

const NODE_SIZE: Vector2 = Vector2(122.0, 102.0)
const CENTER: Vector2 = Vector2(61.0, 30.0)
const RADIUS: float = 24.0
const RING_RADIUS: float = 30.0
const HOLD_SECONDS: float = 0.42
const ICON_SIZE: float = 26.0

const PLANNED: int = 0
const LOCKED: int = 1
const AVAILABLE: int = 2
const RESEARCHED: int = 3
const MAXED: int = 4

var research_id: StringName = &""
var definition: Dictionary = {}
var selected: bool = false

var _state: int = LOCKED
var _mark: int = 0
var _max_mark: int = 1
var _cost: int = 0
var _can_buy: bool = false
var _icon: Texture2D = null
var _hover: float = 0.0
var _hovered: bool = false
var _holding: bool = false
var _hold: float = 0.0
var _flash: float = 0.0
var _charge: float = 1.0
var _wake: float = 1.0
var _wake_waiting: bool = false
var _name_lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	custom_minimum_size = NODE_SIZE
	size = NODE_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	mouse_entered.connect(func() -> void: _set_hovered(true))
	mouse_exited.connect(func() -> void: _set_hovered(false); _cancel_hold())
	focus_entered.connect(func() -> void: research_selected.emit(research_id); set_process(true))
	focus_exited.connect(func() -> void: _cancel_hold(); queue_redraw())


func setup(next_definition: Dictionary) -> void:
	definition = next_definition.duplicate(true)
	research_id = StringName(str(definition["id"]))
	var icon_path: String = str(definition.get("icon_path", ""))
	_icon = load(icon_path) as Texture2D if icon_path != "" else null
	_name_lines = _wrap(str(definition["name"]))
	refresh()


func get_center() -> Vector2:
	return position + CENTER


func get_state() -> int:
	return _state


func is_actionable() -> bool:
	return _state == AVAILABLE or (_state == RESEARCHED and _can_buy)


func refresh() -> void:
	if definition.is_empty():
		return
	_mark = ResearchManager.get_mark(research_id)
	_max_mark = int(definition["max_mark"])
	_cost = ResearchManager.get_next_cost(research_id)
	_can_buy = ResearchManager.can_purchase(research_id)
	if definition["available"] != true:
		_state = PLANNED
	elif _mark >= _max_mark:
		_state = MAXED
	elif _mark > 0:
		_state = RESEARCHED
	elif _requirements_met():
		_state = AVAILABLE
	else:
		_state = LOCKED
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _state != PLANNED else Control.CURSOR_ARROW
	set_process(true)
	queue_redraw()


func _requirements_met() -> bool:
	for requirement in definition.get("requires", []):
		if requirement is Dictionary and ResearchManager.get_mark(StringName(str(requirement["id"]))) < int(requirement["mark"]):
			return false
	return true


## Played right after a mark was researched on this node.
func play_unlock() -> void:
	_flash = 1.0
	_charge = 0.0
	set_process(true)


## Holds a project that is about to open in its dim look until the pulse from its parent arrives.
func prime_wake() -> void:
	_wake = 0.0
	_wake_waiting = true
	queue_redraw()


## Played when this project became reachable because a requirement was just researched.
func play_wake() -> void:
	_wake = 0.0
	_wake_waiting = false
	AudioDirector.play(&"ui_toggle", -10.0, 1.4)
	set_process(true)


func _set_hovered(value: bool) -> void:
	_hovered = value
	set_process(true)
	if value:
		AudioDirector.play(&"ui_hover", -8.0, 1.05)


# --- Input -----------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press()
		else:
			_release()
		accept_event()
		return
	if event.is_action_pressed(&"ui_accept"):
		_press()
		accept_event()
	elif event.is_action_released(&"ui_accept"):
		_release()
		accept_event()


func _press() -> void:
	if _state == PLANNED:
		research_selected.emit(research_id)
		return
	research_selected.emit(research_id)
	if _can_buy:
		_holding = true
		AudioDirector.play(&"ui_click", -6.0, 0.9)
	set_process(true)


func _release() -> void:
	_cancel_hold()


func _cancel_hold() -> void:
	_holding = false
	set_process(true)


# --- Animation & drawing ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_hover = move_toward(_hover, 1.0 if (_hovered or has_focus()) else 0.0, delta * 10.0)
	if _holding:
		_hold = minf(_hold + delta / HOLD_SECONDS, 1.0)
		if _hold >= 1.0:
			_holding = false
			_hold = 0.0
			research_requested.emit(research_id)
	else:
		_hold = move_toward(_hold, 0.0, delta * 4.0)
	_flash = move_toward(_flash, 0.0, delta * 2.6)
	_charge = move_toward(_charge, 1.0, delta / 0.35)
	if not _wake_waiting:
		_wake = move_toward(_wake, 1.0, delta / 0.6)
	queue_redraw()
	var idle: bool = not _holding and _hold <= 0.0 and _flash <= 0.0 and _charge >= 1.0 and _wake >= 1.0 and (_hover == 0.0 or _hover == 1.0)
	if idle and not (_hovered or has_focus()):
		set_process(false)


func _draw() -> void:
	var intel: Color = UiStyle.INTEL
	var amber: Color = UiStyle.ACCENT
	var hover: float = _hover * _hover * (3.0 - 2.0 * _hover)
	draw_set_transform(CENTER)

	var disc: Color = Color(0.075, 0.075, 0.07, 1.0)
	var edge: Color = Color(1, 1, 1, 0.12)
	var icon_alpha: float = 0.9
	match _state:
		PLANNED:
			disc = Color(0.05, 0.05, 0.047, 0.7)
			edge = Color(1, 1, 1, 0.07)
			icon_alpha = 0.16
		LOCKED:
			disc = Color(0.055, 0.055, 0.052, 1.0)
			edge = Color(1, 1, 1, 0.06)
			icon_alpha = 0.3
		AVAILABLE:
			edge = LoadoutStyle.with_alpha(amber, 0.55) if _can_buy else Color(1, 1, 1, 0.18)
			icon_alpha = 1.0 if _can_buy else 0.7
		RESEARCHED, MAXED:
			disc = Color(0.108, 0.106, 0.1, 1.0)
			edge = LoadoutStyle.with_alpha(intel, 0.45)
			icon_alpha = 1.0
	if _wake < 1.0:
		icon_alpha = lerpf(0.3, icon_alpha, _wake)
		edge = edge.lerp(Color(1, 1, 1, 0.06), 1.0 - _wake)
	disc = disc.lerp(disc.lightened(0.12), hover)
	draw_circle(Vector2.ZERO, RADIUS, disc, true, -1.0, true)
	if _state == PLANNED:
		_draw_dashed_circle(RADIUS, edge)
	else:
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, edge.lerp(Color(1, 1, 1, 0.5), hover * 0.4), 1.2, true)
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 1.0, 1.0, _flash * 0.4), true, -1.0, true)

	if _icon != null:
		var icon_color: Color = Color(1, 1, 1, icon_alpha)
		if _state == MAXED or _state == RESEARCHED:
			icon_color = Color(0.973, 0.954, 0.906, 1.0)
		draw_texture_rect(_icon, Rect2(Vector2(-ICON_SIZE, -ICON_SIZE) * 0.5, Vector2(ICON_SIZE, ICON_SIZE)), false, icon_color)

	_draw_ring(intel, amber)
	if _hold > 0.0:
		draw_arc(Vector2.ZERO, RING_RADIUS + 6.0, -PI * 0.5, -PI * 0.5 + TAU * _hold, 48, amber, 3.0, true)
	if selected or has_focus():
		draw_arc(Vector2.ZERO, RING_RADIUS + 6.0, 0.0, TAU, 48, Color(1, 1, 1, 0.22 if _hold <= 0.0 else 0.0), 1.0, true)
	draw_set_transform(Vector2.ZERO)
	_draw_labels(intel)


## One arc segment per mark around the badge.
func _draw_ring(intel: Color, amber: Color) -> void:
	var gap: float = 0.22 if _max_mark > 1 else 0.0
	var span: float = TAU / float(_max_mark)
	for index in range(_max_mark):
		var from: float = -PI * 0.5 + float(index) * span + gap * 0.5
		var to: float = from + span - gap
		var color: Color = Color(1, 1, 1, 0.1)
		var width: float = 3.0
		if _state == PLANNED or _state == LOCKED:
			color = Color(1, 1, 1, 0.06)
		elif index < _mark:
			color = intel
			if index == _mark - 1 and _charge < 1.0:
				draw_arc(Vector2.ZERO, RING_RADIUS, from, to, 24, Color(1, 1, 1, 0.1), width, true)
				to = lerpf(from, to, _charge * _charge * (3.0 - 2.0 * _charge))
				color = intel.lerp(Color.WHITE, 1.0 - _charge)
		elif index == _mark and _can_buy:
			color = LoadoutStyle.with_alpha(amber, 0.8 + 0.2 * _hover)
		elif index == _mark and _state == AVAILABLE:
			color = Color(1, 1, 1, 0.22)
		draw_arc(Vector2.ZERO, RING_RADIUS, from, to, 24, color, width, true)


func _draw_labels(intel: Color) -> void:
	var name_color: Color = LoadoutStyle.TEXT_SECONDARY
	match _state:
		PLANNED:
			name_color = LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, 0.22)
		LOCKED:
			name_color = LoadoutStyle.TEXT_MUTED
		RESEARCHED, MAXED:
			name_color = LoadoutStyle.TEXT
		AVAILABLE:
			name_color = LoadoutStyle.TEXT if _can_buy else LoadoutStyle.TEXT_SECONDARY
	name_color = name_color.lerp(LoadoutStyle.TEXT, _hover * 0.6)
	var y: float = CENTER.y + RING_RADIUS + 17.0
	for line in _name_lines:
		draw_string(UiStyle.FONT_UI, Vector2(0.0, y), line, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, name_color)
		y += 14.0
	if _state == PLANNED:
		draw_string(UiStyle.FONT_BOLD, Vector2(0.0, y + 1.0), "LATER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, 0.22))
		return
	if _state == MAXED or _state == LOCKED:
		return
	var text: String = str(_cost)
	var color: Color = intel if _can_buy else LoadoutStyle.with_alpha(LoadoutStyle.NEGATIVE, 0.75)
	var width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var start: float = (size.x - width) * 0.5
	ResearchNodeButton.draw_rp_glyph(self, Vector2(start + 4.0, y - 3.5), 4.0, color)
	draw_string(UiStyle.FONT_BOLD, Vector2(start + 11.0, y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_dashed_circle(radius: float, color: Color) -> void:
	var segments: int = 18
	for index in range(segments):
		var a: float = TAU * float(index) / float(segments)
		draw_arc(Vector2.ZERO, radius, a, a + TAU / float(segments) * 0.5, 4, color, 1.0, true)


func _wrap(text: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if UiStyle.FONT_UI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= NODE_SIZE.x - 6.0:
		lines.append(text)
		return lines
	var words: PackedStringArray = text.split(" ")
	var split_at: int = words.size() / 2
	lines.append(" ".join(words.slice(0, maxi(split_at, 1))))
	lines.append(" ".join(words.slice(maxi(split_at, 1))))
	return lines


## The research point token: a small hexagon cell (coins are discs, research is a cell).
static func draw_rp_glyph(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(6):
		points.append(center + Vector2.from_angle(TAU * float(index) / 6.0 + PI / 6.0) * radius)
	canvas.draw_colored_polygon(points, color)
	canvas.draw_circle(center, radius * 0.38, Color(0.0, 0.0, 0.0, 0.35 * color.a), true, -1.0, true)
