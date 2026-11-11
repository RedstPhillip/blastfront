class_name TidewaterSharks
extends Node2D

## The sharks of Tidewater. Two of them come up out of the chasms once a flood stands deep enough over the
## plaza, and go back down as it drains. They cruise under the temple's floors with the dorsal fin cutting
## the surface. Whoever stays in the water too long (GRACE seconds, less at a spring tide) is hunted: the
## nearest shark turns and comes in fast on the surface, the fin goes under, and a moment later it comes
## up from below through the spot where the swimmer was, jaws open. Caught, the swimmer takes BITE_DAMAGE
## and is thrown clear of the water; out of the water in time, or simply somewhere else when it breaches,
## and it misses. Being out of the water lets the timer run back down.
##
## Online the host's sharks decide (WorldSync carries their state and every change of it), the client's
## copies swim the same paths; the bite goes through CombatSync like any other hit, credited to the
## opponent the way the arena's border is. Bots already keep out of water they do not need to be in.

enum State { AWAY, ARRIVE, PATROL, STALK, DIVE, STRIKE, RECOVER, LEAVE }

const GRACE: float = 2.6
const SPRING_GRACE: float = 1.8
const BITE_DAMAGE: int = 30
const BITE_RADIUS: float = 46.0
const BITE_THROW: Vector2 = Vector2(240.0, -470.0)
## After a bite the same swimmer is left alone this long, however long they stay in.
const VICTIM_COOLDOWN: float = 2.4
## Spine depth under the surface while cruising: the dorsal fin stands a hand out of the water.
const CRUISE_DEPTH: float = 22.0
const STRIKE_DEPTH: float = 96.0
const PATROL_SPEED: float = 82.0
const STALK_SPEED: float = 255.0
const RISE_SPEED: float = 150.0
const STALK_REACH: float = 150.0
const STALK_LIMIT: float = 1.7
const DIVE_TIME: float = 0.5
const STRIKE_TIME: float = 0.64
const RECOVER_TIME: float = 1.3
## How deep the body has to sit to count as being in the water: a swimmer floats about level with the
## surface, somebody standing on an awash floor has the water at their feet (around -24) and is left alone.
const SOAK_DEPTH: float = -8.0
## Room a shark keeps under a floor that lies in the surface, and how far ahead it looks for one.
const CEILING_CLEARANCE: float = 42.0
const CEILING_LOOKAHEAD: float = 104.0
const DRY_FORGIVE: float = 0.45
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


## One shark: what it is doing, where, and the path of the strike it is on.
class Hunter:
	extends RefCounted
	var body: TideShark = null
	var state: int = State.AWAY
	var position: Vector2 = Vector2.ZERO
	var heading: Vector2 = Vector2.RIGHT
	var direction: float = 1.0
	var timer: float = 0.0
	var target_slot: int = 0
	var home_x: float = 0.0
	var beat: Vector2 = Vector2.ZERO
	var from: Vector2 = Vector2.ZERO
	var control: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO
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
		hunter.heading = Vector2(hunter.direction, 0.0)
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
		body.z_index = 4 if hunter.state == State.STRIKE else -1
		body.thrash = move_toward(body.thrash, _thrash_of(hunter), delta * 5.0)
		body.jaw = _jaw_of(hunter)
		body.animate(delta, hunter.heading, _speed_of(hunter))
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


## How deep a shark at x swims: fin out of the water where the surface is open, ducked under any floor
## that lies in the surface there.
func _cruise_y(x: float, water: float) -> float:
	var y: float = water + CRUISE_DEPTH
	for box in _ceilings:
		if x < box.position.x - CEILING_LOOKAHEAD or x > box.end.x + CEILING_LOOKAHEAD:
			continue
		# In the way if it reaches into the band between the fin's tip and the belly.
		if box.end.y > water - 30.0 and box.position.y < y + 26.0:
			y = maxf(y, box.end.y + CEILING_CLEARANCE)
	return y


# --- What a shark does --------------------------------------------------------------------------------------

