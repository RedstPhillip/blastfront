class_name HoverBehavior
extends ExtensionBehavior


func update(projectile: Projectile, delta: float, _effect_data: Dictionary = {}) -> void:
	if projectile == null:
		return
	projectile.velocity.y -= projectile.gravity * delta * 0.85
