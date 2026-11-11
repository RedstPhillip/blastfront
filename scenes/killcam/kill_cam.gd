class_name KillCam
extends Node2D

## The kill cam: a short slow-motion replay of how a round was won, played inside the kill banner (the pause
## between a knockout and the next round). It never makes that pause longer: the replay is paced to fit the
## banner's time, the banner's own timer ends it wherever it is, and only a match-winning replay may carry
## on behind the results screen (nothing waits for it there).
##
## How it works: a KillCamRecorder keeps the last seconds of every round (poses, rounds in flight, one-shot
## events). The replay poses two puppet fighters, instances of the real player scene switched to replay mode
## (remote-style, no collision, no groups, no gameplay; see Player.pose_replay), and draws the recorded rounds
## with the projectile's own look, over the live world, whose fighters and rounds are only hidden meanwhile.
## This was picked over a frozen copy of the scene or posing the live bodies: the live world keeps running
## untouched (physics, network snapshots and the round flow never see the replay, so nothing has to be
## restored but visibility), and the puppets reuse every bit of the fighter drawing (legs, arms, gun and
## parts, armour, face, slide/swim/wall poses, slow-time tint) without copying terrain, hazards or shaders.
##
## When: the host's (or the offline game's) kill decides. In the set flow the kill banner phase starts it
## with the host's description of the kill (OnlineMatch.last_kill); in first-to-N bot duels the point does.
## Each peer replays from its own record, so neither waits on the other. Never in the sandbox; the setting
## (UserSettings.KILL_CAM) picks which kills, Easy bots only with KILL_CAM_EASY_BOTS.

signal replay_started(label: String)
signal replay_finished

enum Tier { ROUND, SET, MATCH }

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

## What each replay shows: game seconds before the knockout (lead) and after it (tail), where the slow
## part starts before it (slow_lead) and its pace, a hold on the winner at the end (real seconds) and how
## much real time it may take (0: the banner's, less the live beat and a margin).
const PROFILES: Dictionary = {
	Tier.ROUND: {"lead": 1.5, "slow_lead": 0.3, "tail": 0.22, "slow": 0.55, "hold": 0.0, "budget": 0.0},
	Tier.SET: {"lead": 1.8, "slow_lead": 0.4, "tail": 0.28, "slow": 0.45, "hold": 0.0, "budget": 0.0},
	Tier.MATCH: {"lead": 2.4, "slow_lead": 0.55, "tail": 0.4, "slow": 0.4, "hold": 0.9, "budget": 3.4},
}
## Real seconds the knockout plays live (hitstop, burst, banner landing) before the replay cuts in.
const LIVE_BEAT: float = 0.25
## Real seconds left at the banner's end so the replay is over before the next round's respawn.
const BANNER_MARGIN: float = 0.12
## The lead-up may run faster than real time to fit; never faster than this.
const MAX_FAST_PACE: float = 3.0
## Game seconds over which the pace eases from the lead-up's into the slow part.
const PACE_RAMP: float = 0.3
## A throw this recent (game seconds) still counts for a hazard kill or a slam.
const SHOVE_WINDOW: float = 2.5
## The last damage note older than this (game seconds) no longer names the kill.
const DAMAGE_WINDOW: float = 4.0
const SNIPER_RANGE: float = 600.0
const FRAME_PADDING: Vector2 = Vector2(210.0, 140.0)
const MAX_ZOOM: float = 1.5
const DESATURATE: float = 0.3

var _game: Game = null
var _screen_fx: Node = null
var _recorder: KillCamRecorder = KillCamRecorder.new()
var _fighters: Array[Player] = []
var _puppets: Array[Player] = []
var _caption: KillCamCaption = null
var _damage_notes: Dictionary = {}
var _shove_notes: Dictionary = {}
var _style_cache: Dictionary = {}
## A kill waiting out the live beat: {tier, victim, killer, kill}.
var _pending: Dictionary = {}
var _plan: Dictionary = {}
var _playing: bool = false
var _holding: bool = false
var _hold_left: float = 0.0
var _t: float = 0.0
var _wall: float = 0.0
var _since_trigger: float = 0.0
var _death_shown: bool = false
var _seen_rounds: Dictionary = {}
var _slows_world: bool = true
var _decals_since: int = 0
## What the last kill did with the kill cam (tests read it): tier, label, highlight, played, reason.
var last_decision: Dictionary = {}


