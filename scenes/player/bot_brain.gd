class_name BotBrain
extends Node

## AI controller for a Player in CONTROL_AI mode. Produces the same inputs a human would:
## movement axis, jump press/hold, shoot press, block press, dash press and an aim position.
## Movement follows a LevelNavigation graph; firing positions are scored with real ballistic
## line-of-fire checks (including high lobs over cover), amortised across physics frames.

enum Difficulty { DUMMY = -1, EASY = 0, NORMAL = 1, HARD = 2 }

## Distance the bot can see in the thickest storm and in clear air.
const STORM_SIGHT_MIN: float = 380.0
const STORM_SIGHT_MAX: float = 4000.0
const PROFILES: Dictionary = {
	Difficulty.EASY: {
		"aim_error": 7.5, "reaction": 0.45, "fire_delay": 0.6, "block_chance": 0.18, "block_reaction": 0.3,
		"lead": 0.35, "preferred_distance": 0.85, "dodge_chance": 0.12, "turn_rate": 4.0, "pressure": 0.35,
		"use_lobs": false, "capture_drive": 2.2, "dash_dodge": 0.15, "dash_drive": 0.18,
	},
	Difficulty.NORMAL: {
		"aim_error": 3.2, "reaction": 0.27, "fire_delay": 0.25, "block_chance": 0.48, "block_reaction": 0.17,
		"lead": 0.75, "preferred_distance": 0.7, "dodge_chance": 0.28, "turn_rate": 7.5, "pressure": 0.6,
		"use_lobs": true, "capture_drive": 3.6, "dash_dodge": 0.35, "dash_drive": 0.4,
	},
	Difficulty.HARD: {
		"aim_error": 1.3, "reaction": 0.15, "fire_delay": 0.07, "block_chance": 0.78, "block_reaction": 0.09,
		"lead": 1.0, "preferred_distance": 0.58, "dodge_chance": 0.42, "turn_rate": 13.0, "pressure": 0.85,
		"use_lobs": true, "capture_drive": 4.6, "dash_dodge": 0.6, "dash_drive": 0.65,
	},
}

const WORLD_MASK: int = 1
const SAFE_DROP_DEPTH: float = 420.0
const THREAT_HORIZON: float = 0.32
const THREAT_RADIUS: float = 28.0
const CANDIDATES_PER_FRAME: int = 5
const SEARCH_BUDGET_USEC: int = 1200
const SOLUTION_BONUS: float = 3.0
## Shortest gap between two goal searches. Replans can be requested every frame (blocked line of fire,
## getting stuck); the ranked search finishes in a frame or two, so without this it would rerun constantly.
const MIN_SEARCH_INTERVAL: float = 0.35
## In the air the bot never steers weaker than this share of full speed, so a jump always makes progress.
const MIN_AIR_STEER: float = 0.2
## Ground speed (px/s) a jump tolerates beyond what its arc needs, or against it, before the bot brakes.
const TAKEOFF_SPEED_TOLERANCE: float = 110.0
## Longest the bot brakes before a jump; on a slope or in a storm it may never get slow enough.
const MAX_TAKEOFF_BRAKE: float = 0.25
const TRAJECTORY_STEPS: int = 90
const TRAJECTORY_RAY_STRIDE: int = 2
const TARGET_HIT_RADIUS: float = 20.0
const MUZZLE_REACH: float = 34.0
## How far a dash carries (burst plus the glide after it) and how often the bot weighs dashing on purpose.
const DASH_REACH: float = 160.0
const DASH_THINK_INTERVAL: float = 0.35
## Research marks per difficulty (Dashing, Wall Jumps, Time Control): bots never visit the research page, so
## the game hands them these.
const DASH_MARKS: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.NORMAL: 2,
	Difficulty.HARD: 4,
}
## Time Control Mk per difficulty (0: none). Bots cast it as a comeback: low on health, or the target reloading.
const TIME_CONTROL_MARKS: Dictionary = {
	Difficulty.EASY: 0,
	Difficulty.NORMAL: 1,
	Difficulty.HARD: 3,
}
const WALL_JUMP_MARKS: Dictionary = {
	Difficulty.EASY: 0,
	Difficulty.NORMAL: 1,
	Difficulty.HARD: 3,
}
## Health share below which a bot reaches for Time Control, how often it weighs casting, and the chance per
## look by difficulty (a human gets a moment to read the situation first).
const TIME_CONTROL_LOW_HEALTH: float = 0.4
const TIME_CONTROL_THINK_INTERVAL: float = 0.5
const TIME_CONTROL_CHANCE: Dictionary = {
	Difficulty.EASY: 0.0,
	Difficulty.NORMAL: 0.35,
	Difficulty.HARD: 0.6,
}
## A climb that ends back at the wall's foot takes climbing out of the plans for this long.
const FAILED_CLIMB_PAUSE_MSEC: int = 6000

