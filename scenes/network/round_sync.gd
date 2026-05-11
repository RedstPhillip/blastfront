extends "res://scenes/network/sync_module.gd"

const WINS_NEEDED := 2

var _round_state := "playing"
var _score := {
	1: 0,
	2: 0,
}


func get_module_name() -> StringName:
	return &"round"


func get_packet_types() -> Array[StringName]:
	return [&"round_state_changed", &"score_changed", &"match_over"]


func add_score(slot: int) -> bool:
	_score[slot] = _score.get(slot, 0) + 1
	game_sync.send_reliable(&"score_changed", {
		"slot": slot,
		"score": _score[slot],
	}, NetworkSession.CHANNEL_EVENTS)

	if _score[slot] >= WINS_NEEDED:
		_round_state = "finished"
		game_sync.send_reliable(&"round_state_changed", {
			"state": "finished",
		}, NetworkSession.CHANNEL_EVENTS)
		game_sync.send_reliable(&"match_over", {
			"winner_slot": slot,
		}, NetworkSession.CHANNEL_EVENTS)
		return true

	return false


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	match str(packet.get("type", "")):
		"round_state_changed":
			_round_state = str(payload.get("state", _round_state))
		"score_changed":
			_score[int(payload.get("slot", 0))] = int(payload.get("score", 0))
		"match_over":
			_round_state = "finished"
			var winner: int = int(payload.get("winner_slot", 0))
			if game != null and game.has_method("on_match_over"):
				game.on_match_over(winner)


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


func get_scores() -> Dictionary:
	return _score.duplicate()


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
