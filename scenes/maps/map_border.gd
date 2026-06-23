extends Node2D
class_name MapBorder

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
@export var respawn_grace_seconds: float = 0.45
@export var game_sync_path: NodePath = NodePath("../GameSync")

var _bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS
var _last_hit_time: Dictionary = {}
var _disabled_until_time: float = 0.0
var _game_sync: GameSync = null

@onready var _borders: Dictionary = {
	GameSettings.MAP_BORDER_SIDE_LEFT: $Left,
	GameSettings.MAP_BORDER_SIDE_RIGHT: $Right,
	GameSettings.MAP_BORDER_SIDE_TOP: $Top,
	GameSettings.MAP_BORDER_SIDE_BOTTOM: $Bottom,
}


func _ready() -> void:
	_bounds = _get_map_bounds()
	_game_sync = _get_game_sync()
	if not OnlineMatch.phase_changed.is_connected(_on_online_phase_changed):
		OnlineMatch.phase_changed.connect(_on_online_phase_changed)
	for side in GameSettings.border_sides():
		var border: MapBorderSide = _get_border(side)
		if border == null:
			continue
		border.configure(line_color, GameSettings.MAP_BORDER_COLLISION_MASK)
		border.body_entered.connect(_on_border_body_entered.bind(side))

	_update_border_areas()


func _exit_tree() -> void:
	if OnlineMatch.phase_changed.is_connected(_on_online_phase_changed):
		OnlineMatch.phase_changed.disconnect(_on_online_phase_changed)


func _process(_delta: float) -> void:
	var players: Array[Player] = _get_tracked_players()
	if players.is_empty():
		_hide_all_lines()
		return

	var left_edge: float = _bounds.position.x
	var right_edge: float = _bounds.position.x + _bounds.size.x
	var top_edge: float = _bounds.position.y
	var bottom_edge: float = _bounds.position.y + _bounds.size.y

	var closest_players: Dictionary = {
		GameSettings.MAP_BORDER_SIDE_LEFT: null,
		GameSettings.MAP_BORDER_SIDE_RIGHT: null,
		GameSettings.MAP_BORDER_SIDE_TOP: null,
		GameSettings.MAP_BORDER_SIDE_BOTTOM: null
	}
	var closest_distances: Dictionary = {
		GameSettings.MAP_BORDER_SIDE_LEFT: INF,
		GameSettings.MAP_BORDER_SIDE_RIGHT: INF,
		GameSettings.MAP_BORDER_SIDE_TOP: INF,
		GameSettings.MAP_BORDER_SIDE_BOTTOM: INF
	}

	for player in players:
		var px: float = player.global_position.x
		var py: float = player.global_position.y
		var d_left: float = px - left_edge
		var d_right: float = right_edge - px
		var d_top: float = py - top_edge
		var d_bottom: float = bottom_edge - py
		var min_d: float = d_left
		var best_side: StringName = GameSettings.MAP_BORDER_SIDE_LEFT

		if d_right < min_d:
			min_d = d_right
			best_side = GameSettings.MAP_BORDER_SIDE_RIGHT
		if d_top < min_d:
			min_d = d_top
			best_side = GameSettings.MAP_BORDER_SIDE_TOP
		if d_bottom < min_d:
			min_d = d_bottom
			best_side = GameSettings.MAP_BORDER_SIDE_BOTTOM

		if min_d > -warn_distance and min_d < warn_distance:
			if min_d < closest_distances[best_side]:
				closest_distances[best_side] = min_d
				closest_players[best_side] = player

	_update_vertical(GameSettings.MAP_BORDER_SIDE_LEFT, closest_players[GameSettings.MAP_BORDER_SIDE_LEFT])
	_update_vertical(GameSettings.MAP_BORDER_SIDE_RIGHT, closest_players[GameSettings.MAP_BORDER_SIDE_RIGHT])
	_update_horizontal(GameSettings.MAP_BORDER_SIDE_TOP, closest_players[GameSettings.MAP_BORDER_SIDE_TOP], top_edge)
	_update_horizontal(GameSettings.MAP_BORDER_SIDE_BOTTOM, closest_players[GameSettings.MAP_BORDER_SIDE_BOTTOM], bottom_edge)


func _physics_process(_delta: float) -> void:
	if _are_border_hits_suspended():
		return
	for player in _get_tracked_players():
		var check_position: Vector2 = player.get_border_check_position()
		var side: StringName = _get_overlapping_border_side(check_position)
		if side != &"":
			_try_apply_border_hit(player, side)


func _get_tracked_players() -> Array[Player]:
	var players: Array[Player] = []
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player.is_eliminated():
			continue
		players.append(player)
	return players


func _hide_all_lines() -> void:
	for border_variant in _borders.values():
		var border: MapBorderSide = border_variant as MapBorderSide
		if border != null:
			border.hide_warning()


func _update_vertical(side: StringName, player: Player) -> void:
	var border: MapBorderSide = _get_border(side)
	if border == null:
		return

	if player == null:
		border.hide_warning()
		return

	var map_x: float = _bounds.position.x if side == GameSettings.MAP_BORDER_SIDE_LEFT else _bounds.position.x + _bounds.size.x
	var warning_rect: Rect2 = Rect2(
		Vector2(map_x - line_thickness * 0.5, player.global_position.y - line_length * 0.5),
		Vector2(line_thickness, line_length)
	)
	border.set_warning(warning_rect, _get_particle_amount())


