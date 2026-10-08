extends SceneTree

## Edge probe: drives P1 into every open platform corner of a world (the ends of each walkable top edge
## with a drop beside them) from many start points and inputs, and reports every case where P1 stops
## moving near the corner without standing on it: the "hanging on the edge" bug fixed in e6ea37a.
##   run_probe.sh edge_probe.gd headless world=rimefall [verbose] [step=3]
## Runs a bot duel with the bot removed, so the map's own rules (ice, tide, weather) stay live.

var _world: String = "verdant"
var _step: int = 3
var _verbose: bool = false
var _main: Node = null
var _viewport: SubViewport = null
var _frame: int = 0
var _game: Node = null
var _corners: Array = []
var _cases: Array = []
var _case_index: int = -1
var _case_frame: int = 0
var _case: Dictionary = {}
var _trace: PackedStringArray = PackedStringArray()
var _still: int = 0
var _max_still: int = 0
var _last: Vector2 = Vector2.ZERO
var _stuck_cases: int = 0
var _stuck_by_corner: Dictionary = {}
var _printed: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if arg == "verbose":
			_verbose = true
		elif parts.size() == 2 and parts[0] == "world":
			_world = parts[1]
		elif parts.size() == 2 and parts[0] == "step":
			_step = maxi(int(parts[1]), 1)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.handle_input_locally = true
	root.add_child(_viewport)
	_main = load("res://scenes/app/main.tscn").instantiate()
	_main.name = "Main"
	_viewport.add_child(_main)


## Ends of every walkable top edge whose outside is open air (not a wall rising beside it).
func _find_corners() -> void:
	var space: PhysicsDirectSpaceState2D = _game.get_world_2d().direct_space_state
	var nav: Variant = load("res://scenes/player/level_navigation.gd").new()
	var arena: Node = _game.get_node("Arena")
	var bounds: Rect2 = arena.get_node("MapBounds").bounds
	for body in arena.find_children("*", "StaticBody2D", true, false):
		var polygon: Polygon2D = body.get_node_or_null(^"Polygon2D") as Polygon2D
		if polygon == null:
			continue
		for chain in nav._top_chains(polygon.global_transform * polygon.polygon):
			var points: PackedVector2Array = chain
			for end in [[points[0], -1.0], [points[points.size() - 1], 1.0]]:
				var corner: Vector2 = end[0]
				var side: float = end[1]
				if corner.x < bounds.position.x + 30.0 or corner.x > bounds.end.x - 30.0 or corner.y > bounds.end.y - 30.0:
					continue
				var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
				query.collision_mask = 1
				query.position = corner + Vector2(side * 16.0, -20.0)
				if not space.intersect_point(query, 1).is_empty():
					continue
				_corners.append({"at": corner, "side": side, "name": "%s %s" % [body.name, "L" if side < 0.0 else "R"]})
	for corner_index in range(_corners.size()):
		var side: float = _corners[corner_index]["side"]
		var inward: String = "R" if side < 0.0 else "L"
		var outward: String = "L" if side < 0.0 else "R"
		# Falling past the corner from above, outside to slightly inside.
		for dx in range(-34, 8, _step):
			for hold in ["-", inward, outward]:
				_cases.append({"name": "fall dx=%d hold=%s" % [dx, hold], "corner": corner_index,
					"start": Vector2(-side * dx, -70), "vel": Vector2.ZERO, "hold": hold})
		# Jumping up past the corner from below (the typical "jump onto a ledge").
		for dx in range(-34, 4, _step):
			for dy in [40, 70, 100]:
				for hold in ["-", inward]:
					_cases.append({"name": "jump dx=%d dy=%d hold=%s" % [dx, dy, hold], "corner": corner_index,
						"start": Vector2(-side * dx, dy), "vel": Vector2(0, -500), "hold": hold, "held_jump": true})
		# Running off the top over the corner, then reversing into it.
		_cases.append({"name": "runoff_reverse", "corner": corner_index, "start": Vector2(-side * 40.0, -24), "vel": Vector2.ZERO,
			"hold": outward, "reverse_at": 14})
	print("EDGE world=%s corners=%d cases=%d" % [_world, _corners.size(), _cases.size()])


