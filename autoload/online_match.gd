extends Node

signal state_changed
signal phase_changed(phase: StringName)
signal countdown_changed(seconds_left: int)

var phase: StringName = GameSettings.MATCH_PHASE_LOCKER
var player_colors: Dictionary = GameSettings.default_player_colors()
var locker_ready: Dictionary = GameSettings.default_ready_state()
var intermission_ready: Dictionary = GameSettings.default_ready_state()
var extension_loadouts: Dictionary = GameSettings.default_extension_loadouts()
var armor_loadouts: Dictionary = GameSettings.default_armor_loadouts()
var research_profiles: Dictionary = {}
var set_kills: Dictionary = GameSettings.default_score()
var match_points: Dictionary = GameSettings.default_score()
var coin_balances: Dictionary = GameSettings.default_score()
var last_set_earnings: Dictionary = {}
var last_winner_slot: int = 0
var final_winner_slot: int = 0
var intermission_remaining: float = GameSettings.ONLINE_INTERMISSION_SECONDS
var locker_countdown_remaining: float = -1.0
var match_generation: int = 0

var _current_set_stats: Dictionary = {}
var _first_hit_recorded: bool = false
var _kill_banner_remaining: float = 0.0
var _kill_banner_deadline_msec: int = 0
var _kill_banner_generation: int = 0
var _phase_after_banner: StringName = GameSettings.MATCH_PHASE_PLAYING_SET
var _last_countdown_second: int = -1
var _last_locker_countdown_second: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)
	if NetworkSession.has_signal("peer_changed") and not NetworkSession.peer_changed.is_connected(_on_peer_changed):
		NetworkSession.peer_changed.connect(_on_peer_changed)
	if NetworkSession.has_signal("lobby_ready") and not NetworkSession.lobby_ready.is_connected(_on_lobby_ready):
		NetworkSession.lobby_ready.connect(_on_lobby_ready)


# Only the host advances authoritative phase timers and set statistics.
func _process(delta: float) -> void:
	if not _has_authority():
		return

	if phase == GameSettings.MATCH_PHASE_LOCKER:
		_process_locker_countdown(delta)
	elif phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_kill_banner_remaining = maxf(_kill_banner_remaining - delta, 0.0)
		if _kill_banner_remaining <= 0.0 or Time.get_ticks_msec() >= _kill_banner_deadline_msec:
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
	elif phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_record_survival_time(delta)


# Entering the locker starts a fresh session and resets synchronized progression state.
func enter_locker(reset_scores: bool = true) -> void:
	if reset_scores:
		match_generation += 1
		_reset_match_scores()
		_reset_match_economy()
		RoundRewardInventory.reset_match()
		ExtensionInventory.reset_match()
		ArmorInventory.reset_match()
		ResearchQuestManager.reset_match()
	locker_ready = GameSettings.default_ready_state()
	intermission_ready = GameSettings.default_ready_state()
	extension_loadouts = GameSettings.default_extension_loadouts()
	armor_loadouts = GameSettings.default_armor_loadouts()
	research_profiles = {}
	if reset_scores:
		ResearchManager.reset_for_new_game()
	last_winner_slot = 0
	final_winner_slot = 0
	_kill_banner_remaining = 0.0
	_kill_banner_deadline_msec = 0
	intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
	locker_countdown_remaining = -1.0
	_last_locker_countdown_second = -1
	_set_phase(GameSettings.MATCH_PHASE_LOCKER, true)
	call_deferred("_request_local_research_profile")


func start_next_set() -> void:
	if not _has_authority():
		return

	set_kills = GameSettings.default_score()
	locker_ready = GameSettings.default_ready_state()
	intermission_ready = GameSettings.default_ready_state()
	last_winner_slot = 0
	_kill_banner_remaining = 0.0
	_kill_banner_deadline_msec = 0
	intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
	locker_countdown_remaining = -1.0
	_last_locker_countdown_second = -1
	_reset_current_set_stats()
	_set_phase(GameSettings.MATCH_PHASE_PLAYING_SET, true)


