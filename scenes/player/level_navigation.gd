class_name LevelNavigation
extends RefCounted

## Platformer navigation graph built automatically from the level's StaticBody2D polygons.
## Nodes are sampled along walkable top edges; edges are walks along a surface plus jumps and drops
## between surfaces, each validated by simulating the player's jump arc against the physics world, and
## climbs: from the foot of a solid wall up to the ledge on top of it with wall jumps (only planned for
## bots whose Wall Jumps marks reach that high).

enum Move { WALK, JUMP, DROP, CLIMB }

const SAMPLE_SPACING: float = 34.0
const BODY_OFFSET: float = 24.0
const BODY_RADIUS: float = 14.0
const RUN_SPEED: float = 250.0
const LANDING_TOLERANCE: float = 12.0
const JUMP_VELOCITY: float = 500.0
const GRAVITY: float = 1350.0
const FALL_MULTIPLIER: float = 1.5
const MAX_HORIZONTAL_REACH: float = 260.0
const MAX_CLIMB: float = 100.0
const MAX_DROP: float = 460.0
const TOP_NORMAL_THRESHOLD: float = -0.6
## Wall climbs (measured with wall_probe, holding jump): a full jump lifts the body ~92 px, each wall jump
## adds ~55 px more (~85 px with the stronger Mk II kick). Kept a little under the measured values.
const CLIMB_JUMP_RISE: float = 88.0
const CLIMB_KICK_RISE: float = 50.0
const CLIMB_STRONG_KICK_RISE: float = 80.0
const CLIMB_MARGIN: float = 10.0
const MAX_WALL_CLIMB: float = 420.0
const WORLD_MASK: int = 1
## A point counts as flooded once the water stands this far over the feet (wading is still fine).
const FLOOD_MARGIN: float = 10.0
## Highest a leap out of the water lands, feet above the surface (Player.SWIM_LEAP_SCALE jump, with margin).
const SWIM_EXIT_REACH: float = 96.0

static var _cache: Dictionary = {}

var points: Array[Vector2] = []
var _chain_of_point: Array[int] = []
var _edge_moves: Dictionary = {}
var _astar: NavAStar = NavAStar.new()
var _space: PhysicsDirectSpaceState2D = null
var _query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
var _bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS
## Jump physics of the map being built (Mars has lower gravity, so arcs are higher and longer).
var _gravity: float = GRAVITY
var _max_climb: float = MAX_CLIMB
var _max_reach: float = MAX_HORIZONTAL_REACH
var _gravity_scale: float = 1.0
var _flood_level: float = INF


static func get_for(map_root: Node, space: PhysicsDirectSpaceState2D, bounds: Rect2) -> LevelNavigation:
	var key: int = map_root.get_instance_id()
	if _cache.has(key):
		var cached: LevelNavigation = _cache[key]
		if cached != null:
			return cached
	var navigation: LevelNavigation = LevelNavigation.new()
	var started_usec: int = Time.get_ticks_usec()
	navigation._build(map_root, space, bounds)
	if OS.is_debug_build():
		print_verbose("LevelNavigation: %d points built in %.1f ms" % [navigation.points.size(), float(Time.get_ticks_usec() - started_usec) / 1000.0])
	_cache.clear()
	_cache[key] = navigation
	return navigation


func is_valid() -> bool:
	return points.size() > 1


## Leaves every point the water covers out of the paths (Tidewater's tide); INF opens them all again.
## The graph is shared by both bots, and so is the sea.
func set_flood_level(level: float) -> void:
	if level == _flood_level or (level != INF and _flood_level != INF and absf(level - _flood_level) < 3.0):
		return
	_flood_level = level
	for index in range(points.size()):
		_astar.set_point_disabled(index, is_flooded(points[index].y, level))


static func is_flooded(feet_y: float, level: float) -> bool:
	return level != INF and feet_y > level + FLOOD_MARGIN


## The dry point a swimmer at `from` should make for: a leap out of the water reaches it, the nearest
## sideways wins. Falls back to the nearest dry point at all.
func nearest_swim_exit(from: Vector2, level: float) -> int:
	var best: int = -1
	var best_cost: float = INF
	var fallback: int = -1
	var fallback_cost: float = INF
	for index in range(points.size()):
		var point: Vector2 = points[index]
		if is_flooded(point.y, level):
			continue
		var cost: float = absf(point.x - from.x) + absf(point.y - level) * 0.5
		if point.y > level - SWIM_EXIT_REACH and cost < best_cost:
			best_cost = cost
			best = index
		if cost < fallback_cost:
			fallback_cost = cost
			fallback = index
	return best if best >= 0 else fallback


