extends "res://scenes/network/sync_module.gd"

var _block_active := {
	1: false,
	2: false,
}


func get_module_name() -> StringName:
	return &"block"


func get_packet_types() -> Array[StringName]:
	return [&"block_started", &"block_ended", &"block_state"]


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	var slot := int(payload.get("slot", packet.get("from_slot", 0)))

	match str(packet.get("type", "")):
		"block_started":
			_block_active[slot] = true
		"block_ended":
			_block_active[slot] = false
		"block_state":
			_block_active[slot] = bool(payload.get("active", false))


func build_snapshot() -> Dictionary:
	return {"block_active": _block_active.duplicate()}


func apply_snapshot(data: Dictionary) -> void:
	var block_data: Variant = data.get("block_active", {})
	if block_data is Dictionary:
		_block_active = block_data.duplicate()


func is_block_active(slot: int) -> bool:
	return bool(_block_active.get(slot, false))


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