# A kill may advance the set, finish the match, or resume play after a banner.
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
	_kill_banner_deadline_msec = Time.get_ticks_msec() + int(roundf(GameSettings.ONLINE_KILL_BANNER_SECONDS * GameSettings.MILLISECONDS_PER_SECOND))
	_kill_banner_generation += 1
	var banner_generation: int = _kill_banner_generation

	if int(set_kills.get(winner_slot, 0)) >= GameSettings.ONLINE_SET_KILLS_TO_WIN:
		_award_set_coins()
		match_points[winner_slot] = int(match_points.get(winner_slot, 0)) + 1
		if int(match_points.get(winner_slot, 0)) >= GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN:
			final_winner_slot = winner_slot
			_phase_after_banner = GameSettings.MATCH_PHASE_FINAL
		else:
			_phase_after_banner = GameSettings.MATCH_PHASE_INTERMISSION
	else:
		_phase_after_banner = GameSettings.MATCH_PHASE_PLAYING_SET

	_set_phase(GameSettings.MATCH_PHASE_KILL_BANNER, true)
	_finish_kill_banner_after_timeout(banner_generation)


func record_damage(source_slot: int, target_slot: int, amount: int) -> void:
	if not _has_authority() or phase != GameSettings.MATCH_PHASE_PLAYING_SET:
		return
	if not _is_player_slot(source_slot) or not _is_player_slot(target_slot):
		return
	if source_slot == target_slot or amount <= 0:
		return

	var stats: Dictionary = _get_current_stats(source_slot)
	stats["damage"] = int(stats.get("damage", 0)) + amount
	var was_first_hit: bool = not _first_hit_recorded
	if not _first_hit_recorded:
		_first_hit_recorded = true
		stats["first_hit"] = true
	_current_set_stats[source_slot] = stats
	ResearchQuestManager.record_damage(source_slot, target_slot, amount, was_first_hit)


func record_block(blocking_slot: int, blocked_damage: int) -> void:
	if not _has_authority() or phase != GameSettings.MATCH_PHASE_PLAYING_SET:
		return
	if not _is_player_slot(blocking_slot) or blocked_damage <= 0:
		return

	var stats: Dictionary = _get_current_stats(blocking_slot)
	stats["blocked_damage"] = int(stats.get("blocked_damage", 0)) + blocked_damage
	_current_set_stats[blocking_slot] = stats
	ResearchQuestManager.record_block(blocking_slot, blocked_damage)


func get_coin_balance(slot: int) -> int:
	return int(coin_balances.get(slot, 0))


func get_local_coin_balance() -> int:
	return get_coin_balance(NetworkSession.local_player_slot)


func get_last_set_earnings(slot: int) -> Dictionary:
	var earnings_variant: Variant = last_set_earnings.get(slot, {})
	if earnings_variant is Dictionary:
		var earnings: Dictionary = earnings_variant
		return earnings.duplicate()
	return {}


func try_spend_local_coins(cost: int) -> bool:
	var slot: int = NetworkSession.local_player_slot
	if cost <= 0 or cost > _max_coin_spend():
		return false
	if get_coin_balance(slot) < cost:
		return false

	coin_balances[slot] = get_coin_balance(slot) - cost
	state_changed.emit()
	if _has_authority():
		_broadcast_state()
	else:
		_send_request(GameSettings.PACKET_ONLINE_COIN_SPEND, {
			"slot": slot,
			"cost": cost,
		})
	return true


func add_local_coins(amount: int) -> bool:
	var slot: int = NetworkSession.local_player_slot
	if amount <= 0 or amount > GameSettings.SHOP_MAX_PRICE:
		return false
	coin_balances[slot] = get_coin_balance(slot) + amount
	state_changed.emit()
	if _has_authority():
		_broadcast_state()
	else:
		_send_request(GameSettings.PACKET_ONLINE_COIN_ADD, {
			"slot": slot,
			"amount": amount,
		})
	return true


func set_local_color(color_id: StringName) -> void:
	set_player_color(NetworkSession.local_player_slot, color_id)


func set_player_color(slot: int, color_id: StringName) -> void:
	if not _is_player_slot(slot):
		return
	if not GameSettings.is_valid_player_color(color_id):
		return
	if is_color_taken_by_other(slot, color_id):
		return

	if _has_authority():
		_apply_player_color(slot, color_id)
		_broadcast_state()
	else:
		_send_request(GameSettings.PACKET_ONLINE_PLAYER_COLOR, {
			"slot": slot,
			"color_id": str(color_id),
		})


func set_local_extension_loadout(loadout: Dictionary) -> void:
	set_extension_loadout(NetworkSession.local_player_slot, loadout)


