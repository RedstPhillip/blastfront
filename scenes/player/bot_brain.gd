class_name BotBrain
extends Node

## AI controller for a Player in CONTROL_AI mode. Produces the same inputs a human would: movement axis,
## jump press/hold, shoot, block, dash, down (slide on the ground, Ground Slam in the air), Time Control and
## an aim position. The player code treats them like a pad's, so bots play by the same rules and marks.
##
## Each frame: read the world (BotSenses: floor, walls, pits, hazards), learn from what went wrong
## (BotRouteMemory: failed moves, stuck spots, bad goals), weigh its own condition (BotStance: marked, guard
## broken, slowed), react to incoming rounds (timed through BotTimedActions), move, shoot.
##
## Movement follows a LevelNavigation graph towards a goal point chosen by a ranked search: distance to the
## preferred range, height, edges, supply drops, hazards, and a real ballistic line-of-fire check (including
## lobs over cover), amortised across frames. A goal is kept for a moment before the bot turns for another;
## at it the bot shifts its footing now and then instead of standing like a turret.

enum Difficulty { DUMMY = -1, EASY = 0, NORMAL = 1, HARD = 2 }

## Distance the bot can see in the thickest storm and in clear air.
const STORM_SIGHT_MIN: float = 380.0
const STORM_SIGHT_MAX: float = 4000.0
const PROFILES: Dictionary = {
	Difficulty.EASY: {
		"aim_error": 7.5, "reaction": 0.45, "fire_delay": 0.6, "block_chance": 0.18, "block_reaction": 0.3,
		"lead": 0.35, "preferred_distance": 0.85, "dodge_chance": 0.12, "turn_rate": 4.0, "pressure": 0.35,
		"use_lobs": false, "capture_drive": 2.2, "dash_dodge": 0.15, "dash_drive": 0.18, "slide_dodge": 0.1,
		"slam_drive": 0.0, "fidget": 0.25,
	},
	Difficulty.NORMAL: {
		"aim_error": 3.2, "reaction": 0.27, "fire_delay": 0.25, "block_chance": 0.48, "block_reaction": 0.17,
		"lead": 0.75, "preferred_distance": 0.7, "dodge_chance": 0.28, "turn_rate": 7.5, "pressure": 0.6,
		"use_lobs": true, "capture_drive": 3.6, "dash_dodge": 0.35, "dash_drive": 0.4, "slide_dodge": 0.25,
		"slam_drive": 0.35, "fidget": 0.4,
	},
	Difficulty.HARD: {
		"aim_error": 1.3, "reaction": 0.15, "fire_delay": 0.07, "block_chance": 0.78, "block_reaction": 0.09,
		"lead": 1.0, "preferred_distance": 0.58, "dodge_chance": 0.42, "turn_rate": 13.0, "pressure": 0.85,
		"use_lobs": true, "capture_drive": 4.6, "dash_dodge": 0.6, "dash_drive": 0.65, "slide_dodge": 0.4,
		"slam_drive": 0.6, "fidget": 0.55,
	},
}

## Research marks per difficulty: bots never visit the research page, so the game hands them these.
const DASH_MARKS: Dictionary = {Difficulty.EASY: 1, Difficulty.NORMAL: 2, Difficulty.HARD: 4}
const WALL_JUMP_MARKS: Dictionary = {Difficulty.EASY: 0, Difficulty.NORMAL: 1, Difficulty.HARD: 3}
const SLIDE_MARKS: Dictionary = {Difficulty.EASY: 0, Difficulty.NORMAL: 1, Difficulty.HARD: 3}
const AIR_JUMP_MARKS: Dictionary = {Difficulty.EASY: 0, Difficulty.NORMAL: 1, Difficulty.HARD: 3}
const GROUND_SLAM_MARKS: Dictionary = {Difficulty.EASY: 0, Difficulty.NORMAL: 2, Difficulty.HARD: 3}
## Time Control Mk per difficulty (0: none). Bots cast it as a comeback: low on health, or the target reloading.
const TIME_CONTROL_MARKS: Dictionary = {Difficulty.EASY: 0, Difficulty.NORMAL: 1, Difficulty.HARD: 3}

const THREAT_HORIZON: float = 0.32
const THREAT_RADIUS: float = 28.0
const CANDIDATES_PER_FRAME: int = 5
const SEARCH_BUDGET_USEC: int = 1200
## What a clear shot from a goal point is worth in the search (and, under cover-seeking, what it costs).
const SOLUTION_BONUS: float = 3.0
const COVER_BONUS: float = 1.5
## Shortest gap between two goal searches. Replans can be requested every frame (blocked line of fire,
## getting stuck); the ranked search finishes in a frame or two, so without this it would rerun constantly.
const MIN_SEARCH_INTERVAL: float = 0.35
## A freshly chosen goal is kept at least this long (s) unless it floods or goes bad; a better one has to
## beat the current one's score by GOAL_SWITCH_MARGIN once the commitment is over.
const GOAL_COMMIT_MIN: float = 1.1
const GOAL_COMMIT_MAX: float = 2.3
const GOAL_SWITCH_MARGIN: float = 0.35
## A goal in a hazard that lasts longer than this (s) is scored down by HAZARD_GOAL_PENALTY per danger.
const HAZARD_GOAL_MIN_TIME: float = 1.0
const HAZARD_GOAL_PENALTY: float = 4.0
## Longest the bot waits at the edge of a hazard on its path (with no way round) before it gives that goal up.
const HAZARD_WAIT_MAX: float = 3.0
## In the air the bot never steers weaker than this share of full speed, so a jump always makes progress.
const MIN_AIR_STEER: float = 0.2
## Ground speed (px/s) a jump tolerates beyond what its arc needs, or against it, before the bot brakes.
const TAKEOFF_SPEED_TOLERANCE: float = 110.0
## Longest the bot brakes before a jump; on a slope or in a storm it may never get slow enough. Ice
## takes far longer to shed speed.
const MAX_TAKEOFF_BRAKE: float = 0.25
const MAX_ICE_TAKEOFF_BRAKE: float = 0.9
## A move counts as failed when the bot lands this far above or below its target point (on another surface)
## or this far to the side.
const FAILED_MOVE_DROP: float = 28.0
const FAILED_MOVE_SIDE: float = 90.0
## Up to this far (px) below a ledge's top the body slides up onto it by itself (hover, step-up).
const LEDGE_SELF_CLIMB: float = 24.0
## Sideways distance from which a swimming bot leaps for its exit.
const SWIM_LEAP_RANGE: float = 100.0
const TRAJECTORY_STEPS: int = 90
const TRAJECTORY_RAY_STRIDE: int = 2
const TARGET_HIT_RADIUS: float = 20.0
const MUZZLE_REACH: float = 34.0
## How far a dash carries (burst plus the glide after it) and how often the bot weighs dashing on purpose.
const DASH_REACH: float = 160.0
const DASH_THINK_INTERVAL: float = 0.35
const SLIDE_REACH: float = 110.0
const SLAM_THINK_INTERVAL: float = 0.25
## Shortest and longest wait (s) after a slam before the bot weighs another.
const SLAM_COOLDOWN_MIN: float = 3.0
const SLAM_COOLDOWN_MAX: float = 6.0
## Health share below which a bot reaches for Time Control, how often it weighs casting, and the chance per
## look by difficulty (a human gets a moment to read the situation first).
const TIME_CONTROL_LOW_HEALTH: float = 0.4
const TIME_CONTROL_THINK_INTERVAL: float = 0.5
const TIME_CONTROL_CHANCE: Dictionary = {Difficulty.EASY: 0.0, Difficulty.NORMAL: 0.35, Difficulty.HARD: 0.6}
## Kinds of BotTimedActions.
const ACTION_BLOCK: StringName = &"block"
const ACTION_DASH: StringName = &"dash"
const ACTION_SLIDE: StringName = &"slide"

# --- Inputs the Player reads -------------------------------------------------------------------------------
var difficulty: int = Difficulty.NORMAL
var move_direction: float = 0.0
var jump_pressed: bool = false
var jump_held: bool = false
var shoot_pressed: bool = false
var block_pressed: bool = false
var time_control_pressed: bool = false
var dash_pressed: bool = false
## Down: a slide on the ground, a Ground Slam in the air.
var slide_pressed: bool = false
var aim_position: Vector2 = Vector2.ZERO

# --- Parts -------------------------------------------------------------------------------------------------
var _player: Player = null
var _profile: Dictionary = {}
var _target: Player = null
var _senses: BotSenses = null
var _memory: BotRouteMemory = BotRouteMemory.new()
var _timed: BotTimedActions = BotTimedActions.new()
var _stance: BotStance = BotStance.new()
var _nav: LevelNavigation = null

