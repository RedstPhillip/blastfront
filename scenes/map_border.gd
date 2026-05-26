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
var _particles: Dictionary = {}


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

	var closest_players = {
		GameSettings.MAP_BORDER_SIDE_LEFT: null,
		GameSettings.MAP_BORDER_SIDE_RIGHT: null,
		GameSettings.MAP_BORDER_SIDE_TOP: null,
		GameSettings.MAP_BORDER_SIDE_BOTTOM: null
	}
	var closest_distances = {
		GameSettings.MAP_BORDER_SIDE_LEFT: INF,
		GameSettings.MAP_BORDER_SIDE_RIGHT: INF,
		GameSettings.MAP_BORDER_SIDE_TOP: INF,
		GameSettings.MAP_BORDER_SIDE_BOTTOM: INF
	}

	for player in players:
		var px = player.global_position.x
		var py = player.global_position.y
		
		var d_left = px - left_edge
		var d_right = right_edge - px
		var d_top = py - top_edge
		var d_bottom = bottom_edge - py
		
		var min_d = d_left
		var best_side = GameSettings.MAP_BORDER_SIDE_LEFT
		
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


func _create_warning_line(side: StringName) -> void:
	var line := ColorRect.new()
	line.color = line_color
	line.visible = false
	line.z_index = GameSettings.MAP_BORDER_LINE_Z_INDEX
	add_child(line)
	_lines[side] = line

	var parts := CPUParticles2D.new()
	parts.z_index = GameSettings.MAP_BORDER_LINE_Z_INDEX - 1
	parts.amount = 40
	parts.lifetime = 1.2
	parts.lifetime_randomness = 0.6
	parts.preprocess = 0.5
	parts.speed_scale = 1.0
	parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	parts.color = Color.WHITE
	parts.emitting = false
	parts.visible = false
	parts.texture = load("res://assets/particles/square_particle.png")
	parts.spread = 180.0
	parts.gravity = Vector2.ZERO
	parts.initial_velocity_min = 2.0
	parts.initial_velocity_max = 12.0
	parts.scale_amount_min = 1.0
	parts.scale_amount_max = 3.5
	
	var init_ramp := Gradient.new()
	# Color 1: Bright yellowish-orange
	init_ramp.set_color(0, Color(1.0, 0.92, 0.65, 0.95))
	# Color 2: Warning orange
	init_ramp.set_color(1, Color(line_color.r, line_color.g, line_color.b, 0.55))
	parts.color_initial_ramp = init_ramp
	
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	parts.color_ramp = ramp
	
	add_child(parts)
	_particles[side] = parts


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
	for parts in _particles.values():
		var p: CPUParticles2D = parts as CPUParticles2D
		if p != null:
			p.emitting = false
			p.visible = false



func _update_vertical(side: StringName, player: Node2D) -> void:
	var cr: ColorRect = _lines[side] as ColorRect
	if cr == null:
		return
	cr.visible = player != null

	var parts: CPUParticles2D = _particles[side] as CPUParticles2D
	if parts != null:
		if player != null and GameJuice.particles_multiplier > 0.0:
			var target_amount: int = int(40 * GameJuice.particles_multiplier)
			if parts.amount != target_amount:
				parts.amount = target_amount
			parts.visible = true
			parts.emitting = true
		else:
			parts.emitting = false
			parts.visible = false

	if player == null:
		return

	var map_x: float = _bounds.position.x if side == GameSettings.MAP_BORDER_SIDE_LEFT else _bounds.position.x + _bounds.size.x
	cr.size = Vector2(line_thickness, line_length)
	cr.position = Vector2(map_x - line_thickness / 2.0, player.global_position.y - line_length / 2.0)

	if parts != null:
		parts.position = cr.position + cr.size / 2.0
		parts.emission_rect_extents = Vector2(line_thickness * 1.5, line_length / 2.0)
		parts.direction = Vector2.ZERO


func _update_horizontal(side: StringName, player: Node2D, map_y: float) -> void:
	var cr: ColorRect = _lines[side] as ColorRect
	if cr == null:
		return
	cr.visible = player != null

	var parts: CPUParticles2D = _particles[side] as CPUParticles2D
	if parts != null:
		if player != null and GameJuice.particles_multiplier > 0.0:
			var target_amount: int = int(40 * GameJuice.particles_multiplier)
			if parts.amount != target_amount:
				parts.amount = target_amount
			parts.visible = true
			parts.emitting = true
		else:
			parts.emitting = false
			parts.visible = false

	if player == null:
		return

	cr.size = Vector2(line_length, line_thickness)
	cr.position = Vector2(player.global_position.x - line_length / 2.0, map_y - line_thickness / 2.0)

	if parts != null:
		parts.position = cr.position + cr.size / 2.0
		parts.emission_rect_extents = Vector2(line_length / 2.0, line_thickness * 1.5)
		parts.direction = Vector2.ZERO


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