var difficulty: int = Difficulty.NORMAL
var move_direction: float = 0.0
var jump_pressed: bool = false
var jump_held: bool = false
var shoot_pressed: bool = false
var block_pressed: bool = false
var time_control_pressed: bool = false
var dash_pressed: bool = false
var aim_position: Vector2 = Vector2.ZERO

var _player: Player = null
var _profile: Dictionary = {}
var _target: Player = null
var _space: PhysicsDirectSpaceState2D = null
var _nav: LevelNavigation = null
var _home_x: float = 0.0
var _goal_x: float = 0.0
var _decision_timer: float = 0.0

var _path: PackedInt64Array = PackedInt64Array()
var _path_index: int = 0
var _goal_point: int = -1
var _replan_timer: float = 0.0
var _search_cooldown: float = 0.0
var _air_target_x: float = INF
## Sideways speed of the jump or drop in progress, as the navigation validated it.
var _air_speed_x: float = 0.0
var _takeoff_brake_timer: float = 0.0
var _stuck_timer: float = 0.0
## Candidate goal points for the running search with their cheap (raycast-free) scores, best last.
var _search_queue: Array[int] = []
var _search_scores: PackedFloat32Array = PackedFloat32Array()
var _search_best: int = -1
var _search_best_score: float = -INF
var _bad_goals: Dictionary = {}
var _search_bounds: Rect2 = Rect2()
var _search_speed: float = 0.0
var _search_gravity: float = 0.0
## Sideways acceleration the wind puts on the bot's own rounds (Mars storms); folded into every aim solve.
var _wind_accel: float = 0.0
var _search_range: float = 0.0
var _search_capture: Dictionary = {}
var _ray_query: PhysicsRayQueryParameters2D = null

var _jump_hold_timer: float = 0.0
var _jump_cooldown: float = 0.0

var _fire_timer: float = 0.6
var _visible_time: float = 0.0
var _blocked_time: float = 0.0
var _shots_without_hit: int = 0
var _aim_direction: Vector2 = Vector2.LEFT
var _aim_error_angle: float = 0.0
var _aim_error_timer: float = 0.0
var _solution_timer: float = 0.0
var _solution_direction: Vector2 = Vector2.ZERO

var _evaluated_threats: Dictionary = {}
var _pending_block_time: float = -1.0
var _block_focus: Node2D = null
var _block_focus_timer: float = 0.0
var _dash_think_timer: float = 0.0
var _time_control_think_timer: float = 0.0
var _pending_dash_time: float = -1.0
var _pending_dash_direction: float = 0.0
## Set after a dash along the path: the waypoints it flew past are skipped instead of walked back to.
var _skip_passed_points: bool = false
## A wall climb in progress: the way to the wall (0 when not climbing) and the ledge's height.
var _climb_direction: float = 0.0
var _climb_top_y: float = 0.0
var _climbs_blocked_until: int = 0


## Research marks a bot of this difficulty fights with.
static func research_marks(bot_difficulty: int) -> Dictionary:
	if not DASH_MARKS.has(bot_difficulty):
		return {}
	var marks: Dictionary = {
		str(ResearchManager.DASHING): int(DASH_MARKS[bot_difficulty]),
		str(ResearchManager.WALL_JUMPS): int(WALL_JUMP_MARKS[bot_difficulty]),
	}
	if int(TIME_CONTROL_MARKS.get(bot_difficulty, 0)) > 0:
		marks[str(ResearchManager.TIME_CONTROL)] = int(TIME_CONTROL_MARKS[bot_difficulty])
	return marks


