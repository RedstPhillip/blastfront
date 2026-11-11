class_name TidewaterSharks
extends Node2D

## The sharks of Tidewater. Two of them come up out of the chasms once a flood stands deep enough over the
## plaza, and go back down as it drains. They cruise under the temple's floors with the dorsal fin cutting
## the surface. Whoever stays in the water too long (GRACE seconds, less at a spring tide) is hunted: the
## nearest shark turns on them: the fin streaks in along the surface (if it is too close for a run-up it
## swims on past and swings round first), and from a couple of body lengths out it launches up and
## forward through the spot the swimmer is at, jaws open, and crashes back in beyond them. Caught, the swimmer takes BITE_DAMAGE and is
## thrown clear of the water; out of the water in time, or simply somewhere else when it arrives, and it
## misses. Being out of the water lets the timer run back down.
##
## Everything a shark does is steering: it has a velocity, wants another one, and gets there only as fast
## as a body that size can (ACCEL values), so it speeds up, glides, banks into turns and levels out
## instead of sliding about. Only the lunge itself follows a fixed curve, set when it starts.
##
## Online the host's sharks decide (WorldSync carries their state and every change of it), the client's
## copies steer the same way from the same numbers; the bite goes through CombatSync like any other hit,
## credited to the opponent the way the arena's border is. Bots already keep out of water they do not
## need to be in.

enum State { AWAY, ARRIVE, PATROL, RUSH, LUNGE, RECOVER, LEAVE }

const GRACE: float = 2.6
const SPRING_GRACE: float = 1.8
const BITE_DAMAGE: int = 30
const BITE_RADIUS: float = 46.0
const BITE_THROW: Vector2 = Vector2(240.0, -470.0)
## After a bite the same swimmer is left alone this long, however long they stay in.
const VICTIM_COOLDOWN: float = 2.4
## Spine depth under the surface while cruising: the dorsal fin stands a hand out of the water, and just
## clears the underside of a floor that stands over the water.
const CRUISE_DEPTH: float = 32.0
## From the spine up to the tip of the dorsal fin, and down to the belly.
const FIN_HEIGHT: float = 48.0
const BELLY_DEPTH: float = 26.0
const PATROL_SPEED: float = 96.0
const PATROL_ACCEL: float = 150.0
const RUSH_SPEED: float = 500.0
const RUSH_ACCEL: float = 1100.0
## A run-up: the shark comes in from at least RUN_UP px out; closer than that it swims away first.
const RUN_UP: float = 215.0
## Over the last stretch of the run-in it sinks this far under the swimmer, to come up at them.
const ATTACK_DEPTH: float = 74.0
## The leap goes off within this distance of the swimmer, once it is coming at them this fast.
const LUNGE_RANGE: float = 215.0
const LUNGE_ENTRY_SPEED: float = 300.0
const RUSH_LIMIT: float = 2.6
## The leap: up and forward at LUNGE_SPEED, passing through the swimmer, over the top and back in.
const LUNGE_SPEED: float = 700.0
const LUNGE_HEADING: Vector2 = Vector2(0.62, -0.78)
const LUNGE_RISE_LIMITS: Vector2 = Vector2(0.14, 0.3)
const LUNGE_FALL_TIME: float = 0.45
const LUNGE_EXIT: Vector2 = Vector2(260.0, 300.0)
## The body is this far past the swimmer at the top of the rise: the jaws have gone through them.
const LUNGE_OVERSHOOT: float = 20.0
const JAW_REACH: float = 62.0
const RECOVER_TIME: float = 1.1
const RISE_SPEED: float = 150.0
## How deep the body has to sit to count as being in the water: a swimmer floats about level with the
## surface, somebody standing on an awash floor has the water at their feet (around -24) and is left alone.
const SOAK_DEPTH: float = -8.0
const DRY_FORGIVE: float = 0.45
## A floor standing in the surface: how far ahead a shark starts to go down for it and how far past it
## the tail still has to clear. Floors that lie wholly under water it simply swims behind.
const CEILING_AHEAD: float = 150.0
const CEILING_BEHIND: float = 96.0
## It never swims closer to the plaza than this.
const FLOOR_ROOM: float = 36.0
## The plaza must stand this deep under water before the sharks come up.
const MIN_WATER_OVER_FLOOR: float = 96.0