## Called by the game once its fighters are configured. In the sandbox the kill cam stays off entirely.
func setup(game: Game) -> void:
	_game = game
	name = "KillCam"
	_screen_fx = game.get_node_or_null(^"ScreenFx")
	if NetworkSession.is_training():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	_fighters = [game.get_player_by_slot(GameSettings.PLAYER_ONE_SLOT), game.get_player_by_slot(GameSettings.PLAYER_TWO_SLOT)]
	KillLog.listener = self
	OnlineMatch.phase_changed.connect(_on_phase_changed)
	game.point_awarded.connect(_on_point_awarded)
	_build_puppets()
	_build_caption()


func _exit_tree() -> void:
	stop()
	if KillLog.listener == self:
		KillLog.listener = null
	if OnlineMatch.phase_changed.is_connected(_on_phase_changed):
		OnlineMatch.phase_changed.disconnect(_on_phase_changed)


func is_playing() -> bool:
	return _playing


func get_recorder() -> KillCamRecorder:
	return _recorder


## A new round starts (respawn): the old record and notes are dropped, a replay still running ends.
func on_round_reset() -> void:
	stop()
	_recorder.reset()
	_damage_notes.clear()
	_shove_notes.clear()


func _physics_process(delta: float) -> void:
	if _playing or _game == null:
		return
	_recorder.record(delta, _fighters, _game.get_projectiles_root())


func _process(delta: float) -> void:
	var real_delta: float = minf(delta / maxf(Engine.time_scale, 0.0001), 0.1)
	if not _pending.is_empty():
		_since_trigger += real_delta
		if _since_trigger >= LIVE_BEAT:
			var trigger: Dictionary = _pending
			_pending = {}
			_begin(trigger)
		return
	if _playing:
		_since_trigger += real_delta
		_advance(real_delta)


# --- When ---------------------------------------------------------------------------------------------

func _on_phase_changed(next_phase: StringName) -> void:
	if next_phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_on_kill_banner()
	elif next_phase != GameSettings.MATCH_PHASE_FINAL:
		stop()


func _on_kill_banner() -> void:
	if not NetworkSession.uses_set_flow():
		return
	var winner: int = OnlineMatch.last_winner_slot
	if winner != GameSettings.PLAYER_ONE_SLOT and winner != GameSettings.PLAYER_TWO_SLOT:
		return
	var tier: Tier = Tier.ROUND
	if int(OnlineMatch.match_points.get(winner, 0)) >= GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN:
		tier = Tier.MATCH
	elif int(OnlineMatch.set_kills.get(winner, 0)) >= GameSettings.ONLINE_SET_KILLS_TO_WIN:
		tier = Tier.SET
	_trigger(tier, _other(winner), winner, OnlineMatch.last_kill.duplicate(), true)


func _on_point_awarded(winner: int) -> void:
	if NetworkSession.uses_set_flow() or NetworkSession.is_training():
		return
	var tier: Tier = Tier.MATCH if _game.get_score_for_slot(winner) >= _game.get_wins_needed() else Tier.ROUND
	var victim: int = _other(winner)
	_trigger(tier, victim, winner, describe_kill(victim), false)


func _trigger(tier: Tier, victim: int, killer: int, kill: Dictionary, set_flow: bool) -> void:
	stop()
	var reason: String = _refusal(tier, kill, set_flow)
	last_decision = {
		"tier": tier,
		"label": str(kill.get("label", "")),
		"highlight": kill.get("highlight", false) == true,
		"played": false,
		"reason": reason,
	}
	if reason != "":
		return
	if kill.is_empty():
		kill = describe_kill(victim)
	_pending = {"tier": tier, "victim": victim, "killer": killer, "kill": kill}
	_since_trigger = 0.0