func _advance(hunter: Hunter, delta: float, water: float, up: bool) -> void:
	hunter.timer += delta
	var cruise_y: float = _cruise_y(hunter.position.x, water)
	match hunter.state:
		State.AWAY:
			if _authority and up:
				hunter.position = Vector2(hunter.home_x, floor_y + 130.0)
				hunter.heading = Vector2(hunter.direction * 0.3, -1.0).normalized()
				_enter(hunter, State.ARRIVE)
		State.ARRIVE:
			hunter.position.y = move_toward(hunter.position.y, cruise_y, RISE_SPEED * delta)
			hunter.position.x += hunter.direction * 26.0 * delta
			_turn(hunter, Vector2(hunter.direction * 0.5, -1.0), delta, 4.0)
			if _authority and hunter.position.y <= cruise_y + 26.0:
				_enter(hunter, State.PATROL)
		State.PATROL:
			if hunter.position.x > hunter.beat.y:
				hunter.direction = -1.0
			elif hunter.position.x < hunter.beat.x:
				hunter.direction = 1.0
			hunter.position.x += hunter.direction * PATROL_SPEED * delta
			var before_y: float = hunter.position.y
			hunter.position.y = move_toward(hunter.position.y, cruise_y + sin(hunter.timer * 0.9) * 3.0, 64.0 * delta)
			# Nose down going under a floor, nose up coming back to the surface.
			_turn(hunter, Vector2(hunter.direction * PATROL_SPEED, (hunter.position.y - before_y) / maxf(delta, 0.001)), delta, 3.5)
			if _authority and not up:
				_enter(hunter, State.LEAVE)
		State.STALK:
			var target: Player = _player(hunter.target_slot)
			var target_x: float = target.global_position.x if target != null else hunter.position.x
			var to_target: float = target_x - hunter.position.x
			if absf(to_target) > 6.0:
				hunter.direction = signf(to_target)
			hunter.position.x = clampf(hunter.position.x + hunter.direction * STALK_SPEED * delta, lane.x, lane.y)
			var stalk_before_y: float = hunter.position.y
			hunter.position.y = move_toward(hunter.position.y, cruise_y, 110.0 * delta)
			_turn(hunter, Vector2(hunter.direction * STALK_SPEED, (hunter.position.y - stalk_before_y) / maxf(delta, 0.001)), delta, 7.0)
			if _authority:
				if not up or target == null or target.is_eliminated() or float(_dry.get(hunter.target_slot, 0.0)) > DRY_FORGIVE:
					_release(hunter)
				elif absf(to_target) < STALK_REACH or hunter.timer > STALK_LIMIT:
					hunter.from = hunter.position
					hunter.to = Vector2(clampf(target_x - hunter.direction * 78.0, lane.x - 30.0, lane.y + 30.0), water + STRIKE_DEPTH)
					_enter(hunter, State.DIVE)
		State.DIVE:
			var t: float = clampf(hunter.timer / DIVE_TIME, 0.0, 1.0)
			var eased: float = t * t * (3.0 - 2.0 * t)
			var before: Vector2 = hunter.position
			hunter.position = hunter.from.lerp(hunter.to, eased)
			_turn(hunter, hunter.position - before + Vector2(hunter.direction * 0.4, 0.0), delta, 9.0)
			if _authority and t >= 1.0:
				_begin_strike(hunter, water)
		State.STRIKE:
			var t: float = clampf(hunter.timer / STRIKE_TIME, 0.0, 1.0)
			var a: Vector2 = hunter.from.lerp(hunter.control, t)
			var b: Vector2 = hunter.control.lerp(hunter.to, t)
			hunter.position = a.lerp(b, t)
			if (b - a).length_squared() > 0.01:
				hunter.heading = (b - a).normalized()
			_breach_feedback(hunter, water)
			if _authority:
				if not hunter.bitten and t > 0.3 and t < 0.66:
					_try_bite(hunter)
				if t >= 1.0:
					_enter(hunter, State.RECOVER)
		State.RECOVER:
			hunter.direction = signf(hunter.heading.x) if absf(hunter.heading.x) > 0.05 else hunter.direction
			if hunter.position.x > lane.y:
				hunter.direction = -1.0
			elif hunter.position.x < lane.x:
				hunter.direction = 1.0
			hunter.position.x += hunter.direction * 190.0 * delta
			hunter.position.y = move_toward(hunter.position.y, cruise_y + 34.0 * (1.0 - clampf(hunter.timer / RECOVER_TIME, 0.0, 1.0)), 160.0 * delta)
			_turn(hunter, Vector2(hunter.direction, 0.0), delta, 4.0)
			if _authority and hunter.timer >= RECOVER_TIME:
				_enter(hunter, State.PATROL if up else State.LEAVE)
		State.LEAVE:
			var to_home: float = hunter.home_x - hunter.position.x
			if absf(to_home) > 14.0:
				hunter.direction = signf(to_home)
				hunter.position.x += hunter.direction * 170.0 * delta
				hunter.position.y = move_toward(hunter.position.y, maxf(cruise_y, hunter.position.y), 60.0 * delta)
				_turn(hunter, Vector2(hunter.direction, 0.15), delta, 4.0)
			else:
				hunter.position.y += RISE_SPEED * delta
				_turn(hunter, Vector2(hunter.direction * 0.4, 1.0), delta, 4.0)
				if _authority and hunter.position.y > floor_y + 130.0:
					_enter(hunter, State.AWAY)
			if _authority and up and hunter.position.y < floor_y:
				_enter(hunter, State.PATROL)


