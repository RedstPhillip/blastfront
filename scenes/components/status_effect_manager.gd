class_name StatusEffectManager
extends Node

signal effect_added(effect_name: StringName)
signal effect_removed(effect_name: StringName)

var _active_effects: Dictionary = {}


func apply_effect(name: StringName, params: Dictionary) -> void:
	var duration: float = float(params.get("duration", 0.0))
	if duration <= 0.0:
		return

	var instance: Dictionary = {
		"time_remaining": duration,
		"duration": duration,
		"tick_interval": float(params.get("tick_interval", 0.0)),
		"tick_timer": 0.0,
		"damage_per_tick": int(params.get("damage_per_tick", 0)),
		"tint_color": params.get("tint_color", null),
	}

	if not _active_effects.has(name):
		_active_effects[name] = []
	_active_effects[name].append(instance)
	effect_added.emit(name)


func remove_effects(name: StringName) -> void:
	if not _active_effects.has(name):
		return
	_active_effects.erase(name)
	effect_removed.emit(name)


func has_effect(name: StringName) -> bool:
	return _active_effects.has(name) and not _active_effects[name].is_empty()


func get_active_effect_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for key in _active_effects.keys():
		names.append(key as StringName)
	return names


func get_active_count() -> int:
	var total: int = 0
	for instances in _active_effects.values():
		total += (instances as Array).size()
	return total


func clear_all() -> void:
	if _active_effects.is_empty():
		return
	_active_effects.clear()
	effect_removed.emit(&"")


func get_tint_color() -> Color:
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var count: int = 0

	for instances in _active_effects.values():
		for instance in (instances as Array):
			var tint: Variant = (instance as Dictionary).get("tint_color", null)
			if tint is Color:
				r += (tint as Color).r
				g += (tint as Color).g
				b += (tint as Color).b
				count += 1

	if count == 0:
		return Color.WHITE
	return Color(r / count, g / count, b / count)


func _process(delta: float) -> void:
	var expired: Array[StringName] = []

	for effect_name in _active_effects.keys():
		var instances: Array = _active_effects[effect_name]
		var i: int = instances.size() - 1
		while i >= 0:
			var instance: Dictionary = instances[i] as Dictionary
			instance.time_remaining = (instance.time_remaining as float) - delta

			var tick_interval: float = instance.get("tick_interval", 0.0) as float
			if tick_interval > 0.0:
				instance.tick_timer = (instance.tick_timer as float) - delta
				if instance.tick_timer <= 0.0:
					instance.tick_timer = tick_interval
					_tick_instance(instance)

			if instance.time_remaining <= 0.0:
				instances.remove_at(i)
			i -= 1

		if instances.is_empty():
			expired.append(effect_name)

	for effect_name in expired:
		_active_effects.erase(effect_name)
		effect_removed.emit(effect_name)


func _tick_instance(instance: Dictionary) -> void:
	var damage: int = instance.get("damage_per_tick", 0) as int
	if damage <= 0:
		return

	var parent: Node = get_parent()
	if parent == null:
		return
	var health: Node = parent.get_node_or_null("HealthComponent")
	if health != null and health.has_method("damage"):
		health.damage(damage)
