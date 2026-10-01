class_name HudOffscreenIndicators
extends Control

## Edge-of-screen arrows pointing at players that are outside the camera view.

const EDGE_MARGIN: float = 38.0
const BADGE_RADIUS: float = 15.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


var _showing: bool = true


func _process(_delta: float) -> void:
	var needed: bool = _any_offscreen()
	if needed or _showing:
		queue_redraw()
	_showing = needed


func _any_offscreen() -> bool:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_local_player"):
		return false
	var local: Player = world.get_local_player()
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var view: Rect2 = Rect2(Vector2.ZERO, get_viewport_rect().size).grow(-4.0)
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player == local or player.is_eliminated() or not player.visible:
			continue
		if not view.has_point(canvas * player.global_position):
			return true
	return false


func _draw() -> void:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_local_player"):
		return
	var local: Player = world.get_local_player()
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var view: Rect2 = Rect2(Vector2.ZERO, get_viewport_rect().size)
	if view.size.x < 100.0 or view.size.y < 100.0:
		return
	var inner: Rect2 = view.grow(-EDGE_MARGIN)
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player == local or player.is_eliminated() or not player.visible:
			continue
		var screen: Vector2 = canvas * player.global_position
		if view.grow(-4.0).has_point(screen):
			continue
		var center: Vector2 = view.get_center()
		var direction: Vector2 = (screen - center).normalized()
		var edge: Vector2 = _clamp_to_rect(center, direction, inner)
		var color: Color = player.get_visual_tint()
		var pulse: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(edge, BADGE_RADIUS + 2.0, Color(0, 0.03, 0.03, 0.8), true, -1.0, true)
		draw_circle(edge, BADGE_RADIUS, Color(color.r, color.g, color.b, 0.85 * pulse), true, -1.0, true)
		var tip: Vector2 = edge + direction * (BADGE_RADIUS + 11.0)
		var side: Vector2 = direction.orthogonal() * 7.0
		var base: Vector2 = edge + direction * (BADGE_RADIUS + 1.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(color.r, color.g, color.b, pulse))
		var distance: int = int(local.global_position.distance_to(player.global_position) / 10.0) if local != null else 0
		draw_string(UiStyle.FONT_BOLD, edge + Vector2(-20.0, 5.0), "%dm" % distance, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, Color(0.02, 0.04, 0.04, 1.0))


func _clamp_to_rect(origin: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var t_values: Array[float] = []
	if absf(direction.x) > 0.0001:
		t_values.append(((rect.end.x if direction.x > 0.0 else rect.position.x) - origin.x) / direction.x)
	if absf(direction.y) > 0.0001:
		t_values.append(((rect.end.y if direction.y > 0.0 else rect.position.y) - origin.y) / direction.y)
	var t: float = INF
	for value in t_values:
		if value > 0.0:
			t = minf(t, value)
	return origin + direction * (t if t != INF else 0.0)
