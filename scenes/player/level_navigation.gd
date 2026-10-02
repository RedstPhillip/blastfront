class_name LevelNavigation
extends RefCounted

## Platformer navigation graph built automatically from the level's StaticBody2D polygons.
## Nodes are sampled along walkable top edges; edges are walks along a surface plus jumps and drops
## between surfaces, each validated by simulating the player's jump arc against the physics world.

enum Move { WALK, JUMP, DROP }

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
const WORLD_MASK: int = 1

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


func nearest_point(world_feet: Vector2, max_distance: float = 140.0) -> int:
	var best: int = -1
	var best_distance: float = max_distance * max_distance
	for index in range(points.size()):
		var offset: Vector2 = points[index] - world_feet
		var distance: float = offset.x * offset.x + offset.y * offset.y * 2.5
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func find_path(from_id: int, to_id: int) -> PackedInt64Array:
	if from_id < 0 or to_id < 0:
		return PackedInt64Array()
	return _astar.get_id_path(from_id, to_id)


func get_move(from_id: int, to_id: int) -> Dictionary:
	return _edge_moves.get(_edge_key(from_id, to_id), {"move": Move.WALK, "hold": 0.0})


func _build(map_root: Node, space: PhysicsDirectSpaceState2D, bounds: Rect2) -> void:
	_space = space
	_bounds = bounds
	var gravity_scale: float = clampf(WorldConditions.gravity_scale, 0.3, 2.0)
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
			_connect(source, best_target, best_move["move"], best_move["hold"], 1.6)


func _validate_transition(from: Vector2, to: Vector2) -> Dictionary:
	if to.y > from.y + 20.0 and _arc_is_clear(from, to, 0.0):
		return {"move": Move.DROP, "hold": 0.0}
	for hold in [0.32, 0.18]:
		if _arc_is_clear(from, to, JUMP_VELOCITY if hold > 0.25 else JUMP_VELOCITY * 0.82):
			return {"move": Move.JUMP, "hold": hold}
	return {}


## Simulates the body centre travelling from `from` to `to` (feet positions) with the given launch speed.
func _arc_is_clear(from: Vector2, to: Vector2, launch_speed: float) -> bool:
	var start: Vector2 = from - Vector2(0.0, BODY_OFFSET)
	var end_y: float = to.y - BODY_RADIUS - 4.0
	var flight_time: float = _time_to_reach(start.y, end_y, launch_speed)
	if flight_time <= 0.0:
		return false
	var reach_x: float = to.x - signf(to.x - from.x) * minf(LANDING_TOLERANCE, absf(to.x - from.x))
	var horizontal_speed: float = (reach_x - from.x) / flight_time
	if absf(horizontal_speed) > RUN_SPEED:
		return false
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
				return false
		previous = point
	return true


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


func _connect(from_id: int, to_id: int, move: Move, hold: float, weight: float) -> void:
	_astar.connect_points(from_id, to_id, false)
	_edge_moves[_edge_key(from_id, to_id)] = {"move": move, "hold": hold}
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

	func _compute_cost(from_id: int, to_id: int) -> float:
		var weight: float = float(edge_weights.get(from_id * 100000 + to_id, 1.0))
		return get_point_position(from_id).distance_to(get_point_position(to_id)) * weight

	func _estimate_cost(from_id: int, to_id: int) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id))