func setup(player: Player, bot_difficulty: int) -> void:
	_player = player
	difficulty = bot_difficulty
	_profile = PROFILES.get(difficulty, PROFILES[Difficulty.NORMAL])
	process_physics_priority = -10
	_home_x = player.global_position.x
	_goal_x = _home_x
	aim_position = player.global_position + Vector2(-200.0, 0.0)
	_ray_query = PhysicsRayQueryParameters2D.new()
	_ray_query.collision_mask = WORLD_MASK
	_ray_query.exclude = [player.get_rid()]
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
	_space = _player.get_world_2d().direct_space_state
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
	if _player == null or not is_instance_valid(_player) or _player.is_eliminated() or not _player.movement_enabled:
		move_direction = 0.0
		jump_held = false
		_visible_time = 0.0
		return
	# A slowed bot thinks, reacts and aims on its slowed clock too (Time Control).
	delta *= _player.time_scale
	_space = _player.get_world_2d().direct_space_state
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	_update_jump_hold(delta)
	_target = _find_target()
	if difficulty == Difficulty.DUMMY:
		_update_dummy(delta)
		return
	_update_threats(delta)
	_update_movement(delta)
	_update_dash(delta)
	_update_aim_and_fire(delta)
	_update_time_control(delta)


# --- Movement --------------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	_ensure_navigation()
	if _nav == null or not _nav.is_valid():
		_update_movement_fallback(delta)
		return
	var me: Vector2 = _player.global_position
	var feet: Vector2 = me + Vector2(0.0, _player.hover_dist)
	var grounded: bool = _player.is_grounded()
	if grounded and _player.is_time_slowed() and _target != null:
		_back_off_in_slowed_time(me)
		return

	_replan_timer -= delta
	_search_cooldown -= delta
	if _replan_timer <= 0.0 and _search_queue.is_empty() and _search_cooldown <= 0.0:
		_replan_timer = randf_range(0.7, 1.2)
		_search_cooldown = MIN_SEARCH_INTERVAL
		_begin_goal_search()
	_continue_goal_search(feet, grounded)
	if grounded:
		_air_target_x = INF
		if _climb_direction != 0.0:
			_climb_direction = 0.0
			if feet.y > _climb_top_y + 20.0:
				_climbs_blocked_until = Time.get_ticks_msec() + FAILED_CLIMB_PAUSE_MSEC
				_replan_timer = 0.0
		if _skip_passed_points and not _player.is_dashing():
			_skip_passed_points = false
			_skip_walked_points(feet)
		if _path_index >= _path.size() and _goal_point >= 0 and _nav.nearest_point(feet, 60.0) != _goal_point:
			_plan_path(feet)

	var direction: float = 0.0
	if not grounded:
		if _air_target_x != INF:
			var to_target: float = _air_target_x - me.x
			if absf(to_target) > 6.0:
				# Fly the arc the navigation checked: at full speed a jump up to a ledge above and to the
				# side runs under the ledge and bumps its head instead of rising past the edge first.
				var share: float = absf(_air_speed_x) / maxf(_player.speed, 1.0)
				direction = signf(to_target) * clampf(maxf(share, MIN_AIR_STEER), 0.0, 1.0)
		if _climb_direction != 0.0:
			# Climbing: keep pushing into the wall and kick off it whenever it is reached below the ledge.
			direction = _climb_direction
			if _player.is_on_wall() and feet.y > _climb_top_y - 4.0 and _player.velocity.y > -80.0:
				jump_pressed = true
				jump_held = true
				_jump_hold_timer = 0.3
		if not _has_ground_below(me, 700.0) and (_air_target_x == INF or not _has_ground_below(Vector2(_air_target_x, me.y), 700.0)):
			direction = _nearest_safe_side(me)
		if _player.is_on_wall() and _player.velocity.y > 0.0 and not _has_ground_below(me, 500.0):
			_force_jump(0.3)
		move_direction = direction
		return

	if _path_index < _path.size():
		var current_id: int = int(_path[_path_index])
		var current: Vector2 = _nav.points[current_id]
		var arrive_distance: float = 16.0 if _path_index == 0 else 9.0
		if absf(feet.x - current.x) <= arrive_distance:
			if _path_index + 1 < _path.size():
				var next_id: int = int(_path[_path_index + 1])
				var next: Vector2 = _nav.points[next_id]
				var move: Dictionary = _nav.get_move(current_id, next_id)
				var air_speed: float = float(move.get("vx", 0.0))
				if int(move["move"]) == LevelNavigation.Move.JUMP and _too_fast_for_takeoff(air_speed) and _takeoff_brake_timer < MAX_TAKEOFF_BRAKE:
					# Still running the wrong way (or too fast) for this jump: brake on the spot first.
					_takeoff_brake_timer += delta
					move_direction = 0.0
					_stuck_timer = 0.0
					return
				_takeoff_brake_timer = 0.0
				_path_index += 1
				direction = signf(next.x - feet.x)
				_air_speed_x = air_speed
				match int(move["move"]):
					LevelNavigation.Move.JUMP:
						_force_jump(float(move["hold"]))
						_air_target_x = next.x
					LevelNavigation.Move.DROP:
						_air_target_x = next.x
					LevelNavigation.Move.CLIMB:
						_force_jump(float(move["hold"]))
						_air_target_x = next.x
						_climb_direction = signf(next.x - feet.x)
						_climb_top_y = next.y
			else:
				_path_index += 1
		else:
			direction = signf(current.x - feet.x)
	elif _target != null and absf(_target.global_position.x - me.x) < 120.0:
		direction = signf(me.x - _target.global_position.x)
		if not _has_ground_below(me + Vector2(direction * 34.0, 0.0), SAFE_DROP_DEPTH):
			direction = 0.0

	if direction != 0.0 and absf(_player.velocity.x) < 10.0:
		_stuck_timer += delta
		if _stuck_timer > 0.5:
			_stuck_timer = 0.0
			_force_jump(0.3)
			_replan_timer = 0.0
	else:
		_stuck_timer = 0.0
	move_direction = direction


