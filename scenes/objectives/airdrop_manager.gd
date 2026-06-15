extends Node2D
class_name AirdropManager

const AIRDROP_SCENE: PackedScene = preload("res://scenes/objectives/airdrop_crate.tscn")
const PHASE_INACTIVE: StringName = &"inactive"
const PHASE_WARNING: StringName = &"warning"
const PHASE_FALLING: StringName = &"falling"
const PHASE_LANDED: StringName = &"landed"
const PHASE_CAPTURED: StringName = &"captured"

var _round_running: bool = false
var _phase: StringName = PHASE_INACTIVE
var _descent_progress: float = 0.0
var _capture_progress: float = 0.0
var _capturing_slot: int = 0
var _target_position: Vector2 = Vector2.ZERO
var _airdrop: AirdropCrate = null
var _state_send_timer: float = 0.0
var _previous_match_phase: StringName = &""
var _capture_finish_pending: bool = false
var _drop_completed: bool = false
var _siren_pulses_remaining: int = 0
var _remote_descent_target: float = 0.0
var _remote_capture_target: float = 0.0
var _last_remote_packet_msec: int = 0
var _warning_complete: bool = false

@onready var _warning_timer: Timer = get_node_or_null("WarningTimer") as Timer
@onready var _siren_timer: Timer = get_node_or_null("SirenTimer") as Timer
@onready var _siren_player: AudioStreamPlayer = get_node_or_null("SirenPlayer") as AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_feedback_nodes()
	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)
	if not OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.connect(_on_phase_changed)
	_previous_match_phase = OnlineMatch.phase
	if NetworkSession.is_steam_match_active():
		_round_running = OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET
		if _round_running and _has_authority():
			_try_start_decision_drop()


func _exit_tree() -> void:
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)
	if OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.disconnect(_on_phase_changed)


func _process(delta: float) -> void:
	if _has_authority():
		_process_authority(delta)
	else:
		_process_remote(delta)
	_apply_visual_state()


func _process_authority(delta: float) -> void:
	if NetworkSession.is_steam_match_active():
		_round_running = OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET
	if _phase == PHASE_INACTIVE:
		_try_start_decision_drop()
	if _phase == PHASE_WARNING and _warning_complete and _round_running:
		_begin_fall()
	if not _round_running:
		return
	if _phase == PHASE_FALLING:
		_descent_progress = minf(
			_descent_progress + delta / GameSettings.AIRDROP_DESCENT_SECONDS,
			1.0
		)
		if _descent_progress >= 1.0:
			_set_phase(PHASE_LANDED)
			_send_state(true)
	elif _phase == PHASE_LANDED:
		_update_capture(delta)

	_state_send_timer = maxf(_state_send_timer - delta, 0.0)
	if _phase in [PHASE_FALLING, PHASE_LANDED] and _state_send_timer <= 0.0:
		_state_send_timer = 1.0 / GameSettings.AIRDROP_STATE_RATE
		_send_state(false)


func _process_remote(delta: float) -> void:
	if _phase == PHASE_FALLING:
		var elapsed: float = float(Time.get_ticks_msec() - _last_remote_packet_msec) / 1000.0
		var predicted_target: float = minf(
			_remote_descent_target + elapsed / GameSettings.AIRDROP_DESCENT_SECONDS,
			1.0
		)
		_descent_progress = lerpf(
			_descent_progress,
			predicted_target,
			clampf(delta * 11.0, 0.0, 1.0)
		)
	elif _phase == PHASE_LANDED:
		_descent_progress = 1.0
		_capture_progress = lerpf(
			_capture_progress,
			_remote_capture_target,
			clampf(delta * 12.0, 0.0, 1.0)
		)


func _on_phase_changed(next_phase: StringName) -> void:
	var previous_phase: StringName = _previous_match_phase
	_previous_match_phase = next_phase
	if next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_round_running = true
		if previous_phase in [GameSettings.MATCH_PHASE_LOCKER, GameSettings.MATCH_PHASE_INTERMISSION]:
			_start_new_set()
		if _has_authority():
			_try_start_decision_drop()
	elif next_phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_round_running = false
		if _has_authority():
			_try_start_decision_drop()
	elif next_phase in [
		GameSettings.MATCH_PHASE_INTERMISSION,
		GameSettings.MATCH_PHASE_FINAL,
		GameSettings.MATCH_PHASE_LOCKER,
	]:
		_round_running = false
		_clear_airdrop()
		if _has_authority():
			_send_state(true)


