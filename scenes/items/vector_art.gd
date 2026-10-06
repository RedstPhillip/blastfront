class_name VectorArt
extends RefCounted

## Shared renderer for the procedural vector art (WeaponArt, ArmorArt). A part is a list of ops (dictionaries
## with "t" = poly / circle / ring / line, see WeaponArt._poly and friends) drawn as an outline pass, then a
## fill pass.
##
## Drawing op by op cost one draw_colored_polygon per shape, and every one of those re-triangulates the
## polygon and becomes its own draw call: a full gun was ~150 commands per redraw. Here each run of
## consecutive polygons in a pass is triangulated once and submitted as a single triangle array with
## per-vertex colours; circles, rings and lines stay native antialiased draws between the runs, so the
## stacking order is exactly the same. The geometry plan is built once per op list (stored on its first op,
## so it lives exactly as long as the art's own part cache) and the resolved colours are cached per palette.

const PLAN_KEY: String = "_vector_plan"
## Colour sets kept per plan; animated palettes (flashes, fades) cycle through and get rebuilt.
const MAX_PALETTES: int = 6
const FLASH_COLOR: Color = Color(1.0, 0.97, 0.88)


## Applies the art's palette effects to a base colour: desaturation, a flash towards warm white, then the
## overall tint (alpha).
static func shade(color: Color, alpha: float, flash: float, desaturate: float) -> Color:
	var result: Color = color
	if desaturate > 0.0:
		var luma: float = color.r * 0.3 + color.g * 0.55 + color.b * 0.15
		result = Color(luma, luma, luma, color.a).lerp(result, 1.0 - desaturate)
	if flash > 0.0:
		result = result.lerp(Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, result.a), flash)
	return Color(result.r, result.g, result.b, result.a * alpha)


## Draws an op list with the canvas' current transform. palette: {"outline": Color, "roles": {role: Color},
## "alpha": float, "flash": float, "desaturate": float}; an op's colour is its role's colour, else its own.
static func draw_ops(canvas: CanvasItem, ops: Array, palette: Dictionary) -> void:
	if ops.is_empty():
		return
	var plan: Dictionary = _plan(ops)
	var colors: Array = _colors(plan, ops, palette)
	var item: RID = canvas.get_canvas_item()
	var batch: int = 0
	for step in plan["steps"]:
		if step is Dictionary:
			RenderingServer.canvas_item_add_triangle_array(item, step["indices"], step["points"], colors[batch])
			batch += 1
		else:
			_draw_native(canvas, ops[absi(int(step)) - 1], int(step) < 0, palette)


static func _draw_native(canvas: CanvasItem, op: Dictionary, outline: bool, palette: Dictionary) -> void:
	var color: Color = _op_color(op, outline, palette)
	match op["t"]:
		"circle":
			var radius: float = float(op["r"]) + (float(op.get("ow", 0.0)) if outline else 0.0)
			canvas.draw_circle(op["p"], radius, color, true, -1.0, true)
		"ring":
			canvas.draw_arc(op["p"], op["r"], 0.0, TAU, 24, color, op["w"], true)
		"line":
			canvas.draw_polyline(op["pts"], color, op["w"], true)


static func _op_color(op: Dictionary, outline: bool, palette: Dictionary) -> Color:
	var base: Color = palette["outline"] if outline else (palette["roles"] as Dictionary).get(op.get("role", &""), op["c"])
	return shade(base, float(palette["alpha"]), float(palette["flash"]), float(palette["desaturate"]))


## Geometry for an op list: steps in draw order. A step is either a polygon run {points, indices, ranges}
## (ranges: [op index, outline?, first vertex, vertex count] for colouring) or an int naming a native op:
## op index + 1, negative for its outline.
static func _plan(ops: Array) -> Dictionary:
	var head: Dictionary = ops[0]
	if head.has(PLAN_KEY):
		return head[PLAN_KEY]
	var steps: Array = []
	var run: Dictionary = {}
	for outline in [true, false]:
		for index in range(ops.size()):
			var op: Dictionary = ops[index]
			if outline and not op.get("o", false):
				continue
			if op["t"] == "poly":
				var shapes: Array = op["outline"] if outline else [op["pts"]]
				for shape in shapes:
					run = _add_polygon(steps, run, shape, index, outline)
			elif not outline or op["t"] == "circle":
				run = {}
				steps.append(-(index + 1) if outline else index + 1)
	var plan: Dictionary = {"steps": steps, "palettes": {}, "order": []}
	head[PLAN_KEY] = plan
	return plan


static func _add_polygon(steps: Array, run: Dictionary, shape: PackedVector2Array, op_index: int, outline: bool) -> Dictionary:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(shape)
	if indices.is_empty():
		return run
	if run.is_empty():
		run = {"points": PackedVector2Array(), "indices": PackedInt32Array(), "ranges": []}
		steps.append(run)
	# Packed arrays are values: take them out, extend them, put them back.
	var points: PackedVector2Array = run["points"]
	var all_indices: PackedInt32Array = run["indices"]
	var first: int = points.size()
	points.append_array(shape)
	for value in indices:
		all_indices.append(first + value)
	run["points"] = points
	run["indices"] = all_indices
	(run["ranges"] as Array).append([op_index, outline, first, shape.size()])
	return run


static func _colors(plan: Dictionary, ops: Array, palette: Dictionary) -> Array:
	var key: String = "%s|%s|%s|%s|%s" % [palette["outline"], palette["roles"], palette["alpha"], palette["flash"], palette["desaturate"]]
	var cache: Dictionary = plan["palettes"]
	if cache.has(key):
		return cache[key]
	var result: Array = []
	for step in plan["steps"]:
		if not (step is Dictionary):
			continue
		var colors: PackedColorArray = PackedColorArray()
		colors.resize((step["points"] as PackedVector2Array).size())
		for entry in step["ranges"]:
			var color: Color = _op_color(ops[entry[0]], entry[1], palette)
			var first: int = entry[2]
			for vertex in range(first, first + int(entry[3])):
				colors[vertex] = color
		result.append(colors)
	var order: Array = plan["order"]
	order.append(key)
	cache[key] = result
	if order.size() > MAX_PALETTES:
		cache.erase(order.pop_front())
	return result