# --- Wandering without a graph and the sandbox dummy ------------------------------------------------------
var _home_x: float = 0.0
var _goal_x: float = 0.0
var _decision_timer: float = 0.0

# --- Goal and path -----------------------------------------------------------------------------------------
var _path: PackedInt64Array = PackedInt64Array()
var _path_index: int = 0
var _goal_point: int = -1
var _goal_score: float = -INF
var _goal_commit_timer: float = 0.0
var _replan_timer: float = 0.0
var _search_cooldown: float = 0.0
## Candidate goal points for the running search with their cheap (raycast-free) scores, best last.
var _search_queue: Array[int] = []
var _search_scores: PackedFloat32Array = PackedFloat32Array()
var _search_best: int = -1
var _search_best_score: float = -INF
var _search_bounds: Rect2 = Rect2()
var _search_speed: float = 0.0
var _search_gravity: float = 0.0
var _search_range: float = 0.0
var _search_capture: Dictionary = {}
## The tide forecast the current goal was chosen under (Tidewater); a new one triggers a fresh search.
var _known_forecast: float = INF
var _takeoff_brake_timer: float = 0.0
## Replanning after being knocked off the path waits this long between tries (s).
var _off_path_cooldown: float = 0.0
## Waiting at the edge of a hazard on the path (s so far).
var _hazard_wait: float = 0.0
## Set after a dash along the path: the waypoints it flew past are skipped instead of walked back to.
var _skip_passed_points: bool = false
var _stuck_timer: float = 0.0

# --- In the air --------------------------------------------------------------------------------------------
var _air_target_x: float = INF
## Sideways speed of the jump or drop in progress, as the navigation validated it.
var _air_speed_x: float = 0.0
## The jump / drop / climb in the air right now (nav point ids, -1 when none), whether the bot has left the
## ground since taking off (only then does touching it count as the landing) and whether an Air Jump already
## went into it.
var _air_move_from: int = -1
var _air_move_to: int = -1
var _air_move_kind: int = -1
var _air_move_airborne: bool = false
var _air_rescued: bool = false
## A wall climb in progress: the way to the wall (0 when not climbing) and the ledge's height.
var _climb_direction: float = 0.0
var _climb_top_y: float = 0.0
## Leaping out of the water: no sideways steering until the rise is nearly spent.
var _swim_leap: bool = false
## Side a swimming bot is heading to get out from under a ledge; kept until it has open sky above.
var _swim_escape_side: float = 0.0
var _jump_hold_timer: float = 0.0
var _jump_cooldown: float = 0.0

# --- At the goal -------------------------------------------------------------------------------------------
var _fidget_timer: float = 2.0
var _fidget_x: float = INF

# --- Combat ------------------------------------------------------------------------------------------------
var _fire_timer: float = 0.6
var _visible_time: float = 0.0
var _blocked_time: float = 0.0
var _shots_without_hit: int = 0
var _aim_direction: Vector2 = Vector2.LEFT
var _aim_error_angle: float = 0.0
var _aim_error_timer: float = 0.0
var _solution_timer: float = 0.0
var _solution_direction: Vector2 = Vector2.ZERO
## Sideways acceleration the wind puts on the bot's own rounds (Mars storms); folded into every aim solve.
var _wind_accel: float = 0.0
var _evaluated_threats: Dictionary = {}
var _block_focus: Node2D = null
var _block_focus_timer: float = 0.0
var _dash_think_timer: float = 0.0
var _slam_think_timer: float = 0.0
var _slam_cooldown: float = 0.0
var _time_control_think_timer: float = 0.0


## Research marks a bot of this difficulty fights with.
static func research_marks(bot_difficulty: int) -> Dictionary:
	if not DASH_MARKS.has(bot_difficulty):
		return {}
	var tables: Dictionary = {
		ResearchManager.DASHING: DASH_MARKS,
		ResearchManager.WALL_JUMPS: WALL_JUMP_MARKS,
		ResearchManager.SLIDING: SLIDE_MARKS,
		ResearchManager.AIR_JUMP: AIR_JUMP_MARKS,
		ResearchManager.GROUND_SLAM: GROUND_SLAM_MARKS,
		ResearchManager.TIME_CONTROL: TIME_CONTROL_MARKS,
	}
	var marks: Dictionary = {}
	for research in tables.keys():
		var mark: int = int((tables[research] as Dictionary).get(bot_difficulty, 0))
		if mark > 0 or research == ResearchManager.WALL_JUMPS:
			marks[str(research)] = mark
	return marks


func setup(player: Player, bot_difficulty: int) -> void:
	_player = player
	difficulty = bot_difficulty
	_profile = PROFILES.get(difficulty, PROFILES[Difficulty.NORMAL])
	_senses = BotSenses.new(player)
	process_physics_priority = -10
	_home_x = player.global_position.x
	_goal_x = _home_x
	aim_position = player.global_position + Vector2(-200.0, 0.0)
	if difficulty != Difficulty.DUMMY:
		_prewarm_navigation.call_deferred()


## Builds the level graph on the first physics frame, while the scene transition still covers the screen,
## so the cost does not land on the first frame of the fight.
func _prewarm_navigation() -> void:
	if not is_inside_tree():
		return
	for _frame in range(2):
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	_senses.refresh()
	_ensure_navigation()


## Re-anchors idle wandering to the current position (call after teleporting the owner).
func reset_home() -> void:
	if _player == null:
		return
	_home_x = _player.global_position.x
	_goal_x = _home_x
	_path = PackedInt64Array()
	_path_index = 0
	_air_target_x = INF


## Called by the owning player whenever one of its hits lands.
func on_damage_dealt() -> void:
	_shots_without_hit = 0


func _physics_process(delta: float) -> void:
	jump_pressed = false
	shoot_pressed = false
	block_pressed = false
	time_control_pressed = false
	dash_pressed = false
	slide_pressed = false
	if _player == null or not is_instance_valid(_player) or _player.is_eliminated() or not _player.movement_enabled:
		move_direction = 0.0
		jump_held = false
		_visible_time = 0.0
		return
	# A slowed bot thinks, reacts and aims on its slowed clock too (Time Control).
	delta *= _player.time_scale
	_senses.refresh()
	_memory.tick(delta)
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	_update_jump_hold(delta)
	_target = _find_target()
	if difficulty == Difficulty.DUMMY:
		_update_dummy(delta)
		return
	_stance.update(_player, _target)
	if _stance.changed:
		# Marked, its guard broken, slowed, or over it: the old goal was picked for another situation.
		_reconsider_goal()
	_update_threats()
	_update_movement(delta)
	_update_slam(delta)
	_carry_out(_timed.tick(delta))
	_update_dash(delta)
	_update_aim_and_fire(delta)
	_update_time_control(delta)


# --- Movement ----------------------------------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	_ensure_navigation()
	if _nav == null or not _nav.is_valid():
		_update_movement_fallback(delta)
		return
	var me: Vector2 = _player.global_position
	var feet: Vector2 = _feet()
	var grounded: bool = _player.is_grounded()
	_nav.set_flood_level(WorldConditions.water_level)
	_watch_tide()
	if _player.is_swimming() or (_player.is_in_water() and LevelNavigation.is_flooded(feet.y, WorldConditions.water_level)):
		_update_swimming(me)
		return
	if grounded and _wants_to_retreat(me):
		_back_off(me)
		return

	_update_goal_search(delta, feet, grounded)
	if not grounded:
		move_direction = _steer_in_air(me, feet)
		return
	_after_landing(feet)
	if _senses.in_hazard():
		_escape_hazard(me)
		return
	if _path_index < _path.size():
		var direction: Variant = _follow_path(delta, feet)
		if direction == null:
			return
		move_direction = _watch_stuck(delta, me, float(direction))
	else:
		move_direction = _watch_stuck(delta, me, _hold_position(delta, me))


func _feet() -> Vector2:
	return _player.global_position + Vector2(0.0, _player.hover_dist)


## On the ground: close the move that was in the air (did it land where it meant to?), end a climb, tidy
## the path after a dash, and plan again when the path ran out or the bot got knocked off it.
func _after_landing(feet: Vector2) -> void:
	_air_target_x = INF
	_swim_leap = false
	_check_landing(feet)
	if _climb_direction != 0.0:
		_climb_direction = 0.0
		if feet.y > _climb_top_y + 20.0:
			_memory.pause_climbs()
			_replan_timer = 0.0
	if _skip_passed_points and not _player.is_dashing():
		_skip_passed_points = false
		_skip_walked_points(feet)
	if _senses.in_hazard():
		return
	if _path_index >= _path.size() and _goal_point >= 0 and _nav.nearest_point(feet, 60.0) != _goal_point:
		_plan_path(feet)
	elif _off_path_cooldown <= 0.0 and _off_path(feet):
		# Knocked or fallen off the path (its next point is on another level or far away): plan again from
		# here instead of hopping under a point it cannot walk to.
		_off_path_cooldown = 0.4
		_plan_path(feet)