# Clients preview their loadout locally, then ask the host to validate and publish it.
func set_extension_loadout(slot: int, loadout: Dictionary) -> void:
	if not _is_player_slot(slot):
		return

	var loadout_copy: Dictionary = loadout.duplicate(true)
	if _has_authority():
		extension_loadouts[slot] = loadout_copy
		_broadcast_state()
		state_changed.emit()
	else:
		extension_loadouts[slot] = loadout_copy
		state_changed.emit()
		_send_request(GameSettings.PACKET_ONLINE_EXTENSION_LOADOUT, {
			"slot": slot,
			"loadout": loadout_copy,
		})


func get_extension_loadouts() -> Dictionary:
	return extension_loadouts.duplicate(true)


func get_extension_loadout(slot: int) -> Dictionary:
	var loadout_variant: Variant = extension_loadouts.get(slot, {})
	if loadout_variant is Dictionary:
		var loadout: Dictionary = loadout_variant
		return loadout.duplicate(true)
	return {}


func set_local_armor_loadout(loadout: Dictionary) -> void:
	set_armor_loadout(NetworkSession.local_player_slot, loadout)


func set_armor_loadout(slot: int, loadout: Dictionary) -> void:
	if not _is_player_slot(slot):
		return

	var loadout_copy: Dictionary = loadout.duplicate(true)
	if _has_authority():
		armor_loadouts[slot] = loadout_copy
		_broadcast_state()
		state_changed.emit()
	else:
		armor_loadouts[slot] = loadout_copy
		state_changed.emit()
		_send_request(GameSettings.PACKET_ONLINE_ARMOR_LOADOUT, {
			"slot": slot,
			"loadout": loadout_copy,
		})


func get_armor_loadouts() -> Dictionary:
	return armor_loadouts.duplicate(true)


func get_armor_loadout(slot: int) -> Dictionary:
	var loadout_variant: Variant = armor_loadouts.get(slot, {})
	if loadout_variant is Dictionary:
		var loadout: Dictionary = loadout_variant
		return loadout.duplicate(true)
	return {}


func set_local_research_profile(profile: Dictionary) -> void:
	set_research_profile(NetworkSession.local_player_slot, profile)


func set_research_profile(slot: int, profile: Dictionary) -> void:
	if not _is_player_slot(slot):
		return
	var profile_copy: Dictionary = profile.duplicate(true)
	research_profiles[slot] = profile_copy
	_apply_research_profiles_to_manager()
	if _has_authority():
		_broadcast_state()
		state_changed.emit()
	else:
		state_changed.emit()
		_send_request(GameSettings.PACKET_ONLINE_RESEARCH_PROFILE, {
			"slot": slot,
			"profile": profile_copy,
		})


func get_research_profiles() -> Dictionary:
	return research_profiles.duplicate(true)


func set_local_locker_ready(is_ready: bool) -> void:
	set_locker_ready(NetworkSession.local_player_slot, is_ready)


func set_locker_ready(slot: int, is_ready: bool) -> void:
	if not _is_player_slot(slot):
		return

	if _has_authority():
		locker_ready[slot] = is_ready
		_update_locker_countdown_state()
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
		var stored_color_id: StringName = StringName(str(player_colors[slot]))
		if GameSettings.is_valid_player_color(stored_color_id):
			return stored_color_id
	if slot == GameSettings.PLAYER_TWO_SLOT:
		return GameSettings.ONLINE_DEFAULT_REMOTE_COLOR
	return GameSettings.ONLINE_DEFAULT_LOCAL_COLOR


func is_color_taken_by_other(slot: int, color_id: StringName) -> bool:
	if not _is_player_slot(slot):
		return false

	var other_slot: int = GameSettings.PLAYER_TWO_SLOT
	if slot == GameSettings.PLAYER_TWO_SLOT:
		other_slot = GameSettings.PLAYER_ONE_SLOT
	return get_player_color_id(other_slot) == color_id


func get_player_color(slot: int) -> Color:
	return GameSettings.player_color_value(get_player_color_id(slot))


func get_player_color_name(slot: int) -> String:
	return GameSettings.player_color_display_name(get_player_color_id(slot))


func is_playing_set() -> bool:
	return phase == GameSettings.MATCH_PHASE_PLAYING_SET