func _too_fast_for_takeoff(air_speed: float) -> bool:
	# Measured against the ground speed the wind settles a standing bot at, which braking cannot undo.
	var speed: float = _player.velocity.x - _player.get_wind_drift_speed()
	var against: bool = signf(speed) != signf(air_speed) and absf(speed) > TAKEOFF_SPEED_TOLERANCE
	return against or absf(speed) > absf(air_speed) + TAKEOFF_SPEED_TOLERANCE


func _ensure_navigation() -> void:
	if _nav != null:
		return
	var bounds_node: Node = _player.get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node == null or bounds_node.get_parent() == null:
		return
	_nav = LevelNavigation.get_for(bounds_node.get_parent(), _space, _map_bounds())


func _plan_path(feet: Vector2) -> void:
	_path = PackedInt64Array()
	_path_index = 0
	_takeoff_brake_timer = 0.0
	var start_id: int = _nav.nearest_point(feet, 90.0)
	if start_id < 0 or _goal_point < 0:
		return
	_path = _nav.find_path(start_id, _goal_point, _climb_reach())


## How high this bot can climb a wall with its Wall Jumps marks (0 while climbing is paused after a fail).
func _climb_reach() -> float:
	if Time.get_ticks_msec() < _climbs_blocked_until:
		return 0.0
	var slot: int = _player.player_slot
	return _nav.wall_climb_reach(ResearchManager.get_wall_jump_limit(slot), ResearchManager.get_wall_jump_strength(slot).y > 1.0)


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
	var feet: Vector2 = _player.global_position + Vector2(0.0, _player.hover_dist)
	# (cheap score, point index) pairs; Vector2 sorts by x first, natively.
	var ranked: Array[Vector2] = []
	for index in range(_nav.points.size()):
		if _target == null or absf(_nav.points[index].x - _target.global_position.x) < reach or index == _goal_point:
			ranked.append(Vector2(_cheap_score(index, feet), float(index)))
	# Worst first, so pop_back() hands out the most promising candidate. Only the ballistic check is
	# expensive and it can only add SOLUTION_BONUS, so the search can stop as soon as no remaining candidate
	# could beat the best one even with that bonus: same winner as checking everything, far fewer raycasts.
	ranked.sort()
	_search_scores.resize(ranked.size())
	for index in range(ranked.size()):
		_search_queue.append(int(ranked[index].y))
		_search_scores[index] = ranked[index].x


func _continue_goal_search(feet: Vector2, grounded: bool) -> void:
	if _search_queue.is_empty():
		return
	var started_usec: int = Time.get_ticks_usec()
	for _step in range(CANDIDATES_PER_FRAME):
		if _search_queue.is_empty() or Time.get_ticks_usec() - started_usec > SEARCH_BUDGET_USEC:
			break
		var cheap: float = _search_scores[_search_queue.size() - 1]
		if cheap + SOLUTION_BONUS <= _search_best_score:
			_search_queue.clear()
			break
		var candidate: int = _search_queue.pop_back()
		var score: float = cheap + _shot_bonus(candidate)
		if score > _search_best_score:
			_search_best_score = score
			_search_best = candidate
	if _search_queue.is_empty() and _search_best >= 0:
		var changed: bool = _search_best != _goal_point
		_goal_point = _search_best
		if changed and grounded:
			_plan_path(feet)


