extends Node

signal quests_changed
signal research_reward_awarded(amount: int, reason: String)

const TIER_EASY: StringName = &"easy"
const TIER_MEDIUM: StringName = &"medium"
const TIER_HARD: StringName = &"hard"

const EVENT_JUMP: StringName = &"jump"
const EVENT_SHOT: StringName = &"shot"
const EVENT_BLOCK_ATTEMPT: StringName = &"block_attempt"

var _definitions: Dictionary = {}
var _assignments_by_slot: Dictionary = {}
var _last_awarded_by_slot: Dictionary = {}
var _active_set_has_quests: bool = false
var _award_sequence: int = 0
var _processed_awards: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state_dirty: bool = false
var _state_send_timer: float = 0.0
var _last_client_event_msec: Dictionary = {}
var _survival_tick_timer: float = 0.0
var _previous_phase: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_definitions = _build_definitions()
	_rng.randomize()
	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)
	if not OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.connect(_on_phase_changed)
	_previous_phase = OnlineMatch.phase


func _process(delta: float) -> void:
	_state_send_timer = maxf(_state_send_timer - delta, 0.0)
	if _has_authority() and _state_dirty and _state_send_timer <= 0.0:
		_broadcast_state()
		_state_dirty = false
		_state_send_timer = 0.12
	if not _has_authority() or OnlineMatch.phase != GameSettings.MATCH_PHASE_PLAYING_SET:
		return
	if not _active_set_has_quests:
		return
	_survival_tick_timer += delta
	if _survival_tick_timer < 0.2:
		return
	var survival_delta: float = _survival_tick_timer
	_survival_tick_timer = 0.0
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player == null or player.is_eliminated():
			continue
		_apply_progress(slot, &"survive_seconds", survival_delta)