# This complete host snapshot is the source of truth for synchronized match state.
func build_state() -> Dictionary:
	return {
		"phase": str(phase),
		"player_colors": player_colors.duplicate(),
		"extension_loadouts": extension_loadouts.duplicate(true),
		"armor_loadouts": armor_loadouts.duplicate(true),
		"research_profiles": research_profiles.duplicate(true),
		"locker_ready": locker_ready.duplicate(),
		"intermission_ready": intermission_ready.duplicate(),
		"set_kills": set_kills.duplicate(),
		"match_points": match_points.duplicate(),
		"coin_balances": coin_balances.duplicate(),
		"last_set_earnings": last_set_earnings.duplicate(true),
		"last_winner_slot": last_winner_slot,
		"final_winner_slot": final_winner_slot,
		"intermission_remaining": intermission_remaining,
		"locker_countdown_remaining": locker_countdown_remaining,
		"match_generation": match_generation,
	}


func _reset_match_scores() -> void:
	set_kills = GameSettings.default_score()
	match_points = GameSettings.default_score()


func _reset_match_economy() -> void:
	coin_balances = GameSettings.default_score()
	last_set_earnings = {}
	_reset_current_set_stats()


func _reset_current_set_stats() -> void:
	_current_set_stats = {}
	for slot in GameSettings.player_slots():
		_current_set_stats[slot] = {
			"damage": 0,
			"survival_seconds": 0.0,
			"blocked_damage": 0,
			"first_hit": false,
		}
	_first_hit_recorded = false


func _get_current_stats(slot: int) -> Dictionary:
	var stats_variant: Variant = _current_set_stats.get(slot, {})
	if stats_variant is Dictionary:
		var stats: Dictionary = stats_variant
		return stats
	return {}


func _record_survival_time(delta: float) -> void:
	for slot in GameSettings.player_slots():
		var stats: Dictionary = _get_current_stats(slot)
		stats["survival_seconds"] = float(stats.get("survival_seconds", 0.0)) + delta
		_current_set_stats[slot] = stats


# Set rewards combine performance categories, then research multipliers.
func _award_set_coins() -> void:
	last_set_earnings = {}
	for slot in GameSettings.player_slots():
		var stats: Dictionary = _get_current_stats(slot)
		var damage: int = int(stats.get("damage", 0))
		var survival_seconds: float = float(stats.get("survival_seconds", 0.0))
		var blocked_damage: int = int(stats.get("blocked_damage", 0))
		var first_hit: bool = stats.get("first_hit", false) == true
		var damage_coins: int = int(damage / GameSettings.COIN_DAMAGE_STEP)
		var survival_coins: int = int(floor(survival_seconds / GameSettings.COIN_SURVIVAL_STEP_SECONDS))
		var block_steps: int = int(blocked_damage / GameSettings.COIN_BLOCK_DAMAGE_STEP)
		var block_coins: int = block_steps * GameSettings.COIN_BLOCK_REWARD
		var first_hit_coins: int = GameSettings.COIN_FIRST_HIT_REWARD if first_hit else 0
		var base_earned: int = damage_coins + survival_coins + block_coins + first_hit_coins
		var coin_multiplier: float = ResearchManager.get_coin_multiplier(slot)
		var earned: int = int(roundf(float(base_earned) * coin_multiplier))
		var interest_bonus: int = earned - base_earned
		coin_balances[slot] = get_coin_balance(slot) + earned
		last_set_earnings[slot] = {
			"damage": damage,
			"damage_coins": damage_coins,
			"survival_seconds": int(floor(survival_seconds)),
			"survival_coins": survival_coins,
			"blocked_damage": blocked_damage,
			"block_coins": block_coins,
			"first_hit": first_hit,
			"first_hit_coins": first_hit_coins,
			"earned": earned,
			"base_earned": base_earned,
			"interest_bonus": interest_bonus,
			"balance": get_coin_balance(slot),
		}


func _process_locker_countdown(delta: float) -> void:
	if locker_countdown_remaining < 0.0:
		return
	if not _both_ready(locker_ready):
		locker_countdown_remaining = -1.0
		_last_locker_countdown_second = -1
		_broadcast_state()
		state_changed.emit()
		return

	locker_countdown_remaining = maxf(locker_countdown_remaining - delta, 0.0)
	var next_countdown_second: int = int(ceil(locker_countdown_remaining))
	if next_countdown_second != _last_locker_countdown_second:
		_last_locker_countdown_second = next_countdown_second
		_broadcast_state()
		state_changed.emit()
	if locker_countdown_remaining <= 0.0:
		start_next_set()


func _update_locker_countdown_state() -> void:
	if _both_ready(locker_ready):
		if locker_countdown_remaining < 0.0:
			locker_countdown_remaining = GameSettings.ONLINE_LOCKER_COUNTDOWN_SECONDS
			_last_locker_countdown_second = int(ceil(locker_countdown_remaining))
	else:
		locker_countdown_remaining = -1.0
		_last_locker_countdown_second = -1