func _start_new_set() -> void:
	_clear_airdrop()
	_round_running = true
	_capture_finish_pending = false
	_drop_completed = false
	_warning_complete = false


func _try_start_decision_drop() -> void:
	if _phase != PHASE_INACTIVE or _drop_completed:
		return
	if OnlineMatch.phase not in [
		GameSettings.MATCH_PHASE_KILL_BANNER,
		GameSettings.MATCH_PHASE_PLAYING_SET,
	]:
		return
	if OnlineMatch.airdrop_deployed:
		return
	var player_one_kills: int = int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var player_two_kills: int = int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0))
	var completed_rounds: int = player_one_kills + player_two_kills
	if completed_rounds != 1:
		return
	if not OnlineMatch.mark_airdrop_deployed():
		return
	_target_position = _choose_target_position()
	_descent_progress = 0.0
	_capture_progress = 0.0
	_capturing_slot = 0
	_set_phase(PHASE_WARNING)
	_send_state(true)


func _begin_fall() -> void:
	if _phase != PHASE_WARNING:
		return
	_warning_complete = false
	_set_phase(PHASE_FALLING)
	_send_state(true)


func _choose_target_position() -> Vector2:
	var preferred_name: StringName = &"AirdropPointCenter"
	var player_one_points: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var player_two_points: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	if player_one_points < player_two_points:
		preferred_name = &"AirdropPointLeft"
	elif player_two_points < player_one_points:
		preferred_name = &"AirdropPointRight"

	var map_root: Node = get_parent()
	if map_root != null:
		var preferred_marker: Marker2D = map_root.get_node_or_null(NodePath(str(preferred_name))) as Marker2D
		if preferred_marker != null:
			return preferred_marker.global_position

	var markers: Array[Node] = get_tree().get_nodes_in_group(GameSettings.AIRDROP_SPAWN_GROUP)
	var marker_positions: Array[Vector2] = []
	for marker_node in markers:
		var marker: Marker2D = marker_node as Marker2D
		if marker != null:
			marker_positions.append(marker.global_position)
	if marker_positions.is_empty():
		return global_position
	marker_positions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	if preferred_name == &"AirdropPointLeft":
		return marker_positions.front()
	if preferred_name == &"AirdropPointRight":
		return marker_positions.back()
	return marker_positions[marker_positions.size() / 2]


func _set_phase(next_phase: StringName) -> void:
	if _phase == next_phase:
		return
	_phase = next_phase
	if next_phase == PHASE_WARNING:
		_begin_warning_feedback()
	elif next_phase == PHASE_FALLING:
		_stop_warning_feedback()
	elif next_phase in [PHASE_CAPTURED, PHASE_INACTIVE]:
		_stop_warning_feedback()


func _begin_warning_feedback() -> void:
	_ensure_airdrop()
	_siren_pulses_remaining = GameSettings.AIRDROP_SIREN_PULSES
	_play_siren_pulse()
	if _siren_timer != null and _siren_pulses_remaining > 0:
		_siren_timer.start(GameSettings.AIRDROP_SIREN_INTERVAL)
	if _warning_timer != null and _has_authority():
		_warning_timer.start(GameSettings.AIRDROP_WARNING_SECONDS)


func _stop_warning_feedback() -> void:
	if _warning_timer != null:
		_warning_timer.stop()
	if _siren_timer != null:
		_siren_timer.stop()
	if _siren_player != null:
		_siren_player.stop()
	_siren_pulses_remaining = 0


func _on_siren_timer_timeout() -> void:
	if _phase != PHASE_WARNING or _siren_pulses_remaining <= 0:
		if _siren_timer != null:
			_siren_timer.stop()
		return
	_play_siren_pulse()
	if _siren_pulses_remaining <= 0 and _siren_timer != null:
		_siren_timer.stop()


func _play_siren_pulse() -> void:
	if _siren_pulses_remaining <= 0:
		return
	_siren_pulses_remaining -= 1
	if _siren_player != null:
		_siren_player.play()


