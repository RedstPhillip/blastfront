class_name HudToasts
extends Control

## Short notices in the top-right corner: a small-caps title in the notice's colour and one quiet line of
## detail on a soft dark fade (no box, no side stripe). They slide in, hold, and slide out. Anything can raise one
## with `HudToasts.notify(...)`; while no HUD is present the call is simply ignored.

const GROUP: StringName = &"hud_toasts"
const TOAST_SIZE: Vector2 = Vector2(320.0, 46.0)
const MARGIN: Vector2 = Vector2(20.0, 18.0)
const SPACING: float = 4.0
const HOLD_SECONDS: float = 2.8
const MAX_VISIBLE: int = 3

var _active: Array[Control] = []
var _queue: Array[Dictionary] = []


static func notify(title: String, detail: String = "", color: Color = UiStyle.ACCENT, sound: StringName = &"ui_confirm") -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: HudToasts = tree.get_first_node_in_group(GROUP) as HudToasts
	if host != null:
		host.push(title, detail, color, sound)


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func push(title: String, detail: String, color: Color, sound: StringName) -> void:
	_queue.append({"title": title, "detail": detail, "color": color, "sound": sound})
	_drain()


func _drain() -> void:
	while not _queue.is_empty() and _active.size() < MAX_VISIBLE:
		_spawn(_queue.pop_front())


func _spawn(data: Dictionary) -> void:
	var toast: Control = _build_toast(data)
	add_child(toast)
	_active.append(toast)
	_relayout(toast)
	if data["sound"] != &"" and AudioDirector.has_event(data["sound"]):
		AudioDirector.play(data["sound"], -3.0)
	var resting_x: float = toast.position.x
	toast.position.x = resting_x + 36.0
	toast.modulate.a = 0.0
	var tween: Tween = toast.create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(toast, "position:x", resting_x, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	tween.chain().tween_interval(HOLD_SECONDS)
	tween.chain().tween_property(toast, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(toast, "position:x", resting_x + 60.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_retire.bind(toast))


func _retire(toast: Control) -> void:
	_active.erase(toast)
	toast.queue_free()
	for other in _active:
		_relayout(other, true)
	_drain()


func _relayout(toast: Control, animate: bool = false) -> void:
	var index: int = _active.find(toast)
	var target: Vector2 = Vector2(size.x - TOAST_SIZE.x - MARGIN.x, MARGIN.y + float(index) * (TOAST_SIZE.y + SPACING))
	if not animate:
		toast.position = target
		return
	toast.create_tween().set_ignore_time_scale(true).tween_property(toast, "position:y", target.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_toast(data: Dictionary) -> Control:
	var color: Color = data["color"]
	var toast: Control = Control.new()
	toast.size = TOAST_SIZE
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.draw.connect(_draw_toast.bind(toast, color, str(data["title"]), str(data["detail"])))
	return toast


func _draw_toast(toast: Control, color: Color, title: String, detail: String) -> void:
	var w: float = TOAST_SIZE.x
	var h: float = TOAST_SIZE.y
	LoadoutStyle.draw_hgradient_rect(toast, Rect2(0.0, 0.0, w, h), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.55))
	var right: float = w - 8.0
	var title_y: float = 20.0 if detail != "" else h * 0.5 + 5.0
	toast.draw_string_outline(UiStyle.FONT_BOLD, Vector2(0.0, title_y), title, HORIZONTAL_ALIGNMENT_RIGHT, right, 15, 4, Color(0, 0, 0, 0.55))
	toast.draw_string(UiStyle.FONT_BOLD, Vector2(0.0, title_y), title, HORIZONTAL_ALIGNMENT_RIGHT, right, 15, color.lightened(0.2))
	if detail != "":
		toast.draw_string_outline(UiStyle.FONT_BODY, Vector2(0.0, 37.0), detail, HORIZONTAL_ALIGNMENT_RIGHT, right, 12, 3, Color(0, 0, 0, 0.5))
		toast.draw_string(UiStyle.FONT_BODY, Vector2(0.0, 37.0), detail, HORIZONTAL_ALIGNMENT_RIGHT, right, 12, UiStyle.TEXT_DIM)