## Walks the path, taking off for its jumps, drops and climbs. The direction to push, or null when the bot
## holds its input on purpose this frame (braking for a jump, waiting out a hazard), which is not being stuck.
func _follow_path(delta: float, feet: Vector2) -> Variant:
	var current_id: int = int(_path[_path_index])
	var current: Vector2 = _nav.points[current_id]
	if _wait_out_hazard(delta, current):
		move_direction = 0.0
		_stuck_timer = 0.0
		return null
	var arrive_distance: float = 16.0 if _path_index == 0 or _player.is_on_ice() else 9.0
	if absf(feet.x - current.x) > arrive_distance:
		return _steer_to(current.x, feet.x, _path_index >= _path.size() - 1 or _next_move_is_jump())
	if _path_index + 1 >= _path.size():
		_path_index += 1
		return 0.0
	var next_id: int = int(_path[_path_index + 1])
	var next: Vector2 = _nav.points[next_id]
	var move: Dictionary = _nav.get_move(current_id, next_id)
	var kind: int = int(move["move"])
	var air_speed: float = float(move.get("vx", 0.0))
	var max_brake: float = MAX_ICE_TAKEOFF_BRAKE if _player.is_on_ice() else MAX_TAKEOFF_BRAKE
	if kind == LevelNavigation.Move.JUMP and _too_fast_for_takeoff(air_speed) and _takeoff_brake_timer < max_brake:
		# Still running the wrong way (or too fast) for this jump: brake on the spot first (on ice by pushing
		# against the slide, which bites harder than letting it coast).
		_takeoff_brake_timer += delta
		move_direction = -signf(_player.velocity.x) if _player.is_on_ice() else 0.0
		_stuck_timer = 0.0
		return null
	_takeoff_brake_timer = 0.0
	_path_index += 1
	_air_speed_x = air_speed
	if kind != LevelNavigation.Move.WALK:
		_air_move_from = current_id
		_air_move_to = next_id
		_air_move_kind = kind
		_air_move_airborne = false
		_air_rescued = false
		_air_target_x = next.x
	match kind:
		LevelNavigation.Move.JUMP:
			_force_jump(float(move["hold"]))
		LevelNavigation.Move.CLIMB:
			_force_jump(float(move["hold"]))
			_climb_direction = signf(next.x - feet.x)
			_climb_top_y = next.y
	return signf(next.x - feet.x)


## The next point on the path burns (and the bot does not): first a fresh plan (the path keeps off hazards
## where there is another way); with no way round, stand at the edge while it burns out, and give the goal
## up when that would take longer than HAZARD_WAIT_MAX. True while waiting.
func _wait_out_hazard(delta: float, next_point: Vector2) -> bool:
	if _senses.danger_at_feet(next_point) <= 0.0:
		_hazard_wait = 0.0
		return false
	if _hazard_wait == 0.0:
		# Hold this one frame: the fresh path (round it, if there is a way) is followed from the next.
		_hazard_wait = 0.001
		_plan_path(_feet())
		return true
	if _hazard_wait + _senses.hazard_time_left_at_feet(next_point) > HAZARD_WAIT_MAX:
		_hazard_wait = 0.0
		_give_up_goal()
		return true
	_hazard_wait += delta
	return true


## Standing in a hazard: out along the shortest walkable way (dashing out when that is safe and far enough
## to be worth it), or with a jump towards the safer side when there is no walkable way out.
func _escape_hazard(me: Vector2) -> void:
	var exit: Dictionary = _senses.hazard_exit()
	var side: float = float(exit["side"])
	if side == 0.0:
		side = signf(me.x - _target.global_position.x) if _target != null else 1.0
		if side == 0.0:
			side = 1.0
		_request_jump(0.35)
	elif float(exit["distance"]) > 40.0 and _player.can_dash() and _senses.stretch_is_safe(side, DASH_REACH):
		_press_dash(side)
	move_direction = side
	_stuck_timer = 0.0
	# Its path may lead straight back in; the plan is made again once it is out.
	_path = PackedInt64Array()
	_path_index = 0


## Off the path at its goal: back away from a target right on top of it, otherwise shift its footing now
## and then (see _fidget).
func _hold_position(delta: float, me: Vector2) -> float:
	if _target != null and absf(_target.global_position.x - me.x) < 120.0:
		var away: float = signf(me.x - _target.global_position.x)
		if not _senses.ground_below(me + Vector2(away * (34.0 + _stopping_distance()), 0.0), BotSenses.SAFE_DROP_DEPTH):
			return 0.0
		return away
	return _fidget(delta, me)


## Pushing without moving for half a second: hop and replan, and after the third time near the same spot
## give the goal (and the move it was on) up. Returns the direction to push.
func _watch_stuck(delta: float, me: Vector2, direction: float) -> float:
	if direction == 0.0 or absf(_player.velocity.x) >= 10.0:
		_stuck_timer = 0.0
		return direction
	_stuck_timer += delta
	if _stuck_timer <= 0.5:
		return direction
	_stuck_timer = 0.0
	if _memory.note_stuck(me):
		if _path_index > 0 and _path_index < _path.size():
			_memory.fail_move(int(_path[_path_index - 1]), int(_path[_path_index]))
		_give_up_goal()
		return 0.0
	_force_jump(0.3)
	_replan_timer = 0.0
	return direction


## In the air: fly the arc the navigation checked, keep a climb going, steer back from over a pit, and save
## a jump that falls short with an Air Jump. Returns the direction to push.
func _steer_in_air(me: Vector2, feet: Vector2) -> float:
	if _air_move_to >= 0:
		_air_move_airborne = true
	if _swim_leap and _player.velocity.y < -120.0:
		return 0.0
	var direction: float = 0.0
	if _air_target_x != INF:
		var to_target: float = _air_target_x - me.x
		if absf(to_target) > 6.0:
			# At full speed a jump up to a ledge above and to the side runs under the ledge and bumps its head
			# instead of rising past the edge first.
			var share: float = absf(_air_speed_x) / maxf(_player.speed, 1.0)
			direction = signf(to_target) * clampf(maxf(share, MIN_AIR_STEER), 0.0, 1.0)
	if _climb_direction != 0.0:
		# Climbing: keep pushing into the wall and kick off it whenever it is reached below the ledge.
		direction = _climb_direction
		if _player.is_on_wall() and feet.y > _climb_top_y - 4.0 and _player.velocity.y > -80.0:
			_force_jump(0.3)
	if not _senses.footing_below(me, 700.0) and (_air_target_x == INF or not _senses.footing_below(Vector2(_air_target_x, me.y), 700.0)):
		direction = _senses.nearest_safe_side(me)
		# Falling into the void: an air jump buys the way back.
		if _player.velocity.y > 60.0 and _player.get_air_jumps_left() > 0:
			_force_jump(0.3)
	if _player.is_on_wall() and _player.velocity.y > 0.0 and not _senses.ground_below(me, 500.0):
		_force_jump(0.3)
	if _try_air_jump_rescue(feet):
		# Let go of the stick for the jump itself: from Mk II an air jump turns to the held side at full run
		# speed, which would carry it over the ledge instead of onto it.
		direction = 0.0
	return direction


## Falling short of a jump to a ledge above, about to hit the ledge's side: an Air Jump (once per jump)
## carries it the rest of the way. True on the frame it jumps.
func _try_air_jump_rescue(feet: Vector2) -> bool:
	if _air_rescued or _air_move_to < 0 or _air_move_kind != LevelNavigation.Move.JUMP or _player.get_air_jumps_left() <= 0:
		return false
	var target: Vector2 = _nav.points[_air_move_to]
	var takeoff: Vector2 = _nav.points[_air_move_from]
	var side: float = signf(target.x - takeoff.x)
	if target.y > takeoff.y - 12.0 or _player.velocity.y < 30.0 or feet.y < target.y + LEDGE_SELF_CLIMB or (target.x - feet.x) * side < 16.0:
		return false
	var probe: Vector2 = Vector2(feet.x, feet.y - 6.0)
	var wall: Dictionary = _senses.ray(probe, Vector2(target.x, probe.y))
	if wall.is_empty() or absf((wall["normal"] as Vector2).x) < 0.7:
		return false
	_air_rescued = true
	_force_jump(0.3)
	return true


