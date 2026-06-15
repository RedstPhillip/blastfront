extends Node2D
class_name Game

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

@onready var _player_1: Player = $Player1
@onready var _player_2: Player = $Player2
@onready var _projectiles: Node2D = $Projectiles
@onready var _camera: Camera2D = $Camera2D
@onready var _game_sync: GameSync = $GameSync

var _local_player: Player = null
var _offline_score: Dictionary = GameSettings.default_score()
var _offline_match_over: bool = false
var _camera_bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS
var _dummy_players: Array[Player] = []
var _training_dummy_respawning: Dictionary = {}


func _ready() -> void:
	add_to_group(GameSettings.GAME_WORLD_GROUP)

	if NetworkSession.is_steam_match_active():
		OnlineMatch.phase_changed.connect(_on_online_phase_changed)
		OnlineMatch.state_changed.connect(_on_online_state_changed)
		_configure_steam_players()
		_game_sync.setup(self)
	elif NetworkSession.is_training():
		_configure_training_players()
	else:
		_remove_offline_second_player()
		_configure_offline_players()
		_connect_offline_health()

	_set_spawn_positions()
	_apply_camera_bounds()
	_camera.make_current()
	GameJuice.bind_camera(_camera)
	_camera.global_position = Vector2(
		_get_camera_target_x(),
		GameSettings.CAMERA_Y
	)
	_camera.zoom = Vector2.ONE * _get_camera_target_zoom()
	_spawn_initial_feedback()
	if NetworkSession.is_steam_match_active():
		_apply_online_player_colors()
		if OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET:
			_prepare_online_round()
		else:
			_set_player_controls_enabled(false)


func _exit_tree() -> void:
	GameJuice.clear_camera(_camera)
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
	var target_zoom: float = _get_camera_target_zoom()
	_camera.zoom = _camera.zoom.lerp(
		Vector2.ONE * target_zoom,
		clampf(delta * GameSettings.CAMERA_ZOOM_SPEED, 0.0, 1.0)
	)


func get_config() -> Dictionary:
	return GameSettings.game_config()


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


