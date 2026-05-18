extends Node2D

const GAME_SYNC_SCRIPT := preload("res://scenes/network/game_sync.gd")
const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

@onready var _player_1: Player = $Player1
@onready var _player_2: Player = $Player2
@onready var _projectiles: Node2D = $Projectiles
@onready var _camera: Camera2D = $Camera2D
@onready var _score_label: Label = $HUD/ScoreLabel

var _local_player: Player = null
var _game_sync: GameSync = null
var _offline_score: Dictionary = GameSettings.default_score()
var _offline_match_over: bool = false
var _camera_bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS


func _ready() -> void:
	add_to_group(GameSettings.GAME_WORLD_GROUP)

	if NetworkSession.is_steam_match_active():
		OnlineMatch.phase_changed.connect(_on_online_phase_changed)
		OnlineMatch.state_changed.connect(_on_online_state_changed)
		_configure_steam_players()
		_create_game_sync()
	else:
		_configure_offline_players()
		_connect_offline_health()

	_set_spawn_positions()
	_apply_camera_bounds()
	_camera.make_current()
	_camera.global_position = Vector2(
		_get_camera_target_x(),
		GameSettings.CAMERA_Y
	)
	if NetworkSession.is_steam_match_active():
		_apply_online_player_colors()
		if OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET:
			_prepare_online_round()
		else:
			_set_player_controls_enabled(false)


func _exit_tree() -> void:
	if OnlineMatch.phase_changed.is_connected(_on_online_phase_changed):
		OnlineMatch.phase_changed.disconnect(_on_online_phase_changed)
	if OnlineMatch.state_changed.is_connected(_on_online_state_changed):
		OnlineMatch.state_changed.disconnect(_on_online_state_changed)


func _process(delta: float) -> void:
	var target_x: float = _get_camera_target_x()
	_camera.global_position.x = lerp(
		_camera.global_position.x,
		target_x,
		delta * GameSettings.CAMERA_FOLLOW_SPEED
	)
	_update_score_display()


func get_config() -> Dictionary:
	return GameSettings.game_config()


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func request_shot(owner: Node, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
		return

	var owner_slot: int = 0
	if owner != null:
		owner_slot = int(owner.get("player_slot"))
	if NetworkSession.is_steam_match_active() and _game_sync != null:
		_game_sync.request_shot(owner_slot, spawn_position, direction, projectile_data)
		return

	var projectile: Node2D = PROJECTILE_SCENE.instantiate() as Node2D
	var muzzle_speed: float = float(projectile_data.get("muzzle_speed", projectile.get("muzzle_speed")))
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", muzzle_speed)
	projectile.set("gravity", float(projectile_data.get("gravity", projectile.get("gravity"))))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile.get("linear_damping"))))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile.get("max_distance"))))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * muzzle_speed))
	spawn_projectile(projectile, spawn_position)


func build_authoritative_shot(owner_slot: int) -> Dictionary:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
		return {}

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
	if dir_variant is Vector2 and dir_variant.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		direction = dir_variant.normalized()

	return {
		"spawn_position": shot_data.get("spawn_position", player.global_position),
		"direction": direction,
		"fire_interval": shot_data.get("fire_interval", 0.0),
		"projectile": shot_data.get("projectile", {}),
	}


func _configure_offline_players() -> void:
	_local_player = null
	_configure_local_player(
		_player_1,
		GameSettings.PLAYER_ONE_SLOT,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		true
	)
	_configure_local_player(
		_player_2,
		GameSettings.PLAYER_TWO_SLOT,
		GameSettings.INPUT_P2_MOVE_LEFT,
		GameSettings.INPUT_P2_MOVE_RIGHT,
		GameSettings.INPUT_P2_JUMP,
		GameSettings.INPUT_P2_SHOOT,
		true
	)


func _configure_steam_players() -> void:
	_configure_common_player(_player_1, 1)
	_configure_common_player(_player_2, 2)

	var local_slot: int = NetworkSession.local_player_slot
	var remote_slot: int = GameSettings.PLAYER_TWO_SLOT if local_slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT

	_local_player = _get_player_by_slot(local_slot)
	var remote_player: Player = _get_player_by_slot(remote_slot)

	if _local_player != null:
		_configure_local_player(
			_local_player,
			local_slot,
			GameSettings.INPUT_P1_MOVE_LEFT,
			GameSettings.INPUT_P1_MOVE_RIGHT,
			GameSettings.INPUT_P1_JUMP,
			GameSettings.INPUT_P1_SHOOT,
			true
		)

	if remote_player != null:
		remote_player.configure_remote_control(remote_slot)
		remote_player.remove_from_group(GameSettings.LOCAL_PLAYERS_GROUP)
	_apply_online_player_colors()


