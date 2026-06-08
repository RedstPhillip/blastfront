extends Control

var definitions: Array[Dictionary] = []
var root_position: Vector2 = Vector2(55, 252)


func set_definitions(next_definitions: Array[Dictionary]) -> void:
	definitions = next_definitions
	queue_redraw()


func _draw() -> void:
	var positions: Dictionary = {}
	for definition in definitions:
		positions[str(definition.get("id", ""))] = definition.get("position", Vector2.ZERO) + Vector2(37, 37)

	var starters: Dictionary = {
		str(ResearchManager.RECYCLING): Color8(245, 190, 66, 175),
		str(ResearchManager.DASHING): Color8(80, 190, 255, 150),
		str(ResearchManager.LIFE_STEAL): Color8(205, 105, 245, 165),
	}
	for starter_id in starters.keys():
		if positions.has(starter_id):
			_draw_connection(root_position, positions[starter_id], starters[starter_id], true)

	for definition in definitions:
		var target_id: String = str(definition.get("id", ""))
		var target_position: Vector2 = positions.get(target_id, Vector2.ZERO)
		var branch: StringName = StringName(str(definition.get("branch", "")))
		var color: Color = _branch_color(branch)
		if definition.get("available", true) != true:
			color = Color8(75, 79, 86, 125)
		var requirements_variant: Variant = definition.get("requires", [])
		if not (requirements_variant is Array):
			continue
		var requirements: Array = requirements_variant
		for requirement_variant in requirements:
			if not (requirement_variant is Dictionary):
				continue
			var requirement: Dictionary = requirement_variant
			var source_id: String = str(requirement.get("id", ""))
			if positions.has(source_id):
				var unlocked: bool = ResearchManager.get_mark(StringName(source_id)) >= int(requirement.get("mark", 1))
				_draw_connection(positions[source_id], target_position, color, unlocked)

	draw_circle(root_position, 29.0, Color8(28, 36, 43, 255))
	draw_arc(root_position, 29.0, 0.0, TAU, 48, Color8(225, 238, 240, 220), 3.0, true)
	draw_circle(root_position, 8.0, Color8(225, 238, 240, 225))


func _draw_connection(from: Vector2, to: Vector2, color: Color, unlocked: bool) -> void:
	var line_color: Color = color if unlocked else Color(color.r, color.g, color.b, 0.35)
	var midpoint_x: float = lerpf(from.x, to.x, 0.5)
	var points: PackedVector2Array = PackedVector2Array([
		from,
		Vector2(midpoint_x, from.y),
		Vector2(midpoint_x, to.y),
		to,
	])
	draw_polyline(points, line_color, 3.0 if unlocked else 2.0, true)


func _branch_color(branch: StringName) -> Color:
	match branch:
		ResearchManager.BRANCH_ECONOMY:
			return Color8(245, 190, 66, 185)
		ResearchManager.BRANCH_MOVEMENT:
			return Color8(80, 190, 255, 175)
		_:
			return Color8(205, 105, 245, 180)