# Offline shots spawn immediately; online shots go through the authoritative sync module.
func request_shot(owner: Node, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
		return

	var owner_slot: int = 0
	if owner != null:
		owner_slot = int(owner.get("player_slot"))
	if NetworkSession.is_steam_match_active() and _game_sync != null:
		_game_sync.request_shot(owner_slot, spawn_position, direction, projectile_data)
		return

	var directions: Array[Vector2] = Projectile.extract_shot_directions(projectile_data, direction)
	for shot_direction in directions:
		var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
		projectile.configure_from_data(0, owner_slot, shot_direction, projectile_data)
		spawn_projectile(projectile, spawn_position)


func request_block_state(owner: Node, active: bool, direction: Vector2, cooldown_ratio: float) -> void:
	if not NetworkSession.is_steam_match_active() or _game_sync == null:
		return
	if not OnlineMatch.is_playing_set():
		return

	var owner_slot: int = 0
	if owner != null:
		owner_slot = int(owner.get("player_slot"))
	if owner_slot == 0:
		return

	_game_sync.request_block_state(owner_slot, active, direction, cooldown_ratio)


func build_authoritative_shot(owner_slot: int) -> Dictionary:
	if NetworkSession.is_steam_match_active() and not OnlineMatch.is_playing_set():
		return {}

	var player: Player = _get_player_by_slot(owner_slot)
	if player == null:
		return {}

	var gun: Variant = player.get_gun()
	if gun == null:
		return {}

	var shot_data: Dictionary = gun.build_shot_data()
	if shot_data.is_empty():
		return {}

	var direction: Vector2 = Vector2.LEFT
	var dir_variant: Variant = shot_data.get("direction", direction)
	if dir_variant is Vector2 and dir_variant.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		direction = dir_variant.normalized()

	return {
		"spawn_position": shot_data.get("spawn_position", player.global_position),
		"direction": direction,
		"directions": shot_data.get("directions", [direction]),
		"fire_interval": shot_data.get("fire_interval", 0.0),
		"projectile": shot_data.get("projectile", {}),
	}


# Every mode reuses the same Player scene and assigns only its control role here.
func _configure_offline_players() -> void:
	_local_player = _player_1
	_configure_local_player(
		_player_1,
		GameSettings.PLAYER_ONE_SLOT,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		GameSettings.INPUT_P1_BLOCK,
		true
	)


func _configure_training_players() -> void:
	_local_player = _player_1
	_configure_local_player(
		_player_1,
		GameSettings.PLAYER_ONE_SLOT,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		GameSettings.INPUT_P1_BLOCK,
		true
	)

	_dummy_players.clear()

	_configure_dummy_player(_player_2, GameSettings.PLAYER_TWO_SLOT)
	_dummy_players.append(_player_2)

	for i in range(GameSettings.TRAINING_DUMMY_COUNT - 1):
		var spawn_x: float = GameSettings.PLAYER_ONE_SPAWN.x + GameSettings.TRAINING_DUMMY_SPAWN_OFFSET_X * float(i + 2)
		var dummy: Player = _spawn_dummy_at(Vector2(spawn_x, GameSettings.TRAINING_DUMMY_SPAWN_Y))
		if dummy != null:
			_dummy_players.append(dummy)

	_connect_training_health()


func _configure_dummy_player(dummy: Player, slot: int) -> void:
	dummy.player_slot = slot
	dummy.configure_remote_control(slot)
	dummy.add_to_group(GameSettings.PLAYERS_GROUP)
	dummy.remove_from_group(GameSettings.LOCAL_PLAYERS_GROUP)
	dummy.set_eliminated(false)
	dummy.health_component.heal(dummy.health_component.max_health)


func _spawn_dummy_at(position: Vector2) -> Player:
	var dummy: Player = PLAYER_SCENE.instantiate() as Player
	if dummy == null:
		return null
	dummy.name = "Dummy%d" % (_dummy_players.size() + 1)
	add_child(dummy)
	dummy.global_position = position
	_configure_dummy_player(dummy, GameSettings.PLAYER_TWO_SLOT + _dummy_players.size())
	return dummy


func _connect_training_health() -> void:
	for dummy in _dummy_players:
		if dummy != null and is_instance_valid(dummy):
			var health: HealthComponent = dummy.health_component
			if health != null and not health.health_depleted.is_connected(_on_training_dummy_health_depleted):
				health.health_depleted.connect(_on_training_dummy_health_depleted.bind(dummy))
	if _player_1 != null and is_instance_valid(_player_1):
		var health: HealthComponent = _player_1.health_component
		if health != null and not health.health_depleted.is_connected(_on_training_player_health_depleted):
			health.health_depleted.connect(_on_training_player_health_depleted)


func _on_training_dummy_health_depleted(dummy: Player) -> void:
	if dummy != null and dummy.health_component != null and dummy.health_component.health > 0:
		return
	var dummy_id: int = dummy.get_instance_id()
	if _training_dummy_respawning.get(dummy_id, false):
		return
	_training_dummy_respawning[dummy_id] = true
	await get_tree().create_timer(GameSettings.PLAYER_RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	_training_dummy_respawning.erase(dummy_id)
	if dummy != null and is_instance_valid(dummy):
		dummy.health_component.heal(dummy.health_component.max_health)
		dummy.set_eliminated(false)
		dummy.velocity = Vector2.ZERO


func _on_training_player_health_depleted() -> void:
	if _player_1 != null and _player_1.health_component != null and _player_1.health_component.health > 0:
		return
	_heal_and_respawn_after_delay()


func _remove_offline_second_player() -> void:
	if _player_2 == null:
		return
	var removed_player: Player = _player_2
	_player_2 = null
	remove_child(removed_player)
	removed_player.queue_free()


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
			GameSettings.INPUT_P1_BLOCK,
			true
		)

	if remote_player != null:
		remote_player.configure_remote_control(remote_slot)
		remote_player.remove_from_group(GameSettings.LOCAL_PLAYERS_GROUP)
	_apply_online_player_colors()


func _configure_local_player(player: Player, slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, block: StringName, allow_shoot: bool) -> void:
	_configure_common_player(player, slot)
	player.configure_local_control(slot, move_left, move_right, jump, shoot, block, allow_shoot)
	player.add_to_group(GameSettings.LOCAL_PLAYERS_GROUP)


func _configure_common_player(player: Player, slot: int) -> void:
	player.player_slot = slot
	player.add_to_group(GameSettings.PLAYERS_GROUP)
	player.remove_from_group(GameSettings.LOCAL_PLAYERS_GROUP)


func get_player_by_slot(slot: int) -> Player:
	return _get_player_by_slot(slot)


func get_local_player() -> Player:
	return _local_player


func get_score_for_slot(slot: int) -> int:
	return int(_offline_score.get(slot, 0))


func is_match_over() -> bool:
	return _offline_match_over


func get_winner_slot() -> int:
	if not _offline_match_over:
		return 0
	if int(_offline_score.get(GameSettings.PLAYER_ONE_SLOT, 0)) >= GameSettings.MATCH_WINS_NEEDED:
		return GameSettings.PLAYER_ONE_SLOT
	if int(_offline_score.get(GameSettings.PLAYER_TWO_SLOT, 0)) >= GameSettings.MATCH_WINS_NEEDED:
		return GameSettings.PLAYER_TWO_SLOT
	return 0


func get_projectiles_root() -> Node2D:
	return _projectiles


func respawn_players() -> void:
	_set_spawn_positions()
	_player_1.reset_research_round_state()
	_player_1.set_eliminated(false)
	_player_1.set_controls_enabled(true)
	_player_1.velocity = Vector2.ZERO
	_spawn_respawn_feedback(_player_1)
	if NetworkSession.is_training():
		for dummy in _dummy_players:
			if dummy != null and is_instance_valid(dummy):
				dummy.reset_research_round_state()
				dummy.set_eliminated(false)
				dummy.velocity = Vector2.ZERO
	elif _has_player_two():
		_player_2.reset_research_round_state()
		_player_2.set_eliminated(false)
		_player_2.set_controls_enabled(true)
		_player_2.velocity = Vector2.ZERO
		_spawn_respawn_feedback(_player_2)


func _set_spawn_positions() -> void:
	_player_1.global_position = _get_spawn_position(GameSettings.PLAYER_ONE_SPAWN_MARKER, GameSettings.PLAYER_ONE_SPAWN)
	_player_1.last_dir = GameSettings.PLAYER_ONE_START_FACING
	if NetworkSession.is_training():
		for i in range(_dummy_players.size()):
			var dummy: Player = _dummy_players[i]
			if dummy == null or not is_instance_valid(dummy):
				continue
			dummy.global_position = Vector2(
				GameSettings.PLAYER_ONE_SPAWN.x + GameSettings.TRAINING_DUMMY_SPAWN_OFFSET_X * float(i + 1),
				GameSettings.TRAINING_DUMMY_SPAWN_Y
			)
			dummy.last_dir = GameSettings.PLAYER_TWO_START_FACING
	elif _has_player_two():
		_player_2.global_position = _get_spawn_position(GameSettings.PLAYER_TWO_SPAWN_MARKER, GameSettings.PLAYER_TWO_SPAWN)
		_player_2.last_dir = GameSettings.PLAYER_TWO_START_FACING


func _get_spawn_position(marker_name: StringName, fallback_position: Vector2) -> Vector2:
	var marker: Node = find_child(str(marker_name), true, false)
	if marker is Node2D:
		return (marker as Node2D).global_position
	return fallback_position


func _apply_camera_bounds() -> void:
	var bounds_node: Node = get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
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


# Online framing follows the local player; local matches keep both competitors visible.
func _get_camera_target_x() -> float:
	if NetworkSession.is_steam_match_active() and _local_player != null:
		return (_local_player.global_position.x + _get_map_center_x()) * GameSettings.HALF

	if NetworkSession.is_training():
		return _local_player.global_position.x

	if not _has_player_two():
		return _player_1.global_position.x

	return (_player_1.global_position.x + _player_2.global_position.x) * GameSettings.HALF


func _get_camera_target_zoom() -> float:
	if NetworkSession.is_steam_match_active():
		return maxf(GameSettings.CAMERA_ONLINE_ZOOM, _get_vertical_safe_zoom())

	if NetworkSession.is_training():
		return GameSettings.CAMERA_ONLINE_ZOOM

	if not _has_player_two():
		return GameSettings.CAMERA_MAX_ZOOM

	var player_distance: float = absf(_player_1.global_position.x - _player_2.global_position.x)
	var desired_world_width: float = maxf(
		player_distance + GameSettings.CAMERA_DUEL_PADDING_X,
		get_viewport_rect().size.x
	)
	var target_zoom: float = get_viewport_rect().size.x / desired_world_width
	return clampf(target_zoom, GameSettings.CAMERA_MIN_ZOOM, GameSettings.CAMERA_MAX_ZOOM)


func _get_vertical_safe_zoom() -> float:
	if _camera_bounds.size.y <= 0.0:
		return GameSettings.CAMERA_MAX_ZOOM
	return get_viewport_rect().size.y / _camera_bounds.size.y


func _get_map_center_x() -> float:
	return _camera_bounds.position.x + _camera_bounds.size.x * GameSettings.HALF


func _connect_offline_health() -> void:
	_player_1.health_component.health_depleted.connect(_on_offline_health_depleted.bind(1))
	if _has_player_two():
		_player_2.health_component.health_depleted.connect(_on_offline_health_depleted.bind(2))


# Offline rounds resolve locally; OnlineMatch owns scoring for network games.
func _on_offline_health_depleted(slot: int) -> void:
	if _offline_match_over:
		return
	var depleted_player: Player = _get_player_by_slot(slot)
	if depleted_player != null and depleted_player.health_component != null:
		if depleted_player.health_component.health > 0:
			return

	if not _has_player_two():
		_heal_and_respawn_after_delay()
		return

	var source_slot: int = GameSettings.PLAYER_TWO_SLOT if slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT
	_offline_score[source_slot] = _offline_score.get(source_slot, 0) + 1

	if _offline_score[source_slot] >= GameSettings.MATCH_WINS_NEEDED:
		_offline_match_over = true
		_clear_projectiles()
		_set_player_controls_enabled(false)
		return

	_heal_and_respawn_after_delay()


func _heal_and_respawn() -> void:
	_player_1.health_component.heal(_player_1.health_component.max_health)
	if NetworkSession.is_training():
		for dummy in _dummy_players:
			if dummy != null and is_instance_valid(dummy):
				dummy.health_component.heal(dummy.health_component.max_health)
	elif _has_player_two():
		_player_2.health_component.heal(_player_2.health_component.max_health)
	respawn_players()


func _heal_and_respawn_after_delay() -> void:
	await get_tree().create_timer(GameSettings.PLAYER_RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	_heal_and_respawn()


func _get_player_by_slot(slot: int) -> Player:
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return _player_1
	if slot == GameSettings.PLAYER_TWO_SLOT and _has_player_two():
		return _player_2
	for dummy in _dummy_players:
		if dummy != null and is_instance_valid(dummy) and dummy.player_slot == slot:
			return dummy
	return null


func _on_online_phase_changed(next_phase: StringName) -> void:
	if next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_prepare_online_round()
	elif next_phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_set_player_controls_enabled(false)
	elif next_phase == GameSettings.MATCH_PHASE_FINAL:
		_clear_projectiles()
		_set_player_controls_enabled(false)


func _on_online_state_changed() -> void:
	_apply_online_player_colors()


# Synchronized phase changes drive every online round reset.
func _prepare_online_round() -> void:
	_clear_projectiles()
	_heal_players()
	respawn_players()
	_set_player_controls_enabled(true)
	_apply_online_player_colors()


func _set_player_controls_enabled(enabled: bool) -> void:
	_player_1.set_controls_enabled(enabled)
	if _has_player_two():
		_player_2.set_controls_enabled(enabled)


func _heal_players() -> void:
	_player_1.health_component.heal(_player_1.health_component.max_health)
	if _has_player_two():
		_player_2.health_component.heal(_player_2.health_component.max_health)


func _clear_projectiles() -> void:
	for child in _projectiles.get_children():
		child.queue_free()


func _apply_online_player_colors() -> void:
	_player_1.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_ONE_SLOT))
	if _has_player_two():
		_player_2.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_TWO_SLOT))


func _spawn_respawn_feedback(player: Player) -> void:
	if player == null:
		return
	var tint: Color = player.get_visual_tint()
	var spawn_position: Vector2 = player.global_position + Vector2(0.0, player.hover_dist - 4.0)
	GameJuice.spawn_burst(&"spawn", spawn_position, Vector2.UP, tint)
	GameJuice.play_sound_2d(&"spawn", player.global_position, 3.0, 0.05)
	GameJuice.shake(GameSettings.PLAYER_SPAWN_SHAKE_STRENGTH, GameSettings.PLAYER_SPAWN_SHAKE_TIME)


func _spawn_initial_feedback() -> void:
	if NetworkSession.is_training():
		_spawn_respawn_feedback(_player_1)
		return
	_spawn_respawn_feedback(_player_1)
	if _has_player_two():
		_spawn_respawn_feedback(_player_2)


func _has_player_two() -> bool:
	return _player_2 != null and is_instance_valid(_player_2)