## Why this kill gets no replay ("" when it does).
func _refusal(tier: Tier, kill: Dictionary, set_flow: bool) -> String:
	if NetworkSession.is_training():
		return "sandbox"
	var mode: int = UserSettings.get_int(UserSettings.KILL_CAM)
	if mode == UserSettings.KILL_CAM_OFF:
		return "off"
	if NetworkSession.is_bot_duel() and UserSettings.get_int(UserSettings.BOT_DIFFICULTY) == BotBrain.Difficulty.EASY \
			and not UserSettings.get_bool(UserSettings.KILL_CAM_EASY_BOTS):
		return "easy bot"
	if tier != Tier.ROUND:
		return ""
	if mode == UserSettings.KILL_CAM_FINAL:
		return "final kills only"
	# In sets an ordinary mid-set kill needs to stand out; in a first-to-N duel every point wins a round.
	if set_flow and kill.get("highlight", false) != true:
		return "plain kill"
	return ""


# --- What happened (host / offline) ------------------------------------------------------------------

func _on_damage_noted(target: Node, cause: StringName, data: Dictionary) -> void:
	var player: Player = target as Player
	if player == null or player.replay_puppet:
		return
	_damage_notes[player.player_slot] = {"cause": cause, "data": data, "t": _recorder.clock}


func _on_shove_noted(target: Node, source_slot: int, kind: StringName) -> void:
	var player: Player = target as Player
	if player == null or player.replay_puppet:
		return
	var previous: Dictionary = _shove_notes.get(player.player_slot, {})
	# The slam's own throw is noted first; the shove it causes right after must not rename it.
	if kind == &"impact" and previous.get("kind", &"") == &"slam" and _recorder.clock - float(previous.get("t", -99.0)) < 0.1:
		return
	_shove_notes[player.player_slot] = {"kind": kind, "source": source_slot if source_slot > 0 else _other(player.player_slot), "t": _recorder.clock}


func _on_event_noted(kind: StringName, world_position: Vector2, data: Dictionary) -> void:
	if not _playing:
		_recorder.add_event(kind, world_position, data)


## Names the kill of victim_slot from the notes taken during the round: the line under the replay
## ("Ricochet · Bouncy Bullets MK III", "Slam", "Into the fire", "Sniper · 740 px") and whether it stands
## out. Called on the host (OnlineMatch.record_kill) or offline at the knockout.
func describe_kill(victim_slot: int) -> Dictionary:
	var killer: int = _other(victim_slot)
	var now: float = _recorder.clock
	var damage: Dictionary = _damage_notes.get(victim_slot, {})
	if not damage.is_empty() and now - float(damage["t"]) > DAMAGE_WINDOW:
		damage = {}
	var shove: Dictionary = _shove_notes.get(victim_slot, {})
	var shoved: bool = not shove.is_empty() and now - float(shove["t"]) <= SHOVE_WINDOW and int(shove["source"]) == killer
	var cause: StringName = damage.get("cause", &"")
	var data: Dictionary = damage.get("data", {})
	var label: String = "Knockout"
	var highlight: bool = false
	var hazard: bool = cause in [&"fire", &"shark", &"border"]
	if shoved and shove["kind"] == &"slam":
		label = "Slam"
		if hazard:
			label += " · " + _hazard_phrase(cause, true)
		highlight = true
	elif hazard:
		label = _hazard_phrase(cause, shoved)
		highlight = shoved
		if cause == &"fire" and not shoved and int(data.get("slot", 0)) == killer:
			label += " · " + _part_name(killer, "fire_rounds_mk1")
	elif cause == &"round":
		var named: Array = _round_label(data, killer)
		label = named[0]
		highlight = named[1]
	elif cause == &"status":
		label = {&"burn": "Burned", &"poison": "Poisoned", &"shock": "Shocked"}.get(StringName(str(data.get("effect", ""))), "Knockout")
	var victim_flags: int = _recorder.flags_at(victim_slot - 1, _recorder.newest_time()) if _recorder.frame_count() > 0 else 0
	if victim_flags & (KillCamRecorder.FLAG_SLOWED | KillCamRecorder.FLAG_FROZEN):
		var frozen: bool = (victim_flags & KillCamRecorder.FLAG_FROZEN) != 0
		if not highlight:
			label = ("Frozen in time" if frozen else "Caught in slow time") + ("" if label == "Knockout" else " · " + label)
		highlight = true
	return {"label": label, "highlight": highlight, "victim": victim_slot, "killer": killer}


