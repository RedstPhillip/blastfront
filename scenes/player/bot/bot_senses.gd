class_name BotSenses
extends RefCounted

## What one bot can feel of the level around its body: floor, walls, pits, headroom over water, and the
## hazards it must keep out of (BotHazards). Every probe the brain makes goes through here, so "is this
## stretch safe" means the same thing for a dash, a slide, a step, a retreat and an escape.

const WORLD_MASK: int = 1
## Deepest drop a bot walks off without a plan (anything deeper is a pit).
const SAFE_DROP_DEPTH: float = 420.0
## Spacing of the floor checks along a stretch, and the deepest step down a stretch may have.
const STRETCH_STEP: float = 40.0
const STRETCH_MAX_DROP: float = 60.0
## How far (px) the bot looks either way for the edge of a hazard it stands in.
const ESCAPE_REACH: float = 260.0

var _player: Player = null
var _space: PhysicsDirectSpaceState2D = null
var _query: PhysicsRayQueryParameters2D = null
var _hazards: Array[Dictionary] = []


func _init(player: Player) -> void:
	_player = player
	_query = PhysicsRayQueryParameters2D.new()
	_query.collision_mask = WORLD_MASK
	_query.exclude = [player.get_rid()]


## Once a frame: the physics space and the hazards that can hurt this bot right now.
func refresh() -> void:
	_space = _player.get_world_2d().direct_space_state
	_hazards = BotHazards.collect(_player.get_tree(), _player.player_slot)


func space() -> PhysicsDirectSpaceState2D:
	return _space


# --- Rays ------------------------------------------------------------------------------------------------

func ray(from: Vector2, to: Vector2) -> Dictionary:
	if _space == null:
		return {}
	_query.from = from
	_query.to = to
	return _space.intersect_ray(_query)


func blocked(from: Vector2, to: Vector2) -> bool:
	return not ray(from, to).is_empty()


func ground_below(from: Vector2, depth: float) -> bool:
	return blocked(from, from + Vector2(0.0, depth))


## Ground, or water to swim out of (Tidewater), within depth below: falling there is no loss.
func footing_below(from: Vector2, depth: float) -> bool:
	return ground_below(from, depth) or WorldConditions.water_level < from.y + depth


func wall_ahead(direction: float, reach: float = 34.0) -> bool:
	var me: Vector2 = _player.global_position
	var hit: Dictionary = ray(me, me + Vector2(direction * reach, 0.0))
	return not hit.is_empty() and absf((hit["normal"] as Vector2).x) > 0.7


## Nothing overhead for a leap out of the water.
func headroom(at: Vector2) -> bool:
	for offset in [-20.0, 0.0, 20.0]:
		if blocked(at + Vector2(offset, 0.0), at + Vector2(offset, -110.0)):
			return false
	return true


## The side (preferred one first) with open sky above it within a short swim.
func open_side(at: Vector2, preferred: float) -> float:
	for offset in [40.0, 80.0, 130.0, 190.0]:
		for side in [preferred, -preferred]:
			if headroom(at + Vector2(side * offset, 0.0)):
				return side
	return preferred


## The side with ground under it closest by (for steering back from over a pit), or 0.
func nearest_safe_side(from: Vector2) -> float:
	for offset in [60.0, 120.0, 200.0, 300.0]:
		for direction in [1.0, -1.0]:
			if ground_below(Vector2(from.x + direction * offset, from.y - 40.0), 400.0):
				return direction
	return 0.0


## A step of one body width that way does not walk off a ledge deeper than a safe drop.
func step_has_ground(direction: float) -> bool:
	var me: Vector2 = _player.global_position
	return ground_below(me + Vector2(direction * 34.0, 0.0), SAFE_DROP_DEPTH)


# --- Stretches -------------------------------------------------------------------------------------------

## A run of `reach` px that way from the body is safe ground: nothing in the way, floor all along (no pit,
## no step down deeper than a hop, no lip taller than a dash climbs) and no hazard on it (unless the bot
## stands in one already and the stretch leads out of it).
func stretch_is_safe(direction: float, reach: float) -> bool:
	if direction == 0.0:
		return false
	var me: Vector2 = _player.global_position
	if blocked(me, me + Vector2(direction * (reach + 16.0), 0.0)):
		return false
	var depth: float = _player.hover_dist + 30.0
	var floor_hit: Dictionary = ray(me, me + Vector2(0.0, depth))
	if floor_hit.is_empty():
		return false
	var floor_y: float = (floor_hit["position"] as Vector2).y
	var steps: int = int(ceil(reach / STRETCH_STEP))
	for step in range(1, steps + 1):
		var x: float = me.x + direction * minf(float(step) * STRETCH_STEP, reach)
		var hit: Dictionary = ray(Vector2(x, me.y - GameSettings.PLAYER_DASH_STEP_HEIGHT), Vector2(x, me.y + depth + STRETCH_MAX_DROP))
		if hit.is_empty():
			return false
		var rise: float = floor_y - (hit["position"] as Vector2).y
		if rise > GameSettings.PLAYER_DASH_STEP_HEIGHT - 2.0 or rise < -STRETCH_MAX_DROP:
			return false
	return not leads_into_hazard(direction, reach)


# --- Hazards ---------------------------------------------------------------------------------------------

func hazards() -> Array[Dictionary]:
	return _hazards


## Danger at a body position (0 when no hazard covers it).
func danger_at(body: Vector2) -> float:
	return BotHazards.danger_at(_hazards, body)


## Danger at a navigation point (feet on the floor), for goals and paths.
func danger_at_feet(feet: Vector2) -> float:
	return danger_at(feet - Vector2(0.0, _player.hover_dist))


func in_hazard() -> bool:
	return danger_at(_player.global_position) > 0.0


## Seconds until the hazards at a navigation point are gone.
func hazard_time_left_at_feet(feet: Vector2) -> float:
	return BotHazards.time_left_at(_hazards, feet - Vector2(0.0, _player.hover_dist))


## A run that way ends in a hazard the body is not in now (stepping out of one is fine).
func leads_into_hazard(direction: float, reach: float) -> bool:
	if _hazards.is_empty():
		return false
	var me: Vector2 = _player.global_position
	var end: Vector2 = me + Vector2(direction * reach, 0.0)
	if danger_at(me) > 0.0:
		return danger_at(end) > 0.0
	return BotHazards.danger_along(_hazards, me, end) > 0.0


## Which way the body gets out of the hazard it stands in soonest over walkable floor, and how far that is:
## {"side": -1 / 1 (0: no way out), "distance": px}.
func hazard_exit() -> Dictionary:
	var me: Vector2 = _player.global_position
	var best: Dictionary = {"side": 0.0, "distance": INF}
	for side in [1.0, -1.0]:
		var distance: float = 0.0
		var found: bool = false
		while distance < ESCAPE_REACH:
			distance += 16.0
			var body: Vector2 = me + Vector2(side * distance, 0.0)
			if not ground_below(body, _player.hover_dist + STRETCH_MAX_DROP) or blocked(me, body):
				break
			if danger_at(body) <= 0.0:
				found = true
				break
		if found and distance < float(best["distance"]):
			best = {"side": side, "distance": distance}
	return best
