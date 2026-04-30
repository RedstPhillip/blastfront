extends Node2D

@onready var _projectiles: Node2D = $Projectiles


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position
