extends Node2D

@onready var _player_1: Player = $Player1
@onready var _player_2: Player = $Player2
@onready var _projectiles: Node2D = $Projectiles

@export var network_send_rate := 20.0

var _local_player: Player = null
var _network_send_timer := 0.0


func _ready() -> void:
	add_to_group("game_world")

	if NetworkSession.is_steam_match_active():
		NetworkSession.register_game(self)
		_configure_steam_players()
	else:
		_configure_offline_players()


func _exit_tree() -> void:
	NetworkSession.unregister_game(self)


func _physics_process(delta: float) -> void:
	if not NetworkSession.is_steam_match_active() or _local_player == null:
		return

	_network_send_timer -= delta
	if _network_send_timer > 0.0:
		return

	_network_send_timer = 1.0 / network_send_rate
	NetworkSession.send_player_state(
		_local_player.player_slot,
		_local_player.global_position,
		_local_player.velocity,
		_local_player.get_aim_world_position()
	)


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func apply_remote_player_snapshot(slot: int, snapshot: Dictionary) -> void:
	var player := _get_player_by_slot(slot)
	if player == null:
		return

	player.apply_remote_snapshot(snapshot)


func _configure_offline_players() -> void:
	_local_player = null
	_configure_local_player(_player_1, 1, &"p1_move_left", &"p1_move_right", &"p1_jump", &"p1_shoot", true)
	_configure_local_player(_player_2, 2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", true)


func _configure_steam_players() -> void:
	_configure_common_player(_player_1, 1)
	_configure_common_player(_player_2, 2)

	var local_slot := NetworkSession.local_player_slot
	var remote_slot := 2 if local_slot == 1 else 1

	_local_player = _get_player_by_slot(local_slot)
	var remote_player := _get_player_by_slot(remote_slot)

	if _local_player != null:
		_configure_local_player(_local_player, local_slot, &"p1_move_left", &"p1_move_right", &"p1_jump", &"p1_shoot", false)

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


func _get_player_by_slot(slot: int) -> Player:
	if slot == 1:
		return _player_1
	if slot == 2:
		return _player_2
	return null
