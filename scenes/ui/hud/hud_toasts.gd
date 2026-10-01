class_name HudToasts
extends Control

## Stacked notifications in the top-right corner: slide in, hold, slide out. Anything can raise one
## with `HudToasts.notify(...)`; while no HUD is present the call is simply ignored.

const GROUP: StringName = &"hud_toasts"
const TOAST_SIZE: Vector2 = Vector2(316.0, 58.0)
const MARGIN: Vector2 = Vector2(18.0, 96.0)
const SPACING: float = 8.0
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
	toast.position.x = resting_x + TOAST_SIZE.x + 40.0
	toast.modulate.a = 0.0
	var tween: Tween = toast.create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(toast, "position:x", resting_x, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	toast.draw.connect(_draw_toast.bind(toast, color))
	var title: Label = Label.new()
	UiStyle.style_label(title, UiStyle.FONT_DISPLAY, 17, color.lightened(0.15))
	title.text = str(data["title"])
	title.position = Vector2(46.0, 8.0)
	title.size = Vector2(TOAST_SIZE.x - 58.0, 22.0)
	title.clip_text = true
	toast.add_child(title)
	var detail_text: String = str(data["detail"])
	if detail_text != "":
		var detail: Label = Label.new()
		UiStyle.style_label(detail, UiStyle.FONT_BODY, 13, UiStyle.TEXT_DIM)
		detail.text = detail_text
		detail.position = Vector2(46.0, 31.0)
		detail.size = Vector2(TOAST_SIZE.x - 58.0, 18.0)
		detail.clip_text = true
		toast.add_child(detail)
	else:
		title.position.y = 18.0
	return toast


func _draw_toast(toast: Control, color: Color) -> void:
	var w: float = TOAST_SIZE.x
	var h: float = TOAST_SIZE.y
	var shape: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0), Vector2(w, 0.0), Vector2(w - 10.0, h), Vector2(0.0, h)])
	toast.draw_colored_polygon(shape, Color(UiStyle.PANEL_SOLID.r, UiStyle.PANEL_SOLID.g, UiStyle.PANEL_SOLID.b, 0.94))
	toast.draw_colored_polygon(shape, Color(color.r, color.g, color.b, 0.08))
	var outline: PackedVector2Array = shape.duplicate()
	outline.append(shape[0])
	toast.draw_polyline(outline, Color(color.r, color.g, color.b, 0.55), 1.2, true)
	toast.draw_colored_polygon(PackedVector2Array([Vector2(10.0, 0.0), Vector2(16.0, 0.0), Vector2(6.0, h), Vector2(0.0, h)]), color)
	var badge: Vector2 = Vector2(27.0, h * 0.5)
	var diamond: PackedVector2Array = PackedVector2Array([badge + Vector2(0, -10), badge + Vector2(10, 0), badge + Vector2(0, 10), badge + Vector2(-10, 0)])
	toast.draw_colored_polygon(diamond, Color(color.r, color.g, color.b, 0.22))
	var diamond_outline: PackedVector2Array = diamond.duplicate()
	diamond_outline.append(diamond[0])
	toast.draw_polyline(diamond_outline, color, 1.6, true)
	toast.draw_circle(badge, 3.0, color, true, -1.0, true)
