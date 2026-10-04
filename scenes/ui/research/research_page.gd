extends Control
class_name ResearchPage

## Research between sets. The tree fills the left: two lanes (economy, field) read left to right from first
## project to last, every project named, its marks shown as ring segments, links light up in the intel
## colour once powered. Only projects that exist in the game are shown. The panel docked on the right holds
## the research points and the selected project in a fixed layout (name, a few words, what each mark is
## worth, the hold-to-research action), so nothing jumps around. Clicking or pad focus selects; holding on a
## badge or the button researches.

const DOCK_WIDTH: float = 392.0
const DOCK_PAD: float = 24.0
const TREE_LEFT: float = 182.0
const COLUMN_STEP: float = 116.0
const LANES: Array[Dictionary] = [
	{"branch": &"economy", "name": "ECONOMY", "rows": 2},
	{"branch": &"miscellaneous", "name": "FIELD", "rows": 2},
]
## Grid position of every project: column and row inside its lane.
const LAYOUT: Dictionary = {
	&"recycling": Vector2i(0, 0), &"blueprint_storage": Vector2i(1, 0), &"coin_interest": Vector2i(2, 0),
	&"condition_wear": Vector2i(3, 0), &"upgrade_discount": Vector2i(4, 0), &"research_yield": Vector2i(5, 0),
	&"bonus_mark": Vector2i(3, 1), &"luck": Vector2i(4, 1),
	&"life_steal": Vector2i(0, 0), &"rage": Vector2i(1, 0), &"passive_healing": Vector2i(2, 0), &"phoenix": Vector2i(3, 0),
	&"time_control": Vector2i(5, 0), &"faster_capture": Vector2i(2, 1), &"capture_bonus": Vector2i(3, 1), &"capture_radius": Vector2i(4, 1),
	&"dashing": Vector2i(0, 0), &"sliding": Vector2i(1, 0),
}
const ROW_STEP: float = 100.0
const LANE_GAP: float = 64.0

var _top_inset: float = 0.0
var _nodes_by_id: Dictionary = {}
var _tree: Control = null
var _connections: ResearchConnectionLayer = null
var _lane_labels: Array[Dictionary] = []
var _dock: Control = null
var _hold_button: ResearchHoldButton = null
var _prompt_bar: UiPromptBar = null
var _selected_id: StringName = &""
var _shown_points: float = 0.0
var _points_pop: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	ResearchManager.research_changed.connect(_refresh)
	ResearchManager.research_points_changed.connect(_on_points_changed)
	_shown_points = float(ResearchManager.research_points)
	resized.connect(_layout)
	_layout()
	_refresh()
	_select(_suggested_project())
	_prompt_bar.set_prompts(_prompts())


func _exit_tree() -> void:
	if ResearchManager.research_changed.is_connected(_refresh):
		ResearchManager.research_changed.disconnect(_refresh)
	if ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.disconnect(_on_points_changed)


## Leaves room above the page for the intermission tab bar.
func set_top_inset(pixels: float) -> void:
	_top_inset = pixels
	_layout()


func _build() -> void:
	_tree = Control.new()
	_tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.draw.connect(_draw_tree)
	add_child(_tree)
	_connections = ResearchConnectionLayer.new()
	_connections.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.add_child(_connections)
	for definition in ResearchManager.get_all_definitions():
		var id: StringName = StringName(str(definition["id"]))
		if not LAYOUT.has(id) or definition["available"] != true:
			continue
		var node: ResearchNodeButton = ResearchNodeButton.new()
		node.setup(definition)
		node.research_selected.connect(_on_node_selected)
		node.research_requested.connect(_research)
		_tree.add_child(node)
		_nodes_by_id[str(id)] = node
	_connections.setup(_nodes_by_id)

	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.draw.connect(_draw_dock)
	add_child(_dock)
	_hold_button = ResearchHoldButton.new()
	_hold_button.completed.connect(func() -> void: _research(_selected_id))
	_dock.add_child(_hold_button)

	_prompt_bar = UiPromptBar.new()
	add_child(_prompt_bar)
	InputDevice.device_changed.connect(func(_pad: bool) -> void: _prompt_bar.set_prompts(_prompts()))