## The leap: from where it lies under the swimmer, up through the spot they are at now, and back into the
## water beyond them. Set once; whoever has moved on by the time it gets there is missed.
func _begin_strike(hunter: Hunter, water: float) -> void:
	var target: Player = _player(hunter.target_slot)
	if target == null or target.is_eliminated() or target.get_water_depth() < -70.0:
		_release(hunter)
		return
	var aim: Vector2 = target.global_position + target.velocity * 0.12
	aim.y = maxf(aim.y, water - 64.0)
	hunter.from = hunter.position
	hunter.to = Vector2(aim.x + hunter.direction * 124.0, water + 74.0)
	hunter.control = (aim + Vector2(0.0, -12.0)) * 2.0 - (hunter.from + hunter.to) * 0.5
	hunter.bitten = false
	hunter.was_above = false
	_enter(hunter, State.STRIKE)


func _try_bite(hunter: Hunter) -> void:
	var target: Player = _player(hunter.target_slot)
	if target == null or target.is_eliminated():
		return
	var jaws: Vector2 = hunter.position + hunter.heading * (TideShark.LENGTH * 0.5 - 22.0)
	if jaws.distance_to(target.global_position) > BITE_RADIUS:
		return
	hunter.bitten = true
	_step += 1
	var throw: Vector2 = Vector2(BITE_THROW.x * hunter.direction, BITE_THROW.y)
	_soak[hunter.target_slot] = 0.0
	_victim_cooldown[hunter.target_slot] = VICTIM_COOLDOWN
	_bite_feedback(hunter)
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


func _turn(hunter: Hunter, towards: Vector2, delta: float, rate: float) -> void:
	if towards.length_squared() < 0.0001:
		return
	hunter.heading = hunter.heading.slerp(towards.normalized(), clampf(rate * delta, 0.0, 1.0)).normalized()


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
		_enter(best, State.STALK)


func _is_hunted(slot: int) -> bool:
	for hunter in _hunters:
		if hunter.target_slot == slot and (hunter.state == State.STALK or hunter.state == State.DIVE or hunter.state == State.STRIKE):
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

func _speed_of(hunter: Hunter) -> float:
	match hunter.state:
		State.STALK:
			return STALK_SPEED
		State.STRIKE, State.DIVE:
			return 420.0
		State.RECOVER, State.LEAVE:
			return 180.0
	return PATROL_SPEED


func _thrash_of(hunter: Hunter) -> float:
	match hunter.state:
		State.STRIKE:
			return 1.0
		State.STALK, State.DIVE:
			return 0.55
	return 0.0


## Jaws: opening on the way up, wide at the swimmer, snapping shut right after.
func _jaw_of(hunter: Hunter) -> float:
	if hunter.state != State.STRIKE:
		return move_toward(hunter.body.jaw, 0.0, 0.08)
	var t: float = clampf(hunter.timer / STRIKE_TIME, 0.0, 1.0)
	if hunter.bitten:
		return move_toward(hunter.body.jaw, 0.12, 0.3)
	return smoothstep(0.08, 0.4, t) * (1.0 - smoothstep(0.62, 0.8, t))