func _on_warning_timer_timeout() -> void:
	if not _has_authority() or _phase != PHASE_WARNING:
		return
	if _round_running:
		_begin_fall()
	else:
		_warning_complete = true


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
		_set_phase(PHASE_CAPTURED)
		ResearchQuestManager.award_airdrop(_capturing_slot)
		_send_state(true)
		_apply_visual_state()
		_finish_capture_after_feedback()


func _finish_capture_after_feedback() -> void:
	await get_tree().create_timer(0.24, false).timeout
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
	_set_phase(PHASE_INACTIVE)
	_descent_progress = 0.0
	_capture_progress = 0.0
	_remote_descent_target = 0.0
	_remote_capture_target = 0.0
	_capturing_slot = 0
	_warning_complete = false
	if _airdrop != null and is_instance_valid(_airdrop):
		_airdrop.queue_free()
	_airdrop = null


func _apply_visual_state() -> void:
	if _phase == PHASE_INACTIVE:
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
	var next_phase: StringName = StringName(str(payload.get("phase", "inactive")))
	var target_variant: Variant = payload.get("target_position", _target_position)
	if target_variant is Vector2:
		_target_position = target_variant
	_remote_descent_target = clampf(float(payload.get("descent_progress", 0.0)), 0.0, 1.0)
	_remote_capture_target = clampf(float(payload.get("capture_progress", 0.0)), 0.0, 1.0)
	_capturing_slot = int(payload.get("capturing_slot", 0))
	_last_remote_packet_msec = Time.get_ticks_msec()

	if next_phase != _phase:
		_set_phase(next_phase)
		if next_phase == PHASE_WARNING:
			_descent_progress = 0.0
			_capture_progress = 0.0
		elif next_phase == PHASE_FALLING:
			_descent_progress = _remote_descent_target
		elif next_phase == PHASE_LANDED:
			_descent_progress = 1.0
			_capture_progress = _remote_capture_target
		elif next_phase == PHASE_CAPTURED:
			_capture_progress = 1.0
		elif next_phase == PHASE_INACTIVE:
			_clear_airdrop()
			return
	_apply_visual_state()


func _ensure_feedback_nodes() -> void:
	if _warning_timer == null:
		_warning_timer = Timer.new()
		_warning_timer.name = "WarningTimer"
		_warning_timer.one_shot = true
		add_child(_warning_timer)
	if _siren_timer == null:
		_siren_timer = Timer.new()
		_siren_timer.name = "SirenTimer"
		add_child(_siren_timer)
	if _siren_player == null:
		_siren_player = AudioStreamPlayer.new()
		_siren_player.name = "SirenPlayer"
		_siren_player.bus = &"SFX"
		_siren_player.volume_db = -7.0
		add_child(_siren_player)
	if not _warning_timer.timeout.is_connected(_on_warning_timer_timeout):
		_warning_timer.timeout.connect(_on_warning_timer_timeout)
	if not _siren_timer.timeout.is_connected(_on_siren_timer_timeout):
		_siren_timer.timeout.connect(_on_siren_timer_timeout)
	_siren_player.stream = _build_siren_stream()


func _build_siren_stream() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 0.46
	var sample_count: int = int(float(mix_rate) * duration)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(sample_count * 2)
	for sample_index in range(sample_count):
		var time_seconds: float = float(sample_index) / float(mix_rate)
		var phase_ratio: float = time_seconds / duration
		var frequency: float = lerpf(460.0, 760.0, sin(phase_ratio * PI))
		var attack: float = clampf(time_seconds / 0.035, 0.0, 1.0)
		var release: float = clampf((duration - time_seconds) / 0.08, 0.0, 1.0)
		var envelope: float = minf(attack, release)
		var wave: float = sin(TAU * frequency * time_seconds)
		wave += sin(TAU * frequency * 0.5 * time_seconds) * 0.24
		var sample_value: int = int(clampf(wave * envelope * 0.30, -1.0, 1.0) * 32767.0)
		samples.encode_s16(sample_index * 2, sample_value)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = samples
	return stream


func _get_player(slot: int) -> Player:
	var game: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if game == null:
		return null
	return game.get_player_by_slot(slot)


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
