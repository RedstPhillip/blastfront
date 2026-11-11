class_name BotRouteMemory
extends RefCounted

## What one bot has learned the hard way about the level, forgotten again after a while: moves (navigation
## edges) it failed, spots it kept getting stuck at, goals it gave up on, and whether climbing just failed.
## It runs on the bot's own clock (tick), so memories age the same at any frame rate and in slowed time.

## A failed jump / drop / climb is avoided this long.
const FAILED_MOVE_SECONDS: float = 12.0
## Stuck STUCK_LIMIT times within STUCK_MEMORY_SECONDS inside STUCK_RADIUS px counts as a hopeless spot.
const STUCK_LIMIT: int = 3
const STUCK_MEMORY_SECONDS: float = 6.0
const STUCK_RADIUS: float = 70.0
## A goal given up on is left alone this long.
const BAD_GOAL_SECONDS: float = 9.0
## A climb that ends back at the wall's foot takes climbing out of the plans for this long.
const CLIMB_PAUSE_SECONDS: float = 6.0

var _now: float = 0.0
var _failed_moves: Dictionary = {}
var _stuck_spots: Array[Dictionary] = []
var _bad_goals: Dictionary = {}
var _climbs_paused_until: float = 0.0


func tick(delta: float) -> void:
	_now += delta


func fail_move(from_id: int, to_id: int) -> void:
	_failed_moves[LevelNavigation.edge_key(from_id, to_id)] = _now + FAILED_MOVE_SECONDS


## Edge keys of the moves still avoided (expired ones are dropped here), for LevelNavigation.find_path.
func avoided_moves() -> Dictionary:
	for key in _failed_moves.keys():
		if float(_failed_moves[key]) <= _now:
			_failed_moves.erase(key)
	return _failed_moves


func avoided_count() -> int:
	return avoided_moves().size()


## Index of the first point of `path` whose move on is avoided, or -1.
func first_avoided(path: PackedInt64Array) -> int:
	var avoided: Dictionary = avoided_moves()
	for index in range(path.size() - 1):
		if avoided.has(LevelNavigation.edge_key(int(path[index]), int(path[index + 1]))):
			return index
	return -1


## Remembers a stuck spot; true when it is the STUCK_LIMIT-th time near here lately (and forgets the spots).
func note_stuck(at: Vector2) -> bool:
	var recent: Array[Dictionary] = []
	for spot in _stuck_spots:
		if _now - float(spot["time"]) < STUCK_MEMORY_SECONDS:
			recent.append(spot)
	recent.append({"time": _now, "pos": at})
	_stuck_spots = recent
	var near: int = 0
	for spot in recent:
		if (spot["pos"] as Vector2).distance_to(at) < STUCK_RADIUS:
			near += 1
	if near < STUCK_LIMIT:
		return false
	_stuck_spots.clear()
	return true


func stuck_count() -> int:
	return _stuck_spots.size()


func give_up_goal(goal: int, seconds: float = BAD_GOAL_SECONDS) -> void:
	if goal >= 0:
		_bad_goals[goal] = _now + seconds


func is_bad_goal(goal: int) -> bool:
	return float(_bad_goals.get(goal, -1.0)) > _now


func pause_climbs() -> void:
	_climbs_paused_until = _now + CLIMB_PAUSE_SECONDS


func climbs_paused() -> bool:
	return _now < _climbs_paused_until
