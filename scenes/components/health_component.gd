class_name HealthComponent
extends Node

signal max_health_changed(old: int, new: int)
signal health_changed(old: int, new: int)
signal health_depleted

@export var max_health: int = GameSettings.DEFAULT_MAX_HEALTH:
	set(value):
		var new_value: int = maxi(value, GameSettings.MIN_MAX_HEALTH)
		if new_value == max_health:
			return
		var old_value: int = max_health
		max_health = new_value
		if health > max_health:
			health = max_health
		max_health_changed.emit(old_value, max_health)
	get:
		return max_health

var health: int = max_health:
	set(value):
		var new_value: int = clampi(value, 0, max_health)
		if new_value == health:
			return
		var old_value: int = health
		health = new_value
		health_changed.emit(old_value, health)
		if old_value > 0 and health == 0:
			health_depleted.emit()
	get:
		return health


func damage(amount: int) -> void:
	if amount > 0:
		health -= amount


func heal(amount: int) -> void:
	if amount > 0:
		health += amount