func _configure_local_player(player: Player, slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, allow_shoot: bool) -> void:
	_configure_common_player(player, slot)
	player.configure_local_control(slot, move_left, move_right, jump, shoot, allow_shoot)
	player.add_to_group(GameSettings.LOCAL_PLAYERS_GROUP)


func _configure_common_player(player: Player, slot: int) -> void:
	player.player_slot = slot
	player.add_to_group(GameSettings.PLAYERS_GROUP)
	player.remove_from_group(GameSettings.LOCAL_PLAYERS_GROUP)


func _create_game_sync() -> void:
	_game_sync = GAME_SYNC_SCRIPT.new() as GameSync
	_game_sync.name = "GameSync"
	add_child(_game_sync)
	_game_sync.setup(self)


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


func _set_spawn_positions() -> void:
	_player_1.global_position = _get_spawn_position(GameSettings.PLAYER_ONE_SPAWN_MARKER, GameSettings.PLAYER_ONE_SPAWN)
	_player_1.last_dir = GameSettings.PLAYER_ONE_START_FACING
	_player_2.global_position = _get_spawn_position(GameSettings.PLAYER_TWO_SPAWN_MARKER, GameSettings.PLAYER_TWO_SPAWN)
	_player_2.last_dir = GameSettings.PLAYER_TWO_START_FACING


func _get_spawn_position(marker_name: StringName, fallback_position: Vector2) -> Vector2:
	var marker: Node = find_child(str(marker_name), true, false)
	if marker is Node2D:
		return (marker as Node2D).global_position
	return fallback_position


func _apply_camera_bounds() -> void:
	var bounds_node := get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	var bounds: Rect2 = _camera_bounds
	if bounds_node != null:
		var b: Variant = bounds_node.get("bounds")
		if b is Rect2:
			bounds = b

	_camera_bounds = bounds
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_right = int(bounds.position.x + bounds.size.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_bottom = int(bounds.position.y + bounds.size.y)


func _get_camera_target_x() -> float:
	if NetworkSession.is_steam_match_active() and _local_player != null:
		return (_local_player.global_position.x + _get_map_center_x()) * GameSettings.HALF

	return (_player_1.global_position.x + _player_2.global_position.x) * GameSettings.HALF


func _get_map_center_x() -> float:
	return _camera_bounds.position.x + _camera_bounds.size.x * GameSettings.HALF


func _connect_offline_health() -> void:
	_player_1.health_component.health_depleted.connect(_on_offline_health_depleted.bind(1))
	_player_2.health_component.health_depleted.connect(_on_offline_health_depleted.bind(2))


func _on_offline_health_depleted(slot: int) -> void:
	if _offline_match_over:
		return

	var source_slot := GameSettings.PLAYER_TWO_SLOT if slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT
	_offline_score[source_slot] = _offline_score.get(source_slot, 0) + 1

	if _offline_score[source_slot] >= GameSettings.MATCH_WINS_NEEDED:
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
		_score_label.hide()
	elif not NetworkSession.is_steam_match_active():
		_score_label.text = "%d - %d" % [
			_offline_score.get(GameSettings.PLAYER_ONE_SLOT, 0),
			_offline_score.get(GameSettings.PLAYER_TWO_SLOT, 0),
		]
		_score_label.show()


func _get_player_by_slot(slot: int) -> Player:
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return _player_1
	if slot == GameSettings.PLAYER_TWO_SLOT:
		return _player_2
	return null


func _on_online_phase_changed(next_phase: StringName) -> void:
	if next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_prepare_online_round()
	elif next_phase == GameSettings.MATCH_PHASE_KILL_BANNER or next_phase == GameSettings.MATCH_PHASE_FINAL:
		_set_player_controls_enabled(false)


func _on_online_state_changed() -> void:
	_apply_online_player_colors()


func _prepare_online_round() -> void:
	_clear_projectiles()
	_heal_players()
	respawn_players()
	_set_player_controls_enabled(true)
	_apply_online_player_colors()


func _set_player_controls_enabled(enabled: bool) -> void:
	_player_1.set_controls_enabled(enabled)
	_player_2.set_controls_enabled(enabled)


func _heal_players() -> void:
	_player_1.health_component.heal(_player_1.health_component.max_health)
	_player_2.health_component.heal(_player_2.health_component.max_health)


func _clear_projectiles() -> void:
	for child in _projectiles.get_children():
		child.queue_free()


func _apply_online_player_colors() -> void:
	_player_1.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_ONE_SLOT))
	_player_2.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_TWO_SLOT))
