class_name HudOffscreenIndicators
extends Control

## Edge markers for what matters but is out of view: the opponent (a chevron in their colour with the
## distance) and the supply drop (an amber chevron with a crate mark), including while the crate is still
## falling above the screen. Nothing is drawn while everything is visible.

const EDGE_MARGIN: float = 30.0
const CHEVRON: float = 11.0

var _showing: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var needed: bool = not _targets().is_empty()
	if needed or _showing:
		queue_redraw()
	_showing = needed


## [{position (screen), color, label, kind}] for everything off screen.
func _targets() -> Array:
	var result: Array = []
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_local_player"):
		return result
	var local: Player = world.get_local_player()
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var view: Rect2 = Rect2(Vector2.ZERO, get_viewport_rect().size).grow(-4.0)
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player == local or player.is_eliminated() or not player.visible:
			continue
		var screen: Vector2 = canvas * player.global_position
		if view.has_point(screen):
			continue
		var distance: int = int(local.global_position.distance_to(player.global_position) / 10.0) if local != null else 0
		result.append({"position": screen, "color": player.get_visual_tint(), "label": "%dm" % distance, "kind": &"player"})
	var manager: Node = get_tree().get_first_node_in_group(&"airdrop_manager")
	if manager != null and manager.has_method(&"get_indicator_target"):
		var target: Variant = manager.get_indicator_target()
		if target is Vector2:
			var screen: Vector2 = canvas * (target as Vector2)
			if not view.has_point(screen):
				result.append({"position": screen, "color": UiStyle.ACCENT, "label": "DROP", "kind": &"drop"})
	return result


func _draw() -> void:
	var view: Rect2 = Rect2(Vector2.ZERO, get_viewport_rect().size)
	if view.size.x < 100.0 or view.size.y < 100.0:
		return
	var inner: Rect2 = view.grow(-EDGE_MARGIN)
	var center: Vector2 = view.get_center()
	var pulse: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.007)
	for target in _targets():
		var screen: Vector2 = target["position"]
		var direction: Vector2 = (screen - center).normalized()
		var edge: Vector2 = _clamp_to_rect(center, direction, inner)
		# Keep clear of the score at the top centre.
		if edge.y < 84.0 and absf(edge.x - center.x) < 210.0:
			edge.y = 84.0
		var color: Color = target["color"]
		var tip: Vector2 = edge + direction * CHEVRON
		var side: Vector2 = direction.orthogonal() * CHEVRON * 0.75
		var back: Vector2 = edge - direction * CHEVRON * 0.35
		var chevron: PackedVector2Array = PackedVector2Array([tip, edge + side - direction * CHEVRON * 0.6, back, edge - side - direction * CHEVRON * 0.6])
		var outline: PackedVector2Array = PackedVector2Array()
		for point in chevron:
			outline.append(edge + (point - edge) * 1.3)
		draw_colored_polygon(outline, Color(0.0, 0.0, 0.0, 0.75))
		draw_colored_polygon(chevron, LoadoutStyle.with_alpha(color, pulse))
		var label: String = target["label"]
		var label_center: Vector2 = edge - direction * 24.0
		if target["kind"] == &"drop":
			var box: Rect2 = Rect2(label_center - Vector2(7.0, 12.0), Vector2(14.0, 9.0))
			draw_rect(box.grow(1.5), Color(0.0, 0.0, 0.0, 0.75))
			draw_rect(box, LoadoutStyle.with_alpha(color, pulse))
			draw_rect(Rect2(box.position.x, box.position.y + 2.5, box.size.x, 1.0), Color(0.0, 0.0, 0.0, 0.6))
			label_center.y += 8.0
		draw_string_outline(UiStyle.FONT_BOLD, label_center + Vector2(-30.0, 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, 4, Color(0, 0, 0, 0.7))
		draw_string(UiStyle.FONT_BOLD, label_center + Vector2(-30.0, 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, color.lightened(0.25))


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