@export var tide_path: NodePath = ^"../Tide"
## The open water between the towers the sharks keep to (x from, x to).
@export var lane: Vector2 = Vector2(566.0, 1674.0)
## Where each shark comes up and goes down: the chasms at the towers' feet.
@export var homes: PackedFloat32Array = PackedFloat32Array([582.0, 1658.0])
@export var floor_y: float = 716.0
@export var warning_color: Color = Color(0.9, 0.32, 0.27)

var _tide: TidewaterTide = null
var _hunters: Array[Hunter] = []
var _soak: Dictionary = {}
var _dry: Dictionary = {}
var _victim_cooldown: Dictionary = {}
var _step: int = 0
var _authority: bool = true
var _announced: bool = false
var _game: Node = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The floating floors between the towers, as boxes: where a shark has to duck under instead of cutting
## the surface.
var _ceilings: Array[Rect2] = []


## One shark: what it is doing, where it is and how it is moving, and the curve of the lunge it is on.
class Hunter:
	extends RefCounted
	var body: TideShark = null
	var state: int = State.AWAY
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	## Which way it is patrolling (or lunging): +1 right, -1 left.
	var direction: float = 1.0
	var timer: float = 0.0
	var target_slot: int = 0
	var home_x: float = 0.0
	var beat: Vector2 = Vector2.ZERO
	## Its own rhythm, so the two never weave in step.
	var phase: float = 0.0
	## How hard it is working right now (0 gliding .. 1 all out): what its tail shows.
	var effort: float = 0.0
	# The lunge: from, through (where the body is as the jaws close on the swimmer) and back in, each with
	# the velocity it has there.
	var from: Vector2 = Vector2.ZERO
	var from_velocity: Vector2 = Vector2.ZERO
	var through: Vector2 = Vector2.ZERO
	var through_velocity: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO
	var rise_time: float = 0.2
	## In a rush: coming at the swimmer (true) or still swimming out for the run-up (false).
	var run_in: bool = true
	var bitten: bool = false
	var wake_timer: float = 0.0
	var was_above: bool = false


func _ready() -> void:
	_rng.randomize()
	_tide = get_node_or_null(tide_path) as TidewaterTide
	_authority = not NetworkSession.is_client()
	_game = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	add_to_group(WorldSync.GROUP)
	_collect_ceilings()
	var middle: float = (lane.x + lane.y) * 0.5
	for index in range(homes.size()):
		var hunter: Hunter = Hunter.new()
		hunter.home_x = homes[index]
		hunter.direction = 1.0 if hunter.home_x < middle else -1.0
		hunter.phase = float(index) * 2.3
		# Each keeps to its own half until it has someone to chase.
		hunter.beat = Vector2(lane.x, middle - 30.0) if hunter.home_x < middle else Vector2(middle + 30.0, lane.y)
		hunter.body = TideShark.new()
		hunter.body.name = "Shark%d" % (index + 1)
		hunter.body.visible = false
		hunter.body.z_index = -1
		add_child(hunter.body)
		_hunters.append(hunter)


func _physics_process(delta: float) -> void:
	var water: float = WorldConditions.water_level
	var up: bool = _tide != null and _tide.is_water_up() and water < floor_y - MIN_WATER_OVER_FLOOR
	if _authority:
		_update_soak(delta, up)
	for hunter in _hunters:
		_advance(hunter, delta, water, up)
	if _authority and up:
		_send_hunters()


func _process(delta: float) -> void:
	var water: float = WorldConditions.water_level
	for hunter in _hunters:
		var body: TideShark = hunter.body
		body.visible = hunter.state != State.AWAY
		if not body.visible:
			continue
		body.global_position = hunter.position
		body.z_index = 4 if hunter.state == State.LUNGE else -1
		body.jaw = _jaw_of(hunter, delta)
		body.animate(delta, hunter.velocity, hunter.effort, hunter.state == State.LUNGE)
		_update_wake(hunter, delta, water)


