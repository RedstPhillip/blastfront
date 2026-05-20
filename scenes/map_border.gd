extends Node2D

@export var warn_distance: float = GameSettings.MAP_BORDER_WARN_DISTANCE
@export var line_length: float = GameSettings.MAP_BORDER_LINE_LENGTH
@export var line_thickness: float = GameSettings.MAP_BORDER_LINE_THICKNESS
@export var line_color: Color = GameSettings.MAP_BORDER_LINE_COLOR
@export var border_thickness: float = GameSettings.MAP_BORDER_THICKNESS
@export var knockback_speed: float = GameSettings.MAP_BORDER_KNOCKBACK_SPEED
@export var knockback_lift: float = GameSettings.MAP_BORDER_KNOCKBACK_LIFT
@export var bottom_knockback_speed: float = GameSettings.MAP_BORDER_BOTTOM_KNOCKBACK_SPEED
@export var damage_amount: int = GameSettings.MAP_BORDER_DAMAGE
@export var hit_cooldown: float = GameSettings.MAP_BORDER_HIT_COOLDOWN

var _lines: Dictionary = {}
var _bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS
var _areas: Dictionary = {}
var _last_hit_time: Dictionary = {}
var _game_sync: GameSync = null


func _ready() -> void:
	_bounds = _get_map_bounds()
	_game_sync = _get_game_sync()
	for side in GameSettings.border_sides():
		_create_warning_line(side)
		_create_border_area(side)

	_update_border_areas()


func _process(_delta: float) -> void:
	var players: Array[Node2D] = _get_tracked_players()
	if players.is_empty():
		_hide_all_lines()
		return

	var left_edge: float = _bounds.position.x
	var right_edge: float = _bounds.position.x + _bounds.size.x
	var top_edge: float = _bounds.position.y
	var bottom_edge: float = _bounds.position.y + _bounds.size.y

	_update_vertical(GameSettings.MAP_BORDER_SIDE_LEFT, _find_player_near_vertical_edge(players, left_edge, true))
	_update_vertical(GameSettings.MAP_BORDER_SIDE_RIGHT, _find_player_near_vertical_edge(players, right_edge, false))
	_update_horizontal(GameSettings.MAP_BORDER_SIDE_TOP, _find_player_near_horizontal_edge(players, top_edge, true), top_edge)
	_update_horizontal(GameSettings.MAP_BORDER_SIDE_BOTTOM, _find_player_near_horizontal_edge(players, bottom_edge, false), bottom_edge)


func _create_warning_line(side: StringName) -> void:
	var line := ColorRect.new()
	line.color = line_color
	line.visible = false
	line.z_index = GameSettings.MAP_BORDER_LINE_Z_INDEX
	add_child(line)
	_lines[side] = line


func _create_border_area(side: StringName) -> void:
	var area := Area2D.new()
	area.monitoring = true
	area.monitorable = true
	area.collision_mask = GameSettings.MAP_BORDER_COLLISION_MASK

	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_border_body_entered.bind(side))
	_areas[side] = area


func _get_tracked_players() -> Array[Node2D]:
	var players: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		if node is Node2D:
			if node.has_method("is_eliminated") and node.call("is_eliminated") == true:
				continue
			players.append(node)
	return players


func _hide_all_lines() -> void:
	for line in _lines.values():
		var color_rect: ColorRect = line as ColorRect
		if color_rect != null:
			color_rect.visible = false


func _find_player_near_vertical_edge(players: Array[Node2D], edge_x: float, is_left_edge: bool) -> Node2D:
	var best_player: Node2D = null
	var best_distance: float = INF
	for player in players:
		var distance: float = player.global_position.x - edge_x if is_left_edge else edge_x - player.global_position.x
		if _is_inside_warning_distance(distance, best_distance):
			best_distance = distance
			best_player = player
	return best_player


func _find_player_near_horizontal_edge(players: Array[Node2D], edge_y: float, is_top_edge: bool) -> Node2D:
	var best_player: Node2D = null
	var best_distance: float = INF
	for player in players:
		var distance: float = player.global_position.y - edge_y if is_top_edge else edge_y - player.global_position.y
		if _is_inside_warning_distance(distance, best_distance):
			best_distance = distance
			best_player = player
	return best_player