func _hazard_phrase(cause: StringName, shoved: bool) -> String:
	match cause:
		&"fire":
			return "Into the fire" if shoved else "Burned"
		&"shark":
			return "Fed to the sharks" if shoved else "Shark"
		_:
			return "Over the edge" if shoved else "Out of bounds"


## [label, highlight] for a kill by a round.
func _round_label(data: Dictionary, killer: int) -> Array:
	var extensions: Array = data.get("extensions", [])
	var distance: float = float(data.get("distance", 0.0))
	if data.get("bounced", false) == true:
		return ["Ricochet · " + _part_name(killer, "bouncy_bullets_mk1"), true]
	if int(data.get("walls", 0)) > 0:
		return ["Through the wall · " + _part_name(killer, "drill_bullets_mk1"), true]
	if extensions.has("sniper_barrel_mk1") and distance > SNIPER_RANGE:
		return ["Sniper · %d px" % int(roundf(distance / 10.0) * 10.0), true]
	if extensions.has("explosive_bullet_mk1"):
		return ["Blast · " + _part_name(killer, "explosive_bullet_mk1"), false]
	if extensions.has("grenades_mk1"):
		return ["Grenade · " + _part_name(killer, "grenades_mk1"), false]
	var look: String = str(data.get("look", ""))
	return [_part_name(killer, look) if look != "" else "Knockout", false]


## "Bouncy Bullets MK III": the part as the killer has it equipped, else its plain name.
func _part_name(slot: int, extension_id: String) -> String:
	for item_variant in ExtensionInventory.get_equipped_for_player(slot).values():
		var item: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if item != null and str(item.get_definition_id()) == extension_id:
			return "%s MK %s" % [LoadoutStyle.base_name(item.get_display_name()), LoadoutStyle.roman(item.mark)]
	var definition: WeaponExtensionDefinition = ExtensionInventory.get_definition(StringName(extension_id))
	if definition != null:
		return LoadoutStyle.base_name(definition.display_name)
	return extension_id.trim_suffix("_mk1").capitalize()


# --- Playing it -----------------------------------------------------------------------------------------