## Every terrain body that floats inside the sharks' lane (the towers and the plaza are walls and floor,
## not ceilings).
func _collect_ceilings() -> void:
	var arena: Node = get_parent()
	if arena == null:
		return
	for body in arena.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var polygon: Polygon2D = child as Polygon2D
			if polygon == null or polygon.polygon.size() < 3:
				continue
			var points: PackedVector2Array = polygon.global_transform * polygon.polygon
			var box: Rect2 = Rect2(points[0], Vector2.ZERO)
			for point in points:
				box = box.expand(point)
			if box.position.x >= lane.x - 40.0 and box.end.x <= lane.y + 40.0 and box.end.y < floor_y - 20.0:
				_ceilings.append(box)


## How deep a shark at x, heading `direction`, swims: fin out of the water where the surface is open,
## just deep enough for the fin to pass under a floor that stands in the surface, starting down in good
## time and staying down until the tail is clear.
func _cruise_y(x: float, direction: float, water: float) -> float:
	var y: float = water + CRUISE_DEPTH
	for box in _ceilings:
		var ahead: float = CEILING_AHEAD if direction > 0.0 else CEILING_BEHIND
		var behind: float = CEILING_BEHIND if direction > 0.0 else CEILING_AHEAD
		if x < box.position.x - ahead or x > box.end.x + behind:
			continue
		# Only a floor whose top is out of the water is in the fin's way.
		if box.position.y < water + 4.0 and box.end.y > y - FIN_HEIGHT:
			y = maxf(y, box.end.y + FIN_HEIGHT + 6.0)
	return minf(y, floor_y - FLOOR_ROOM)


# --- What a shark does --------------------------------------------------------------------------------------

func _advance(hunter: Hunter, delta: float, water: float, up: bool) -> void:
	hunter.timer += delta
	match hunter.state:
		State.AWAY:
			if _authority and up:
				hunter.position = Vector2(hunter.home_x, floor_y + 130.0)
				hunter.velocity = Vector2(hunter.direction * 30.0, -RISE_SPEED)
				_enter(hunter, State.ARRIVE)
		State.ARRIVE:
			# Up out of the chasm, levelling off into the patrol as the surface comes near.
			var arrive_y: float = _cruise_y(hunter.position.x, hunter.direction, water)
			var level: float = clampf((hunter.position.y - arrive_y) / 150.0, 0.0, 1.0)
			_steer(hunter, Vector2(hunter.direction * lerpf(PATROL_SPEED, 34.0, level), -RISE_SPEED * level), 260.0, delta, 0.35)
			if _authority and level < 0.12:
				_enter(hunter, State.PATROL)
		State.PATROL:
			if hunter.position.x > hunter.beat.y:
				hunter.direction = -1.0
			elif hunter.position.x < hunter.beat.x:
				hunter.direction = 1.0
			_steer(hunter, _cruise_velocity(hunter, water, PATROL_SPEED), PATROL_ACCEL, delta, 0.0)
			if _authority and not up:
				_enter(hunter, State.LEAVE)
		State.RUSH:
			# `direction` is the way it will come at the swimmer. Swimming out for the run-up it goes the
			# other way along the surface; far enough out (or at the end of the lane) it turns in.
			var target: Player = _player(hunter.target_slot)
			var prey: Vector2 = target.global_position if target != null else hunter.position
			var ahead_of_it: float = (prey.x - hunter.position.x) * hunter.direction
			var cruise: float = _cruise_y(hunter.position.x, hunter.direction if hunter.run_in else -hunter.direction, water)
			if not hunter.run_in:
				var at_end: bool = hunter.position.x < lane.x + 30.0 or hunter.position.x > lane.y - 30.0
				if ahead_of_it > RUN_UP or at_end:
					hunter.run_in = true
					_step += 1
				_steer(hunter, Vector2(-hunter.direction * RUSH_SPEED * 0.85, clampf((cruise - hunter.position.y) * 3.0, -160.0, 160.0)), RUSH_ACCEL, delta, 0.8)
			else:
				# Fin out on the way in; over the last stretch it sinks to come up from below.
				var sink: float = 1.0 - smoothstep(LUNGE_RANGE, LUNGE_RANGE + 170.0, ahead_of_it)
				var depth: float = minf(lerpf(cruise, maxf(cruise, maxf(prey.y, water) + ATTACK_DEPTH), sink), floor_y - FLOOR_ROOM)
				_steer(hunter, Vector2(hunter.direction * RUSH_SPEED, clampf((depth - hunter.position.y) * 3.5, -220.0, 220.0)), RUSH_ACCEL, delta, 1.0)
			if _authority:
				if not up or target == null or target.is_eliminated() or float(_dry.get(hunter.target_slot, 0.0)) > DRY_FORGIVE:
					_release(hunter)
				elif hunter.run_in and ahead_of_it > 40.0 and ahead_of_it < LUNGE_RANGE and hunter.velocity.x * hunter.direction > LUNGE_ENTRY_SPEED:
					_begin_lunge(hunter, water)
				elif hunter.timer > RUSH_LIMIT or (hunter.run_in and ahead_of_it < -40.0):
					# Overshot, or too slow: give it up rather than lunge at nothing.
					_release(hunter)
		State.LUNGE:
			_follow_lunge(hunter)
			_breach_feedback(hunter, water)
			if _authority:
				if not hunter.bitten and hunter.timer < hunter.rise_time + 0.06:
					_try_bite(hunter)
				if hunter.timer >= hunter.rise_time + LUNGE_FALL_TIME:
					# Back in the water with the speed it came down with.
					hunter.velocity = Vector2(LUNGE_EXIT.x * hunter.direction, LUNGE_EXIT.y)
					_enter(hunter, State.RECOVER)
		State.RECOVER:
			# Carries its speed on, levels out and slows back into the patrol.
			if hunter.position.x > lane.y:
				hunter.direction = -1.0
			elif hunter.position.x < lane.x:
				hunter.direction = 1.0
			elif absf(hunter.velocity.x) > 40.0:
				hunter.direction = signf(hunter.velocity.x)
			_steer(hunter, _cruise_velocity(hunter, water, 150.0), 620.0, delta, 0.1)
			if _authority and hunter.timer >= RECOVER_TIME:
				_enter(hunter, State.PATROL if up else State.LEAVE)
		State.LEAVE:
			var to_home: float = hunter.home_x - hunter.position.x
			if absf(to_home) > 26.0:
				hunter.direction = signf(to_home)
				var leaving: Vector2 = _cruise_velocity(hunter, water, 170.0)
				_steer(hunter, Vector2(leaving.x, maxf(leaving.y, 0.0)), 260.0, delta, 0.3)
			else:
				_steer(hunter, Vector2(to_home * 1.5, RISE_SPEED), 260.0, delta, 0.3)
				if _authority and hunter.position.y > floor_y + 130.0:
					_enter(hunter, State.AWAY)
			if _authority and up and hunter.position.y < floor_y:
				_enter(hunter, State.PATROL)


