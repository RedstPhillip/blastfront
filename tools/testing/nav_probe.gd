extends SceneTree

## Navigation coverage of a world: builds the bots' LevelNavigation graph for the map and checks that every
## walkable surface can be reached from both spawns and that both spawns can be reached from it (a surface
## the bots can get onto but not off would trap them). Prints one line per terrain body and a verdict.
##   run_probe.sh nav_probe.gd headless world=tidewater

var _world: String = "verdant"
var _frame: int = 0
var _map: Node = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2 and parts[0] == "world":
			_world = parts[1]


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var catalog: Script = load("res://scenes/maps/world_catalog.gd")
		var entry: Dictionary = catalog.WORLDS.get(StringName(_world), {})
		if entry.is_empty():
			print("NAV unknown world ", _world)
			return true
		_map = (load(str(entry["scene"])) as PackedScene).instantiate()
		root.add_child(_map)
		return false
	if _frame < 8:
		return false
	_report()
	return true


func _report() -> void:
	var space: PhysicsDirectSpaceState2D = _map.get_world_2d().direct_space_state
	var bounds: Rect2 = _map.get_node("MapBounds").bounds
	var nav: Variant = load("res://scenes/player/level_navigation.gd").get_for(_map, space, bounds)
	var points: Array[Vector2] = nav.points
	print("NAV world=%s points=%d gravity=%.2f" % [_world, points.size(), WorldConditions.gravity_scale])
	var spawns: Array[int] = []
	for marker_name in ["Spawn1", "Spawn2"]:
		var marker: Node2D = _map.get_node(marker_name)
		var feet: Vector2 = _ground_below(space, marker.global_position)
		var id: int = nav.nearest_point(feet, 90.0)
		print("  %s at %s -> point %d %s" % [marker_name, feet.round(), id, points[id].round() if id >= 0 else "NONE"])
		spawns.append(id)
	var by_body: Dictionary = {}
	for index in range(points.size()):
		var body: String = _body_at(space, points[index])
		if not by_body.has(body):
			by_body[body] = []
		by_body[body].append(index)
	var failures: int = 0
	for body in by_body.keys():
		var ids: Array = by_body[body]
		var reach_from: int = 0
		var reach_to: int = 0
		for id in ids:
			if _connected(nav, spawns[0], id) and _connected(nav, spawns[1], id):
				reach_from += 1
			if _connected(nav, id, spawns[0]) and _connected(nav, id, spawns[1]):
				reach_to += 1
		var ok: bool = reach_from > 0 and reach_to == ids.size()
		if not ok:
			failures += 1
		print("  %-16s points=%2d reachable=%2d can_return=%2d %s" % [body, ids.size(), reach_from, reach_to, "ok" if ok else "FAIL"])
	print("NAV %s %s" % [_world, "OK" if failures == 0 else "FAIL (%d bodies)" % failures])


func _connected(nav: Variant, from_id: int, to_id: int) -> bool:
	if from_id < 0 or to_id < 0:
		return false
	return from_id == to_id or nav.find_path(from_id, to_id).size() > 0


func _ground_below(space: PhysicsDirectSpaceState2D, from: Vector2) -> Vector2:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, 400.0), 1)
	var hit: Dictionary = space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else from


func _body_at(space: PhysicsDirectSpaceState2D, point: Vector2) -> String:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point + Vector2(0.0, 3.0)
	query.collision_mask = 1
	var hits: Array[Dictionary] = space.intersect_point(query, 4)
	return (hits[0]["collider"] as Node).name if not hits.is_empty() else "?"