func _begin(trigger: Dictionary) -> void:
	var tier: Tier = trigger["tier"]
	var victim: int = trigger["victim"]
	var victim_index: int = victim - 1
	var t_kill: float = _recorder.elimination_time(victim_index)
	if t_kill == INF or _recorder.frame_count() < 20:
		last_decision["reason"] = "no record"
		return
	var profile: Dictionary = PROFILES[tier]
	var budget: float = float(profile["budget"])
	if budget <= 0.0:
		budget = GameSettings.POINT_TRANSITION_SECONDS - LIVE_BEAT - BANNER_MARGIN
	var round_id: float = _recorder.killing_round(victim_index, t_kill)
	var t_start: float = maxf(t_kill - float(profile["lead"]), _recorder.oldest_time())
	if round_id >= 0.0:
		# The killing round's whole flight, when it was fired a little before the clip would start.
		var fired: float = _recorder.first_seen(round_id, t_kill - float(profile["lead"]) - 1.0, t_kill)
		if fired < t_start:
			t_start = maxf(fired - 0.12, _recorder.oldest_time())
	var kill: Dictionary = trigger["kill"]
	var plan: Dictionary = {
		"tier": tier,
		"victim": victim,
		"killer": int(trigger["killer"]),
		"label": str(kill.get("label", "Knockout")),
		"t_start": t_start,
		"t_kill": t_kill,
		"t_end": minf(t_kill + float(profile["tail"]), _recorder.newest_time()),
		"slow_lead": float(profile["slow_lead"]),
		"slow": float(profile["slow"]),
		"fast": 1.0,
		"boost": 1.0,
		"hold": float(profile["hold"]),
		"budget": budget,
		"round": round_id,
	}
	_fit_pace(plan)
	_plan = plan
	_playing = true
	_holding = false
	_t = t_start
	_wall = 0.0
	_death_shown = false
	_seen_rounds.clear()
	_slows_world = not NetworkSession.is_steam_match_active()
	_hide_live(true)
	_decals_since = _recorder.msec_at(t_start)
	ImpactDecals.set_hidden_since(_decals_since, true)
	GameJuice.clear_damage_numbers()
	for effect in get_tree().get_nodes_in_group(GameJuice.TRANSIENT_FX_GROUP):
		(effect as CanvasItem).visible = false
	FxLib.hide_live_emitters()
	AudioDirector.world_muted = true
	for index in range(_puppets.size()):
		var puppet: Player = _puppets[index]
		var fighter: Player = _fighters[index]
		if fighter != null and is_instance_valid(fighter):
			puppet.set_player_color(fighter.player_color_id)
			puppet.z_index = fighter.z_index
		puppet.process_mode = Node.PROCESS_MODE_INHERIT
	_set_world_pace(_pace(plan, _t))
	_show_frame(_t, _t, true)
	last_decision["played"] = true
	last_decision["plan"] = plan.duplicate()
	var killer_color: Color = _puppets[int(plan["killer"]) - 1].get_visual_tint()
	_caption.play(str(plan["label"]), killer_color, "B" if InputDevice.using_gamepad else "ESC")
	_game.snap_camera_to_kill_cam()
	GameJuice.flash(Color(1.0, 1.0, 1.0, 1.0), 0.16, 0.16)
	AudioDirector.play(&"ui_whoosh", -4.0, 0.8)
	replay_started.emit(str(plan["label"]))
	queue_redraw()


## Picks the lead-up's pace (and, if that is not enough, a later start, then an overall speed-up) so the clip
## fits its real-time budget, holds included.
func _fit_pace(plan: Dictionary) -> void:
	var budget: float = float(plan["budget"])
	var ramp_start: float = float(plan["t_kill"]) - float(plan["slow_lead"]) - PACE_RAMP
	if _wall_seconds(plan, 1.0) > budget:
		if _wall_seconds(plan, MAX_FAST_PACE) > budget:
			plan["fast"] = MAX_FAST_PACE
			while float(plan["t_start"]) < ramp_start - 0.05 and _wall_seconds(plan, MAX_FAST_PACE) > budget:
				plan["t_start"] = float(plan["t_start"]) + 0.05
		else:
			var low: float = 1.0
			var high: float = MAX_FAST_PACE
			for _step in range(14):
				var middle: float = (low + high) * 0.5
				if _wall_seconds(plan, middle) > budget:
					low = middle
				else:
					high = middle
			plan["fast"] = high
	var wall: float = _wall_seconds(plan, float(plan["fast"]))
	if wall > budget:
		plan["boost"] = wall / budget
		wall = budget
	plan["wall"] = wall


func _wall_seconds(plan: Dictionary, fast: float) -> float:
	var step: float = 1.0 / 120.0
	var total: float = 0.0
	var t: float = float(plan["t_start"])
	var end: float = float(plan["t_end"])
	var saved: float = float(plan["fast"])
	plan["fast"] = fast
	while t < end:
		total += minf(step, end - t) / _pace(plan, t)
		t += step
	plan["fast"] = saved
	return total


## Game seconds per real second at game time t: the lead-up's pace, easing into the slow part before the
## knockout.
func _pace(plan: Dictionary, t: float) -> float:
	var ramp_end: float = float(plan["t_kill"]) - float(plan["slow_lead"])
	var ramp_start: float = ramp_end - PACE_RAMP
	var fast: float = float(plan["fast"])
	var slow: float = float(plan["slow"])
	var pace: float = slow
	if t <= ramp_start:
		pace = fast
	elif t < ramp_end:
		pace = lerpf(fast, slow, smoothstep(ramp_start, ramp_end, t))
	return pace * float(plan["boost"])