## Moves a shark towards the velocity it wants, no faster than `accel` lets it, and on by one frame.
## Its effort (what the tail shows) is the push that takes, never less than `base_effort`. Over the plaza
## it is turned back up before it reaches the floor (the chasms at the sides go down further).
func _steer(hunter: Hunter, wanted: Vector2, accel: float, delta: float, base_effort: float) -> void:
	var push: float = (wanted - hunter.velocity).length()
	var bottom: float = floor_y - FLOOR_ROOM
	if hunter.state != State.ARRIVE and hunter.state != State.LEAVE and hunter.position.y > bottom - 60.0:
		# Easing off the dive over the last 60 px.
		wanted.y = minf(wanted.y, (bottom - hunter.position.y) * 4.0)
		accel = maxf(accel, 700.0)
	hunter.velocity = hunter.velocity.move_toward(wanted, accel * delta)
	hunter.position += hunter.velocity * delta
	hunter.effort = clampf(maxf(base_effort, push / 190.0), 0.0, 1.0)


## The velocity of a shark on its beat: along it at an easy, uneven pace, weaving a little in depth, and
## down or up towards the depth the water ahead allows.
func _cruise_velocity(hunter: Hunter, water: float, speed: float) -> Vector2:
	var pace: float = speed * (0.86 + 0.2 * sin(hunter.timer * 0.41 + hunter.phase))
	var ahead: float = hunter.position.x + hunter.direction * 46.0
	var depth: float = _cruise_y(ahead, hunter.direction, water) + sin(hunter.timer * 0.63 + hunter.phase) * 3.0
	return Vector2(hunter.direction * pace, clampf((depth - hunter.position.y) * 2.4, -110.0, 80.0))


