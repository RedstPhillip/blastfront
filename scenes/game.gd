extends Node2D

@onready var _player_1: Player = $Player1
@onready var _player_2: Player = $Player2
@onready var _projectiles: Node2D = $Projectiles


func _ready() -> void:
	add_to_group("game_world")
	_configure_local_player(_player_1, 1, &"p1_move_left", &"p1_move_right", &"p1_jump", &"p1_shoot")
	_configure_local_player(_player_2, 2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot")


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func _configure_local_player(player: Player, slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName) -> void:
	player.player_slot = slot
	player.move_left_action = move_left
	player.move_right_action = move_right
	player.jump_action = jump
	player.shoot_action = shoot
	player.add_to_group("players")
	player.add_to_group("local_players")