func _advance(real_delta: float) -> void:
	_wall += real_delta
	if _screen_fx != null:
		_screen_fx.call(&"set_desaturate", DESATURATE)
	if _since_trigger > GameSettings.POINT_TRANSITION_SECONDS:
		_caption.set_skippable(false)
	if _holding:
		_hold_left -= real_delta
		_caption.set_progress(1.0, 1.0)
		if _hold_left <= 0.0:
			stop()
		return
	var pace: float = _pace(_plan, _t)
	var previous: float = _t
	_t = minf(_t + real_delta * pace, float(_plan["t_end"]))
	_set_world_pace(pace)
	_show_frame(previous, _t, false)
	var span: float = maxf(float(_plan["t_end"]) - float(_plan["t_start"]), 0.001)
	_caption.set_progress((_t - float(_plan["t_start"])) / span, pace)
	queue_redraw()
	if _t >= float(_plan["t_end"]) or _wall >= float(_plan["budget"]):
		if float(_plan["hold"]) > 0.0:
			_holding = true
			_hold_left = float(_plan["hold"])
			_set_world_pace(1.0)
		else:
			stop()


## The world runs at the replay's pace (offline; online it keeps real time, the puppets alone slow down) and
## the puppets animate at it either way.
func _set_world_pace(pace: float) -> void:
	GameJuice.hold_time_scale(clampf(pace, 0.05, 1.0) if _slows_world else 1.0)
	for puppet in _puppets:
		puppet.replay_rate = pace / maxf(Engine.time_scale, 0.05)


## Poses everything at game time t; what happened since previous (hits, the knockout, shots, events) plays.
func _show_frame(previous: float, t: float, snap: bool) -> void:
	var victim_index: int = int(_plan["victim"]) - 1
	var t_kill: float = float(_plan["t_kill"])
	for index in range(_puppets.size()):
		var puppet: Player = _puppets[index]
		var pose: Dictionary = _recorder.sample_fighter(index, t)
		if index == victim_index and not _death_shown and t >= t_kill:
			_death_shown = true
			if not snap:
				puppet.replay_death()
				_on_knockout_moment()
		if (int(pose["flags"]) & KillCamRecorder.FLAG_ELIMINATED) != 0:
			puppet.visible = false
			continue
		var appearing: bool = not puppet.visible
		puppet.visible = true
		puppet.pose_replay(pose, snap or appearing)
		if not snap:
			var before: int = _recorder.health_at(index, previous)
			var now: int = int(pose["health"])
			if now < before:
				puppet.replay_hit(_puppets[1 - index].global_position, before - now)
	var rounds: PackedFloat32Array = _recorder.rounds_at(t)
	for i in range(0, rounds.size(), KillCamRecorder.ROUND_STRIDE):
		var id: float = rounds[i]
		if _seen_rounds.has(id):
			continue
		_seen_rounds[id] = true
		if not snap:
			var style: Dictionary = _style(int(rounds[i + 5]))
			GameJuice.spawn_muzzle(Vector2(rounds[i + 1], rounds[i + 2]), Vector2.RIGHT.rotated(rounds[i + 3]), (style["body_color"] as Color).lightened(0.3), maxf(rounds[i + 6], 0.7))
	if not snap:
		for event in _recorder.events_between(previous, t):
			_replay_event(event)


func _on_knockout_moment() -> void:
	AudioDirector.play(&"hit_heavy", 0.0, 0.72)
	AudioDirector.play(&"death", -3.0, 0.8)
	_caption.punch()