func nearest_point(world_feet: Vector2, max_distance: float = 140.0) -> int:
	var best: int = -1
	var best_distance: float = max_distance * max_distance
	for index in range(points.size()):
		if _astar.is_point_disabled(index):
			continue
		var offset: Vector2 = points[index] - world_feet
		var distance: float = offset.x * offset.x + offset.y * offset.y * 2.5
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## A path for a bot that can climb walls up to `climb_reach` px (see wall_climb_reach); climbs higher than
## that are never part of it.
func find_path(from_id: int, to_id: int, climb_reach: float = 0.0) -> PackedInt64Array:
	if from_id < 0 or to_id < 0:
		return PackedInt64Array()
	_astar.climb_reach = climb_reach
	var path: PackedInt64Array = _astar.get_id_path(from_id, to_id)
	for index in range(path.size() - 1):
		if float(_astar.climb_heights.get(_edge_key(int(path[index]), int(path[index + 1])), 0.0)) > climb_reach:
			return PackedInt64Array()
	return path


## How high a player climbs a wall with this many wall jumps in a row (-1: no limit) and kick strength.
func wall_climb_reach(wall_jump_limit: int, strong_kick: bool) -> float:
	if wall_jump_limit < 0 and strong_kick:
		return MAX_WALL_CLIMB / _gravity_scale
	var kicks: int = wall_jump_limit if wall_jump_limit >= 0 else 4
	var kick_rise: float = CLIMB_STRONG_KICK_RISE if strong_kick else CLIMB_KICK_RISE
	return (CLIMB_JUMP_RISE + kick_rise * float(kicks) - CLIMB_MARGIN) / _gravity_scale


## {"move", "hold", "vx"}: how to get from one point to the next. "vx" is the sideways speed the jump or drop
## was validated with; flying the arc at full speed instead would hit what the slower arc clears.
func get_move(from_id: int, to_id: int) -> Dictionary:
	return _edge_moves.get(_edge_key(from_id, to_id), {"move": Move.WALK, "hold": 0.0, "vx": 0.0})


func _build(map_root: Node, space: PhysicsDirectSpaceState2D, bounds: Rect2) -> void:
	_space = space
	_bounds = bounds
	var gravity_scale: float = clampf(WorldConditions.gravity_scale, 0.3, 2.0)
	_gravity_scale = gravity_scale
	_gravity = GRAVITY * gravity_scale
	_max_climb = MAX_CLIMB / gravity_scale
	_max_reach = MAX_HORIZONTAL_REACH / sqrt(gravity_scale)
	var chains: Array = []
	for body in map_root.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var polygon: Polygon2D = child as Polygon2D
			if polygon == null or polygon.polygon.size() < 3:
				continue
			for chain in _top_chains(polygon.global_transform * polygon.polygon):
				chains.append(chain)
	var chain_ranges: Array[Vector2i] = []
	for chain_index in range(chains.size()):
		var start: int = points.size()
		_sample_chain(chains[chain_index], chain_index)
		chain_ranges.append(Vector2i(start, points.size()))
	for index in range(points.size()):
		_astar.add_point(index, points[index])
	for chain_range in chain_ranges:
		for index in range(chain_range.x, chain_range.y - 1):
			_connect(index, index + 1, Move.WALK, 0.0, 1.0)
			_connect(index + 1, index, Move.WALK, 0.0, 1.0)
	for chain_range in chain_ranges:
		if chain_range.y <= chain_range.x:
			continue
		var edge_sources: Array[int] = []
		for offset in range(mini(3, chain_range.y - chain_range.x)):
			edge_sources.append(chain_range.x + offset)
			edge_sources.append(chain_range.y - 1 - offset)
		for source in range(chain_range.x, chain_range.y):
			_link_to_other_chains(source, chain_ranges, not edge_sources.has(source))
	for chain_range in chain_ranges:
		if chain_range.y > chain_range.x:
			_link_climb(chain_range.x, -1.0)
			_link_climb(chain_range.y - 1, 1.0)


func _link_to_other_chains(source: int, chain_ranges: Array[Vector2i], climb_only: bool) -> void:
	var from: Vector2 = points[source]
	var source_chain: int = _chain_of_point[source]
	for chain_index in range(chain_ranges.size()):
		if chain_index == source_chain:
			continue
		var best_target: int = -1
		var best_move: Dictionary = {}
		var best_cost: float = INF
		var chain_range: Vector2i = chain_ranges[chain_index]
		for target in range(chain_range.x, chain_range.y):
			var to: Vector2 = points[target]
			var dx: float = to.x - from.x
			var dy: float = to.y - from.y
			if absf(dx) > _max_reach or dy < -_max_climb or dy > MAX_DROP:
				continue
			if climb_only and (dy > -24.0 or absf(dx) > 150.0):
				continue
			var move: Dictionary = _validate_transition(from, to)
			if move.is_empty():
				continue
			var cost: float = from.distance_to(to) * (1.4 if move["move"] == Move.JUMP else 1.15)
			if cost < best_cost:
				best_cost = cost
				best_target = target
				best_move = move
		if best_target >= 0:
			_connect(source, best_target, best_move["move"], best_move["hold"], 1.6, best_move["vx"])


