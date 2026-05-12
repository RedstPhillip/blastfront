extends Node2D

const GAME_SYNC_SCRIPT := preload("res://scenes/network/game_sync.gd")
const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

@onready var _player_1: Player = $Player1
@onready var _player_2: Player = $Player2
@onready var _projectiles: Node2D = $Projectiles
@onready var _camera: Camera2D = $Camera2D
@onready var _score_label: Label = $HUD/ScoreLabel

var _local_player: Player = null
var _game_sync = null
var _offline_score := {1: 0, 2: 0}
var _offline_match_over := false


func _ready() -> void:
	add_to_group("game_world")

	if NetworkSession.is_steam_match_active():
		_configure_steam_players()
		_create_game_sync()
	else:
		_configure_offline_players()
		_connect_offline_health()

	_set_spawn_positions()
	_camera.make_current()
	_camera.global_position = Vector2(
		(_player_1.global_position.x + _player_2.global_position.x) * 0.5,
		get_config().camera_y
	)
	_apply_camera_bounds()


func _process(delta: float) -> void:
	var target_x := (_player_1.global_position.x + _player_2.global_position.x) * 0.5
	_camera.global_position.x = lerp(_camera.global_position.x, target_x, delta * get_config().camera_follow_speed)
	_update_score_display()


func get_config() -> Dictionary:
	return {
		"spawn_left": Vector2(200, 116),
		"spawn_right": Vector2(1100, 116),
		"wins_needed": 2,
		"camera_follow_speed": 5.0,
		"camera_y": 360.0,
		"snapshot_rate": 10.0,
	}


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func request_shot(owner: Node, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var owner_slot: int = 0
	if owner != null:
		owner_slot = int(owner.get("player_slot"))
	if NetworkSession.is_steam_match_active() and _game_sync != null and _game_sync.has_method("request_shot"):
		_game_sync.call("request_shot", owner_slot, spawn_position, direction, projectile_data)
		return

	var projectile := PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", float(projectile_data.get("muzzle_speed", projectile.get("muzzle_speed"))))
	projectile.set("gravity", float(projectile_data.get("gravity", projectile.get("gravity"))))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile.get("linear_damping"))))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile.get("max_distance"))))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * float(projectile_data.get("muzzle_speed", 1200))))
	spawn_projectile(projectile, spawn_position)


func build_authoritative_shot(owner_slot: int) -> Dictionary:
	var player: Player = _get_player_by_slot(owner_slot)
	if player == null:
		return {}

	var gun: Node = player.get_node_or_null("Gun")
	if gun == null or not gun.has_method("build_shot_data"):
		return {}

	var shot_data: Dictionary = gun.call("build_shot_data")
	if shot_data.is_empty():
		return {}

	var direction: Vector2 = Vector2.LEFT
	var dir_variant: Variant = shot_data.get("direction", direction)
	if dir_variant is Vector2 and dir_variant.length_squared() > 0.0001:
		direction = dir_variant.normalized()

	return {
		"spawn_position": shot_data.get("spawn_position", player.global_position),
		"direction": direction,
		"fire_interval": shot_data.get("fire_interval", 0.0),
		"projectile": shot_data.get("projectile", {}),
	}


func _configure_offline_players() -> void:
	_local_player = null
	_configure_local_player(_player_1, 1, &"p1_move_left", &"p1_move_right", &"p1_jump", &"p1_shoot", true)
	_configure_local_player(_player_2, 2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", true)


func _configure_steam_players() -> void:
	_configure_common_player(_player_1, 1)
	_configure_common_player(_player_2, 2)

	var local_slot: int = NetworkSession.local_player_slot
	var remote_slot: int = 2 if local_slot == 1 else 1

	_local_player = _get_player_by_slot(local_slot)
	var remote_player: Player = _get_player_by_slot(remote_slot)

	if _local_player != null:
		_configure_local_player(_local_player, local_slot, &"p1_move_left", &"p1_move_right", &"p1_jump", &"p1_shoot", true)

	if remote_player != null:
		remote_player.configure_remote_control(remote_slot)
		remote_player.remove_from_group("local_players")


func _configure_local_player(player: Player, slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, allow_shoot: bool) -> void:
	_configure_common_player(player, slot)
	player.configure_local_control(slot, move_left, move_right, jump, shoot, allow_shoot)
	player.add_to_group("local_players")


func _configure_common_player(player: Player, slot: int) -> void:
	player.player_slot = slot
	player.add_to_group("players")
	player.remove_from_group("local_players")


func _create_game_sync() -> void:
	_game_sync = GAME_SYNC_SCRIPT.new()
	_game_sync.name = "GameSync"
	add_child(_game_sync)
	_game_sync.call("setup", self)


func get_player_by_slot(slot: int) -> Player:
	return _get_player_by_slot(slot)


func get_local_player() -> Player:
	return _local_player


func get_projectiles_root() -> Node2D:
	return _projectiles


func respawn_players() -> void:
	_set_spawn_positions()
	_player_1.velocity = Vector2.ZERO
	_player_2.velocity = Vector2.ZERO


func on_match_over(winner_slot: int) -> void:
	_score_label.text = "Player %d wins!" % winner_slot
	_score_label.show()


func _set_spawn_positions() -> void:
	var config := get_config()
	_player_1.global_position = config.spawn_left
	_player_1.last_dir = 1.0
	_player_2.global_position = config.spawn_right
	_player_2.last_dir = -1.0


func _apply_camera_bounds() -> void:
	var bounds_node := get_tree().get_first_node_in_group("map_bounds")
	var bounds := Rect2(0, 0, 2262, 720)
	if bounds_node != null:
		var b: Variant = bounds_node.get("bounds")
		if b is Rect2:
			bounds = b

	_camera.limit_left = int(bounds.position.x)
	_camera.limit_right = int(bounds.position.x + bounds.size.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_bottom = int(bounds.position.y + bounds.size.y)


func _connect_offline_health() -> void:
	_player_1.health_component.health_depleted.connect(_on_offline_health_depleted.bind(1))
	_player_2.health_component.health_depleted.connect(_on_offline_health_depleted.bind(2))


func _on_offline_health_depleted(slot: int) -> void:
	if _offline_match_over:
		return

	var config := get_config()
	var source_slot := 2 if slot == 1 else 1
	_offline_score[source_slot] = _offline_score.get(source_slot, 0) + 1

	if _offline_score[source_slot] >= config.wins_needed:
		_offline_match_over = true
		_score_label.text = "Player %d wins!" % source_slot
		return

	_heal_and_respawn()


func _heal_and_respawn() -> void:
	respawn_players()
	_player_1.health_component.heal(_player_1.health_component.max_health)
	_player_2.health_component.heal(_player_2.health_component.max_health)


func _update_score_display() -> void:
	if _score_label == null:
		return

	if NetworkSession.is_steam_match_active() and _game_sync != null:
		var round_sync = _game_sync.get_module(&"round")
		if round_sync != null and round_sync.has_method("get_scores"):
			var scores = round_sync.get_scores()
			_score_label.text = "%d - %d" % [scores.get(1, 0), scores.get(2, 0)]
		_score_label.show()
	elif not NetworkSession.is_steam_match_active():
		_score_label.text = "%d - %d" % [_offline_score.get(1, 0), _offline_score.get(2, 0)]
		_score_label.show()


func _get_player_by_slot(slot: int) -> Player:
	if slot == 1:
		return _player_1
	if slot == 2:
		return _player_2
	return null