## Back on the ground after a jump, drop or climb: when it landed on another surface than the point it was
## going for, that move is remembered as failed and the path is planned again from here.
func _check_landing(feet: Vector2) -> void:
	if _air_move_to < 0 or not _air_move_airborne:
		return
	var target: Vector2 = _nav.points[_air_move_to]
	var failed: bool = absf(feet.y - target.y) > FAILED_MOVE_DROP or absf(feet.x - target.x) > FAILED_MOVE_SIDE
	var from_id: int = _air_move_from
	var to_id: int = _air_move_to
	_air_move_from = -1
	_air_move_to = -1
	_air_move_kind = -1
	if not failed:
		return
	_memory.fail_move(from_id, to_id)
	_climb_direction = 0.0
	_plan_path(feet)
	if _goal_point >= 0 and _path.is_empty():
		_give_up_goal()


## Standing somewhere the path's next point cannot be walked to from: a different height, or far to the
## side of both it and the point before it. Only checked between moves (not mid-climb).
func _off_path(feet: Vector2) -> bool:
	if _path_index >= _path.size() or _climb_direction != 0.0:
		return false
	var current: Vector2 = _nav.points[int(_path[_path_index])]
	if absf(feet.y - current.y) > 48.0:
		var previous: Vector2 = _nav.points[int(_path[_path_index - 1])] if _path_index > 0 else current
		# Right at a jump's or drop's take-off the next point is meant to be higher or lower.
		return absf(feet.x - previous.x) > 24.0 or absf(feet.y - previous.y) > 48.0
	if _path_index > 0 and absf(feet.x - current.x) > 140.0:
		var before: Vector2 = _nav.points[int(_path[_path_index - 1])]
		return absf(feet.x - before.x) > 140.0
	return false


## Steering towards a path point. On ice the bot cannot stop on the spot: where it has to stop (the end of
## its path, a jump) it pushes against the slide early enough to come to rest on the point instead of
## sailing past it and turning back and forth.
func _steer_to(target_x: float, from_x: float, must_stop: bool) -> float:
	var direction: float = signf(target_x - from_x)
	if not must_stop or not _player.is_on_ice() or signf(_player.velocity.x) != direction:
		return direction
	var brake: float = _player.ground_acceleration * Player.ICE_ACCELERATION_SCALE
	var stopping: float = _player.velocity.x * _player.velocity.x / (2.0 * maxf(brake, 1.0))
	return -direction if stopping >= absf(target_x - from_x) - 6.0 else direction


func _next_move_is_jump() -> bool:
	if _path_index + 1 >= _path.size():
		return false
	return int(_nav.get_move(int(_path[_path_index]), int(_path[_path_index + 1]))["move"]) == LevelNavigation.Move.JUMP


## How far the bot would still slide if it let go now (only ice makes this more than a step).
func _stopping_distance() -> float:
	if not _player.is_on_ice():
		return 0.0
	return _player.velocity.x * _player.velocity.x / (2.0 * maxf(_player.get_ground_friction(), 1.0))


func _too_fast_for_takeoff(air_speed: float) -> bool:
	# Measured against the ground speed the wind settles a standing bot at, which braking cannot undo.
	var speed: float = _player.velocity.x - _player.get_wind_drift_speed()
	var against: bool = signf(speed) != signf(air_speed) and absf(speed) > TAKEOFF_SPEED_TOLERANCE
	return against or absf(speed) > absf(air_speed) + TAKEOFF_SPEED_TOLERANCE


## How far the path runs on as plain walking in `direction` from here.
func _walk_ahead(direction: float) -> float:
	if _nav == null or _path_index >= _path.size():
		return 0.0
	var from_x: float = _player.global_position.x
	var reach: float = 0.0
	for index in range(_path_index, _path.size()):
		if index > 0 and int(_nav.get_move(int(_path[index - 1]), int(_path[index]))["move"]) != LevelNavigation.Move.WALK:
			break
		var along: float = (_nav.points[int(_path[index])].x - from_x) * direction
		if along < reach:
			break
		reach = along
	return reach


## After a dash the feet are past some waypoints: drop the ones behind on the walk ahead, so the bot does
## not turn round to touch them.
func _skip_walked_points(feet: Vector2) -> void:
	while _path_index + 1 < _path.size():
		var current: Vector2 = _nav.points[int(_path[_path_index])]
		var next: Vector2 = _nav.points[int(_path[_path_index + 1])]
		if int(_nav.get_move(int(_path[_path_index]), int(_path[_path_index + 1]))["move"]) != LevelNavigation.Move.WALK:
			return
		if (feet.x - current.x) * signf(next.x - current.x) <= 0.0:
			return
		_path_index += 1


## At its goal the bot does not stand still like a turret: now and then it shifts its footing a step or two
## (on safe floor of this level, away from walls and hazards), sidesteps with a dash or hops, at an uneven
## rhythm. Returns the direction to push (0 while it holds still).
func _fidget(delta: float, me: Vector2) -> float:
	if _target == null or not _player.is_grounded() or _player.is_on_ice():
		_fidget_x = INF
		return 0.0
	if _fidget_x != INF:
		var side: float = signf(_fidget_x - me.x)
		if absf(_fidget_x - me.x) < 8.0 or _senses.wall_ahead(side) \
				or not _senses.ground_below(me + Vector2(side * 24.0, 0.0), _player.hover_dist + 22.0):
			_fidget_x = INF
			return 0.0
		return side * 0.6
	_fidget_timer -= delta
	if _fidget_timer > 0.0:
		return 0.0
	_fidget_timer = randf_range(1.4, 3.6)
	if randf() >= float(_profile.get("fidget", 0.3)):
		return 0.0
	if randf() < 0.2:
		_request_jump(0.12)
		return 0.0
	var step: float = randf_range(26.0, 70.0) * (1.0 if randf() < 0.5 else -1.0)
	# Lean towards the preferred range rather than wandering off it.
	var preferred: float = _preferred_distance()
	var distance: float = absf(_target.global_position.x - me.x)
	if absf(distance - preferred) > 60.0:
		step = absf(step) * signf(me.x - _target.global_position.x) * (1.0 if distance < preferred else -1.0)
	var side: float = signf(step)
	# Now and then the shift is a quick sidestep dash instead of a walk.
	if _player.can_dash() and randf() < float(_profile.get("dash_drive", 0.0)) * 0.6 and _senses.stretch_is_safe(side, DASH_REACH):
		_press_dash(side)
		return side
	if _senses.stretch_is_safe(side, absf(step)):
		_fidget_x = me.x + step
	return 0.0


## Whether its condition says back off now (see BotStance.retreat_within): slowed in time, or its guard
## broken with the target close.
func _wants_to_retreat(me: Vector2) -> bool:
	return _target != null and absf(_target.global_position.x - me.x) < _stance.retreat_within


## Backs away from the target along safe floor (dashing when it can) and leans on its block or dodges (see
## BotStance) until its condition is over.
func _back_off(me: Vector2) -> void:
	var away: float = signf(me.x - _target.global_position.x)
	if away == 0.0:
		away = 1.0 if randf() < 0.5 else -1.0
	if not _can_walk(away):
		away = -away
		if not _can_walk(away):
			move_direction = 0.0
			return
	move_direction = away
	if _player.can_dash() and _senses.stretch_is_safe(away, DASH_REACH) and not _player.is_time_frozen():
		_press_dash(away)
	_replan_timer = 0.0


## A step that way hits no wall, keeps ground under it and does not walk into a hazard.
func _can_walk(direction: float) -> bool:
	return not _senses.wall_ahead(direction) and _senses.step_has_ground(direction) and not _senses.leads_into_hazard(direction, 34.0)


## In the water: swim for the nearest ledge a leap reaches and leap out once it is close. Bots never stay in
## the sea; it makes them slow targets.
func _update_swimming(me: Vector2) -> void:
	_path = PackedInt64Array()
	_path_index = 0
	var level: float = WorldConditions.water_level
	var exit_id: int = _nav.nearest_swim_exit(me, level)
	if exit_id < 0:
		move_direction = 0.0
		return
	var exit: Vector2 = _nav.points[exit_id]
	var to_exit: float = exit.x - me.x
	var direction: float = signf(to_exit) if absf(to_exit) > 6.0 else 0.0
	var headroom: bool = _senses.headroom(me)
	if not headroom:
		# Under a ledge or an arch: swim out into open water before leaping, committed to one side so it does
		# not dither back and forth under the ledge.
		if _swim_escape_side == 0.0:
			_swim_escape_side = _senses.open_side(me, signf(to_exit) if to_exit != 0.0 else 1.0)
		direction = _swim_escape_side
	else:
		_swim_escape_side = 0.0
	move_direction = direction
	var can_leap: bool = _player.is_grounded() or _player.get_water_depth() < Player.SWIM_LEAP_DEPTH
	if headroom and can_leap and absf(to_exit) < SWIM_LEAP_RANGE and exit.y > level - LevelNavigation.SWIM_EXIT_REACH:
		_request_jump(0.4)
		_air_target_x = exit.x
		# Rise first, then steer over onto the ledge: steering at once runs into its side.
		_air_speed_x = _player.speed
		_swim_leap = true


