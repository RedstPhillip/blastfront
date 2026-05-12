extends "res://scenes/network/sync_module.gd"

var _round_state: String = GameSettings.ROUND_STATE_PLAYING
var _score: Dictionary = GameSettings.default_score()
var _wins_needed: int = GameSettings.MATCH_WINS_NEEDED


func get_module_name() -> StringName:
	return GameSettings.MODULE_ROUND


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_ROUND_STATE_CHANGED,
		GameSettings.PACKET_SCORE_CHANGED,
		GameSettings.PACKET_MATCH_OVER,
	]


func setup(sync: Node, game_world: Node) -> void:
	game_sync = sync
	game = game_world
	if game != null and game.has_method("get_config"):
		var config: Variant = game.call("get_config")
		if config is Dictionary:
			_wins_needed = config.get("wins_needed", GameSettings.MATCH_WINS_NEEDED)


func add_score(slot: int) -> bool:
	_score[slot] = _score.get(slot, 0) + 1
	game_sync.send_reliable(GameSettings.PACKET_SCORE_CHANGED, {
		"slot": slot,
		"score": _score[slot],
	}, GameSettings.NETWORK_CHANNEL_EVENTS)

	if _score[slot] >= _wins_needed:
		_round_state = GameSettings.ROUND_STATE_FINISHED
		game_sync.send_reliable(GameSettings.PACKET_ROUND_STATE_CHANGED, {
			"state": GameSettings.ROUND_STATE_FINISHED,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)
		game_sync.send_reliable(GameSettings.PACKET_MATCH_OVER, {
			"winner_slot": slot,
		}, GameSettings.NETWORK_CHANNEL_EVENTS)
		return true

	return false


func handle_packet(packet: Dictionary) -> void:
	var payload := _get_payload(packet)
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type == GameSettings.PACKET_ROUND_STATE_CHANGED:
		_round_state = str(payload.get("state", _round_state))
	elif packet_type == GameSettings.PACKET_SCORE_CHANGED:
		_score[int(payload.get("slot", 0))] = int(payload.get("score", 0))
	elif packet_type == GameSettings.PACKET_MATCH_OVER:
		_round_state = GameSettings.ROUND_STATE_FINISHED
		var winner: int = int(payload.get("winner_slot", 0))
		if game != null and game.has_method("on_match_over"):
			game.call("on_match_over", winner)


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


func get_wins_needed() -> int:
	return _wins_needed


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
