extends "res://scenes/network/sync_module.gd"

const DEFAULT_HEALTH := 100
const PROJECTILE_DAMAGE := 25

var _health := {
	1: DEFAULT_HEALTH,
	2: DEFAULT_HEALTH,
}


func get_module_name() -> StringName:
	return &"combat"


func get_packet_types() -> Array[StringName]:
	return [&"player_hit", &"health_changed"]


func apply_hit(target_slot: int, source_slot: int, projectile_id: int, damage := PROJECTILE_DAMAGE) -> void:
	if game_sync == null or not game_sync.is_host():
		return

	var current_health := int(_health.get(target_slot, DEFAULT_HEALTH))
	var new_health := maxi(current_health - damage, 0)
	_health[target_slot] = new_health

	game_sync.send_reliable(&"player_hit", {
		"target_slot": target_slot,
		"source_slot": source_slot,
		"projectile_id": projectile_id,
		"damage": damage,
	}, NetworkSession.CHANNEL_EVENTS)
	game_sync.send_reliable(&"health_changed", {
		"slot": target_slot,
		"health": new_health,
	}, NetworkSession.CHANNEL_EVENTS)


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	match str(packet.get("type", "")):
		"health_changed":
			_health[int(payload.get("slot", 0))] = int(payload.get("health", DEFAULT_HEALTH))
		"player_hit":
			pass


func build_snapshot() -> Dictionary:
	return {"health": _health.duplicate()}


func apply_snapshot(data: Dictionary) -> void:
	var health_data: Variant = data.get("health", {})
	if health_data is Dictionary:
		_health = health_data.duplicate()


func get_health(slot: int) -> int:
	return int(_health.get(slot, DEFAULT_HEALTH))


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