## A new tide forecast (a flood announced, the water draining) sends the bot looking for a fresh goal when
## its current one is going under.
func _watch_tide() -> void:
	var forecast: float = WorldConditions.water_forecast
	if forecast == _known_forecast or (forecast != INF and _known_forecast != INF and absf(forecast - _known_forecast) < 20.0):
		return
	_known_forecast = forecast
	if _goal_point >= 0 and LevelNavigation.is_flooded(_nav.points[_goal_point].y, forecast):
		_replan_timer = 0.0
		_search_cooldown = 0.0


func _update_movement_fallback(delta: float) -> void:
	var me: Vector2 = _player.global_position
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.35, 0.95)
		_goal_x = _home_x + randf_range(-80.0, 80.0)
		if _target != null:
			var side: float = signf(me.x - _target.global_position.x)
			_goal_x = _target.global_position.x + (side if side != 0.0 else 1.0) * _weapon_range() * 0.7
	var direction: float = signf(_goal_x - me.x) if absf(_goal_x - me.x) > 20.0 else 0.0
	if direction != 0.0 and _player.is_grounded():
		if not _senses.step_has_ground(direction):
			direction = 0.0
		elif _senses.wall_ahead(direction):
			_request_jump(0.28)
	move_direction = direction


# --- Goal and path -----------------------------------------------------------------------------------------

func _ensure_navigation() -> void:
	if _nav != null:
		return
	var bounds_node: Node = _player.get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node == null or bounds_node.get_parent() == null or _senses.space() == null:
		return
	_nav = LevelNavigation.get_for(bounds_node.get_parent(), _senses.space(), _map_bounds())


func _plan_path(feet: Vector2) -> void:
	_path = PackedInt64Array()
	_path_index = 0
	_takeoff_brake_timer = 0.0
	var start_id: int = _nav.nearest_point(feet, 90.0)
	if start_id < 0 or _goal_point < 0:
		return
	_path = _nav.find_path(start_id, _goal_point, _climb_reach(), _memory.avoided_moves(), _hazard_points())
	# The only way there is a move it just failed: go as far as the take-off of that move and fight from there
	# (the goal beyond is left alone for a while) instead of failing it again or standing still.
	var cut: int = _memory.first_avoided(_path)
	if cut >= 0:
		_memory.give_up_goal(_goal_point)
		_path = _path.slice(0, cut + 1)
		_goal_point = int(_path[_path.size() - 1])
		_goal_commit_timer = randf_range(GOAL_COMMIT_MIN, GOAL_COMMIT_MAX)


## Navigation points inside a hazard right now, for the path to keep off (empty without hazards).
func _hazard_points() -> Dictionary:
	var points: Dictionary = {}
	if _senses.hazards().is_empty():
		return points
	for index in range(_nav.points.size()):
		if _senses.danger_at_feet(_nav.points[index]) > 0.0:
			points[index] = true
	return points


## How high this bot can climb a wall with its Wall Jumps marks (0 while climbing is paused after a fail).
func _climb_reach() -> float:
	if _memory.climbs_paused():
		return 0.0
	var slot: int = _player.player_slot
	return _nav.wall_climb_reach(ResearchManager.get_wall_jump_limit(slot), ResearchManager.get_wall_jump_strength(slot).y > 1.0)


## The current goal goes on the bad list for a while and a fresh search starts.
func _give_up_goal() -> void:
	_memory.give_up_goal(_goal_point)
	_path = PackedInt64Array()
	_path_index = 0
	_reconsider_goal()


## Drops the commitment to the current goal and asks for a fresh search right away.
func _reconsider_goal() -> void:
	_goal_commit_timer = 0.0
	_goal_score = -INF
	_replan_timer = 0.0
	_search_cooldown = 0.0


func _goal_gone_bad(goal: int) -> bool:
	var point: Vector2 = _nav.points[goal]
	return _memory.is_bad_goal(goal) or LevelNavigation.is_flooded(point.y, WorldConditions.water_forecast) \
		or _senses.hazard_time_left_at_feet(point) > HAZARD_GOAL_MIN_TIME


func _update_goal_search(delta: float, feet: Vector2, grounded: bool) -> void:
	_replan_timer -= delta
	_search_cooldown -= delta
	_goal_commit_timer = maxf(_goal_commit_timer - delta, 0.0)
	_off_path_cooldown = maxf(_off_path_cooldown - delta, 0.0)
	if _replan_timer <= 0.0 and _search_queue.is_empty() and _search_cooldown <= 0.0:
		_replan_timer = randf_range(0.7, 1.2)
		_search_cooldown = MIN_SEARCH_INTERVAL
		_begin_goal_search()
	_continue_goal_search(feet, grounded)


func _begin_goal_search() -> void:
	_search_queue.clear()
	_search_best = -1
	_search_best_score = -INF
	_search_bounds = _map_bounds()
	_search_range = _weapon_range()
	_search_capture = _capture_goal()
	_search_speed = GameSettings.PROJECTILE_MUZZLE_SPEED
	_search_gravity = GameSettings.PROJECTILE_GRAVITY
	var gun: Variant = _player.get_gun()
	if gun != null:
		var ballistics: Dictionary = gun.get_ballistics()
		_wind_accel = float(ballistics.get("wind", 0.0))
		_search_speed = float(ballistics.get("speed", _search_speed))
		_search_gravity = float(ballistics.get("gravity", _search_gravity))
	var reach: float = _search_range * 1.6
	var feet: Vector2 = _feet()
	# (cheap score, point index) pairs; Vector2 sorts by x first, natively.
	var ranked: Array[Vector2] = []
	for index in range(_nav.points.size()):
		if _target == null or absf(_nav.points[index].x - _target.global_position.x) < reach or index == _goal_point:
			ranked.append(Vector2(_cheap_score(index, feet), float(index)))
	# Worst first, so pop_back() hands out the most promising candidate. Only the line-of-fire check is
	# expensive and it can only add up to _best_shot_bonus(), so the search stops as soon as no remaining
	# candidate could beat the best one even with that: same winner as checking everything, far fewer rays.
	ranked.sort()
	_search_scores.resize(ranked.size())
	for index in range(ranked.size()):
		_search_queue.append(int(ranked[index].y))
		_search_scores[index] = ranked[index].x


func _continue_goal_search(feet: Vector2, grounded: bool) -> void:
	if _search_queue.is_empty():
		return
	var started_usec: int = Time.get_ticks_usec()
	var best_bonus: float = _best_shot_bonus()
	for _step in range(CANDIDATES_PER_FRAME):
		if _search_queue.is_empty() or Time.get_ticks_usec() - started_usec > SEARCH_BUDGET_USEC:
			break
		var cheap: float = _search_scores[_search_queue.size() - 1]
		if cheap + best_bonus <= _search_best_score:
			_search_queue.clear()
			break
		var candidate: int = _search_queue.pop_back()
		var score: float = cheap + _shot_bonus(candidate)
		if candidate == _goal_point:
			_goal_score = score
		if score > _search_best_score:
			_search_best_score = score
			_search_best = candidate
	if not _search_queue.is_empty() or _search_best < 0:
		return
	var changed: bool = _search_best != _goal_point
	if changed and _goal_point >= 0 and not _goal_gone_bad(_goal_point):
		# Keep a fresh goal for a moment, and only turn for a clearly better one: chasing every small change in
		# the scores is what made bots dither back and forth.
		if _goal_commit_timer > 0.0 or _search_best_score < _goal_score + GOAL_SWITCH_MARGIN:
			return
	_goal_score = _search_best_score
	_goal_point = _search_best
	if changed:
		_goal_commit_timer = randf_range(GOAL_COMMIT_MIN, GOAL_COMMIT_MAX)
		_fidget_x = INF
		if grounded:
			_plan_path(feet)


## What a goal point gains from the line-of-fire check: a clear shot is worth SOLUTION_BONUS; while the
## stance seeks cover (marked), a spot the target cannot be shot from (and so, mostly, cannot shoot from
## either) is worth COVER_BONUS and an open one costs.
func _shot_bonus(candidate: int) -> float:
	if _target == null:
		return 0.0
	var target_center: Vector2 = _target.global_position
	var from: Vector2 = _nav.points[candidate] - Vector2(0.0, _player.hover_dist)
	var in_range: bool = from.distance_to(target_center) <= _search_range * 1.15
	var clear: bool = in_range and _find_clear_shot(from, target_center, _search_speed, _search_gravity) != Vector2.ZERO
	if clear:
		return SOLUTION_BONUS * (1.0 - _stance.cover) - _stance.cover
	return COVER_BONUS * _stance.cover