func _finish_kill_banner() -> void:
	_kill_banner_remaining = 0.0
	_kill_banner_deadline_msec = 0
	if _phase_after_banner == GameSettings.MATCH_PHASE_INTERMISSION:
		intermission_ready = GameSettings.default_ready_state()
		intermission_remaining = GameSettings.ONLINE_INTERMISSION_SECONDS
		_last_countdown_second = int(ceil(intermission_remaining))
		_set_phase(GameSettings.MATCH_PHASE_INTERMISSION, true)
	elif _phase_after_banner == GameSettings.MATCH_PHASE_FINAL:
		_set_phase(GameSettings.MATCH_PHASE_FINAL, true)
	else:
		_set_phase(GameSettings.MATCH_PHASE_PLAYING_SET, true)


func _finish_kill_banner_after_timeout(banner_generation: int) -> void:
	await get_tree().create_timer(GameSettings.ONLINE_KILL_BANNER_SECONDS, true).timeout
	if not _has_authority():
		return
	if phase != GameSettings.MATCH_PHASE_KILL_BANNER:
		return
	if banner_generation != _kill_banner_generation:
		return
	_finish_kill_banner()


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


# Replace synchronized containers in place so existing UI references remain valid.
func _apply_state(state: Dictionary) -> void:
	var incoming_generation: int = int(state.get("match_generation", match_generation))
	var generation_changed: bool = incoming_generation != match_generation
	if generation_changed:
		match_generation = incoming_generation
		if not _has_authority():
			_reset_local_client_progression()

	_apply_dictionary(state.get("player_colors", {}), player_colors, true)
	_apply_extension_loadouts(state.get("extension_loadouts", {}))
	_apply_armor_loadouts(state.get("armor_loadouts", {}))
	_apply_research_profiles(state.get("research_profiles", {}))
	_apply_dictionary(state.get("locker_ready", {}), locker_ready, false)
	_apply_dictionary(state.get("intermission_ready", {}), intermission_ready, false)
	_apply_dictionary(state.get("set_kills", {}), set_kills, false)
	_apply_dictionary(state.get("match_points", {}), match_points, false)
	_apply_dictionary(state.get("coin_balances", {}), coin_balances, false)
	_apply_nested_dictionary(state.get("last_set_earnings", {}), last_set_earnings)

	last_winner_slot = int(state.get("last_winner_slot", last_winner_slot))
	final_winner_slot = int(state.get("final_winner_slot", final_winner_slot))
	intermission_remaining = float(state.get("intermission_remaining", intermission_remaining))
	locker_countdown_remaining = float(state.get("locker_countdown_remaining", locker_countdown_remaining))

	var next_phase: StringName = StringName(str(state.get("phase", str(phase))))
	var previous_phase: StringName = phase
	phase = next_phase
	if phase != previous_phase:
		phase_changed.emit(phase)
	state_changed.emit()
	countdown_changed.emit(int(ceil(intermission_remaining)))
	if generation_changed and not _has_authority():
		call_deferred("_request_local_research_profile")


func _reset_local_client_progression() -> void:
	RoundRewardInventory.reset_match()
	ExtensionInventory.reset_match()
	ArmorInventory.reset_match()
	ResearchManager.reset_for_new_game()
	ResearchQuestManager.reset_match()


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


func _apply_extension_loadouts(source_variant: Variant) -> void:
	extension_loadouts = GameSettings.default_extension_loadouts()
	if not (source_variant is Dictionary):
		return

	var source: Dictionary = source_variant
	for raw_slot in source.keys():
		var slot: int = int(raw_slot)
		if not _is_player_slot(slot):
			continue

		var loadout_variant: Variant = source[raw_slot]
		if loadout_variant is Dictionary:
			var loadout_data: Dictionary = loadout_variant
			extension_loadouts[slot] = loadout_data.duplicate(true)


func _apply_armor_loadouts(source_variant: Variant) -> void:
	armor_loadouts = GameSettings.default_armor_loadouts()
	if not (source_variant is Dictionary):
		return

	var source: Dictionary = source_variant
	for raw_slot in source.keys():
		var slot: int = int(raw_slot)
		if not _is_player_slot(slot):
			continue

		var loadout_variant: Variant = source[raw_slot]
		if loadout_variant is Dictionary:
			var loadout_data: Dictionary = loadout_variant
			armor_loadouts[slot] = loadout_data.duplicate(true)


