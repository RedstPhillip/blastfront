class_name StatusEffectManager
extends Node

signal effect_added(effect_name: StringName)
signal effect_removed(effect_name: StringName)

var _active_effects: Dictionary = {}


func apply_effect(name: StringName, params: Dictionary) -> void:
	var adjusted_params: Dictionary = params
	var parent: Node = get_parent()
	if parent != null and parent.has_method("adjust_status_effect_data"):
		var adjusted_variant: Variant = parent.call("adjust_status_effect_data", name, params)
		if adjusted_variant is Dictionary:
			adjusted_params = adjusted_variant

	var duration: float = float(adjusted_params.get("duration", 0.0))
	if duration <= 0.0:
		return

	var instance: Dictionary = {
		"time_remaining": duration,
		"duration": duration,
		"tick_interval": float(adjusted_params.get("tick_interval", 0.0)),
		"tick_timer": 0.0,
		"damage_per_tick": int(adjusted_params.get("damage_per_tick", 0)),
		"ticks_remaining": int(adjusted_params.get("tick_count", -1)),
		"stun_duration": float(adjusted_params.get("stun_duration", 0.0)),
		"speed_multiplier": float(adjusted_params.get("speed_multiplier", 1.0)),
		"tint_color": adjusted_params.get("tint_color", null),
		"source_slot": int(adjusted_params.get("source_slot", 0)),
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


func get_slow_multiplier() -> float:
	var result: float = 1.0
	for instances in _active_effects.values():
		for instance in (instances as Array):
			var mult: float = (instance as Dictionary).get("speed_multiplier", 1.0) as float
			if mult < result:
				result = mult
	return result


# Multiple instances of one effect stack and expire on independent timers.
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
				var ticks_remaining: int = int(instance.get("ticks_remaining", -1))
				if instance.tick_timer <= 0.0 and ticks_remaining != 0:
					instance.tick_timer = tick_interval
					_tick_instance(instance)
					if ticks_remaining > 0:
						instance.ticks_remaining = ticks_remaining - 1

			if instance.time_remaining <= 0.0:
				instances.remove_at(i)
			i -= 1

		if instances.is_empty():
			expired.append(effect_name)

	for effect_name in expired:
		_active_effects.erase(effect_name)
		effect_removed.emit(effect_name)


# Tick effects delegate health and stun behavior to the owning Player components.
func _tick_instance(instance: Dictionary) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	var damage: int = instance.get("damage_per_tick", 0) as int
	if damage > 0:
		var health: Node = parent.get_node_or_null("HealthComponent")
		if parent.has_method("apply_incoming_damage"):
			var armor_source_slot: int = int(instance.get("source_slot", 0))
			var modified_damage: int = ResearchManager.apply_rage_to_damage(armor_source_slot, damage)
			var applied_damage: int = int(parent.call("apply_incoming_damage", modified_damage, armor_source_slot, parent.get("global_position"), false))
			if armor_source_slot > 0 and applied_damage > 0:
				ResearchManager.apply_local_life_steal(armor_source_slot, applied_damage)
				_notify_damage_dealt(armor_source_slot, applied_damage)
		elif health != null and health.has_method("damage"):
			var source_slot: int = int(instance.get("source_slot", 0))
			damage = ResearchManager.apply_rage_to_damage(source_slot, damage)
			var old_health: int = int(health.get("health"))
			health.damage(damage)
			var target_player: Player = parent as Player
			if source_slot > 0 and (target_player == null or target_player.player_slot != source_slot):
				ResearchManager.apply_local_life_steal(source_slot, mini(damage, old_health))

	var stun: float = instance.get("stun_duration", 0.0) as float
	if stun > 0.0 and parent.has_method("apply_stun"):
		parent.apply_stun(stun)


func _notify_damage_dealt(source_slot: int, applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player != null and player.player_slot == source_slot:
			player.note_damage_dealt(applied_damage)
			return
