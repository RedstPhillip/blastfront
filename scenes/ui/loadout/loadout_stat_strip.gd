class_name LoadoutStatStrip
extends Control

## The key numbers under a stage. Values count to their new value when the build changes, flash green or
## red and show a small delta tag. Hovering an item previews its effect: the value shows the result in
## green or red and the bar grows (or gives back) a ghost segment of the same colour.

const CELL_GAP: float = 16.0
const LABEL_SIZE: int = 10
const VALUE_SIZE: int = 18

var _cells: Array[Dictionary] = []
var _time: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 44.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## entries: [{key, label, value, text(value)->String callable, max, lower_is_better}]
func set_stats(entries: Array, animate: bool) -> void:
	var previous: Dictionary = {}
	for cell in _cells:
		previous[cell["key"]] = cell
	var next: Array[Dictionary] = []
	for entry in entries:
		var key: StringName = entry["key"]
		var cell: Dictionary = entry.duplicate()
		cell["shown"] = float(entry["value"])
		cell["flash"] = 0.0
		cell["delta"] = 0.0
		cell["preview"] = null
		if previous.has(key):
			var old: Dictionary = previous[key]
			cell["shown"] = float(old["shown"])
			cell["preview"] = old.get("preview", null)
			if animate and not is_equal_approx(float(old["value"]), float(entry["value"])):
				var diff: float = float(entry["value"]) - float(old["value"])
				var better: bool = diff < 0.0 if entry.get("lower_is_better", false) else diff > 0.0
				cell["flash"] = 1.0
				cell["delta"] = diff
				cell["better"] = better
			elif not animate:
				cell["shown"] = float(entry["value"])
		next.append(cell)
	_cells = next
	set_process(true)
	queue_redraw()


## Preview values while an item is hovered (key -> value); empty dictionary clears.
func set_preview(values: Dictionary) -> void:
	for cell in _cells:
		cell["preview"] = values.get(cell["key"], null)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var busy: bool = false
	for cell in _cells:
		var target: float = float(cell["value"])
		var shown: float = float(cell["shown"])
		if not is_equal_approx(shown, target):
			cell["shown"] = lerpf(shown, target, 1.0 - exp(-12.0 * delta))
			if absf(float(cell["shown"]) - target) < 0.005:
				cell["shown"] = target
			busy = true
		if float(cell["flash"]) > 0.0:
			cell["flash"] = maxf(float(cell["flash"]) - delta * 0.6, 0.0)
			busy = true
	queue_redraw()
	if not busy:
		set_process(false)


func _draw() -> void:
	if _cells.is_empty():
		return
	var width: float = (size.x - CELL_GAP * float(_cells.size() - 1)) / float(_cells.size())
	for index in range(_cells.size()):
		var cell: Dictionary = _cells[index]
		var x: float = float(index) * (width + CELL_GAP)
		var flash: float = float(cell["flash"])
		var better: bool = cell.get("better", true)
		var flash_color: Color = LoadoutStyle.POSITIVE if better else LoadoutStyle.NEGATIVE
		draw_string(UiStyle.FONT_BOLD, Vector2(x, 10.0), str(cell["label"]), HORIZONTAL_ALIGNMENT_LEFT, width, LABEL_SIZE, LoadoutStyle.TEXT_MUTED)
		var formatter: Callable = cell["text"]
		var shown: float = float(cell["shown"])
		var preview: Variant = cell["preview"]
		var value_text: String = formatter.call(shown)
		var value_color: Color = LoadoutStyle.TEXT.lerp(flash_color, flash)
		var previewing: bool = preview != null and not is_equal_approx(float(preview), float(cell["value"]))
		var preview_color: Color = LoadoutStyle.TEXT
		if previewing:
			var diff: float = float(preview) - float(cell["value"])
			var preview_better: bool = diff < 0.0 if cell.get("lower_is_better", false) else diff > 0.0
			preview_color = LoadoutStyle.POSITIVE if preview_better else LoadoutStyle.NEGATIVE
			value_text = formatter.call(float(preview))
			value_color = preview_color
		draw_string(UiStyle.FONT_DISPLAY, Vector2(x, 32.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, width, VALUE_SIZE, value_color)
		var bar: Rect2 = Rect2(x, size.y - 3.0, width, 3.0)
		draw_rect(bar, Color(1, 1, 1, 0.07))
		var ratio: float = _ratio(cell, shown)
		if previewing:
			var preview_ratio: float = _ratio(cell, float(preview))
			var base: float = minf(ratio, preview_ratio)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * base, bar.size.y)), Color(1, 1, 1, 0.55))
			draw_rect(Rect2(bar.position.x + bar.size.x * base, bar.position.y, bar.size.x * absf(preview_ratio - ratio), bar.size.y), preview_color)
		else:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(1, 1, 1, 0.55).lerp(flash_color, flash * 0.8))
		if flash > 0.0 and not is_zero_approx(float(cell["delta"])) and not previewing:
			# The change rides high after the value like a superscript, small enough to stay inside the cell.
			var delta_value: float = float(cell["delta"])
			var tag: String = ("+" if delta_value > 0.0 else "−") + _trim_number(formatter.call(absf(delta_value)).replace("/s", "").replace("s", ""))
			var value_width: float = UiStyle.FONT_DISPLAY.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE).x
			draw_string(UiStyle.FONT_BOLD, Vector2(x + value_width + 3.0, 22.0 - (1.0 - flash) * 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(flash_color.r, flash_color.g, flash_color.b, clampf(flash * 1.6, 0.0, 1.0)))


func _ratio(cell: Dictionary, value: float) -> float:
	var maximum: float = maxf(float(cell.get("max", 1.0)), 0.001)
	if cell.get("lower_is_better", false):
		return clampf(1.0 - value / maximum, 0.04, 1.0)
	return clampf(value / maximum, 0.0, 1.0)


## "0.10" -> "0.1", "2.00" -> "2": deltas are read at a glance, trailing zeros only add width.
func _trim_number(text: String) -> String:
	if not text.contains("."):
		return text
	return text.rstrip("0").rstrip(".")