func _release_all() -> void:
	for action_name in ["p1_move_left", "p1_move_right", "p1_jump"]:
		Input.action_release(action_name)


func _set_action(action_name: String, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(action_name):
		Input.action_press(action_name)
	elif not pressed and Input.is_action_pressed(action_name):
		Input.action_release(action_name)


func _start_case() -> void:
	_release_all()
	_case = _cases[_case_index]
	_case_frame = 0
	_still = 0
	_max_still = 0
	_trace = PackedStringArray()
	var p1: Node = _game.get_player_by_slot(1)
	var corner: Vector2 = _corners[int(_case["corner"])]["at"]
	p1.global_position = corner + (_case["start"] as Vector2)
	p1.velocity = _case["vel"]
	p1.health_component.health = p1.health_component.max_health
	_last = p1.global_position


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		root.get_node("UserSettings").set_value(&"progress_bot_world", _world)
		root.get_node("NetworkSession").start_bot_duel()
		_main.start_game()
	if _frame < 20:
		return false
	if _game == null:
		_game = get_first_node_in_group(&"game_world")
		return false
	if _game.get_player_by_slot(1) == null or _game.get_player_by_slot(2) == null:
		return false
	if _game.is_round_intro_running() or _frame < 400:
		return false
	var p1: Node = _game.get_player_by_slot(1)
	var p2: Node = _game.get_player_by_slot(2)
	if _case_index == -1:
		p2.set_eliminated(true)
		p1.set_controls_enabled(true)
		_find_corners()
		if _cases.is_empty():
			print("DONE no corners")
			return true
		_case_index = 0
		_start_case()
		return false
	var hold: String = _case["hold"]
	if _case.has("reverse_at") and _case_frame >= int(_case["reverse_at"]):
		hold = "R" if hold == "L" else "L"
	_set_action("p1_move_right", hold == "R")
	_set_action("p1_move_left", hold == "L")
	_set_action("p1_jump", _case.get("held_jump", false) and _case_frame < 20)
	var corner: Vector2 = _corners[int(_case["corner"])]["at"]
	var rel: Vector2 = p1.global_position - corner
	var moved: float = p1.global_position.distance_to(_last)
	_last = p1.global_position
	# "Stuck": not moving, near the corner, and not standing on top (standing sits ~24 above).
	if _case_frame > 3 and moved < 0.3 and rel.length() < 40.0 and rel.y > -20.0:
		_still += 1
		_max_still = maxi(_max_still, _still)
	else:
		_still = 0
	if _verbose or _printed < 3:
		_trace.append("f%03d %-10s rel=(%6.1f,%6.1f) v=(%7.1f,%7.1f) fl=%d wl=%d gr=%d rays=%d%d %s" % [
			_case_frame, p1._state_machine.current_state.name, rel.x, rel.y, p1.velocity.x, p1.velocity.y,
			int(p1.is_on_floor()), int(p1.is_on_wall()), int(p1.is_grounded()),
			int(p1._is_floor_ray(p1._ray_l)), int(p1._is_floor_ray(p1._ray_r)), hold])
	_case_frame += 1
	if _case_frame >= 100:
		var stuck: bool = _max_still >= 20 and not p1._is_floor_ray(p1._ray_l) and not p1._is_floor_ray(p1._ray_r)
		if stuck:
			_stuck_cases += 1
			var corner_name: String = _corners[int(_case["corner"])]["name"]
			_stuck_by_corner[corner_name] = int(_stuck_by_corner.get(corner_name, 0)) + 1
		if stuck or _verbose:
			print("CASE %-18s %-28s max_still=%3d end_rel=(%.1f,%.1f) state=%s%s" % [_corners[int(_case["corner"])]["name"], _case["name"], _max_still, rel.x, rel.y, p1._state_machine.current_state.name, " STUCK" if stuck else ""])
			if stuck and _printed < 3:
				_printed += 1
				for line in _trace.slice(0, 60):
					print("   ", line)
		_case_index += 1
		if _case_index >= _cases.size():
			_release_all()
			print("EDGE %s corners=%d cases=%d stuck=%d %s" % [_world, _corners.size(), _cases.size(), _stuck_cases, _stuck_by_corner])
			return true
		_start_case()
	return false