func _layout() -> void:
	if _tree == null:
		return
	var top: float = _top_inset
	_tree.position = Vector2.ZERO
	_tree.size = size
	_connections.size = size
	var y: float = top + 92.0
	_lane_labels.clear()
	for lane in LANES:
		var lane_top: float = y
		for node in _nodes_by_id.values():
			var button: ResearchNodeButton = node
			if StringName(str(button.definition["branch"])) != lane["branch"]:
				continue
			var cell: Vector2i = LAYOUT[button.research_id]
			var center: Vector2 = Vector2(TREE_LEFT + float(cell.x) * COLUMN_STEP, lane_top + float(cell.y) * ROW_STEP)
			button.position = center - ResearchNodeButton.CENTER
		_lane_labels.append({"lane": lane, "y": lane_top})
		y += float(lane["rows"]) * ROW_STEP + LANE_GAP
	_connect_focus()
	_dock.position = Vector2(size.x - DOCK_WIDTH, top)
	_dock.size = Vector2(DOCK_WIDTH, size.y - top)
	_hold_button.position = Vector2(DOCK_PAD, _dock.size.y - 96.0)
	_hold_button.size = Vector2(DOCK_WIDTH - DOCK_PAD * 2.0, 48.0)
	_prompt_bar.position = Vector2(48.0, size.y - 42.0)
	_prompt_bar.size = Vector2(size.x - DOCK_WIDTH - 72.0, 22.0)
	queue_redraw()
	_tree.queue_redraw()


## Pad navigation follows the picture: the nearest badge in each direction.
func _connect_focus() -> void:
	var nodes: Array = _nodes_by_id.values()
	for node in nodes:
		var from: Vector2 = (node as ResearchNodeButton).get_center()
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var best: ResearchNodeButton = null
			var best_score: float = INF
			for other in nodes:
				if other == node:
					continue
				var offset: Vector2 = (other as ResearchNodeButton).get_center() - from
				var along: float = offset.dot(direction)
				if along <= 1.0:
					continue
				var score: float = along + absf(offset.dot(Vector2(direction.y, direction.x))) * 2.5
				if score < best_score:
					best_score = score
					best = other
			if best == null:
				continue
			var path: NodePath = (node as Control).get_path_to(best)
			match direction:
				Vector2.LEFT:
					node.focus_neighbor_left = path
				Vector2.RIGHT:
					node.focus_neighbor_right = path
				Vector2.UP:
					node.focus_neighbor_top = path
				Vector2.DOWN:
					node.focus_neighbor_bottom = path


func focus_default() -> void:
	var node: ResearchNodeButton = _nodes_by_id.get(str(_selected_id), null)
	if node != null:
		node.grab_focus()


# --- State -----------------------------------------------------------------------------------------------

func _refresh() -> void:
	for node in _nodes_by_id.values():
		(node as ResearchNodeButton).refresh()
	_connections.queue_redraw()
	_update_action()
	_dock.queue_redraw()
	_tree.queue_redraw()


func _on_points_changed(_points: int) -> void:
	_points_pop = 1.0
	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	var target: float = float(ResearchManager.research_points)
	_shown_points = move_toward(_shown_points, target, maxf(absf(target - _shown_points) * 8.0, 6.0) * delta)
	_points_pop = move_toward(_points_pop, 0.0, delta * 3.0)
	_dock.queue_redraw()
	if is_equal_approx(_shown_points, target) and _points_pop <= 0.0:
		set_process(false)


