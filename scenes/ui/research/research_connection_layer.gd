extends Control
class_name ResearchConnectionLayer

var definitions: Array[Dictionary] = []
var root_position: Vector2 = Vector2(55, 280)


func set_definitions(next_definitions: Array[Dictionary]) -> void:
	definitions = next_definitions
	queue_redraw()


func _draw() -> void:
	var positions: Dictionary = {}
	for definition in definitions:
		positions[str(definition.get("id", ""))] = definition.get("position", Vector2.ZERO) + Vector2(37, 37)

	var starters: Dictionary = {
		str(ResearchManager.RECYCLING): Color8(205, 151, 65, 255),
		str(ResearchManager.DASHING): Color8(137, 148, 101, 255),
		str(ResearchManager.LIFE_STEAL): Color8(176, 91, 62, 255),
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

	var root_rect: Rect2 = Rect2(root_position - Vector2(27, 27), Vector2(54, 54))
	draw_rect(root_rect, Color8(45, 40, 32, 255), true)
	draw_rect(root_rect, Color8(184, 155, 105, 220), false, 3.0)
	draw_rect(Rect2(root_position - Vector2(7, 7), Vector2(14, 14)), Color8(205, 167, 99, 225), true)


func _draw_connection(from: Vector2, to: Vector2, color: Color, unlocked: bool) -> void:
	var line_alpha: float = 0.56 if unlocked else 0.28
	var line_color: Color = Color(color.r, color.g, color.b, line_alpha)
	var midpoint_x: float = lerpf(from.x, to.x, 0.5)
	var points: PackedVector2Array = PackedVector2Array([
		from,
		Vector2(midpoint_x, from.y),
		Vector2(midpoint_x, to.y),
		to,
	])
	draw_polyline(points, line_color, 2.1, true)


func _branch_color(branch: StringName) -> Color:
	match branch:
		ResearchManager.BRANCH_ECONOMY:
			return Color8(205, 151, 65, 185)
		ResearchManager.BRANCH_MOVEMENT:
			return Color8(137, 148, 101, 175)
		_:
			return Color8(176, 91, 62, 180)