func _replay_event(event: Dictionary) -> void:
	var at: Vector2 = event["position"]
	var data: Dictionary = event["data"]
	match StringName(event["kind"]):
		&"blast":
			var power: float = clampf(float(data.get("radius", 80.0)) / 80.0, 0.6, 2.2)
			GameJuice.spawn_burst(&"explosion", at, Vector2.UP, data.get("tint", Color(1.0, 0.55, 0.18, 1.0)), power)
			GameJuice.shockwave(at, 0.9 * power)
			GameJuice.add_trauma(0.25 * power)
		&"fire":
			GameJuice.spawn_burst(&"explosion", at, Vector2.UP, Color(1.0, 0.5, 0.16, 1.0), 0.45)
		&"shockwave":
			var slot: int = int(data.get("slot", 1))
			var tint: Color = _puppets[clampi(slot - 1, 0, 1)].get_visual_tint()
			if data.get("slam", false) == true:
				GameJuice.spawn_burst(&"dash_shockwave", at, Vector2.LEFT, tint)
				GameJuice.spawn_burst(&"dash_shockwave", at, Vector2.RIGHT, tint)
				GameJuice.spawn_burst(&"land", at, Vector2.UP, Color(0.78, 0.70, 0.54, 0.8), 1.4)
				GameJuice.shockwave(at, 0.6, 0.45)
			else:
				GameJuice.spawn_burst(&"dash_shockwave", at, Vector2(float(data.get("direction", 1.0)), 0.0), tint)
				GameJuice.shockwave(at, 0.45, 0.35)
		&"breach":
			GameJuice.spawn_burst(&"splash", at, Vector2.UP, Color.WHITE, 1.6)
			GameJuice.spawn_burst(&"splash", at + Vector2(-float(data.get("direction", 1.0)) * 34.0, 0.0), Vector2.UP, Color.WHITE, 1.0)


## Ends the replay (or a kill still waiting out the live beat) and gives the live world back exactly as it
## was: visibility, sound, desaturation and Engine.time_scale (1).
func stop() -> void:
	_pending = {}
	if not _playing:
		return
	_playing = false
	_holding = false
	for puppet in _puppets:
		puppet.visible = false
		puppet.time_scale = 1.0
		puppet.replay_rate = 1.0
		puppet.process_mode = Node.PROCESS_MODE_DISABLED
	_hide_live(false)
	ImpactDecals.set_hidden_since(_decals_since, false)
	AudioDirector.world_muted = false
	GameJuice.release_time_scale()
	if _screen_fx != null:
		_screen_fx.call(&"set_desaturate", 0.0)
	if _caption != null:
		_caption.dismiss()
	queue_redraw()
	replay_finished.emit()


func _hide_live(hidden: bool) -> void:
	for fighter in _fighters:
		if fighter != null and is_instance_valid(fighter):
			fighter.visible = false if hidden else not fighter.is_eliminated()
	var rounds_root: Node2D = _game.get_projectiles_root() if _game != null else null
	if rounds_root != null:
		rounds_root.visible = not hidden


## Skipped with a confirm or back input (not one that also plays: jump on Space, a pad's A). Only while the
## banner is up; a match-winning replay running behind the results leaves their buttons alone.
func _input(event: InputEvent) -> void:
	if not _playing or _since_trigger > GameSettings.POINT_TRANSITION_SECONDS:
		return
	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		last_decision["skipped"] = true
		stop()


static func _is_skip_event(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction):
		return false
	for action in InputMap.get_actions():
		if str(action).begins_with("p1_") and event.is_action(action):
			return false
	if event.is_action(&"ui_accept") or event.is_action(&"ui_cancel") or event.is_action(GameSettings.INPUT_PAUSE):
		return true
	var key: InputEventKey = event as InputEventKey
	return key != null and key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]


# --- Camera and drawing ---------------------------------------------------------------------------------