func _apply_research_profiles(source_variant: Variant) -> void:
	research_profiles.clear()
	if source_variant is Dictionary:
		var source: Dictionary = source_variant
		for raw_slot in source.keys():
			var slot: int = int(raw_slot)
			if not _is_player_slot(slot):
				continue
			var profile_variant: Variant = source[raw_slot]
			if profile_variant is Dictionary:
				var profile: Dictionary = profile_variant
				research_profiles[slot] = profile.duplicate(true)
	_apply_research_profiles_to_manager()


func _apply_research_profiles_to_manager() -> void:
	ResearchManager.apply_online_profiles(research_profiles)


func _request_local_research_profile() -> void:
	set_local_research_profile(ResearchManager.get_local_profile())


func _apply_nested_dictionary(source_variant: Variant, target: Dictionary) -> void:
	target.clear()
	if not (source_variant is Dictionary):
		return
	var source: Dictionary = source_variant
	for raw_slot in source.keys():
		var slot: int = int(raw_slot)
		if not _is_player_slot(slot):
			continue
		var value_variant: Variant = source[raw_slot]
		if value_variant is Dictionary:
			var value: Dictionary = value_variant
			target[slot] = value.duplicate(true)


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


# The host validates requests; clients consume only authoritative state snapshots.
func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	var payload: Dictionary = _get_payload(packet)

	if packet_type == GameSettings.PACKET_ONLINE_MATCH_STATE:
		if not _has_authority():
			_apply_state(payload)
	elif packet_type == GameSettings.PACKET_ONLINE_PLAYER_COLOR and _has_authority():
		var color_slot: int = _slot_from_packet(packet)
		var color_id: StringName = StringName(str(payload.get("color_id", "")))
		set_player_color(color_slot, color_id)
	elif packet_type == GameSettings.PACKET_ONLINE_EXTENSION_LOADOUT and _has_authority():
		var loadout_variant: Variant = payload.get("loadout", {})
		if loadout_variant is Dictionary:
			var loadout_data: Dictionary = loadout_variant
			set_extension_loadout(_slot_from_packet(packet), loadout_data)
	elif packet_type == GameSettings.PACKET_ONLINE_ARMOR_LOADOUT and _has_authority():
		var loadout_variant: Variant = payload.get("loadout", {})
		if loadout_variant is Dictionary:
			var loadout_data: Dictionary = loadout_variant
			set_armor_loadout(_slot_from_packet(packet), loadout_data)
	elif packet_type == GameSettings.PACKET_ONLINE_LOCKER_READY and _has_authority():
		set_locker_ready(_slot_from_packet(packet), payload.get("ready", false) == true)
	elif packet_type == GameSettings.PACKET_ONLINE_INTERMISSION_READY and _has_authority():
		set_intermission_ready(_slot_from_packet(packet), payload.get("ready", false) == true)
	elif packet_type == GameSettings.PACKET_ONLINE_COIN_SPEND and _has_authority():
		_apply_coin_spend_request(_slot_from_packet(packet), int(payload.get("cost", 0)))
	elif packet_type == GameSettings.PACKET_ONLINE_RESEARCH_PROFILE and _has_authority():
		var profile_variant: Variant = payload.get("profile", {})
		if profile_variant is Dictionary:
			var profile: Dictionary = profile_variant
			set_research_profile(_slot_from_packet(packet), profile)
	elif packet_type == GameSettings.PACKET_ONLINE_COIN_ADD and _has_authority():
		_apply_coin_add_request(_slot_from_packet(packet), int(payload.get("amount", 0)))


func _apply_coin_spend_request(slot: int, cost: int) -> void:
	if not _is_player_slot(slot):
		return
	if cost <= 0 or cost > _max_coin_spend():
		return
	if get_coin_balance(slot) < cost:
		_broadcast_state()
		return
	coin_balances[slot] = get_coin_balance(slot) - cost
	_broadcast_state()
	state_changed.emit()


func _apply_coin_add_request(slot: int, amount: int) -> void:
	if not _is_player_slot(slot):
		return
	if amount <= 0 or amount > GameSettings.SHOP_MAX_PRICE:
		return
	coin_balances[slot] = get_coin_balance(slot) + amount
	_broadcast_state()
	state_changed.emit()


func _max_coin_spend() -> int:
	return maxi(GameSettings.SHOP_MAX_PRICE, maxi(GameSettings.EXTENSION_MERGE_MK3_COST, GameSettings.ARMOR_MERGE_MK3_COST))


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