func _best_shot_bonus() -> float:
	return maxf(SOLUTION_BONUS * (1.0 - _stance.cover) - _stance.cover, COVER_BONUS * _stance.cover)


func _preferred_distance() -> float:
	return _weapon_range() * float(_profile["preferred_distance"]) * _stance.distance


## Everything about a goal point that needs no raycast: distance to the preferred range, height, edges,
## travel, stickiness to the current goal, remembered bad spots, flooding, hazards and supply-drop pull.
func _cheap_score(candidate: int, feet: Vector2) -> float:
	var point: Vector2 = _nav.points[candidate]
	if _target == null:
		return -absf(point.x - _home_x) / 200.0
	var target_center: Vector2 = _target.global_position
	var preferred: float = _search_range * float(_profile["preferred_distance"]) * _stance.distance
	var horizontal: float = absf(point.x - target_center.x)
	var bounds: Rect2 = _search_bounds
	var score: float = -absf(horizontal - preferred) / 320.0
	score += clampf((target_center.y - point.y) / 500.0, -0.3, 0.3)
	score -= feet.distance_to(point) / 1400.0
	if point.x < bounds.position.x + 110.0 or point.x > bounds.end.x - 110.0:
		score -= 0.5
	if horizontal < 90.0:
		score -= 0.6
	if candidate == _goal_point:
		var arrived: bool = _path_index >= _path.size()
		score += -2.0 if arrived and _blocked_time >= 1.2 else 0.6
	if _memory.is_bad_goal(candidate):
		score -= 3.0
	if LevelNavigation.is_flooded(point.y, WorldConditions.water_forecast):
		score -= 4.0
	if _senses.hazard_time_left_at_feet(point) > HAZARD_GOAL_MIN_TIME:
		score -= HAZARD_GOAL_PENALTY * _senses.danger_at_feet(point)
	score += _capture_bonus(point)
	score += randf() * 0.15
	return score


## Pull towards supply drops in set-based matches: strong once the crate is down, a lighter lean towards the
## landing zone while it is still announced or falling.
func _capture_bonus(point: Vector2) -> float:
	if _search_capture.is_empty():
		return 0.0
	var target: Vector2 = _search_capture["position"]
	var radius: float = float(_search_capture["radius"])
	var distance: float = Vector2(point.x - target.x, (point.y - target.y) * 1.6).length()
	var drive: float = float(_profile.get("capture_drive", 3.0))
	if not bool(_search_capture["landed"]):
		return drive * 0.4 * clampf(1.0 - distance / 420.0, 0.0, 1.0)
	if distance <= radius * 0.75:
		return drive
	return drive * clampf(1.0 - distance / 700.0, 0.0, 1.0) * 0.7


func _capture_goal() -> Dictionary:
	var manager: Node = _player.get_tree().get_first_node_in_group(&"airdrop_manager")
	if manager == null or not manager.has_method(&"get_capture_goal"):
		return {}
	return manager.get_capture_goal()


# --- Jump input --------------------------------------------------------------------------------------------

func _force_jump(hold_seconds: float) -> void:
	jump_pressed = true
	jump_held = true
	_jump_hold_timer = hold_seconds
	_jump_cooldown = 0.3


func _request_jump(hold_seconds: float) -> void:
	if _jump_cooldown > 0.0:
		return
	_force_jump(hold_seconds)


func _update_jump_hold(delta: float) -> void:
	if _jump_hold_timer > 0.0:
		_jump_hold_timer -= delta
		if _jump_hold_timer <= 0.0:
			jump_held = false


# --- Ground Slam -------------------------------------------------------------------------------------------

## In the air above a target standing on the floor below (in the slam's throw), the bot slams down on it now
## and then: never mid-way up a jump to a ledge, never onto a ledge in between.
func _update_slam(delta: float) -> void:
	_slam_cooldown = maxf(_slam_cooldown - delta, 0.0)
	_slam_think_timer -= delta
	if _slam_think_timer > 0.0 or _slam_cooldown > 0.0:
		return
	_slam_think_timer = SLAM_THINK_INTERVAL
	if _target == null or _player.is_grounded() or not _player.can_slam():
		return
	var radius: float = float(ResearchManager.get_ground_slam_profile(_player.player_slot).get("radius", 0.0))
	if radius <= 0.0 or randf() >= float(_profile.get("slam_drive", 0.0)):
		return
	var me: Vector2 = _player.global_position
	var offset: Vector2 = _target.global_position - me
	if offset.y < 70.0 or absf(offset.x) > radius * 0.7 or not _target.is_grounded():
		return
	if _air_move_to >= 0 and _air_move_kind != LevelNavigation.Move.DROP and _nav.points[_air_move_to].y < me.y + _player.hover_dist:
		return
	var landing: Dictionary = _senses.ray(me, me + Vector2(0.0, offset.y + 120.0))
	if landing.is_empty() or absf((landing["position"] as Vector2).y - (_target.global_position.y + _target.hover_dist)) > 40.0:
		return
	if _senses.danger_at((landing["position"] as Vector2) - Vector2(0.0, _player.hover_dist)) > 0.0:
		return
	slide_pressed = true
	_slam_cooldown = randf_range(SLAM_COOLDOWN_MIN, SLAM_COOLDOWN_MAX)


# --- Dash --------------------------------------------------------------------------------------------------

## Now and then dashes on purpose: away when hurt and pressed, into a shockwave poke when the target stands
## close, or along a long flat stretch of the path. Never off a ledge, into a wall or into a hazard.
func _update_dash(delta: float) -> void:
	_dash_think_timer -= delta
	if _dash_think_timer > 0.0 or not _player.can_dash() or not _player.is_grounded():
		return
	_dash_think_timer = DASH_THINK_INTERVAL
	if randf() >= float(_profile.get("dash_drive", 0.0)):
		return
	var me: Vector2 = _player.global_position
	if _target != null and _player.health_component != null:
		var away: float = signf(me.x - _target.global_position.x)
		var hurt: bool = _player.health_component.health * 3 <= _player.health_component.max_health
		if hurt and away != 0.0 and absf(_target.global_position.x - me.x) < 180.0 and _senses.stretch_is_safe(away, DASH_REACH):
			_press_dash(away)
			return
	if _target != null and ResearchManager.has_dash_shockwave(_player.player_slot):
		var offset: Vector2 = _target.global_position - me
		if absf(offset.x) > 50.0 and absf(offset.x) < 140.0 and absf(offset.y) < 40.0 and _senses.stretch_is_safe(signf(offset.x), absf(offset.x)):
			_press_dash(signf(offset.x))
			return
	var direction: float = move_direction
	var ahead: float = _walk_ahead(direction) if direction != 0.0 else 0.0
	if ahead < DASH_REACH:
		return
	var closing: bool = _target == null or absf(_target.global_position.x - me.x) > _preferred_distance() + 120.0
	# Moving to a new firing spot along a long straight floor is worth a dash too, not only closing in.
	var relocating: bool = ahead >= DASH_REACH + 60.0
	if (closing or relocating or not _search_capture.is_empty()) and _senses.stretch_is_safe(direction, DASH_REACH):
		_press_dash(direction)
		_skip_passed_points = true


func _press_dash(direction: float) -> void:
	dash_pressed = true
	move_direction = direction
	_dash_think_timer = DASH_THINK_INTERVAL


# --- Reactions to incoming rounds --------------------------------------------------------------------------

## Looks at every enemy round once: one about to hit gets one answer, picked by chance per difficulty and
## shaded by the stance (a broken guard never blocks and dodges more; marked, it dodges harder): a slide under
## a flat shot, a dash out of a lob's way (or through anything with protection), a block, a hop, or an air
## jump when already in the air. The answers are timed (BotTimedActions) to land just before the round.
func _update_threats() -> void:
	var world: Node = _player.get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_projectiles_root"):
		return
	var me: Vector2 = _player.global_position
	for node in world.get_projectiles_root().get_children():
		var projectile: Projectile = node as Projectile
		if projectile == null or projectile.owner_slot == _player.player_slot:
			continue
		var id: int = projectile.get_instance_id()
		if _evaluated_threats.has(id):
			continue
		# A slowed bot looks further ahead in the round's time: the same reaction window in its own.
		var horizon: float = THREAT_HORIZON / maxf(_player.time_scale, 0.05)
		var impact_time: float = _predict_impact_time(projectile, me, horizon)
		if impact_time < 0.0:
			continue
		# Predicted in the round's own time; the bot's timers count in its own. Either clock may be slowed.
		impact_time *= _player.time_scale / maxf(TimeFlow.scale_for(projectile.owner_slot), 0.05)
		_evaluated_threats[id] = true
		_answer_threat(projectile, me, impact_time)
	if _evaluated_threats.size() > 64:
		_evaluated_threats.clear()


