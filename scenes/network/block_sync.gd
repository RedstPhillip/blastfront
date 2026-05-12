extends "res://scenes/network/sync_module.gd"

var _block_active: Dictionary = GameSettings.default_block_state()


func get_module_name() -> StringName:
	return GameSettings.MODULE_BLOCK


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_BLOCK_STARTED,
		GameSettings.PACKET_BLOCK_ENDED,
		GameSettings.PACKET_BLOCK_STATE,
	]


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = _get_payload(packet)
	var slot: int = int(payload.get("slot", packet.get("from_slot", 0)))

	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_BLOCK_STARTED:
		_block_active[slot] = true
	elif packet_type == GameSettings.PACKET_BLOCK_ENDED:
		_block_active[slot] = false
	elif packet_type == GameSettings.PACKET_BLOCK_STATE:
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