## The leap, set once: from where it is (keeping the speed it has) up and forward through the swimmer,
## over the top and back into the water beyond. Whoever has moved on by the time it gets there is missed.
func _begin_lunge(hunter: Hunter, water: float) -> void:
	var target: Player = _player(hunter.target_slot)
	if target == null or target.is_eliminated() or target.get_water_depth() < -70.0:
		_release(hunter)
		return
	var prey: Vector2 = target.global_position + target.velocity * 0.12
	prey.y = maxf(prey.y, water - 64.0)
	var heading: Vector2 = Vector2(LUNGE_HEADING.x * hunter.direction, LUNGE_HEADING.y)
	hunter.from = hunter.position
	hunter.from_velocity = hunter.velocity
	hunter.through = prey + heading * LUNGE_OVERSHOOT
	hunter.through_velocity = heading * LUNGE_SPEED
	var average: float = (hunter.velocity.length() + LUNGE_SPEED) * 0.5
	hunter.rise_time = clampf(hunter.from.distance_to(hunter.through) / maxf(average, 1.0), LUNGE_RISE_LIMITS.x, LUNGE_RISE_LIMITS.y)
	hunter.to = Vector2(prey.x + hunter.direction * 230.0, water + 44.0)
	hunter.bitten = false
	hunter.was_above = hunter.position.y < water
	_enter(hunter, State.LUNGE)


## Where the lunge has got to: two smooth pieces that share their velocity where they meet.
func _follow_lunge(hunter: Hunter) -> void:
	var exit: Vector2 = Vector2(LUNGE_EXIT.x * hunter.direction, LUNGE_EXIT.y)
	var before: Vector2 = hunter.position
	if hunter.timer < hunter.rise_time:
		hunter.position = _curve(hunter.from, hunter.from_velocity * hunter.rise_time, hunter.through, hunter.through_velocity * hunter.rise_time, hunter.timer / hunter.rise_time)
	else:
		var t: float = clampf((hunter.timer - hunter.rise_time) / LUNGE_FALL_TIME, 0.0, 1.0)
		hunter.position = _curve(hunter.through, hunter.through_velocity * LUNGE_FALL_TIME, hunter.to, exit * LUNGE_FALL_TIME, t)
	var step: float = maxf(get_physics_process_delta_time(), 0.001)
	if hunter.position.distance_squared_to(before) > 0.01:
		hunter.velocity = (hunter.position - before) / step
	hunter.effort = 1.0