func _answer_threat(projectile: Projectile, me: Vector2, impact_time: float) -> void:
	var dodge: float = clampf(float(_profile["dodge_chance"]) * _stance.dodge, 0.0, 0.95)
	# A protected dash beats a block (it also moves); without protection the dash only sidesteps lobs.
	var dash_odds: float = float(_profile.get("dash_dodge", 0.0)) * (1.0 if ResearchManager.has_dash_protection(_player.player_slot) else 0.5)
	dash_odds = clampf(dash_odds * _stance.dash_dodge, 0.0, 0.95)
	var block_odds: float = maxf(float(_profile["block_chance"]) * _stance.block, _stance.block_floor)
	var can_block: bool = not _player.is_guard_broken() and _player.get_block_cooldown_ratio() >= 0.999 and not _player.is_blocking()
	if not _timed.is_pending(ACTION_SLIDE) and randf() < float(_profile.get("slide_dodge", 0.0)) and _plan_slide_dodge(projectile, me, impact_time):
		return
	if not _timed.is_pending(ACTION_DASH) and _player.can_dash() and randf() < dash_odds and _plan_dash_dodge(projectile, me, impact_time):
		return
	if can_block and randf() < block_odds:
		var reaction: float = _reaction_time()
		if reaction < impact_time:
			_timed.schedule(ACTION_BLOCK, maxf(impact_time - _player.block_duration * 0.5, reaction), projectile)
		return
	if _player.is_grounded():
		if randf() < dodge:
			_request_jump(0.25)
	elif randf() < dodge * 0.4 and _player.velocity.y > -50.0 and _player.get_air_jumps_left() > 0 and _air_move_to < 0:
		# Already in the air and coming down: now and then an air jump lifts it over the round (not every time,
		# or it would hardly touch the ground, where it dashes and slides).
		_force_jump(0.2)


func _reaction_time() -> float:
	return float(_profile["block_reaction"]) * randf_range(0.8, 1.25)


## A flat round at body height can be slid under: plans that slide (along the way the bot runs, else towards
## the shooter) on safe floor; false when it does not fit.
func _plan_slide_dodge(projectile: Projectile, me: Vector2, impact_time: float) -> bool:
	if ResearchManager.get_slide_profile(_player.player_slot).is_empty() or not _player.is_grounded():
		return false
	var velocity: Vector2 = projectile.velocity
	if absf(velocity.y) > absf(velocity.x) * 0.6:
		return false
	var fall: float = 0.5 * projectile.gravity * WorldConditions.projectile_gravity_scale * impact_time * impact_time
	var height: float = projectile.global_position.y + velocity.y * impact_time + fall - me.y
	if height < -16.0 or height > 4.0:
		return false
	var direction: float = signf(move_direction) if move_direction != 0.0 else signf(projectile.global_position.x - me.x)
	if direction == 0.0 or not _senses.stretch_is_safe(direction, SLIDE_REACH):
		return false
	var reaction: float = _reaction_time()
	if reaction >= impact_time:
		return false
	_timed.schedule(ACTION_SLIDE, maxf(impact_time - 0.16, reaction), direction)
	return true


## Times a dash against a round about to land; false when no dash fits. With protection the bot dashes
## through it (towards the shooter); without, it only sidesteps rounds coming down from above, since a flat
## shot follows it.
func _plan_dash_dodge(projectile: Projectile, me: Vector2, impact_time: float) -> bool:
	var velocity: Vector2 = projectile.velocity
	var direction: float = 0.0
	if ResearchManager.has_dash_protection(_player.player_slot):
		direction = signf(projectile.global_position.x - me.x)
	elif absf(velocity.y) > absf(velocity.x) * 0.6:
		direction = -signf(velocity.x) if absf(velocity.x) > 20.0 else (1.0 if randf() < 0.5 else -1.0)
	if direction == 0.0 or not _player.is_grounded() or not _senses.stretch_is_safe(direction, DASH_REACH):
		return false
	var reaction: float = _reaction_time()
	if reaction >= impact_time:
		return false
	_timed.schedule(ACTION_DASH, maxf(impact_time - GameSettings.PLAYER_DASH_TIME * 0.6, reaction), direction)
	return true


## The timed answers that are due now, checked again before they go out (the situation may have changed).
func _carry_out(due: Array[Dictionary]) -> void:
	for action in due:
		match StringName(action["kind"]):
			ACTION_BLOCK:
				# The round may be gone by now (it hit something else, or was blocked).
				if not is_instance_valid(action["data"]):
					continue
				var focus: Node2D = action["data"] as Node2D
				if focus != null and not _player.is_guard_broken() and _player.get_block_cooldown_ratio() >= 0.999:
					_block_focus = focus
					aim_position = focus.global_position
					block_pressed = true
					_block_focus_timer = _player.block_duration
			ACTION_SLIDE:
				var slide_direction: float = float(action["data"])
				if _player.is_grounded() and _senses.stretch_is_safe(slide_direction, SLIDE_REACH):
					slide_pressed = true
					move_direction = slide_direction
			ACTION_DASH:
				var dash_direction: float = float(action["data"])
				if _player.can_dash() and _player.is_grounded() and _senses.stretch_is_safe(dash_direction, DASH_REACH):
					_press_dash(dash_direction)


func _predict_impact_time(projectile: Projectile, me: Vector2, horizon: float = THREAT_HORIZON) -> float:
	var position: Vector2 = projectile.global_position
	var velocity: Vector2 = projectile.velocity
	var step: float = 1.0 / 60.0
	var t: float = 0.0
	var drift: Vector2 = WorldConditions.projectile_wind_acceleration(projectile.get_wind_response())
	while t < horizon:
		velocity.y += projectile.gravity * WorldConditions.projectile_gravity_scale * step
		velocity += drift * step
		position += velocity * step
		t += step
		if position.distance_to(me) < THREAT_RADIUS:
			return t
	return -1.0


# --- Time Control ------------------------------------------------------------------------------------------

## Casts Time Control as a comeback: low on health, or the target reloading or empty (an opening), with the
## target in sight and in range. Weighed every half second with a chance per difficulty, so it stays a rare,
## readable move rather than an instant reflex.
func _update_time_control(delta: float) -> void:
	_time_control_think_timer -= delta
	if _time_control_think_timer > 0.0:
		return
	_time_control_think_timer = TIME_CONTROL_THINK_INTERVAL
	if _target == null or _target.is_time_slowed() or not _player.can_cast_time_control():
		return
	var me: Vector2 = _player.global_position
	if me.distance_to(_target.global_position) > _weapon_range() or _senses.blocked(me, _target.global_position):
		return
	var health: HealthComponent = _player.health_component
	var low: bool = health != null and float(health.health) < float(health.max_health) * TIME_CONTROL_LOW_HEALTH
	var gun: Gun = _target.get_gun()
	var opening: bool = gun != null and (gun.is_reloading() or gun.get_current_ammo() <= 0)
	if (low or opening) and randf() < float(TIME_CONTROL_CHANCE.get(difficulty, 0.0)):
		time_control_pressed = true


# --- Aim and fire ------------------------------------------------------------------------------------------

func _update_aim_and_fire(delta: float) -> void:
	_fire_timer -= delta
	_solution_timer -= delta
	_block_focus_timer = maxf(_block_focus_timer - delta, 0.0)
	if _block_focus_timer > 0.0 and _block_focus != null and is_instance_valid(_block_focus):
		aim_position = _block_focus.global_position
		return
	if _target == null:
		_visible_time = 0.0
		return
	var gun: Variant = _player.get_gun()
	if gun == null:
		return

	_aim_error_timer -= delta
	if _aim_error_timer <= 0.0:
		_aim_error_timer = randf_range(0.25, 0.6)
		_aim_error_angle = deg_to_rad(randfn(0.0, float(_profile["aim_error"])))

	var ballistics: Dictionary = gun.get_ballistics()
	_wind_accel = float(ballistics.get("wind", 0.0))
	var speed: float = float(ballistics.get("speed", GameSettings.PROJECTILE_MUZZLE_SPEED))
	var gravity: float = float(ballistics.get("gravity", GameSettings.PROJECTILE_GRAVITY))
	var origin: Vector2 = _player.global_position
	var target_point: Vector2 = _target.global_position
	for _iteration in range(2):
		var flight_time: float = origin.distance_to(target_point) / maxf(speed, 1.0)
		target_point = _target.global_position + _target.velocity * flight_time * float(_profile["lead"])

	if _solution_timer <= 0.0:
		_solution_timer = 0.08
		_solution_direction = _find_clear_shot(origin, target_point, speed, gravity)
	# In a dust storm the bot only sees as far as a player does.
	var sight: float = lerpf(STORM_SIGHT_MIN, STORM_SIGHT_MAX, clampf(WorldConditions.visibility, 0.0, 1.0))
	var clear: bool = _solution_direction != Vector2.ZERO and origin.distance_to(_target.global_position) <= sight
	var desired: Vector2 = _solution_direction if clear else _aim_line(origin, target_point, speed, gravity, false)
	desired = desired.rotated(_aim_error_angle)
	var turn: float = clampf(float(_profile["turn_rate"]) * delta, 0.0, 1.0)
	_aim_direction = _aim_direction.slerp(desired, turn).normalized()
	aim_position = origin + _aim_direction * 220.0

	if clear:
		_visible_time += delta
		_blocked_time = 0.0
	else:
		_visible_time = maxf(_visible_time - delta * 2.0, 0.0)
		_blocked_time += delta
		if _blocked_time > 1.4 and _replan_timer > 0.1 and _stance.cover <= 0.0:
			_replan_timer = 0.0
	var aligned: bool = _aim_direction.dot(desired) > 0.985
	if clear and aligned and _visible_time >= float(_profile["reaction"]) and _fire_timer <= 0.0 and gun.is_ready_to_fire():
		shoot_pressed = true
		_fire_timer = float(_profile["fire_delay"]) + randf_range(0.0, 0.18)
		_shots_without_hit += 1
		if _shots_without_hit >= 5 and _target.velocity.length() < 40.0:
			# Five misses at a target standing still: this spot does not work, try another for a while.
			_shots_without_hit = 0
			_memory.give_up_goal(_goal_point, 8.0)
			_replan_timer = 0.0


