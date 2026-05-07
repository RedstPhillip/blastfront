extends "res://scenes/network/sync_module.gd"

var _round_state := "playing"
var _score := {
	1: 0,
	2: 0,
}


func get_module_name() -> StringName:
	return &"round"


func get_packet_types() -> Array[StringName]:
	return [&"round_state_changed", &"score_changed"]


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	match str(packet.get("type", "")):
		"round_state_changed":
			_round_state = str(payload.get("state", _round_state))
		"score_changed":
			_score[int(payload.get("slot", 0))] = int(payload.get("score", 0))


func build_snapshot() -> Dictionary:
	return {
		"round_state": _round_state,
		"score": _score.duplicate(),
	}


func apply_snapshot(data: Dictionary) -> void:
	_round_state = str(data.get("round_state", _round_state))
	var score_data: Variant = data.get("score", {})
	if score_data is Dictionary:
		_score = score_data.duplicate()


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