func _suggested_project() -> StringName:
	var fallback: StringName = &""
	for definition in ResearchManager.get_all_definitions():
		var id: StringName = StringName(str(definition["id"]))
		if ResearchManager.can_purchase(id):
			return id
		if fallback == &"" and definition["available"] == true and ResearchManager.get_mark(id) < int(definition["max_mark"]):
			fallback = id
	return fallback


func _on_node_selected(research_id: StringName) -> void:
	if research_id != _selected_id:
		AudioDirector.play(&"ui_toggle", -6.0)
	_select(research_id)


func _select(research_id: StringName) -> void:
	_selected_id = research_id
	for node in _nodes_by_id.values():
		(node as ResearchNodeButton).selected = (node as ResearchNodeButton).research_id == research_id
		(node as ResearchNodeButton).queue_redraw()
	_update_action()
	_dock.queue_redraw()


## The button always speaks about the selected project.
func _update_action() -> void:
	var id: StringName = _selected_id
	var definition: Dictionary = ResearchManager.get_definition(id)
	if definition.is_empty():
		_hold_button.configure(false, "SELECT A PROJECT")
		return
	var mark: int = ResearchManager.get_mark(id)
	var max_mark: int = int(definition["max_mark"])
	var cost: int = ResearchManager.get_next_cost(id)
	if mark >= max_mark:
		_hold_button.configure(false, "MAXED")
	elif mark == 0 and not _requirements_met(definition):
		_hold_button.configure(false, "LOCKED")
	elif ResearchManager.research_points < cost:
		_hold_button.configure(false, "NEED %d RP" % cost)
	else:
		_hold_button.configure(true, "HOLD TO RESEARCH" if mark == 0 else "HOLD TO UPGRADE", cost)


func _requirements_met(definition: Dictionary) -> bool:
	return _missing_requirement(definition) == ""


func _missing_requirement(definition: Dictionary) -> String:
	for requirement in definition.get("requires", []):
		if not (requirement is Dictionary):
			continue
		var required_id: StringName = StringName(str(requirement["id"]))
		var required_mark: int = int(requirement["mark"])
		if ResearchManager.get_mark(required_id) < required_mark:
			var name: String = str(ResearchManager.get_definition(required_id).get("name", required_id))
			return name if required_mark <= 1 else "%s MK %s" % [name, LoadoutStyle.roman(required_mark)]
	return ""


func _research(research_id: StringName) -> void:
	if research_id == &"":
		return
	if not ResearchManager.can_purchase(research_id):
		AudioDirector.play(&"shop_denied")
		return
	var closed: Array = []
	for node in _nodes_by_id.values():
		if (node as ResearchNodeButton).get_state() == ResearchNodeButton.LOCKED:
			closed.append((node as ResearchNodeButton).research_id)
	var name: String = str(ResearchManager.get_definition(research_id).get("name", ""))
	if not ResearchManager.purchase(research_id):
		AudioDirector.play(&"shop_denied")
		return
	var opened: Array = []
	for id in closed:
		var node: ResearchNodeButton = _nodes_by_id[str(id)]
		if node.get_state() != ResearchNodeButton.LOCKED:
			opened.append(id)
			node.prime_wake()
	var unlocked: ResearchNodeButton = _nodes_by_id.get(str(research_id), null)
	if unlocked != null:
		unlocked.play_unlock()
	_connections.pulse_from(research_id, opened)
	_hold_button.flash()
	AudioDirector.play(&"research_unlock")
	var mark: int = ResearchManager.get_mark(research_id)
	_prompt_bar.notify("%s MK %s" % [name.to_upper(), LoadoutStyle.roman(mark)], UiStyle.INTEL)
	_select(research_id)


# --- Prompts ---------------------------------------------------------------------------------------------