## Returns a direction that reaches the target unobstructed (low arc first, then a lob), or ZERO.
func _find_clear_shot(origin: Vector2, target_point: Vector2, speed: float, gravity: float) -> Vector2:
	var arcs: Array[bool] = [false]
	if bool(_profile.get("use_lobs", false)):
		arcs.append(true)
	if origin.distance_to(target_point) < MUZZLE_REACH + 16.0:
		return (target_point - origin).normalized()
	for high_arc in arcs:
		var direction: Vector2 = _aim_line(origin, target_point, speed, gravity, high_arc)
		if direction == Vector2.ZERO:
			continue
		if _trajectory_reaches(origin + direction * MUZZLE_REACH, direction * speed, gravity, target_point):
			return direction
	return Vector2.ZERO


func _aim_line(origin: Vector2, target_point: Vector2, speed: float, gravity: float, high_arc: bool) -> Vector2:
	var muzzle: Vector2 = origin + (target_point - origin).normalized() * MUZZLE_REACH
	var direction: Vector2 = _solve_ballistic(muzzle, target_point, speed, gravity, high_arc)
	return _refine_aim(muzzle, target_point, direction, speed, gravity)


func _solve_ballistic(from: Vector2, to: Vector2, speed: float, gravity: float, high_arc: bool) -> Vector2:
	var dx: float = to.x - from.x
	var dy_up: float = from.y - to.y
	var x: float = absf(dx)
	if x < 8.0 or gravity <= 1.0:
		return Vector2.ZERO if high_arc else (to - from).normalized()
	var v2: float = speed * speed
	var discriminant: float = v2 * v2 - gravity * (gravity * x * x + 2.0 * dy_up * v2)
	var angle: float = PI * 0.25
	if discriminant >= 0.0:
		var root: float = sqrt(discriminant)
		angle = atan((v2 + root) / (gravity * x)) if high_arc else atan((v2 - root) / (gravity * x))
	elif high_arc:
		return Vector2.ZERO
	return Vector2(signf(dx) * cos(angle), -sin(angle)).normalized()


## Corrects the analytic solution against the engine's discrete integration (velocity updated before move).
func _refine_aim(from: Vector2, to: Vector2, direction: Vector2, speed: float, gravity: float) -> Vector2:
	var dx: float = to.x - from.x
	if absf(dx) < 20.0 or direction == Vector2.ZERO:
		return direction
	var result: Vector2 = direction
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	for _iteration in range(2):
		var position: Vector2 = from
		var velocity: Vector2 = result * speed
		var reached: bool = false
		for _index in range(150):
			velocity.y += gravity * step
			velocity.x += _wind_accel * step
			var next: Vector2 = position + velocity * step
			if (next.x - to.x) * signf(dx) >= 0.0:
				var ratio: float = absf(to.x - position.x) / maxf(absf(next.x - position.x), 0.0001)
				position = position.lerp(next, clampf(ratio, 0.0, 1.0))
				reached = true
				break
			position = next
		if not reached:
			return result
		var miss: float = position.y - to.y
		var correction: float = atan2(miss, absf(dx)) * (0.5 if result.y < -0.75 else 1.0)
		result = result.rotated(-correction * signf(dx)).normalized()
	return result


## Conservative line-of-fire test: a thick swept path (three parallel rays) must reach the target.
## Integrates like the projectile does, but casts rays along chords spanning a few steps. The centre ray goes
## first along the whole arc (most arcs are rejected there, at a third of the cost); only an arc that is
## clear down the middle gets its two side rays checked.
func _trajectory_reaches(start: Vector2, velocity: Vector2, gravity: float, target_point: Vector2) -> bool:
	var position: Vector2 = start
	var current_velocity: Vector2 = velocity
	var step: float = 1.0 / 60.0
	var chord_start: Vector2 = start
	var heading: float = signf(target_point.x - start.x)
	var chords: PackedVector2Array = PackedVector2Array([start])
	var reached: bool = false
	for index in range(TRAJECTORY_STEPS):
		current_velocity.y += gravity * step
		current_velocity.x += _wind_accel * step
		position += current_velocity * step
		var last_step: bool = index == TRAJECTORY_STEPS - 1
		if (index + 1) % TRAJECTORY_RAY_STRIDE != 0 and not last_step:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target_point, chord_start, position)
		var reaches: bool = closest.distance_to(target_point) < TARGET_HIT_RADIUS
		var chord_end: Vector2 = closest if reaches else position
		if chord_start.distance_squared_to(chord_end) >= 0.01 and _senses.blocked(chord_start, chord_end):
			return false
		chords.append(chord_end)
		if reaches:
			reached = true
			break
		if heading != 0.0 and (position.x - target_point.x) * heading > TARGET_HIT_RADIUS * 2.0:
			return false
		if current_velocity.y > 0.0 and position.y > target_point.y + 260.0:
			return false
		chord_start = position
	if not reached:
		return false
	for index in range(chords.size() - 1):
		if _side_rays_blocked(chords[index], chords[index + 1]):
			return false
	return true


func _side_rays_blocked(from: Vector2, to: Vector2) -> bool:
	if from.distance_squared_to(to) < 0.01:
		return false
	var side: Vector2 = (to - from).orthogonal().normalized() * 6.0
	return _senses.blocked(from + side, to + side) or _senses.blocked(from - side, to - side)


# --- Sandbox dummy -----------------------------------------------------------------------------------------

func _update_dummy(delta: float) -> void:
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(1.5, 3.5)
		_goal_x = _home_x + randf_range(-70.0, 70.0)
		if randf() < 0.25 and _player.is_grounded():
			_request_jump(0.15)
	var me: Vector2 = _player.global_position
	var direction: float = signf(_goal_x - me.x) if absf(_goal_x - me.x) > 14.0 else 0.0
	if direction != 0.0 and not _senses.step_has_ground(direction):
		direction = 0.0
		_goal_x = me.x
	move_direction = direction * 0.45
	aim_position = _target.global_position if _target != null else me + Vector2(-200.0, 0.0)


# --- Helpers -----------------------------------------------------------------------------------------------

func _find_target() -> Player:
	var best: Player = null
	var best_distance: float = INF
	for node in _player.get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var other: Player = node as Player
		if other == null or other == _player or other.is_eliminated() or other.player_slot == _player.player_slot:
			continue
		var distance: float = other.global_position.distance_squared_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


## Flat-ground maximum range of the current weapon (v² / g), clamped to sensible engagement distances.
func _weapon_range() -> float:
	var gun: Variant = _player.get_gun()
	if gun == null:
		return 380.0
	var ballistics: Dictionary = gun.get_ballistics()
	_wind_accel = float(ballistics.get("wind", 0.0))
	var speed: float = float(ballistics.get("speed", GameSettings.PROJECTILE_MUZZLE_SPEED))
	var gravity: float = maxf(float(ballistics.get("gravity", GameSettings.PROJECTILE_GRAVITY)), 1.0)
	return clampf(speed * speed / gravity, 220.0, 900.0)


func _map_bounds() -> Rect2:
	var bounds_node: Node = _player.get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node != null:
		var bounds: Variant = bounds_node.get("bounds")
		if bounds is Rect2:
			return bounds
	return GameSettings.DEFAULT_MAP_BOUNDS