func _state_feedback(hunter: Hunter) -> void:
	match hunter.state:
		State.ARRIVE:
			if not _announced:
				_announced = true
				HudToasts.notify("SHARKS", "Swimmers get bitten", warning_color, &"")
		State.STALK:
			AudioDirector.play_at(&"shark_alert", hunter.position)
			var target: Player = _player(hunter.target_slot)
			if target != null:
				GameJuice.spawn_callout(target.global_position, "SHARK", warning_color, target.get_instance_id())
		State.DIVE:
			# The fin slips under: a last swirl where it was.
			GameJuice.spawn_burst(&"ripple", Vector2(hunter.position.x, WorldConditions.water_level), Vector2(hunter.direction, 0.0), Color.WHITE)


func _bite_feedback(hunter: Hunter) -> void:
	AudioDirector.play_at(&"shark_bite", hunter.position)
	GameJuice.add_trauma(0.4)
	GameJuice.zoom_punch(0.03)


## The surface breaking on the way out and again on the way back in.
func _breach_feedback(hunter: Hunter, water: float) -> void:
	var jaws_y: float = hunter.position.y + hunter.heading.y * 60.0
	var above: bool = jaws_y < water
	if above == hunter.was_above:
		return
	hunter.was_above = above
	var at: Vector2 = Vector2(hunter.position.x + hunter.heading.x * 60.0, water)
	GameJuice.spawn_burst(&"splash", at, Vector2.UP, Color.WHITE, 1.7 if above else 1.4)
	GameJuice.spawn_burst(&"splash", at + Vector2(-hunter.direction * 34.0, 0.0), Vector2.UP, Color.WHITE, 1.0)
	AudioDirector.play_at(&"shark_breach", at, 0.0 if above else -3.0, 1.0 if above else 0.85)
	if above:
		GameJuice.add_trauma(0.18)


## The dorsal fin drags a wake along the surface while it is out of the water.
func _update_wake(hunter: Hunter, delta: float, water: float) -> void:
	if hunter.state == State.STRIKE or hunter.state == State.DIVE:
		return
	var tip: Vector2 = hunter.body.fin_tip()
	if tip.y > water - 2.0:
		return
	hunter.wake_timer -= delta
	if hunter.wake_timer > 0.0:
		return
	hunter.wake_timer = 0.14 if hunter.state == State.STALK else 0.34
	GameJuice.spawn_burst(&"ripple", Vector2(tip.x, water), Vector2(-hunter.direction, 0.0), Color.WHITE)


# --- Online -------------------------------------------------------------------------------------------------

func net_state() -> Dictionary:
	var hunters: Array = []
	for hunter in _hunters:
		hunters.append([
			hunter.state, hunter.position, hunter.heading, hunter.direction, hunter.timer, hunter.target_slot,
			hunter.from, hunter.control, hunter.to, hunter.bitten,
		])
	return {"step": _step, "hunters": hunters}


func apply_net_state(state: Dictionary) -> void:
	_step = int(state.get("step", _step))
	var hunters: Variant = state.get("hunters", [])
	if not (hunters is Array):
		return
	for index in range(mini((hunters as Array).size(), _hunters.size())):
		var data: Variant = (hunters as Array)[index]
		if not (data is Array) or (data as Array).size() < 10:
			continue
		var hunter: Hunter = _hunters[index]
		var entered: bool = int(data[0]) != hunter.state
		var bit: bool = data[9] == true and not hunter.bitten
		hunter.state = int(data[0])
		hunter.direction = float(data[3])
		hunter.timer = float(data[4])
		hunter.target_slot = int(data[5])
		hunter.from = data[6]
		hunter.control = data[7]
		hunter.to = data[8]
		hunter.bitten = data[9] == true
		# A strike follows its path from the timer alone; anywhere else take the host's place for it.
		if hunter.state != State.STRIKE and hunter.state != State.DIVE:
			hunter.position = data[1]
			hunter.heading = data[2]
		if entered:
			if hunter.state == State.STRIKE:
				hunter.was_above = false
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