## SOLUTION_BONUS when a round fired from this goal point would reach the target, else 0.
func _shot_bonus(candidate: int) -> float:
	if _target == null:
		return 0.0
	var target_center: Vector2 = _target.global_position
	var from: Vector2 = _nav.points[candidate] - Vector2(0.0, _player.hover_dist)
	if from.distance_to(target_center) <= _search_range * 1.15 and _find_clear_shot(from, target_center, _search_speed, _search_gravity) != Vector2.ZERO:
		return SOLUTION_BONUS
	return 0.0


## Everything about a goal point that needs no raycast: distance to the preferred range, height, edges,
## travel, stickiness to the current goal, remembered bad spots and supply-drop pull.
func _cheap_score(candidate: int, feet: Vector2) -> float:
	var point: Vector2 = _nav.points[candidate]
	if _target == null:
		return -absf(point.x - _home_x) / 200.0
	var target_center: Vector2 = _target.global_position
	var preferred: float = _search_range * float(_profile["preferred_distance"])
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
	if int(_bad_goals.get(candidate, 0)) > Time.get_ticks_msec():
		score -= 3.0
	score += _capture_bonus(point)
	score += randf() * 0.15
	return score


## Pull towards supply drops in set-based matches: strong once the crate is down, a lighter lean
## towards the landing zone while it is still announced or falling.
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
		if not _has_ground_below(me + Vector2(direction * 34.0, 0.0), SAFE_DROP_DEPTH):
			direction = 0.0
		elif _wall_ahead(direction):
			_request_jump(0.28)
	move_direction = direction


func _nearest_safe_side(from: Vector2) -> float:
	for offset in [60.0, 120.0, 200.0, 300.0]:
		for direction in [1.0, -1.0]:
			if _has_ground_below(Vector2(from.x + direction * offset, from.y - 40.0), 400.0):
				return direction
	return 0.0


func _has_ground_below(from: Vector2, depth: float) -> bool:
	return not _ray(from, from + Vector2(0.0, depth)).is_empty()


func _wall_ahead(direction: float) -> bool:
	var me: Vector2 = _player.global_position
	var hit: Dictionary = _ray(me, me + Vector2(direction * 34.0, 0.0))
	return not hit.is_empty() and absf((hit["normal"] as Vector2).x) > 0.7


## Caught in slowed time the bot cannot win a trade: it backs away from the target along safe floor (dashing
## when it can) and leans on its block (see _update_threats) until the clock runs normally again.
func _back_off_in_slowed_time(me: Vector2) -> void:
	var away: float = signf(me.x - _target.global_position.x)
	if away == 0.0:
		away = 1.0 if randf() < 0.5 else -1.0
	if _wall_ahead(away) or not _has_ground_below(me + Vector2(away * 34.0, 0.0), SAFE_DROP_DEPTH):
		away = -away
		if _wall_ahead(away) or not _has_ground_below(me + Vector2(away * 34.0, 0.0), SAFE_DROP_DEPTH):
			move_direction = 0.0
			return
	move_direction = away
	if _player.can_dash() and _dash_is_safe(away) and not _player.is_time_frozen():
		_press_dash(away)
	_replan_timer = 0.0


# --- Time Control ------------------------------------------------------------------------

## Casts Time Control as a comeback: low on health, or the target reloading or empty (an opening), with
## the target in sight and in range. Weighed every half second with a chance per difficulty, so it stays a
## rare, readable move rather than an instant reflex.
func _update_time_control(delta: float) -> void:
	_time_control_think_timer -= delta
	if _time_control_think_timer > 0.0:
		return
	_time_control_think_timer = TIME_CONTROL_THINK_INTERVAL
	if _target == null or _target.is_time_slowed() or not _player.can_cast_time_control():
		return
	var me: Vector2 = _player.global_position
	if me.distance_to(_target.global_position) > _weapon_range() or _ray_blocked(me, _target.global_position):
		return
	var health: HealthComponent = _player.health_component
	var low: bool = health != null and float(health.health) < float(health.max_health) * TIME_CONTROL_LOW_HEALTH
	var gun: Gun = _target.get_gun()
	var opening: bool = gun != null and (gun.is_reloading() or gun.get_current_ammo() <= 0)
	if (low or opening) and randf() < float(TIME_CONTROL_CHANCE.get(difficulty, 0.0)):
		time_control_pressed = true


