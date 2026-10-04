extends Control
class_name ResearchConnectionLayer

## The links between projects, drawn under the badges. A link is faint until its requirement is met, then
## in the intel colour ("powered"). Where a project needs more than MK I of its parent the link carries a
## small mark tag. Researching a project sends one pulse down its links; the projects it opens fade in when
## the pulse arrives. Nothing moves otherwise.

const LINE_WIDTH: float = 2.0

var _nodes: Dictionary = {}
var _links: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)


func setup(nodes: Dictionary) -> void:
	_nodes = nodes
	_links.clear()
	for node in nodes.values():
		var target: ResearchNodeButton = node
		for requirement in target.definition.get("requires", []):
			if not (requirement is Dictionary):
				continue
			var source: ResearchNodeButton = nodes.get(str(requirement["id"]), null)
			if source != null:
				_links.append({"source": source, "target": target, "mark": int(requirement["mark"])})
	queue_redraw()


## Sends a pulse from a freshly researched project down every link; targets that just became reachable
## wake when it arrives.
func pulse_from(source_id: StringName, newly_open: Array) -> void:
	for link in _links:
		var source: ResearchNodeButton = link["source"]
		if source.research_id != source_id:
			continue
		var target: ResearchNodeButton = link["target"]
		_pulses.append({"link": link, "t": 0.0, "wake": newly_open.has(target.research_id)})
	set_process(true)


func _process(delta: float) -> void:
	for index in range(_pulses.size() - 1, -1, -1):
		var pulse: Dictionary = _pulses[index]
		pulse["t"] = float(pulse["t"]) + delta / 0.5
		if float(pulse["t"]) >= 1.0:
			if pulse["wake"]:
				(pulse["link"]["target"] as ResearchNodeButton).play_wake()
			_pulses.remove_at(index)
	queue_redraw()
	if _pulses.is_empty():
		set_process(false)


func _path(link: Dictionary) -> PackedVector2Array:
	var from: Vector2 = (link["source"] as ResearchNodeButton).get_center()
	var to: Vector2 = (link["target"] as ResearchNodeButton).get_center()
	if absf(to.y - from.y) < 1.0:
		return PackedVector2Array([from, to])
	# Change rows halfway between two columns, where the names under the badges leave a gap, and round
	# the two corners a little.
	var turn_x: float = from.x + ResearchPage.COLUMN_STEP * 0.5
	var down: float = signf(to.y - from.y)
	var r: float = 8.0
	var points: PackedVector2Array = PackedVector2Array([from, Vector2(turn_x - r, from.y)])
	for step in range(1, 4):
		var a: float = PI * 0.5 * float(step) / 4.0
		points.append(Vector2(turn_x - r + sin(a) * r, from.y + down * (r - cos(a) * r)))
	points.append(Vector2(turn_x, from.y + down * r))
	points.append(Vector2(turn_x, to.y - down * r))
	for step in range(1, 4):
		var a: float = PI * 0.5 * float(step) / 4.0
		points.append(Vector2(turn_x + r - cos(a) * r, to.y - down * (r - sin(a) * r)))
	points.append(Vector2(turn_x + r, to.y))
	points.append(to)
	return points


func _powered(link: Dictionary) -> bool:
	var source: ResearchNodeButton = link["source"]
	return ResearchManager.get_mark(source.research_id) >= int(link["mark"])


func _draw() -> void:
	var intel: Color = UiStyle.INTEL
	for link in _links:
		var target: ResearchNodeButton = link["target"]
		var points: PackedVector2Array = _path(link)
		var powered: bool = _powered(link)
		var planned: bool = target.get_state() == ResearchNodeButton.PLANNED
		var color: Color = LoadoutStyle.with_alpha(intel, 0.42) if powered else Color(1, 1, 1, 0.07)
		if planned:
			color = Color(1, 1, 1, 0.04)
		draw_polyline(points, color, LINE_WIDTH, true)
		if int(link["mark"]) > 1:
			_draw_mark_tag(points, int(link["mark"]), powered)
	for pulse in _pulses:
		var t: float = float(pulse["t"])
		_draw_runner(_path(pulse["link"]), t * t * (3.0 - 2.0 * t), Color(0.97, 0.951, 0.903, 1.0), 5.0)


## A short bright dash travelling along a path at progress t (0..1).
func _draw_runner(points: PackedVector2Array, t: float, color: Color, length: float = 3.5) -> void:
	var total: float = 0.0
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	var head: float = total * t
	var at: Vector2 = _point_at(points, head)
	var tail: Vector2 = _point_at(points, maxf(head - 18.0, 0.0))
	draw_line(tail, at, LoadoutStyle.with_alpha(color, color.a * 0.35), LINE_WIDTH + 1.0, true)
	draw_circle(at, length * 0.6, color, true, -1.0, true)


func _point_at(points: PackedVector2Array, distance: float) -> Vector2:
	var remaining: float = distance
	for index in range(points.size() - 1):
		var segment: float = points[index].distance_to(points[index + 1])
		if remaining <= segment:
			return points[index].lerp(points[index + 1], remaining / maxf(segment, 0.001))
		remaining -= segment
	return points[points.size() - 1]


func _draw_mark_tag(points: PackedVector2Array, mark: int, powered: bool) -> void:
	var a: Vector2 = points[points.size() - 2]
	var b: Vector2 = points[points.size() - 1]
	var center: Vector2 = a.lerp(b, 0.5)
	var text: String = "MK " + LoadoutStyle.roman(mark)
	var width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
	var rect: Rect2 = Rect2(center - Vector2(width * 0.5, 7.0), Vector2(width, 14.0))
	var style: StyleBoxFlat = LoadoutStyle.flat(Color(0.05, 0.05, 0.047, 1.0), 2)
	style.border_color = LoadoutStyle.with_alpha(UiStyle.INTEL, 0.5) if powered else Color(1, 1, 1, 0.14)
	style.set_border_width_all(1)
	draw_style_box(style, rect)
	draw_string(UiStyle.FONT_BOLD, Vector2(rect.position.x, rect.position.y + 10.5), text, HORIZONTAL_ALIGNMENT_CENTER, width, 9, UiStyle.INTEL if powered else LoadoutStyle.TEXT_MUTED)