## A climb onto the ledge at `top` (a surface's end point; side -1 = its left end): needs a solid wall
## under that end, open air beside it, and floor at its foot higher than a plain jump reaches.
func _link_climb(top_id: int, side: float) -> void:
	var top: Vector2 = points[top_id]
	var face: Dictionary = _ray(top + Vector2(side * 90.0, 30.0), top + Vector2(0.0, 30.0))
	if face.is_empty() or signf((face["normal"] as Vector2).x) != side:
		return
	var face_x: float = (face["position"] as Vector2).x
	var best: int = -1
	var best_dy: float = INF
	for index in range(points.size()):
		if _chain_of_point[index] == _chain_of_point[top_id]:
			continue
		var foot: Vector2 = points[index]
		var out: float = (foot.x - face_x) * side
		var dy: float = foot.y - top.y
		if out < 18.0 or out > 70.0 or dy <= _max_climb or dy > MAX_WALL_CLIMB / _gravity_scale or dy >= best_dy:
			continue
		best = index
		best_dy = dy
	if best < 0:
		return
	var foot: Vector2 = points[best]
	var column_x: float = face_x + side * (BODY_RADIUS + 4.0)
	# Open air all the way up beside the wall, and wall to kick off all the way up.
	if not _ray(Vector2(column_x, foot.y - BODY_OFFSET), Vector2(column_x, top.y - BODY_OFFSET - BODY_RADIUS)).is_empty():
		return
	var y: float = foot.y - 30.0
	while y > top.y + 12.0:
		var hit: Dictionary = _ray(Vector2(column_x, y), Vector2(face_x - side * 6.0, y))
		if hit.is_empty() or signf((hit["normal"] as Vector2).x) != side:
			return
		y -= 40.0
	_connect(best, top_id, Move.CLIMB, 0.32, 2.2, -side * RUN_SPEED)
	_astar.climb_heights[_edge_key(best, top_id)] = best_dy + CLIMB_MARGIN


func _validate_transition(from: Vector2, to: Vector2) -> Dictionary:
	if to.y > from.y + 20.0:
		var drop_speed: float = _arc_speed(from, to, 0.0)
		if drop_speed != INF:
			return {"move": Move.DROP, "hold": 0.0, "vx": drop_speed}
	for hold in [0.32, 0.18]:
		var jump_speed: float = _arc_speed(from, to, JUMP_VELOCITY if hold > 0.25 else JUMP_VELOCITY * 0.82)
		if jump_speed != INF:
			return {"move": Move.JUMP, "hold": hold, "vx": jump_speed}
	return {}


## Simulates the body centre travelling from `from` to `to` (feet positions) with the given launch speed at
## the one constant sideways speed that lands it there. Returns that speed, or INF when the arc is blocked.
func _arc_speed(from: Vector2, to: Vector2, launch_speed: float) -> float:
	var start: Vector2 = from - Vector2(0.0, BODY_OFFSET)
	var end_y: float = to.y - BODY_RADIUS - 4.0
	var flight_time: float = _time_to_reach(start.y, end_y, launch_speed)
	if flight_time <= 0.0:
		return INF
	var reach_x: float = to.x - signf(to.x - from.x) * minf(LANDING_TOLERANCE, absf(to.x - from.x))
	var horizontal_speed: float = (reach_x - from.x) / flight_time
	if absf(horizontal_speed) > RUN_SPEED:
		return INF
	var steps: int = maxi(4, int(flight_time / 0.045))
	var previous: Vector2 = start
	for step in range(1, steps + 1):
		var t: float = flight_time * float(step) / float(steps)
		var point: Vector2 = Vector2(start.x + horizontal_speed * t, start.y + _vertical_offset(t, launch_speed))
		var final_segment: bool = step == steps
		var probe_end: Vector2 = point
		if final_segment:
			probe_end = point - (point - previous).normalized() * (BODY_RADIUS * 0.5)
		for lateral in [-BODY_RADIUS * 0.7, BODY_RADIUS * 0.7]:
			var offset: Vector2 = Vector2(lateral, 0.0)
			if not _ray(previous + offset, probe_end + offset).is_empty():
				return INF
		previous = point
	return horizontal_speed


func _vertical_offset(t: float, launch_speed: float) -> float:
	var rise_time: float = launch_speed / _gravity
	if t <= rise_time:
		return -launch_speed * t + 0.5 * _gravity * t * t
	var apex: float = -launch_speed * rise_time + 0.5 * _gravity * rise_time * rise_time
	var fall_t: float = t - rise_time
	return apex + 0.5 * _gravity * FALL_MULTIPLIER * fall_t * fall_t


