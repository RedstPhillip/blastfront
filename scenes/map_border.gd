extends Node2D

@export var warn_distance: float = 50.0
@export var line_length: float = 60.0
@export var line_thickness: float = 5.0
@export var line_color: Color = Color(1, 0, 0, 0.85)
@export var border_thickness: float = 24.0
@export var knockback_speed: float = 1250.0
@export var knockback_lift: float = 380.0
@export var bottom_knockback_speed: float = 1500.0
@export var damage_amount: int = 50
@export var hit_cooldown: float = 0.25

var _lines: Dictionary = {}
var _bounds := Rect2(0.0, 0.0, 2262.0, 720.0)
var _areas: Dictionary = {}
var _last_hit_time: Dictionary = {}
var _game_sync = null

func _ready() -> void:
	_bounds = _get_map_bounds()
	_game_sync = _get_game_sync()
	for side in ["left", "right", "top", "bottom"]:
		var cr := ColorRect.new()
		cr.color = line_color
		cr.visible = false
		cr.z_index = 100
		add_child(cr)
		_lines[side] = cr

		var area := Area2D.new()
		area.monitoring = true
		area.monitorable = true
		area.collision_mask = 2
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		area.add_child(shape)
		add_child(area)
		area.body_entered.connect(_on_border_body_entered.bind(side))
		_areas[side] = area

	_update_border_areas()


func _process(_delta: float) -> void:
	var players: Array[Node2D] = _get_tracked_players()
	if players.is_empty():
		_hide_all_lines()
		return

	_update_vertical("left", _find_left_player(players))
	_update_vertical("right", _find_right_player(players))
	var map_top := _bounds.position.y
	var map_bottom := _bounds.position.y + _bounds.size.y
	_update_horizontal("top", _find_top_player(players, map_top), map_top)
	_update_horizontal("bottom", _find_bottom_player(players, map_bottom), map_bottom)


func _get_tracked_players() -> Array[Node2D]:
	var players: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node2D:
			players.append(node)
	return players


func _hide_all_lines() -> void:
	for line in _lines.values():
		line.visible = false


func _find_left_player(players: Array[Node2D]):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := player.global_position.x - _bounds.position.x
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_right_player(players: Array[Node2D]):
	var best_player = null
	var best_distance := INF
	var right_edge := _bounds.position.x + _bounds.size.x
	for player in players:
		var distance := right_edge - player.global_position.x
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_top_player(players: Array[Node2D], map_top: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := player.global_position.y - map_top
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_bottom_player(players: Array[Node2D], map_bottom: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := map_bottom - player.global_position.y
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _update_vertical(side: String, player) -> void:
	var cr: ColorRect = _lines[side]
	cr.visible = player != null
	if player == null:
		return

	var map_x := _bounds.position.x if side == "left" else _bounds.position.x + _bounds.size.x
	cr.size = Vector2(line_thickness, line_length)
	cr.position = Vector2(map_x - line_thickness / 2.0, player.global_position.y - line_length / 2.0)


func _update_horizontal(side: String, player, map_y: float) -> void:
	var cr: ColorRect = _lines[side]
	cr.visible = player != null
	if player == null:
		return

	cr.size = Vector2(line_length, line_thickness)
	cr.position = Vector2(player.global_position.x - line_length / 2.0, map_y - line_thickness / 2.0)


func _update_border_areas() -> void:
	var left_x := _bounds.position.x
	var right_x := _bounds.position.x + _bounds.size.x
	var top_y := _bounds.position.y
	var bottom_y := _bounds.position.y + _bounds.size.y
	var center_x := _bounds.position.x + _bounds.size.x * 0.5
	var center_y := _bounds.position.y + _bounds.size.y * 0.5

	_update_border_area("left", Vector2(left_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area("right", Vector2(right_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area("top", Vector2(center_x, top_y), Vector2(_bounds.size.x, border_thickness))
	_update_border_area("bottom", Vector2(center_x, bottom_y), Vector2(_bounds.size.x, border_thickness))


func _update_border_area(side: String, position: Vector2, size: Vector2) -> void:
	var area: Area2D = _areas.get(side, null)
	if area == null:
		return
	area.position = position
	var shape := area.get_child(0) as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		(shape.shape as RectangleShape2D).size = size


func _on_border_body_entered(body: Node, side: String) -> void:
	var player := body as Player
	if player == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	var last_time: float = float(_last_hit_time.get(player, -1000.0))
	if now - last_time < hit_cooldown:
		return
	_last_hit_time[player] = now

	if not NetworkSession.is_steam_match_active() or player.control_mode == Player.CONTROL_LOCAL:
		player.velocity = _get_knockback_vector(side)

	if NetworkSession.is_steam_match_active():
		if _game_sync != null and _game_sync.is_host():
			var source_slot := 2 if player.player_slot == 1 else 1
			var combat_sync = _game_sync.get_module(&"combat")
			if combat_sync != null and combat_sync.has_method("apply_hit"):
				combat_sync.call("apply_hit", player.player_slot, source_slot, 0, damage_amount)
	else:
		if player.health_component != null:
			player.health_component.damage(damage_amount)


func _get_knockback_vector(side: String) -> Vector2:
	match side:
		"left":
			return Vector2(knockback_speed, -knockback_lift)
		"right":
			return Vector2(-knockback_speed, -knockback_lift)
		"top":
			return Vector2(0.0, knockback_speed)
		"bottom":
			return Vector2(0.0, -bottom_knockback_speed)
	return Vector2.ZERO


func _get_map_bounds() -> Rect2:
	var bounds_node := get_tree().get_first_node_in_group("map_bounds")
	if bounds_node != null:
		var bounds: Variant = bounds_node.get("bounds")
		if bounds is Rect2:
			return bounds
	return Rect2(0.0, 0.0, 2262.0, 720.0)


func _get_game_sync():
	return get_node_or_null("../GameSync")