func _update_horizontal(side: StringName, player: Player, map_y: float) -> void:
	var border: MapBorderSide = _get_border(side)
	if border == null:
		return

	if player == null:
		border.hide_warning()
		return

	var warning_rect: Rect2 = Rect2(
		Vector2(player.global_position.x - line_length * 0.5, map_y - line_thickness * 0.5),
		Vector2(line_length, line_thickness)
	)
	border.set_warning(warning_rect, _get_particle_amount())


func _update_border_areas() -> void:
	var left_x: float = _bounds.position.x
	var right_x: float = _bounds.position.x + _bounds.size.x
	var top_y: float = _bounds.position.y
	var bottom_y: float = _bounds.position.y + _bounds.size.y
	var center_x: float = _bounds.position.x + _bounds.size.x * GameSettings.HALF
	var center_y: float = _bounds.position.y + _bounds.size.y * GameSettings.HALF

	_update_border_area(GameSettings.MAP_BORDER_SIDE_LEFT, Vector2(left_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_RIGHT, Vector2(right_x, center_y), Vector2(border_thickness, _bounds.size.y))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_TOP, Vector2(center_x, top_y), Vector2(_bounds.size.x, border_thickness))
	_update_border_area(GameSettings.MAP_BORDER_SIDE_BOTTOM, Vector2(center_x, bottom_y), Vector2(_bounds.size.x, border_thickness))


func _update_border_area(side: StringName, position: Vector2, size: Vector2) -> void:
	var border: MapBorderSide = _get_border(side)
	if border != null:
		border.set_collision_rect(position, size)


func _on_border_body_entered(body: Node, side: StringName) -> void:
	var player: Player = body as Player
	if player == null:
		return
	if _are_border_hits_suspended():
		return
	_try_apply_border_hit(player, side)


func _try_apply_border_hit(player: Player, side: StringName) -> void:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
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
			if combat_sync != null:
				combat_sync.apply_hit(
					player.player_slot,
					source_slot,
					0,
					damage_amount,
					false,
					_get_border_source_position(player, side),
					_get_knockback_vector(side)
				)
	else:
		player.apply_incoming_damage(damage_amount, 0, player.global_position, true)


func _get_overlapping_border_side(position: Vector2) -> StringName:
	var left_edge: float = _bounds.position.x
	var right_edge: float = _bounds.position.x + _bounds.size.x
	var top_edge: float = _bounds.position.y
	var bottom_edge: float = _bounds.position.y + _bounds.size.y
	var overlap_padding: float = border_thickness * GameSettings.HALF + 18.0
	var distances: Dictionary = {
		GameSettings.MAP_BORDER_SIDE_LEFT: position.x - left_edge,
		GameSettings.MAP_BORDER_SIDE_RIGHT: right_edge - position.x,
		GameSettings.MAP_BORDER_SIDE_TOP: position.y - top_edge,
		GameSettings.MAP_BORDER_SIDE_BOTTOM: bottom_edge - position.y,
	}
	var best_side: StringName = &""
	var best_distance: float = INF
	for raw_side in distances.keys():
		var side: StringName = StringName(str(raw_side))
		var distance: float = float(distances[side])
		if distance <= overlap_padding and distance < best_distance:
			best_distance = distance
			best_side = side
	return best_side


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


func _get_border_source_position(player: Player, side: StringName) -> Vector2:
	var left_edge: float = _bounds.position.x
	var right_edge: float = _bounds.position.x + _bounds.size.x
	var top_edge: float = _bounds.position.y
	var bottom_edge: float = _bounds.position.y + _bounds.size.y
	var source_offset: float = maxf(border_thickness, 24.0)
	if side == GameSettings.MAP_BORDER_SIDE_LEFT:
		return Vector2(left_edge - source_offset, player.global_position.y)
	if side == GameSettings.MAP_BORDER_SIDE_RIGHT:
		return Vector2(right_edge + source_offset, player.global_position.y)
	if side == GameSettings.MAP_BORDER_SIDE_TOP:
		return Vector2(player.global_position.x, top_edge - source_offset)
	if side == GameSettings.MAP_BORDER_SIDE_BOTTOM:
		return Vector2(player.global_position.x, bottom_edge + source_offset)
	return player.global_position


func _get_map_bounds() -> Rect2:
	var bounds_node: Node = get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node != null:
		var bounds: Variant = bounds_node.get("bounds")
		if bounds is Rect2:
			return bounds
	return GameSettings.DEFAULT_MAP_BOUNDS


func _get_game_sync() -> GameSync:
	return get_node_or_null(game_sync_path) as GameSync


func _get_border(side: StringName) -> MapBorderSide:
	return _borders.get(side, null) as MapBorderSide


func _get_particle_amount() -> int:
	return int(40.0 * GameJuice.particles_multiplier)


func _on_online_phase_changed(next_phase: StringName) -> void:
	_last_hit_time.clear()
	if next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_disabled_until_time = Time.get_ticks_msec() / GameSettings.MILLISECONDS_PER_SECOND + respawn_grace_seconds
	else:
		_disabled_until_time = INF


func _are_border_hits_suspended() -> bool:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
		return true
	var now: float = Time.get_ticks_msec() / GameSettings.MILLISECONDS_PER_SECOND
	return _disabled_until_time < INF and now < _disabled_until_time