func _prompts() -> Array:
	if InputDevice.using_gamepad:
		return [["A", "Select"], ["HOLD A", "Research"], ["LB RB", "Pages"]]
	return [["LMB", "Select"], ["HOLD LMB", "Research"], ["Q E", "Pages"]]


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Pads research the pinned project by holding X from anywhere on the page.
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_X:
		_hold_button.set_holding((event as InputEventJoypadButton).pressed)
		get_viewport().set_input_as_handled()


# --- Drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LoadoutStyle.BACKDROP)
	var tree_width: float = size.x - DOCK_WIDTH
	LoadoutStyle.draw_glow(self, Vector2(tree_width * 0.52, size.y * 0.5), Vector2(tree_width * 0.6, size.y * 0.5), Color(0.739, 0.725, 0.689, 0.025), 48)


func _draw_tree() -> void:
	for entry in _lane_labels:
		var lane: Dictionary = entry["lane"]
		var y: float = float(entry["y"])
		var total: int = 0
		var researched: int = 0
		for node in _nodes_by_id.values():
			var button: ResearchNodeButton = node
			if StringName(str(button.definition["branch"])) != lane["branch"]:
				continue
			total += 1
			if ResearchManager.get_mark(button.research_id) > 0:
				researched += 1
		_tree.draw_string(UiStyle.FONT_BOLD, Vector2(48.0, y - 2.0), str(lane["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LoadoutStyle.TEXT_SECONDARY)
		_tree.draw_string(UiStyle.FONT_BOLD, Vector2(48.0, y + 14.0), "%d / %d" % [researched, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LoadoutStyle.TEXT_MUTED)
		_tree.draw_line(Vector2(122.0, y), Vector2(TREE_LEFT - 34.0, y), LoadoutStyle.with_alpha(UiStyle.INTEL, 0.25), 2.0)


func _draw_dock() -> void:
	var w: float = _dock.size.x
	var x: float = DOCK_PAD
	var inner: float = w - DOCK_PAD * 2.0
	_dock.draw_rect(Rect2(Vector2.ZERO, _dock.size), LoadoutStyle.DOCK)
	_dock.draw_line(Vector2(0.5, 0.0), Vector2(0.5, _dock.size.y), LoadoutStyle.HAIRLINE, 1.0)

	_section(x, 30.0, inner, "RESEARCH POINTS")
	var pop: float = sin(_points_pop * PI) * 0.12
	var points_text: String = str(int(roundf(_shown_points)))
	ResearchNodeButton.draw_rp_glyph(_dock, Vector2(x + 10.0, 58.0), 10.0 * (1.0 + pop), UiStyle.INTEL)
	_dock.draw_string(UiStyle.FONT_DISPLAY, Vector2(x + 28.0, 70.0), points_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiStyle.INTEL.lerp(Color.WHITE, _points_pop * 0.5))
	_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, 66.0), "RESETS TO %d NEXT SET" % ResearchManager.DEFAULT_RESEARCH_POINTS, HORIZONTAL_ALIGNMENT_RIGHT, inner, 10, LoadoutStyle.TEXT_MUTED)
	_dock.draw_line(Vector2(x, 100.0), Vector2(x + inner, 100.0), LoadoutStyle.HAIRLINE, 1.0)

	var id: StringName = _selected_id
	var definition: Dictionary = ResearchManager.get_definition(id)
	if definition.is_empty():
		return
	var mark: int = ResearchManager.get_mark(id)
	var max_mark: int = int(definition["max_mark"])
	var unlocked: bool = mark > 0 or _requirements_met(definition)
	var state_text: String = ""
	var state_color: Color = LoadoutStyle.TEXT_MUTED
	if mark >= max_mark:
		state_text = "MAXED"
		state_color = UiStyle.INTEL
	elif mark > 0:
		state_text = "MK %s / %s" % [LoadoutStyle.roman(mark), LoadoutStyle.roman(max_mark)]
		state_color = UiStyle.INTEL
	elif not unlocked:
		state_text = "LOCKED"
	_dock.draw_string(UiStyle.FONT_DISPLAY, Vector2(x, 140.0), str(definition["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, inner - 80.0, 24, LoadoutStyle.TEXT)
	_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, 136.0), state_text, HORIZONTAL_ALIGNMENT_RIGHT, inner, 11, state_color)
	_draw_wrapped(str(definition.get("summary", "")), x, 166.0, inner, 14, LoadoutStyle.TEXT_SECONDARY, 2)

	var levels: Array = definition.get("levels", [])
	var costs: Array = definition.get("costs", [])
	_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, 222.0), str(definition.get("level_label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LoadoutStyle.TEXT_MUTED)
	for index in range(max_mark):
		var y: float = 250.0 + float(index) * 30.0
		var row_mark: int = index + 1
		var done: bool = row_mark <= mark
		var next: bool = row_mark == mark + 1 and unlocked
		var row_color: Color = UiStyle.INTEL if done else (LoadoutStyle.TEXT if next else LoadoutStyle.TEXT_MUTED)
		if next:
			_dock.draw_rect(Rect2(x - 10.0, y - 19.0, inner + 20.0, 27.0), Color(1, 1, 1, 0.07 if ResearchManager.can_purchase(id) else 0.035))
		_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, y), "MK " + LoadoutStyle.roman(row_mark), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, row_color)
		var value: String = str(levels[index]) if index < levels.size() else ""
		_dock.draw_string(UiStyle.FONT_DISPLAY, Vector2(x + 56.0, y + 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row_color)
		if done:
			LoadoutStyle.draw_check(_dock, Vector2(x + inner - 7.0, y - 5.0), 7.0, UiStyle.INTEL, LoadoutStyle.SURFACE_DEEP)
		elif index < costs.size():
			var cost: int = int(costs[index])
			var affordable: bool = next and ResearchManager.research_points >= cost
			var cost_color: Color = UiStyle.INTEL if affordable else (LoadoutStyle.with_alpha(LoadoutStyle.NEGATIVE, 0.8) if next else LoadoutStyle.TEXT_MUTED)
			var cost_text: String = str(cost)
			var cost_width: float = UiStyle.FONT_BOLD.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			ResearchNodeButton.draw_rp_glyph(_dock, Vector2(x + inner - cost_width - 9.0, y - 4.5), 4.5, cost_color)
			_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x + inner - cost_width, y), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cost_color)
	var missing: String = _missing_requirement(definition) if mark == 0 else ""
	if missing != "":
		_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, 362.0), "NEEDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LoadoutStyle.TEXT_MUTED)
		_dock.draw_string(UiStyle.FONT_UI, Vector2(x + 56.0, 363.0), missing, HORIZONTAL_ALIGNMENT_LEFT, inner - 56.0, 14, LoadoutStyle.TEXT)


func _section(x: float, y: float, width: float, text: String) -> void:
	_dock.draw_string(UiStyle.FONT_BOLD, Vector2(x, y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LoadoutStyle.TEXT_SECONDARY)
	var text_width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_dock.draw_line(Vector2(x + text_width + 10.0, y), Vector2(x + width, y), LoadoutStyle.HAIRLINE, 1.0)


## Word-wraps text into at most max_lines lines; returns the baseline of the last line.
func _draw_wrapped(text: String, x: float, y: float, width: float, font_size: int, color: Color, max_lines: int) -> float:
	var font: Font = UiStyle.FONT_BODY
	var words: PackedStringArray = text.split(" ")
	var line: String = ""
	var lines: PackedStringArray = PackedStringArray()
	for word in words:
		var candidate: String = word if line == "" else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
			lines.append(line)
			line = word
		else:
			line = candidate
	if line != "":
		lines.append(line)
	var baseline: float = y
	for index in range(mini(lines.size(), max_lines)):
		baseline = y + float(index) * (font_size + 6.0)
		_dock.draw_string(font, Vector2(x, baseline), lines[index], HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
	return baseline