func get_definitions_for_tier(tier: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition_variant in _definitions.values():
		if not (definition_variant is Dictionary):
			continue
		var definition: Dictionary = definition_variant
		if StringName(str(definition.get("tier", ""))) == tier:
			result.append(definition.duplicate(true))
	return result


func get_local_quests() -> Array[Dictionary]:
	return get_quests_for_slot(NetworkSession.local_player_slot)


func get_quests_for_slot(slot: int) -> Array[Dictionary]:
	var quests_variant: Variant = _assignments_by_slot.get(slot, [])
	var result: Array[Dictionary] = []
	if not (quests_variant is Array):
		return result
	for quest_variant in quests_variant:
		if quest_variant is Dictionary:
			var quest: Dictionary = quest_variant
			result.append(quest.duplicate(true))
	return result


func get_last_awarded_points(slot: int = 0) -> int:
	var effective_slot: int = NetworkSession.local_player_slot if slot <= 0 else slot
	return int(_last_awarded_by_slot.get(effective_slot, 0))


func reset_match() -> void:
	_assignments_by_slot.clear()
	_last_awarded_by_slot.clear()
	_active_set_has_quests = false
	_award_sequence = 0
	_processed_awards.clear()
	_last_client_event_msec.clear()
	_state_dirty = false
	_state_send_timer = 0.0
	_survival_tick_timer = 0.0
	_previous_phase = OnlineMatch.phase
	quests_changed.emit()
	if _has_authority():
		_broadcast_state(true)


func record_local_action(event_name: StringName, amount: float = 1.0) -> void:
	if OnlineMatch.phase != GameSettings.MATCH_PHASE_PLAYING_SET:
		return
	if not _is_allowed_client_event(event_name):
		return
	var local_slot: int = NetworkSession.local_player_slot
	if _has_authority():
		_apply_progress(local_slot, event_name, amount)
		return
	NetworkSession.send_reliable(
		_make_packet(GameSettings.PACKET_RESEARCH_QUEST_EVENT, {
			"event": str(event_name),
			"amount": clampf(amount, 0.0, 1.0),
		}),
		GameSettings.NETWORK_CHANNEL_EVENTS
	)


func record_damage(source_slot: int, target_slot: int, amount: int, was_first_hit: bool) -> void:
	if not _has_authority() or amount <= 0:
		return
	_apply_progress(source_slot, &"damage", float(amount))
	_apply_progress(source_slot, &"hits", 1.0)
	if was_first_hit:
		_apply_progress(source_slot, &"first_hit", 1.0)
	_fail_quest(target_slot, &"no_hit")


func record_block(slot: int, blocked_damage: int) -> void:
	if not _has_authority() or blocked_damage <= 0:
		return
	_apply_progress(slot, &"blocked_damage", float(blocked_damage))


func award_airdrop(slot: int) -> int:
	if not _has_authority():
		return 0
	var amount: int = ResearchManager.get_capture_research_reward(slot)
	_award_points(slot, amount, "Airdrop secured")
	return amount


func assign_quests_for_next_set() -> void:
	if not _has_authority():
		return
	for slot in GameSettings.player_slots():
		var quests: Array[Dictionary] = []
		for tier in [TIER_EASY, TIER_MEDIUM, TIER_HARD]:
			var options: Array[Dictionary] = get_definitions_for_tier(tier)
			if options.is_empty():
				continue
			var selected: Dictionary = options[_rng.randi_range(0, options.size() - 1)]
			quests.append(_make_assignment(selected))
		_assignments_by_slot[slot] = quests
	_active_set_has_quests = false
	quests_changed.emit()
	_broadcast_state(true)


func _on_phase_changed(next_phase: StringName) -> void:
	var previous_phase: StringName = _previous_phase
	_previous_phase = next_phase
	if not _has_authority():
		return
	if next_phase == GameSettings.MATCH_PHASE_LOCKER:
		reset_match()
	elif next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		if previous_phase in [GameSettings.MATCH_PHASE_LOCKER, GameSettings.MATCH_PHASE_INTERMISSION]:
			_last_awarded_by_slot.clear()
			_survival_tick_timer = 0.0
		_active_set_has_quests = not _assignments_by_slot.is_empty()
		_broadcast_state(true)
	elif next_phase == GameSettings.MATCH_PHASE_INTERMISSION:
		if _active_set_has_quests:
			_finalize_set_quests()
		if _completed_set_count() >= 1:
			assign_quests_for_next_set()
	elif next_phase == GameSettings.MATCH_PHASE_FINAL and _active_set_has_quests:
		_finalize_set_quests()
		_broadcast_state(true)


func _finalize_set_quests() -> void:
	for slot in GameSettings.player_slots():
		if OnlineMatch.last_winner_slot == slot:
			_apply_progress(slot, &"win_set", 1.0)
		var player: Player = _get_player(slot)
		if player != null and player.health_component != null:
			var health_ratio: float = float(player.health_component.health) / maxf(float(player.health_component.max_health), 1.0)
			if health_ratio >= 0.6:
				_apply_progress(slot, &"healthy_finish", 1.0)
		_complete_unfailed_no_hit(slot)
	_active_set_has_quests = false


func _complete_unfailed_no_hit(slot: int) -> void:
	var quests: Array = _assignments_by_slot.get(slot, [])
	for quest_index in range(quests.size()):
		var quest: Dictionary = quests[quest_index]
		if StringName(str(quest.get("event", ""))) != &"no_hit":
			continue
		if quest.get("failed", false) == true or quest.get("completed", false) == true:
			continue
		quest["progress"] = 1.0
		quests[quest_index] = quest
		_complete_quest(slot, quest_index)
	_assignments_by_slot[slot] = quests


func _apply_progress(slot: int, event_name: StringName, amount: float) -> void:
	if not _active_set_has_quests or amount <= 0.0:
		return
	var quests_variant: Variant = _assignments_by_slot.get(slot, [])
	if not (quests_variant is Array):
		return
	var quests: Array = quests_variant
	var changed: bool = false
	for quest_index in range(quests.size()):
		var quest: Dictionary = quests[quest_index]
		if quest.get("completed", false) == true or quest.get("failed", false) == true:
			continue
		if StringName(str(quest.get("event", ""))) != event_name:
			continue
		var target: float = maxf(float(quest.get("target", 1.0)), 1.0)
		quest["progress"] = minf(float(quest.get("progress", 0.0)) + amount, target)
		quests[quest_index] = quest
		changed = true
		if float(quest.get("progress", 0.0)) >= target:
			_assignments_by_slot[slot] = quests
			_complete_quest(slot, quest_index)
			quests = _assignments_by_slot.get(slot, quests)
	if changed:
		_assignments_by_slot[slot] = quests
		quests_changed.emit()
		_state_dirty = true


func _fail_quest(slot: int, event_name: StringName) -> void:
	if not _active_set_has_quests:
		return
	var quests: Array = _assignments_by_slot.get(slot, [])
	for quest_index in range(quests.size()):
		var quest: Dictionary = quests[quest_index]
		if StringName(str(quest.get("event", ""))) != event_name:
			continue
		if quest.get("completed", false) == true:
			continue
		quest["failed"] = true
		quests[quest_index] = quest
		_assignments_by_slot[slot] = quests
		quests_changed.emit()
		_state_dirty = true
		return


func _complete_quest(slot: int, quest_index: int) -> void:
	var quests: Array = _assignments_by_slot.get(slot, [])
	if quest_index < 0 or quest_index >= quests.size():
		return
	var quest: Dictionary = quests[quest_index]
	if quest.get("completed", false) == true:
		return
	quest["completed"] = true
	quests[quest_index] = quest
	_assignments_by_slot[slot] = quests
	var base_reward: int = int(quest.get("reward", 0))
	var awarded: int = maxi(1, int(roundf(float(base_reward) * ResearchManager.get_research_point_multiplier(slot))))
	_award_points(slot, awarded, str(quest.get("title", "Quest complete")))


func _award_points(slot: int, amount: int, reason: String) -> void:
	if amount <= 0:
		return
	_award_sequence += 1
	var award_id: String = "%d:%d:%d" % [OnlineMatch.match_generation, slot, _award_sequence]
	_last_awarded_by_slot[slot] = int(_last_awarded_by_slot.get(slot, 0)) + amount
	if slot == NetworkSession.local_player_slot:
		_apply_local_award(award_id, amount, reason)
	else:
		NetworkSession.send_reliable(
			_make_packet(GameSettings.PACKET_RESEARCH_POINTS_AWARDED, {
				"award_id": award_id,
				"target_slot": slot,
				"amount": amount,
				"reason": reason,
			}),
			GameSettings.NETWORK_CHANNEL_CONTROL
		)
	quests_changed.emit()


func _apply_local_award(award_id: String, amount: int, reason: String) -> void:
	if _processed_awards.has(award_id):
		return
	_processed_awards[award_id] = true
	ResearchManager.add_research_points_exact(amount)
	research_reward_awarded.emit(amount, reason)


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	var payload: Dictionary = _get_payload(packet)
	if packet_type == GameSettings.PACKET_RESEARCH_QUEST_EVENT and _has_authority():
		var event_name: StringName = StringName(str(payload.get("event", "")))
		var source_slot: int = int(packet.get("from_slot", 0))
		if _is_allowed_client_event(event_name) and _accept_client_event(source_slot, event_name):
			_apply_progress(source_slot, event_name, clampf(float(payload.get("amount", 1.0)), 0.0, 1.0))
	elif packet_type == GameSettings.PACKET_RESEARCH_QUEST_STATE and not _has_authority():
		_apply_state(payload)
	elif packet_type == GameSettings.PACKET_RESEARCH_POINTS_AWARDED and not _has_authority():
		if int(payload.get("target_slot", 0)) != NetworkSession.local_player_slot:
			return
		_apply_local_award(
			str(payload.get("award_id", "")),
			int(payload.get("amount", 0)),
			str(payload.get("reason", "Research reward"))
		)


func _broadcast_state(reliable: bool = false) -> void:
	if not NetworkSession.is_steam_match_active() or not _has_authority():
		return
	var packet: Dictionary = _make_packet(GameSettings.PACKET_RESEARCH_QUEST_STATE, {
		"assignments": _assignments_by_slot.duplicate(true),
		"last_awarded": _last_awarded_by_slot.duplicate(),
		"active": _active_set_has_quests,
	})
	if reliable:
		NetworkSession.send_reliable(packet, GameSettings.NETWORK_CHANNEL_CONTROL)
	else:
		NetworkSession.send_unreliable(packet, GameSettings.NETWORK_CHANNEL_STATE)


func _apply_state(state: Dictionary) -> void:
	var assignments_variant: Variant = state.get("assignments", {})
	if assignments_variant is Dictionary:
		_assignments_by_slot = (assignments_variant as Dictionary).duplicate(true)
	var awarded_variant: Variant = state.get("last_awarded", {})
	if awarded_variant is Dictionary:
		_last_awarded_by_slot = (awarded_variant as Dictionary).duplicate()
	_active_set_has_quests = state.get("active", false) == true
	quests_changed.emit()


func _make_assignment(definition: Dictionary) -> Dictionary:
	return {
		"id": str(definition.get("id", "")),
		"title": str(definition.get("title", "Quest")),
		"description": str(definition.get("description", "")),
		"tier": str(definition.get("tier", "")),
		"event": str(definition.get("event", "")),
		"target": float(definition.get("target", 1.0)),
		"reward": int(definition.get("reward", 1)),
		"progress": 0.0,
		"completed": false,
		"failed": false,
	}


func _quest(
	quest_id: StringName,
	title: String,
	description: String,
	tier: StringName,
	event_name: StringName,
	target: float,
	reward: int
) -> Dictionary:
	return {
		"id": str(quest_id),
		"title": title,
		"description": description,
		"tier": str(tier),
		"event": str(event_name),
		"target": target,
		"reward": reward,
	}


func _build_definitions() -> Dictionary:
	var definitions: Dictionary = {}
	var entries: Array[Dictionary] = [
		_quest(&"jump_5", "Jump 5 times", "", TIER_EASY, EVENT_JUMP, 5.0, 1),
		_quest(&"fire_8", "Fire 8 shots", "", TIER_EASY, EVENT_SHOT, 8.0, 1),
		_quest(&"damage_20", "Deal 20 damage", "", TIER_EASY, &"damage", 20.0, 1),
		_quest(&"block_attempt_3", "Raise your shield 3 times", "", TIER_EASY, EVENT_BLOCK_ATTEMPT, 3.0, 1),
		_quest(&"survive_15", "Stay alive for 15 seconds", "", TIER_EASY, &"survive_seconds", 15.0, 1),

		_quest(&"first_hit", "Land the first hit", "", TIER_MEDIUM, &"first_hit", 1.0, 2),
		_quest(&"jump_12", "Jump 12 times", "", TIER_MEDIUM, EVENT_JUMP, 12.0, 2),
		_quest(&"damage_50", "Deal 50 damage", "", TIER_MEDIUM, &"damage", 50.0, 2),
		_quest(&"hit_4", "Hit the opponent 4 times", "", TIER_MEDIUM, &"hits", 4.0, 2),
		_quest(&"block_20", "Block 20 damage", "", TIER_MEDIUM, &"blocked_damage", 20.0, 2),

		_quest(&"no_hit", "Take no damage this set", "", TIER_HARD, &"no_hit", 1.0, 4),
		_quest(&"win_set", "Win this set", "", TIER_HARD, &"win_set", 1.0, 4),
		_quest(&"damage_100", "Deal 100 damage", "", TIER_HARD, &"damage", 100.0, 4),
		_quest(&"block_50", "Block 50 damage", "", TIER_HARD, &"blocked_damage", 50.0, 4),
		_quest(&"healthy_finish", "Finish above 60% health", "", TIER_HARD, &"healthy_finish", 1.0, 4),
	]
	for entry in entries:
		definitions[str(entry.get("id", ""))] = entry
	return definitions


func _completed_set_count() -> int:
	return int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)) \
		+ int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))


func _is_allowed_client_event(event_name: StringName) -> bool:
	return event_name in [EVENT_JUMP, EVENT_SHOT, EVENT_BLOCK_ATTEMPT]


func _accept_client_event(slot: int, event_name: StringName) -> bool:
	if slot not in GameSettings.player_slots():
		return false
	var min_interval_msec: int = 40 if event_name == EVENT_SHOT else 140
	var event_key: String = "%d:%s" % [slot, str(event_name)]
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_client_event_msec.get(event_key, -min_interval_msec))
	if now_msec - last_msec < min_interval_msec:
		return false
	_last_client_event_msec[event_key] = now_msec
	return true


func _has_authority() -> bool:
	return not NetworkSession.is_steam_match_active() or NetworkSession.is_host()


func _get_player(slot: int) -> Player:
	var world: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null:
		return null
	return world.get_player_by_slot(slot)


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