# --- Dash ------------------------------------------------------------------------------

## Fires a planned dodge on time, otherwise now and then dashes on purpose: away when hurt and pressed,
## into a shockwave poke when the target stands close, or along a flat stretch of the path to close the
## gap. Never off a ledge or into a wall.
func _update_dash(delta: float) -> void:
	if _pending_dash_time >= 0.0:
		_pending_dash_time -= delta
		if _pending_dash_time < 0.0:
			if _player.can_dash() and _player.is_grounded() and _dash_is_safe(_pending_dash_direction):
				_press_dash(_pending_dash_direction)
			return
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
		if hurt and away != 0.0 and absf(_target.global_position.x - me.x) < 180.0 and _dash_is_safe(away):
			_press_dash(away)
			return
	if _target != null and ResearchManager.has_dash_shockwave(_player.player_slot):
		var offset: Vector2 = _target.global_position - me
		if absf(offset.x) > 50.0 and absf(offset.x) < 140.0 and absf(offset.y) < 40.0 and _dash_is_safe(signf(offset.x), absf(offset.x)):
			_press_dash(signf(offset.x))
			return
	var direction: float = move_direction
	if direction == 0.0 or _walk_ahead(direction) < DASH_REACH:
		return
	var closing: bool = _target == null or absf(_target.global_position.x - me.x) > _weapon_range() * float(_profile["preferred_distance"]) + 120.0
	if (closing or not _search_capture.is_empty()) and _dash_is_safe(direction):
		_press_dash(direction)
		_skip_passed_points = true


func _press_dash(direction: float) -> void:
	dash_pressed = true
	move_direction = direction
	_dash_think_timer = DASH_THINK_INTERVAL


## Times a dash against a round about to land; false when no dash fits. With protection the bot dashes
## through it (towards the shooter); without, it only sidesteps rounds coming down from above, since a
## flat shot follows it.
func _plan_dash_dodge(projectile: Projectile, me: Vector2, impact_time: float) -> bool:
	var velocity: Vector2 = projectile.velocity
	var direction: float = 0.0
	if ResearchManager.has_dash_protection(_player.player_slot):
		direction = signf(projectile.global_position.x - me.x)
	elif absf(velocity.y) > absf(velocity.x) * 0.6:
		direction = -signf(velocity.x) if absf(velocity.x) > 20.0 else (1.0 if randf() < 0.5 else -1.0)
	if direction == 0.0 or not _player.is_grounded() or not _dash_is_safe(direction):
		return false
	var reaction: float = float(_profile["block_reaction"]) * randf_range(0.8, 1.25)
	if reaction >= impact_time:
		return false
	_pending_dash_time = maxf(impact_time - GameSettings.PLAYER_DASH_TIME * 0.6, reaction)
	_pending_dash_direction = direction
	return true


## Floor all the way (no pit, no step down deeper than a hop, no lip taller than the dash climbs) and
## nothing in the way for a dash of `reach` px.
func _dash_is_safe(direction: float, reach: float = DASH_REACH) -> bool:
	if direction == 0.0:
		return false
	var me: Vector2 = _player.global_position
	if _ray_blocked(me, me + Vector2(direction * (reach + 16.0), 0.0)):
		return false
	var depth: float = _player.hover_dist + 30.0
	var floor_hit: Dictionary = _ray(me, me + Vector2(0.0, depth))
	var max_drop: float = 60.0
	if floor_hit.is_empty():
		return false
	var floor_y: float = (floor_hit["position"] as Vector2).y
	var steps: int = int(ceil(reach / 40.0))
	for step in range(1, steps + 1):
		var x: float = me.x + direction * minf(float(step) * 40.0, reach)
		var hit: Dictionary = _ray(Vector2(x, me.y - GameSettings.PLAYER_DASH_STEP_HEIGHT), Vector2(x, me.y + depth + max_drop))
		if hit.is_empty():
			return false
		var rise: float = floor_y - (hit["position"] as Vector2).y
		if rise > GameSettings.PLAYER_DASH_STEP_HEIGHT - 2.0 or rise < -max_drop:
			return false
	return true


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