func _is_inside_warning_distance(distance: float, best_distance: float) -> bool:
	return distance >= 0.0 and distance < warn_distance and distance < best_distance


func _update_vertical(side: StringName, player: Node2D) -> void:
	var cr: ColorRect = _lines[side] as ColorRect
	if cr == null:
		return
	cr.visible = player != null
	if player == null:
		return

	var map_x: float = _bounds.position.x if side == GameSettings.MAP_BORDER_SIDE_LEFT else _bounds.position.x + _bounds.size.x
	cr.size = Vector2(line_thickness, line_length)
	cr.position = Vector2(map_x - line_thickness / 2.0, player.global_position.y - line_length / 2.0)


func _update_horizontal(side: StringName, player: Node2D, map_y: float) -> void:
	var cr: ColorRect = _lines[side] as ColorRect
	if cr == null:
		return
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
	var center_x := _bounds.position.x + _bounds.size.x * GameSettings.HALF
	var center_y := _bounds.position.y + _bounds.size.y * GameSettings.HALF

	_update_border_area(GameSettings.MAP_BORDER_SIDE_LEFT, Vector2(left_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_RIGHT, Vector2(right_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_TOP, Vector2(center_x, top_y), Vector2(_bounds.size.x, border_thickness))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_BOTTOM, Vector2(center_x, bottom_y), Vector2(_bounds.size.x, border_thickness))


func _update_border_area(side: StringName, position: Vector2, size: Vector2) -> void:
	var area: Area2D = _areas.get(side, null) as Area2D
	if area == null:
		return
	area.position = position
	var shape: CollisionShape2D = area.get_child(0) as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		(shape.shape as RectangleShape2D).size = size


func _on_border_body_entered(body: Node, side: StringName) -> void:
	var player: Player = body as Player
	if player == null:
		return

	var now: float = Time.get_ticks_msec() / GameSettings.MILLISECONDS_PER_SECOND
	var last_time: float = float(_last_hit_time.get(player, GameSettings.MAP_BORDER_INITIAL_HIT_TIME))
	if now - last_time < hit_cooldown:
		return
	_last_hit_time[player] = now

	if not NetworkSession.is_steam_match_active() or player.control_mode == GameSettings.CONTROL_LOCAL:
		player.velocity = _get_knockback_vector(side)

	if NetworkSession.is_steam_match_active():
		if _game_sync == null:
			_game_sync = _get_game_sync()
		if _game_sync != null and _game_sync.is_host():
			var source_slot: int = GameSettings.PLAYER_TWO_SLOT if player.player_slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT
			var combat_sync: Variant = _game_sync.get_module(GameSettings.MODULE_COMBAT)
			if combat_sync != null and combat_sync.has_method("apply_hit"):
				combat_sync.call("apply_hit", player.player_slot, source_slot, 0, damage_amount)
	else:
		if player.health_component != null:
			player.health_component.damage(damage_amount)


func _get_knockback_vector(side: StringName) -> Vector2:
	if side == GameSettings.MAP_BORDER_SIDE_LEFT:
		return Vector2(knockback_speed, -knockback_lift)
	if side == GameSettings.MAP_BORDER_SIDE_RIGHT:
		return Vector2(-knockback_speed, -knockback_lift)
	if side == GameSettings.MAP_BORDER_SIDE_TOP:
		return Vector2(0.0, knockback_speed)
	if side == GameSettings.MAP_BORDER_SIDE_BOTTOM:
		return Vector2(0.0, -bottom_knockback_speed)
	return Vector2.ZERO


func _get_map_bounds() -> Rect2:
	var bounds_node := get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node != null:
		var bounds: Variant = bounds_node.get("bounds")
		if bounds is Rect2:
			return bounds
	return GameSettings.DEFAULT_MAP_BOUNDS


func _get_game_sync() -> GameSync:
	return get_node_or_null("../GameSync") as GameSync