## A cubic Hermite curve: from a to b, leaving with tangent a_out and arriving with b_in.
func _curve(a: Vector2, a_out: Vector2, b: Vector2, b_in: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return a * (2.0 * t3 - 3.0 * t2 + 1.0) + a_out * (t3 - 2.0 * t2 + t) + b * (-2.0 * t3 + 3.0 * t2) + b_in * (t3 - t2)


func _try_bite(hunter: Hunter) -> void:
	var target: Player = _player(hunter.target_slot)
	if target == null or target.is_eliminated():
		return
	var heading: Vector2 = hunter.velocity.normalized() if hunter.velocity.length_squared() > 1.0 else Vector2(hunter.direction, 0.0)
	var jaws: Vector2 = hunter.position + heading * JAW_REACH
	if heading.y > -0.25 or jaws.distance_to(target.global_position) > BITE_RADIUS:
		return
	hunter.bitten = true
	_step += 1
	var throw: Vector2 = Vector2(BITE_THROW.x * hunter.direction, BITE_THROW.y)
	_soak[hunter.target_slot] = 0.0
	_victim_cooldown[hunter.target_slot] = VICTIM_COOLDOWN
	_bite_feedback(hunter)
	KillLog.note_damage(target, &"shark")
	if NetworkSession.is_steam_match_active():
		var game_sync: Variant = _game.get(&"_game_sync") if _game != null else null
		var combat: Variant = game_sync.get_module(GameSettings.MODULE_COMBAT) if game_sync != null else null
		if combat != null:
			var other: int = GameSettings.PLAYER_TWO_SLOT if target.player_slot == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT
			combat.apply_hit(target.player_slot, other, 0, BITE_DAMAGE, false, jaws, throw)
	else:
		target.velocity = throw
		target.apply_incoming_damage(BITE_DAMAGE, 0, jaws, true)


## The hunt is off: back to the beat.
func _release(hunter: Hunter) -> void:
	hunter.target_slot = 0
	_enter(hunter, State.RECOVER)


func _enter(hunter: Hunter, next_state: int) -> void:
	hunter.state = next_state
	hunter.timer = 0.0
	if next_state == State.PATROL or next_state == State.AWAY or next_state == State.LEAVE:
		hunter.target_slot = 0
	_step += 1
	_state_feedback(hunter)


# --- Who is hunted ------------------------------------------------------------------------------------------

func _update_soak(delta: float, up: bool) -> void:
	var live: bool = _hunt_allowed()
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null:
			continue
		var slot: int = player.player_slot
		_victim_cooldown[slot] = maxf(float(_victim_cooldown.get(slot, 0.0)) - delta, 0.0)
		if up and live and not player.is_eliminated() and player.get_water_depth() > SOAK_DEPTH:
			_soak[slot] = float(_soak.get(slot, 0.0)) + delta
			_dry[slot] = 0.0
		else:
			_dry[slot] = float(_dry.get(slot, 0.0)) + delta
			if float(_dry[slot]) > DRY_FORGIVE:
				_soak[slot] = maxf(float(_soak.get(slot, 0.0)) - delta * 2.5, 0.0)


func _send_hunters() -> void:
	var grace: float = SPRING_GRACE if _tide.is_spring() else GRACE
	for slot in _soak.keys():
		if float(_soak[slot]) < grace or float(_victim_cooldown.get(slot, 0.0)) > 0.0 or _is_hunted(int(slot)):
			continue
		var player: Player = _player(int(slot))
		if player == null:
			continue
		var best: Hunter = null
		for hunter in _hunters:
			if hunter.state != State.PATROL:
				continue
			if best == null or absf(hunter.position.x - player.global_position.x) < absf(best.position.x - player.global_position.x):
				best = hunter
		if best == null:
			continue
		best.target_slot = int(slot)
		var away: float = player.global_position.x - best.position.x
		var towards: bool = best.velocity.x * away > 0.0
		if absf(away) >= RUN_UP * 0.8 and towards:
			# Already coming their way with room to spare: straight in.
			best.direction = signf(away)
			best.run_in = true
		elif towards:
			# Coming their way but too close: on past them, then round and in from the far side.
			best.direction = -signf(away) if away != 0.0 else -best.direction
			best.run_in = false
		else:
			# Heading away: on out a little, then round and in.
			best.direction = signf(away) if away != 0.0 else best.direction
			best.run_in = absf(away) >= RUN_UP
		_enter(best, State.RUSH)


func _is_hunted(slot: int) -> bool:
	for hunter in _hunters:
		if hunter.target_slot == slot and (hunter.state == State.RUSH or hunter.state == State.LUNGE):
			return true
	return false


## No hunting while nobody can move: round intros, the kill banner, a finished match.
func _hunt_allowed() -> bool:
	if NetworkSession.is_steam_match_active() or NetworkSession.uses_set_flow():
		return OnlineMatch.is_playing_set()
	if _game == null:
		return true
	return not _game.is_match_over() and not _game.is_round_intro_running()


func _player(slot: int) -> Player:
	if slot <= 0:
		return null
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player != null and player.player_slot == slot:
			return player
	return null


# --- Looks and sound ----------------------------------------------------------------------------------------

## Jaws: thrown open as the lunge starts, shut on the swimmer or, missing, as it goes over the top.
func _jaw_of(hunter: Hunter, delta: float) -> float:
	var open: float = 0.0
	if hunter.state == State.RUSH and hunter.run_in:
		open = 0.18
	elif hunter.state == State.LUNGE and not hunter.bitten and hunter.timer < hunter.rise_time + 0.05:
		open = 1.0
	# Open fast, snap shut faster.
	return move_toward(hunter.body.jaw, open, delta * (9.0 if open > hunter.body.jaw else 14.0))


func _state_feedback(hunter: Hunter) -> void:
	match hunter.state:
		State.ARRIVE:
			if not _announced:
				_announced = true
				HudToasts.notify("SHARKS", "Swimmers get bitten", warning_color, &"")
		State.RUSH:
			AudioDirector.play_at(&"shark_alert", hunter.position)
			var target: Player = _player(hunter.target_slot)
			if target != null:
				GameJuice.spawn_callout(target.global_position, "SHARK", warning_color, target.get_instance_id())


func _bite_feedback(hunter: Hunter) -> void:
	AudioDirector.play_at(&"shark_bite", hunter.position)
	GameJuice.add_trauma(0.4)
	GameJuice.zoom_punch(0.03)


## The surface breaking on the way out and again on the way back in.
func _breach_feedback(hunter: Hunter, water: float) -> void:
	var heading: Vector2 = hunter.velocity.normalized() if hunter.velocity.length_squared() > 1.0 else Vector2(hunter.direction, 0.0)
	var jaws: Vector2 = hunter.position + heading * JAW_REACH
	var above: bool = jaws.y < water
	if above == hunter.was_above:
		return
	hunter.was_above = above
	var at: Vector2 = Vector2(jaws.x, water)
	KillLog.note_event(&"breach", at, {"direction": hunter.direction})
	GameJuice.spawn_burst(&"splash", at, Vector2.UP, Color.WHITE, 1.7 if above else 1.4)
	GameJuice.spawn_burst(&"splash", at + Vector2(-hunter.direction * 34.0, 0.0), Vector2.UP, Color.WHITE, 1.0)
	AudioDirector.play_at(&"shark_breach", at, 0.0 if above else -3.0, 1.0 if above else 0.85)
	if above:
		GameJuice.add_trauma(0.18)


## The dorsal fin drags a wake along the surface while it is out of the water.
func _update_wake(hunter: Hunter, delta: float, water: float) -> void:
	if hunter.state == State.LUNGE or not hunter.body.is_side_on():
		return
	var tip: Vector2 = hunter.body.fin_tip()
	if tip.y > water - 2.0:
		return
	hunter.wake_timer -= delta
	if hunter.wake_timer > 0.0:
		return
	# The faster it goes, the closer the rings.
	hunter.wake_timer = clampf(34.0 / maxf(absf(hunter.velocity.x), 40.0), 0.07, 0.4)
	GameJuice.spawn_burst(&"ripple", Vector2(tip.x, water), Vector2(-signf(hunter.velocity.x), 0.0), Color.WHITE)


# --- Online -------------------------------------------------------------------------------------------------

func net_state() -> Dictionary:
	var hunters: Array = []
	for hunter in _hunters:
		hunters.append([
			hunter.state, hunter.position, hunter.velocity, hunter.direction, hunter.timer, hunter.target_slot,
			hunter.from, hunter.from_velocity, hunter.through, hunter.to, hunter.bitten,
			hunter.through_velocity, hunter.rise_time, hunter.run_in,
		])
	return {"step": _step, "hunters": hunters}


func apply_net_state(state: Dictionary) -> void:
	_step = int(state.get("step", _step))
	var hunters: Variant = state.get("hunters", [])
	if not (hunters is Array):
		return
	for index in range(mini((hunters as Array).size(), _hunters.size())):
		var data: Variant = (hunters as Array)[index]
		if not (data is Array) or (data as Array).size() < 14:
			continue
		var hunter: Hunter = _hunters[index]
		var entered: bool = int(data[0]) != hunter.state
		var bit: bool = data[10] == true and not hunter.bitten
		hunter.state = int(data[0])
		hunter.direction = float(data[3])
		hunter.timer = float(data[4])
		hunter.target_slot = int(data[5])
		hunter.from = data[6]
		hunter.from_velocity = data[7]
		hunter.through = data[8]
		hunter.to = data[9]
		hunter.bitten = data[10] == true
		hunter.through_velocity = data[11]
		hunter.rise_time = float(data[12])
		hunter.run_in = data[13] == true
		# A lunge follows its curve from the timer alone; anywhere else take the host's place and speed.
		if hunter.state != State.LUNGE:
			hunter.position = data[1]
			hunter.velocity = data[2]
		if entered:
			if hunter.state == State.LUNGE:
				hunter.was_above = hunter.position.y < WorldConditions.water_level
			_state_feedback(hunter)
		if bit:
			_bite_feedback(hunter)


# --- Tests --------------------------------------------------------------------------------------------------

## Tests: how long a slot has been in the water, as the sharks count it.
func soak_of(slot: int) -> float:
	return float(_soak.get(slot, 0.0))


## Tests: the state of every shark, in order.
func states() -> Array:
	var result: Array = []
	for hunter in _hunters:
		result.append(hunter.state)
	return result