# --- Combat ---------------------------------------------------------------------------

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
	var sight: float = lerpf(BotBrain.STORM_SIGHT_MIN, BotBrain.STORM_SIGHT_MAX, clampf(WorldConditions.visibility, 0.0, 1.0))
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
		if _blocked_time > 1.4 and _replan_timer > 0.1:
			_replan_timer = 0.0
	var aligned: bool = _aim_direction.dot(desired) > 0.985
	if clear and aligned and _visible_time >= float(_profile["reaction"]) and _fire_timer <= 0.0 and gun.is_ready_to_fire():
		shoot_pressed = true
		_fire_timer = float(_profile["fire_delay"]) + randf_range(0.0, 0.18)
		_shots_without_hit += 1
		if _shots_without_hit >= 5 and _target.velocity.length() < 40.0:
			_shots_without_hit = 0
			_bad_goals[_goal_point] = Time.get_ticks_msec() + 8000
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
## Integrates like the projectile does, but casts rays along chords spanning a few steps. The centre ray
## goes first along the whole arc (most arcs are rejected there, at a third of the cost); only an arc that
## is clear down the middle gets its two side rays checked.
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
		if chord_start.distance_squared_to(chord_end) >= 0.01 and _ray_blocked(chord_start, chord_end):
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
	return _ray_blocked(from + side, to + side) or _ray_blocked(from - side, to - side)


func _update_threats(delta: float) -> void:
	var world: Node = _player.get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_projectiles_root"):
		return
	var me: Vector2 = _player.global_position
	if _pending_block_time >= 0.0:
		_pending_block_time -= delta
		if _pending_block_time <= 0.0:
			_pending_block_time = -1.0
			if _block_focus != null and is_instance_valid(_block_focus) and _player.get_block_cooldown_ratio() >= 0.999:
				aim_position = _block_focus.global_position
				block_pressed = true
				_block_focus_timer = _player.block_duration
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
		var block_ready: bool = _player.get_block_cooldown_ratio() >= 0.999 and not _player.is_blocking()
		# A protected dash beats a block (it also moves); without protection the dash only sidesteps lobs.
		var dash_odds: float = float(_profile.get("dash_dodge", 0.0)) * (1.0 if ResearchManager.has_dash_protection(_player.player_slot) else 0.5)
		if _pending_dash_time < 0.0 and _player.can_dash() and randf() < dash_odds and _plan_dash_dodge(projectile, me, impact_time):
			pass
		elif block_ready and randf() < (maxf(float(_profile["block_chance"]), 0.85) if _player.is_time_slowed() else float(_profile["block_chance"])):
			var reaction: float = float(_profile["block_reaction"]) * randf_range(0.8, 1.25)
			if reaction < impact_time:
				_block_focus = projectile
				_pending_block_time = maxf(impact_time - _player.block_duration * 0.5, reaction)
		elif randf() < float(_profile["dodge_chance"]) and _player.is_grounded():
			_request_jump(0.25)
	if _evaluated_threats.size() > 64:
		_evaluated_threats.clear()


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


# --- Sandbox dummy -----------------------------------------------------------------------

func _update_dummy(delta: float) -> void:
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(1.5, 3.5)
		_goal_x = _home_x + randf_range(-70.0, 70.0)
		if randf() < 0.25 and _player.is_grounded():
			_request_jump(0.15)
	var me: Vector2 = _player.global_position
	var direction: float = signf(_goal_x - me.x) if absf(_goal_x - me.x) > 14.0 else 0.0
	if direction != 0.0 and not _has_ground_below(me + Vector2(direction * 34.0, 0.0), SAFE_DROP_DEPTH):
		direction = 0.0
		_goal_x = me.x
	move_direction = direction * 0.45
	aim_position = _target.global_position if _target != null else me + Vector2(-200.0, 0.0)


# --- Helpers -----------------------------------------------------------------------------

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


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	if _space == null or _ray_query == null:
		return {}
	_ray_query.from = from
	_ray_query.to = to
	return _space.intersect_ray(_ray_query)


func _ray_blocked(from: Vector2, to: Vector2) -> bool:
	return not _ray(from, to).is_empty()


func _map_bounds() -> Rect2:
	var bounds_node: Node = _player.get_tree().get_first_node_in_group(GameSettings.MAP_BOUNDS_GROUP)
	if bounds_node != null:
		var bounds: Variant = bounds_node.get("bounds")
		if bounds is Rect2:
			return bounds
	return GameSettings.DEFAULT_MAP_BOUNDS
