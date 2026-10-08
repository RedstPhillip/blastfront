extends SceneTree

## Swim probe (Tidewater): the water must never trap anyone. Holds the tide at a high tide and at a spring
## tide and drops the bot into the water every 40 px across the arena; each drop passes once the bot stands
## on dry ground again, and is reported TRAPPED if it is still in the water after the time limit.
##   run_probe.sh swim_probe.gd sim [world=tidewater] [step=40] [limit=8] [only=920] [spring_only]
## only=<x> runs just the drops at that x and traces the bot every few frames.

var _world: String = "tidewater"
var _step: float = 40.0
var _limit: float = 8.0
var _main: Node = null
var _viewport: SubViewport = null
var _frame: int = 0
var _game: Node = null
var _cases: Array = []
var _case_index: int = -1
var _case_time: float = 0.0
var _results: Dictionary = {}
var _slowest: float = 0.0
var _only: float = -1.0
var _spring_only: bool = false
var _trace_frame: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if arg == "spring_only":
			_spring_only = true
		if parts.size() != 2:
			continue
		match parts[0]:
			"world":
				_world = parts[1]
			"step":
				_step = float(parts[1])
			"limit":
				_limit = float(parts[1])
			"only":
				_only = float(parts[1])
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	root.add_child(_viewport)
	_main = load("res://scenes/app/main.tscn").instantiate()
	_main.name = "Main"
	_viewport.add_child(_main)


func _tide() -> Node:
	return _game.get_node("Arena/Tide")


func _build_cases() -> void:
	var space: PhysicsDirectSpaceState2D = _game.get_world_2d().direct_space_state
	var bounds: Rect2 = _game.get_node("Arena/MapBounds").bounds
	for spring in [false, true]:
		var level: float = _tide().spring_level if spring else _tide().flood_level
		var x: float = bounds.position.x + 40.0
		while x < bounds.end.x - 40.0:
			var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
			query.collision_mask = 1
			query.position = Vector2(x, level + 16.0)
			if space.intersect_point(query, 1).is_empty() and (_only < 0.0 or absf(x - _only) < 1.0) and (spring or not _spring_only):
				_cases.append({"spring": spring, "at": Vector2(x, level + 16.0)})
			x += _step
	print("SWIM world=%s cases=%d" % [_world, _cases.size()])


func _start_case() -> void:
	var case: Dictionary = _cases[_case_index]
	if case["spring"] != (_case_index > 0 and _cases[_case_index - 1]["spring"]) or _case_index == 0:
		_tide().hold_flood(case["spring"])
	var bot: Node = _game.get_player_by_slot(2)
	bot.global_position = case["at"]
	bot.velocity = Vector2.ZERO
	bot.health_component.health = bot.health_component.max_health
	if bot.ai_brain != null:
		bot.ai_brain.reset_home()
	_case_time = 0.0


func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		root.get_node("UserSettings").set_value(&"progress_bot_world", _world)
		root.get_node("UserSettings").set_value(&"gameplay_bot_difficulty", 2)
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
	var bot: Node = _game.get_player_by_slot(2)
	if _case_index == -1:
		_game.get_player_by_slot(1).set_eliminated(true)
		_build_cases()
		_case_index = 0
		_start_case()
		return false
	# Let the water settle around the bot for a moment before judging.
	_case_time += delta
	_trace_frame += 1
	if _only >= 0.0 and _trace_frame % 5 == 0:
		var brain: Node = bot.ai_brain
		print("  t=%.2f pos=%s v=%s %s move=%.2f jump=%s depth=%.0f leap=%s air_x=%.0f" % [_case_time, bot.global_position.round(), bot.velocity.round(), bot._state_machine.current_state.name, brain.move_direction, brain.jump_held, bot.get_water_depth(), brain._swim_leap, brain._air_target_x if brain._air_target_x != INF else -1.0])
	# Out means standing on ground the water does not flood (wading ankle-deep at the edge counts).
	var feet_y: float = bot.global_position.y + bot.hover_dist
	var out: bool = _case_time > 0.3 and bot.is_grounded() and not bot.is_swimming() and feet_y < WorldConditions.water_level + 10.0
	if out or _case_time >= _limit:
		var case: Dictionary = _cases[_case_index]
		var key: String = "spring" if case["spring"] else "flood"
		if not _results.has(key):
			_results[key] = {"ok": 0, "trapped": []}
		if out:
			_results[key]["ok"] += 1
			_slowest = maxf(_slowest, _case_time)
		else:
			_results[key]["trapped"].append(int(case["at"].x))
			print("TRAPPED %s x=%d ended at %s state=%s" % [key, int(case["at"].x), bot.global_position.round(), bot._state_machine.current_state.name])
		_case_index += 1
		if _case_index >= _cases.size():
			var trapped: int = 0
			for result in _results.values():
				trapped += (result["trapped"] as Array).size()
			print("SWIM %s %s slowest_exit=%.1fs %s" % [_world, "OK" if trapped == 0 else "FAIL", _slowest, _results])
			return true
		_start_case()
	return false
