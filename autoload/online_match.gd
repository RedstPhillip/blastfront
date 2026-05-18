extends Node

signal state_changed
signal phase_changed(phase: StringName)
signal countdown_changed(seconds_left: int)

var phase: StringName = GameSettings.MATCH_PHASE_LOCKER
var player_colors: Dictionary = GameSettings.default_player_colors()
var locker_ready: Dictionary = GameSettings.default_ready_state()
var intermission_ready: Dictionary = GameSettings.default_ready_state()
var set_kills: Dictionary = GameSettings.default_score()
var match_points: Dictionary = GameSettings.default_score()
var last_winner_slot: int = 0
var final_winner_slot: int = 0
var intermission_remaining: float = GameSettings.ONLINE_INTERMISSION_SECONDS

var _kill_banner_remaining: float = 0.0
var _phase_after_banner: StringName = GameSettings.MATCH_PHASE_PLAYING_SET
var _last_countdown_second: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)
	if NetworkSession.has_signal("peer_changed") and not NetworkSession.peer_changed.is_connected(_on_peer_changed):
		NetworkSession.peer_changed.connect(_on_peer_changed)
	if NetworkSession.has_signal("lobby_ready") and not NetworkSession.lobby_ready.is_connected(_on_lobby_ready):
		NetworkSession.lobby_ready.connect(_on_lobby_ready)


func _process(delta: float) -> void:
	if not _has_authority():
		return

	if phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_kill_banner_remaining = maxf(_kill_banner_remaining - delta, 0.0)
		if _kill_banner_remaining <= 0.0:
			_finish_kill_banner()
	elif phase == GameSettings.MATCH_PHASE_INTERMISSION:
		intermission_remaining = maxf(intermission_remaining - delta, 0.0)
		var next_countdown_second: int = int(ceil(intermission_remaining))
		if next_countdown_second != _last_countdown_second:
			_last_countdown_second = next_countdown_second
			countdown_changed.emit(next_countdown_second)
			_broadcast_state()
		if _both_ready(intermission_ready) or intermission_remaining <= 0.0:
			start_next_set()


func enter_locker(reset_scores: bool = true) -> void:
	if reset_scores:
		_reset_match_scores()
	locker_ready = GameSettings.default_ready_state()
	intermission_ready = GameSettings.default_ready_state()
	last_winner_slot = 0
	final_winner_slot = 0
	_kill_banner_remaining = 0.0
	intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
	_set_phase(GameSettings.MATCH_PHASE_LOCKER, true)


func start_next_set() -> void:
	if not _has_authority():
		return

	set_kills = GameSettings.default_score()
	locker_ready = GameSettings.default_ready_state()
	intermission_ready = GameSettings.default_ready_state()
	last_winner_slot = 0
	_kill_banner_remaining = 0.0
	intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
	_set_phase(GameSettings.MATCH_PHASE_PLAYING_SET, true)


func record_kill(winner_slot: int) -> void:
	if not _has_authority():
		return
	if phase != GameSettings.MATCH_PHASE_PLAYING_SET:
		return
	if not _is_player_slot(winner_slot):
		return

	set_kills[winner_slot] = int(set_kills.get(winner_slot, 0)) + 1
	last_winner_slot = winner_slot
	_kill_banner_remaining = GameSettings.ONLINE_KILL_BANNER_SECONDS

	if int(set_kills.get(winner_slot, 0)) >= GameSettings.ONLINE_SET_KILLS_TO_WIN:
		match_points[winner_slot] = int(match_points.get(winner_slot, 0)) + 1
		if int(match_points.get(winner_slot, 0)) >= GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN:
			final_winner_slot = winner_slot
			_phase_after_banner = GameSettings.MATCH_PHASE_FINAL
		else:
			_phase_after_banner = GameSettings.MATCH_PHASE_INTERMISSION
	else:
		_phase_after_banner = GameSettings.MATCH_PHASE_PLAYING_SET

	_set_phase(GameSettings.MATCH_PHASE_KILL_BANNER, true)


func set_local_color(color_id: StringName) -> void:
	set_player_color(NetworkSession.local_player_slot, color_id)


func set_player_color(slot: int, color_id: StringName) -> void:
	if not _is_player_slot(slot):
		return
	if not GameSettings.is_valid_player_color(color_id):
		return

	_apply_player_color(slot, color_id)
	if _has_authority():
		_broadcast_state()
	else:
		_send_request(GameSettings.PACKET_ONLINE_PLAYER_COLOR, {
			"slot": slot,
			"color_id": str(color_id),
		})


func set_local_locker_ready(is_ready: bool) -> void:
	set_locker_ready(NetworkSession.local_player_slot, is_ready)


func set_locker_ready(slot: int, is_ready: bool) -> void:
	if not _is_player_slot(slot):
		return

	if _has_authority():
		locker_ready[slot] = is_ready
		if _both_ready(locker_ready):
			start_next_set()
		else:
			_broadcast_state()
			state_changed.emit()
	else:
		locker_ready[slot] = is_ready
		state_changed.emit()
		_send_request(GameSettings.PACKET_ONLINE_LOCKER_READY, {
			"slot": slot,
			"ready": is_ready,
		})


func set_local_intermission_ready(is_ready: bool) -> void:
	set_intermission_ready(NetworkSession.local_player_slot, is_ready)


func set_intermission_ready(slot: int, is_ready: bool) -> void:
	if not _is_player_slot(slot):
		return

	if _has_authority():
		intermission_ready[slot] = is_ready
		if _both_ready(intermission_ready):
			start_next_set()
		else:
			_broadcast_state()
			state_changed.emit()
	else:
		intermission_ready[slot] = is_ready
		state_changed.emit()
		_send_request(GameSettings.PACKET_ONLINE_INTERMISSION_READY, {
			"slot": slot,
			"ready": is_ready,
		})


func get_player_color_id(slot: int) -> StringName:
	if player_colors.has(slot):
		return StringName(str(player_colors[slot]))
	if slot == GameSettings.PLAYER_TWO_SLOT:
		return GameSettings.ONLINE_DEFAULT_REMOTE_COLOR
	return GameSettings.ONLINE_DEFAULT_LOCAL_COLOR


func get_player_color(slot: int) -> Color:
	return GameSettings.player_color_value(get_player_color_id(slot))


func get_player_color_name(slot: int) -> String:
	return GameSettings.player_color_display_name(get_player_color_id(slot))


func is_playing_set() -> bool:
	return phase == GameSettings.MATCH_PHASE_PLAYING_SET


func build_state() -> Dictionary:
	return {
		"phase": str(phase),
		"player_colors": player_colors.duplicate(),
		"locker_ready": locker_ready.duplicate(),
		"intermission_ready": intermission_ready.duplicate(),
		"set_kills": set_kills.duplicate(),
		"match_points": match_points.duplicate(),
		"last_winner_slot": last_winner_slot,
		"final_winner_slot": final_winner_slot,
		"intermission_remaining": intermission_remaining,
	}


func _reset_match_scores() -> void:
	set_kills = GameSettings.default_score()
	match_points = GameSettings.default_score()


func _finish_kill_banner() -> void:
	if _phase_after_banner == GameSettings.MATCH_PHASE_INTERMISSION:
		intermission_ready = GameSettings.default_ready_state()
		intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
		_last_countdown_second = int(ceil(intermission_remaining))
		_set_phase(GameSettings.MATCH_PHASE_INTERMISSION, true)
	elif _phase_after_banner == GameSettings.MATCH_PHASE_FINAL:
		_set_phase(GameSettings.MATCH_PHASE_FINAL, true)
	else:
		_set_phase(GameSettings.MATCH_PHASE_PLAYING_SET, true)


func _set_phase(next_phase: StringName, should_broadcast: bool) -> void:
	var previous_phase: StringName = phase
	phase = next_phase
	if phase != previous_phase:
		phase_changed.emit(phase)
	state_changed.emit()
	if should_broadcast and _has_authority():
		_broadcast_state()


func _apply_player_color(slot: int, color_id: StringName) -> void:
	player_colors[slot] = color_id
	state_changed.emit()


func _apply_state(state: Dictionary) -> void:
	_apply_dictionary(state.get("player_colors", {}), player_colors, true)
	_apply_dictionary(state.get("locker_ready", {}), locker_ready, false)
	_apply_dictionary(state.get("intermission_ready", {}), intermission_ready, false)
	_apply_dictionary(state.get("set_kills", {}), set_kills, false)
	_apply_dictionary(state.get("match_points", {}), match_points, false)

	last_winner_slot = int(state.get("last_winner_slot", last_winner_slot))
	final_winner_slot = int(state.get("final_winner_slot", final_winner_slot))
	intermission_remaining = float(state.get("intermission_remaining", intermission_remaining))

	var next_phase: StringName = StringName(str(state.get("phase", str(phase))))
	var previous_phase: StringName = phase
	phase = next_phase
	if phase != previous_phase:
		phase_changed.emit(phase)
	state_changed.emit()
	countdown_changed.emit(int(ceil(intermission_remaining)))


func _apply_dictionary(source_variant: Variant, target: Dictionary, stores_color_ids: bool) -> void:
	if not (source_variant is Dictionary):
		return

	var source: Dictionary = source_variant
	for raw_slot in source.keys():
		var slot: int = int(raw_slot)
		if not _is_player_slot(slot):
			continue
		if stores_color_ids:
			target[slot] = StringName(str(source[raw_slot]))
		elif source[raw_slot] is bool:
			target[slot] = source[raw_slot] == true
		else:
			target[slot] = int(source[raw_slot])


func _broadcast_state() -> void:
	if not _has_authority():
		return
	NetworkSession.send_reliable(
		_make_packet(GameSettings.PACKET_ONLINE_MATCH_STATE, build_state()),
		GameSettings.NETWORK_CHANNEL_CONTROL
	)


func _send_request(packet_type: StringName, payload: Dictionary) -> void:
	NetworkSession.send_reliable(_make_packet(packet_type, payload), GameSettings.NETWORK_CHANNEL_CONTROL)


func _make_packet(packet_type: StringName, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": GameSettings.NETWORK_PROTOCOL_VERSION,
		"type": str(packet_type),
		"seq": 0,
		"tick": 0,
		"from_slot": NetworkSession.local_player_slot,
		"payload": payload,
	}


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	var payload: Dictionary = _get_payload(packet)

	if packet_type == GameSettings.PACKET_ONLINE_MATCH_STATE:
		if not _has_authority():
			_apply_state(payload)
	elif packet_type == GameSettings.PACKET_ONLINE_PLAYER_COLOR and _has_authority():
		var color_slot: int = _slot_from_packet(packet)
		var color_id: StringName = StringName(str(payload.get("color_id", "")))
		if GameSettings.is_valid_player_color(color_id):
			_apply_player_color(color_slot, color_id)
			_broadcast_state()
	elif packet_type == GameSettings.PACKET_ONLINE_LOCKER_READY and _has_authority():
		set_locker_ready(_slot_from_packet(packet), payload.get("ready", false) == true)
	elif packet_type == GameSettings.PACKET_ONLINE_INTERMISSION_READY and _has_authority():
		set_intermission_ready(_slot_from_packet(packet), payload.get("ready", false) == true)


func _on_peer_changed() -> void:
	if NetworkSession.remote_steam_id == 0:
		enter_locker(false)
		return
	if _has_authority():
		_broadcast_state()


func _on_lobby_ready() -> void:
	if _has_authority():
		_broadcast_state()


func _slot_from_packet(packet: Dictionary) -> int:
	var slot: int = int(packet.get("from_slot", 0))
	if _is_player_slot(slot):
		return slot
	return NetworkSession.get_remote_slot()


func _both_ready(ready_state: Dictionary) -> bool:
	if NetworkSession.remote_steam_id == 0:
		return false
	return ready_state.get(GameSettings.PLAYER_ONE_SLOT, false) == true and ready_state.get(GameSettings.PLAYER_TWO_SLOT, false) == true


func _has_authority() -> bool:
	return NetworkSession.mode == GameSettings.NETWORK_MODE_HOST


func _is_player_slot(slot: int) -> bool:
	return slot == GameSettings.PLAYER_ONE_SLOT or slot == GameSettings.PLAYER_TWO_SLOT


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