func _time_to_reach(start_y: float, end_y: float, launch_speed: float) -> float:
	var rise_time: float = launch_speed / _gravity
	var apex_offset: float = -launch_speed * rise_time + 0.5 * _gravity * rise_time * rise_time
	var needed: float = end_y - start_y
	if needed < apex_offset - 0.5:
		return -1.0
	var fall_distance: float = needed - apex_offset
	return rise_time + sqrt(maxf(fall_distance, 0.0) * 2.0 / (_gravity * FALL_MULTIPLIER))


func _sample_chain(chain: PackedVector2Array, chain_index: int) -> void:
	var length: float = 0.0
	for index in range(chain.size() - 1):
		length += chain[index].distance_to(chain[index + 1])
	if length < 12.0:
		return
	var count: int = maxi(1, int(floor(length / SAMPLE_SPACING)))
	var margin: float = minf(10.0, length * 0.2)
	for sample in range(count + 1):
		var distance: float = lerpf(margin, length - margin, float(sample) / float(count)) if count > 0 else length * 0.5
		var point: Vector2 = _point_along(chain, distance)
		if point.y > _bounds.end.y - 24.0 or point.x < _bounds.position.x + 16.0 or point.x > _bounds.end.x - 16.0:
			continue
		if not _ray(point - Vector2(0.0, 3.0), point - Vector2(0.0, BODY_OFFSET + BODY_RADIUS + 6.0)).is_empty():
			continue
		points.append(point)
		_chain_of_point.append(chain_index)


func _point_along(chain: PackedVector2Array, distance: float) -> Vector2:
	var remaining: float = distance
	for index in range(chain.size() - 1):
		var segment: float = chain[index].distance_to(chain[index + 1])
		if remaining <= segment:
			return chain[index].lerp(chain[index + 1], remaining / maxf(segment, 0.001))
		remaining -= segment
	return chain[chain.size() - 1]


func _top_chains(polygon_points: PackedVector2Array) -> Array:
	var chains: Array = []
	var count: int = polygon_points.size()
	var tops: Array[bool] = []
	for index in range(count):
		var a: Vector2 = polygon_points[index]
		var b: Vector2 = polygon_points[(index + 1) % count]
		var is_top: bool = false
		if a.distance_squared_to(b) > 1.0:
			var tangent: Vector2 = (b - a).normalized()
			var normal: Vector2 = Vector2(tangent.y, -tangent.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal * 1.5, polygon_points):
				normal = -normal
			is_top = normal.y <= TOP_NORMAL_THRESHOLD
		tops.append(is_top)
	var start: int = 0
	for index in range(count):
		if not tops[index]:
			start = (index + 1) % count
			break
	var current: PackedVector2Array = PackedVector2Array()
	for offset in range(count):
		var index: int = (start + offset) % count
		if tops[index]:
			if current.is_empty():
				current.append(polygon_points[index])
			current.append(polygon_points[(index + 1) % count])
		elif not current.is_empty():
			chains.append(_left_to_right(current))
			current = PackedVector2Array()
	if not current.is_empty():
		chains.append(_left_to_right(current))
	return chains


func _left_to_right(chain: PackedVector2Array) -> PackedVector2Array:
	if chain.size() > 1 and chain[0].x > chain[chain.size() - 1].x:
		chain.reverse()
	return chain


func _connect(from_id: int, to_id: int, move: Move, hold: float, weight: float, speed_x: float = 0.0) -> void:
	_astar.connect_points(from_id, to_id, false)
	_edge_moves[_edge_key(from_id, to_id)] = {"move": move, "hold": hold, "vx": speed_x}
	_astar.edge_weights[_edge_key(from_id, to_id)] = weight


func _edge_key(from_id: int, to_id: int) -> int:
	return from_id * 100000 + to_id


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	if _space == null:
		return {}
	_query.from = from
	_query.to = to
	_query.collision_mask = WORLD_MASK
	return _space.intersect_ray(_query)


class NavAStar:
	extends AStar2D

	var edge_weights: Dictionary = {}
	## Height of every climb edge, and how high the bot asking for a path can climb.
	var climb_heights: Dictionary = {}
	var climb_reach: float = 0.0

	func _compute_cost(from_id: int, to_id: int) -> float:
		var key: int = from_id * 100000 + to_id
		if float(climb_heights.get(key, 0.0)) > climb_reach:
			return 1.0e9
		var weight: float = float(edge_weights.get(key, 1.0))
		return get_point_position(from_id).distance_to(get_point_position(to_id)) * weight

	func _estimate_cost(from_id: int, to_id: int) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id))
