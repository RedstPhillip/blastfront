extends Node2D

@export var warn_distance: float = 50.0
@export var line_length: float = 60.0
@export var line_thickness: float = 5.0
@export var line_color: Color = Color(1, 0, 0, 0.85)

var _lines: Dictionary = {}

func _ready() -> void:
	for side in ["left", "right", "top", "bottom"]:
		var cr := ColorRect.new()
		cr.color = line_color
		cr.visible = false
		cr.z_index = 100
		add_child(cr)
		_lines[side] = cr

func _process(_delta: float) -> void:
	var players: Array[Node2D] = _get_tracked_players()
	if players.is_empty():
		_hide_all_lines()
		return

	var vp   := get_viewport_rect()
	var left   := vp.position.x
	var right  := vp.position.x + vp.size.x
	var top    := vp.position.y
	var bottom := vp.position.y + vp.size.y

	_update_vertical("left", _find_left_player(players, left), left)
	_update_vertical("right", _find_right_player(players, right), right)
	_update_horizontal("top", _find_top_player(players, top), top)
	_update_horizontal("bottom", _find_bottom_player(players, bottom), bottom)


func _get_tracked_players() -> Array[Node2D]:
	var players: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node2D:
			players.append(node)
	return players


func _hide_all_lines() -> void:
	for line in _lines.values():
		line.visible = false


func _find_left_player(players: Array[Node2D], left: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := player.global_position.x - left
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_right_player(players: Array[Node2D], right: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := right - player.global_position.x
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_top_player(players: Array[Node2D], top: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := player.global_position.y - top
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _find_bottom_player(players: Array[Node2D], bottom: float):
	var best_player = null
	var best_distance := INF
	for player in players:
		var distance := bottom - player.global_position.y
		if distance >= 0.0 and distance < warn_distance and distance < best_distance:
			best_distance = distance
			best_player = player
	return best_player


func _update_vertical(side: String, player, x: float) -> void:
	var cr: ColorRect = _lines[side]
	cr.visible = player != null
	if player == null:
		return

	cr.size = Vector2(line_thickness, line_length)
	cr.position = Vector2(x - line_thickness / 2.0, player.global_position.y - line_length / 2.0)


func _update_horizontal(side: String, player, y: float) -> void:
	var cr: ColorRect = _lines[side]
	cr.visible = player != null
	if player == null:
		return

	cr.size = Vector2(line_length, line_thickness)
	cr.position = Vector2(player.global_position.x - line_length / 2.0, y - line_thickness / 2.0)
