extends SyncModule

## Online Time Control. The host owns every cast: a client only asks, the host checks it against the same
## rules as offline (playing set, no kill banner, cooldown, research mark), applies it and replays it on the
## client. Each side then runs the slow on its own clocks, so a slowed client simulates its own player
## slowed and both sides slow (or freeze) the same player's rounds. The host's world snapshot carries every
## player's remaining slow, freeze and cooldown so the client can line up with it (a late packet, a missed
## one, a round reset in between); anything outside a playing set is ignored and cleared.

func get_module_name() -> StringName:
	return GameSettings.MODULE_TIME


func get_packet_types() -> Array[StringName]:
	return [
		GameSettings.PACKET_TIME_CAST_REQUEST,
		GameSettings.PACKET_TIME_CAST,
	]


## Client: the local player pressed Time Control. The host answers with a cast packet, or not at all.
func request_cast() -> void:
	if game_sync == null or not game_sync.is_network_active() or game_sync.is_host():
		return
	game_sync.send_reliable(GameSettings.PACKET_TIME_CAST_REQUEST, {}, GameSettings.NETWORK_CHANNEL_EVENTS)


## Host: a cast went through here (see Game.cast_time_control); the client plays the same one.
func broadcast_cast(cast: Dictionary) -> void:
	if game_sync == null or not game_sync.is_host() or cast.is_empty():
		return
	game_sync.send_reliable(GameSettings.PACKET_TIME_CAST, cast, GameSettings.NETWORK_CHANNEL_EVENTS)


func handle_packet(packet: Dictionary) -> void:
	var payload: Dictionary = NetworkSession.get_payload(packet)
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	match packet_type:
		GameSettings.PACKET_TIME_CAST_REQUEST:
			if not game_sync.is_host():
				return
			# A client only ever casts for its own player, whatever the payload claims.
			var caster: Player = _get_player(int(packet.get("from_slot", 0)))
			if caster == null or caster.player_slot == game_sync.get_local_slot():
				return
			broadcast_cast(game.cast_time_control(caster))
		GameSettings.PACKET_TIME_CAST:
			if game_sync.is_host():
				return
			apply_cast(payload)


## Client: plays the host's cast. A cast that lands after the set stopped (kill banner, intermission, a
## phase change in flight) is dropped.
func apply_cast(cast: Dictionary) -> void:
	if not OnlineMatch.is_playing_set():
		return
	var caster: Player = _get_player(int(cast.get("caster", 0)))
	var duration: float = float(cast.get("duration", 0.0))
	var freeze: float = float(cast.get("freeze", 0.0))
	if caster == null or duration <= 0.0:
		return
	caster.begin_time_control_cooldown(float(cast.get("cooldown", 0.0)), duration + freeze)
	var targets: Variant = cast.get("targets", [])
	if not (targets is Array):
		return
	for raw_slot in targets:
		var target: Player = _get_player(int(raw_slot))
		if target != null and target != caster and not target.is_eliminated():
			target.apply_time_slow(float(cast.get("scale", 1.0)), duration, freeze)


func build_snapshot() -> Dictionary:
	if game_sync == null or not game_sync.is_host() or not OnlineMatch.is_playing_set():
		return {}
	var states: Dictionary = {}
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player != null:
			var state: Dictionary = player.get_time_state()
			if not state.is_empty():
				states[slot] = state
	return {"players": states}


func apply_snapshot(data: Dictionary) -> void:
	if not OnlineMatch.is_playing_set():
		return
	var states: Variant = data.get("players", {})
	if not (states is Dictionary):
		return
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player == null:
			continue
		var state: Variant = (states as Dictionary).get(slot, (states as Dictionary).get(str(slot), {}))
		player.sync_time_state(state if state is Dictionary else {})


## Slows never outlive the set: on both sides they end with it (kill banner, intermission, final).
func physics_sync_tick(_delta: float) -> void:
	if game_sync == null or not game_sync.is_network_active() or OnlineMatch.is_playing_set() or not TimeFlow.active:
		return
	for slot in GameSettings.player_slots():
		var player: Player = _get_player(slot)
		if player != null:
			player.reset_time_control_state()


func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)