## Where the game camera looks while the replay plays: both fighters (the fallen one a moment longer) and the
## killing round while it flies; on the winner during the hold. Never wider than the normal view.
func camera_frame(view_size: Vector2, base_zoom: float) -> Dictionary:
	var winner_index: int = int(_plan["killer"]) - 1
	var victim_index: int = int(_plan["victim"]) - 1
	var t_kill: float = float(_plan["t_kill"])
	var points: Array[Vector2] = []
	if _holding:
		points.append(_recorder.position_at(winner_index, _t))
	else:
		for index in range(2):
			var down: bool = (_recorder.flags_at(index, _t) & KillCamRecorder.FLAG_ELIMINATED) != 0
			if not down or (index == victim_index and _t - t_kill < 0.6):
				points.append(_recorder.position_at(index, _t))
		var round_id: float = float(_plan["round"])
		if round_id >= 0.0 and _t <= t_kill + 0.05:
			var round_at: Vector2 = _recorder.round_position(round_id, _t)
			if round_at != Vector2.INF:
				points.append(round_at)
	if points.is_empty():
		points.append(_recorder.position_at(winner_index, _t))
	var rect: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	rect = rect.grow_individual(FRAME_PADDING.x, FRAME_PADDING.y, FRAME_PADDING.x, FRAME_PADDING.y * 0.7)
	var zoom: float = minf(view_size.x / maxf(rect.size.x, 1.0), view_size.y / maxf(rect.size.y, 1.0))
	zoom = clampf(zoom * (1.12 if _holding else 1.0), base_zoom, MAX_ZOOM)
	return {"focus": rect.get_center(), "zoom": zoom}


func _draw() -> void:
	if not _playing:
		return
	var rounds: PackedFloat32Array = _recorder.rounds_at(_t)
	for i in range(0, rounds.size(), KillCamRecorder.ROUND_STRIDE):
		var at: Vector2 = Vector2(rounds[i + 1], rounds[i + 2])
		var rotation_angle: float = rounds[i + 3]
		var speed: float = rounds[i + 4]
		var style: Dictionary = _style(int(rounds[i + 5]))
		var round_scale: float = maxf(rounds[i + 6], 0.5)
		var body: Color = style["body_color"]
		var direction: Vector2 = Vector2.RIGHT.rotated(rotation_angle)
		# The tracer streak the live round draws, longer for faster rounds.
		var streak: float = (clampf(speed * 0.085, 60.0, 250.0) + 30.0 * round_scale) * 0.6
		var trail: PackedVector2Array = PackedVector2Array([at - direction * streak, at - direction * streak * 0.4, at])
		var trail_colors: PackedColorArray = PackedColorArray([Color(body, 0.0), Color(body.lightened(0.15), 0.35), Color(body.lightened(0.3), 0.85)])
		draw_polyline_colors(trail, trail_colors, 3.2 * maxf(round_scale, 0.6), true)
		draw_circle(at, 7.0 * round_scale, Color(body, 0.16))
		draw_set_transform(at, rotation_angle, Vector2.ONE * round_scale)
		draw_colored_polygon(style["outline_points"], style["outline_color"])
		draw_colored_polygon(style["body_points"], body)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _style(index: int) -> Dictionary:
	if not _style_cache.has(index):
		var extension_id: String = Projectile.VISUAL_PRIORITY[index - 1] if index > 0 and index <= Projectile.VISUAL_PRIORITY.size() else ""
		_style_cache[index] = Projectile.visual_style_for(extension_id)
	return _style_cache[index]


# --- Building ---------------------------------------------------------------------------------------------

## The two puppets are made once, when the game starts, and stay disabled and hidden until a replay: a
## replay never instantiates anything, and rounds pay nothing for them.
func _build_puppets() -> void:
	for slot in [GameSettings.PLAYER_ONE_SLOT, GameSettings.PLAYER_TWO_SLOT]:
		var puppet: Player = PLAYER_SCENE.instantiate() as Player
		puppet.name = "ReplayFighter%d" % slot
		puppet.replay_puppet = true
		puppet.control_mode = GameSettings.CONTROL_REMOTE
		puppet.player_slot = slot
		puppet.visible = false
		puppet.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(puppet)
		puppet.collision_layer = 0
		puppet.collision_mask = 0
		puppet.get_gun().process_mode = Node.PROCESS_MODE_DISABLED
		_puppets.append(puppet)


func _build_caption() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "KillCamLayer"
	# Over the screen effects (the replay's grade leaves the caption alone), under the HUD's banner.
	layer.layer = 3
	add_child(layer)
	_caption = KillCamCaption.new()
	layer.add_child(_caption)


func _other(slot: int) -> int:
	return GameSettings.PLAYER_TWO_SLOT if slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT
