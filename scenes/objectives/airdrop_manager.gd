extends Node2D
class_name AirdropManager

const AIRDROP_SCENE: PackedScene = preload("res://scenes/objectives/airdrop_crate.tscn")

var _round_running: bool = false
var _spawn_timer: float = GameSettings.AIRDROP_DELAY_SECONDS
var _phase: StringName = &"inactive"
var _descent_progress: float = 0.0
var _capture_progress: float = 0.0
var _capturing_slot: int = 0
var _target_position: Vector2 = Vector2.ZERO
var _airdrop: AirdropCrate = null
var _state_send_timer: float = 0.0
var _previous_match_phase: StringName = &""
var _capture_finish_pending: bool = false
var _drop_completed: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)
	if not OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.connect(_on_phase_changed)
	_previous_match_phase = OnlineMatch.phase
	if NetworkSession.is_steam_match_active():
		if OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET:
			_start_new_set()
	else:
		_start_new_set()


func _exit_tree() -> void:
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)
	if OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.disconnect(_on_phase_changed)


func _process(delta: float) -> void:
	if not _round_running or not _has_authority():
		return
	if _phase == &"inactive":
		if _drop_completed:
			return
		_spawn_timer = maxf(_spawn_timer - delta, 0.0)
		if _spawn_timer <= 0.0:
			_spawn_airdrop()
	elif _phase == &"falling":
		_descent_progress = minf(_descent_progress + delta / GameSettings.AIRDROP_DESCENT_SECONDS, 1.0)
		if _descent_progress >= 1.0:
			_phase = &"landed"
			_send_state(true)
	elif _phase == &"landed":
		_update_capture(delta)

	_state_send_timer = maxf(_state_send_timer - delta, 0.0)
	if _phase in [&"falling", &"landed"] and _state_send_timer <= 0.0:
		_state_send_timer = 1.0 / GameSettings.AIRDROP_STATE_RATE
		_send_state(false)
	_apply_visual_state()


func _on_phase_changed(next_phase: StringName) -> void:
	var previous_phase: StringName = _previous_match_phase
	_previous_match_phase = next_phase
	if next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_round_running = true
		if previous_phase in [GameSettings.MATCH_PHASE_LOCKER, GameSettings.MATCH_PHASE_INTERMISSION]:
			_start_new_set()
	elif next_phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_round_running = false
	elif next_phase in [GameSettings.MATCH_PHASE_INTERMISSION, GameSettings.MATCH_PHASE_FINAL, GameSettings.MATCH_PHASE_LOCKER]:
		_round_running = false
		_clear_airdrop()
		if _has_authority():
			_send_state(true)


func _start_new_set() -> void:
	_clear_airdrop()
	_round_running = true
	_spawn_timer = GameSettings.AIRDROP_DELAY_SECONDS
	_capture_finish_pending = false
	_drop_completed = false


func _spawn_airdrop() -> void:
	var markers: Array[Node] = get_tree().get_nodes_in_group(GameSettings.AIRDROP_SPAWN_GROUP)
	if markers.is_empty():
		return
	var marker: Node2D = markers[_rng.randi_range(0, markers.size() - 1)] as Node2D
	if marker == null:
		return
	_target_position = marker.global_position
	_phase = &"falling"
	_descent_progress = 0.0
	_capture_progress = 0.0
	_capturing_slot = 0
	_ensure_airdrop()
	_send_state(true)


func _update_capture(delta: float) -> void:
	var nearby_slots: Array[int] = []
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player == null or player.is_eliminated():
			continue
		var capture_radius: float = ResearchManager.get_capture_radius(slot)
		if player.global_position.distance_squared_to(_target_position) <= capture_radius * capture_radius:
			nearby_slots.append(slot)

	if nearby_slots.size() == 1:
		var next_slot: int = nearby_slots[0]
		if _capturing_slot != next_slot:
			_capturing_slot = next_slot
			_capture_progress = 0.0
		var capture_seconds: float = GameSettings.AIRDROP_BASE_CAPTURE_SECONDS \
			* ResearchManager.get_capture_time_multiplier(_capturing_slot)
		_capture_progress = minf(_capture_progress + delta / maxf(capture_seconds, 0.25), 1.0)
	else:
		_capturing_slot = 0
		_capture_progress = maxf(
			_capture_progress - delta * GameSettings.AIRDROP_CAPTURE_DECAY_RATE,
			0.0
		)

	if _capture_progress >= 1.0 and not _capture_finish_pending:
		_capture_finish_pending = true
		_drop_completed = true
		_phase = &"captured"
		ResearchQuestManager.award_airdrop(_capturing_slot)
		_send_state(true)
		_finish_capture_after_feedback()


func _finish_capture_after_feedback() -> void:
	await get_tree().create_timer(1.4, false).timeout
	if not is_inside_tree():
		return
	_clear_airdrop()
	if _has_authority():
		_send_state(true)


func _ensure_airdrop() -> void:
	if _airdrop != null and is_instance_valid(_airdrop):
		return
	_airdrop = AIRDROP_SCENE.instantiate() as AirdropCrate
	if _airdrop == null:
		return
	add_child(_airdrop)
	_airdrop.global_position = _target_position


func _clear_airdrop() -> void:
	_phase = &"inactive"
	_descent_progress = 0.0
	_capture_progress = 0.0
	_capturing_slot = 0
	if _airdrop != null and is_instance_valid(_airdrop):
		_airdrop.queue_free()
	_airdrop = null


func _apply_visual_state() -> void:
	if _phase == &"inactive":
		return
	_ensure_airdrop()
	if _airdrop == null:
		return
	_airdrop.global_position = _target_position
	_airdrop.apply_state(_build_visual_state())


func _build_visual_state() -> Dictionary:
	var local_slot: int = NetworkSession.local_player_slot
	return {
		"phase": str(_phase),
		"descent_progress": _descent_progress,
		"capture_progress": _capture_progress,
		"capturing_slot": _capturing_slot,
		"target_position": _target_position,
		"local_capture_radius": ResearchManager.get_capture_radius(local_slot),
		"local_reward": ResearchManager.get_capture_research_reward(local_slot),
	}


func _send_state(reliable: bool) -> void:
	if not NetworkSession.is_steam_match_active() or not _has_authority():
		return
	var packet: Dictionary = _make_packet(GameSettings.PACKET_AIRDROP_STATE, {
		"phase": str(_phase),
		"descent_progress": _descent_progress,
		"capture_progress": _capture_progress,
		"capturing_slot": _capturing_slot,
		"target_position": _target_position,
	})
	if reliable:
		NetworkSession.send_reliable(packet, GameSettings.NETWORK_CHANNEL_EVENTS)
	else:
		NetworkSession.send_unreliable(packet, GameSettings.NETWORK_CHANNEL_STATE)


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	if _has_authority():
		return
	if StringName(str(packet.get("type", ""))) != GameSettings.PACKET_AIRDROP_STATE:
		return
	var payload: Dictionary = _get_payload(packet)
	_phase = StringName(str(payload.get("phase", "inactive")))
	var target_variant: Variant = payload.get("target_position", _target_position)
	if target_variant is Vector2:
		_target_position = target_variant
	_descent_progress = clampf(float(payload.get("descent_progress", 0.0)), 0.0, 1.0)
	_capture_progress = clampf(float(payload.get("capture_progress", 0.0)), 0.0, 1.0)
	_capturing_slot = int(payload.get("capturing_slot", 0))
	if _phase == &"inactive":
		_clear_airdrop()
	else:
		_apply_visual_state()


func _get_player(slot: int) -> Player:
	var game: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if game == null or not game.has_method("get_player_by_slot"):
		return null
	return game.call("get_player_by_slot", slot) as Player


func _has_authority() -> bool:
	return not NetworkSession.is_steam_match_active() or NetworkSession.is_host()


func _make_packet(packet_type: StringName, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": GameSettings.NETWORK_PROTOCOL_VERSION,
		"type": str(packet_type),
		"seq": 0,
		"tick": 0,
		"from_slot": NetworkSession.local_player_slot,
		"payload": payload,
	}


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload_variant: Variant = packet.get("payload", {})
	if payload_variant is Dictionary:
		return payload_variant
	return {}
