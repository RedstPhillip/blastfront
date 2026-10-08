extends SceneTree

## Stuck probe: two local players; P1 is driven through jump/run cases around P2 (landing on heads, bodies
## overlapping, a remote player snapping through) and each case reports whether P1 ever stopped making
## progress while holding a direction (stuck), plus a compact trace (the bugs fixed in 42b0047).
## The map's terrain is swapped for one long flat floor, so every case runs on the same ground; the map's
## conditions (gravity, ice, water) stay live.
##   run_probe.sh stuck_probe.gd headless world=rimefall [floor_group=ice_surface] [verbose]
## floor_group puts the test floor in that group (ice_surface: the cases run on Rimefall ice).

var _main: Node = null
var _viewport: SubViewport = null
var _frame: int = 0
var _game = null
var _base: Vector2 = Vector2.ZERO
var _cases: Array = []
var _case_index: int = -1
var _case_frame: int = 0
var _case: Dictionary = {}
var _trace: PackedStringArray = PackedStringArray()
var _stuck_frames: int = 0
var _max_stuck: int = 0
var _last_p1: Vector2 = Vector2.ZERO
var _verbose: bool = false
var _results: PackedStringArray = PackedStringArray()
var _world: String = "verdant"
var _floor_group: String = ""
var _failures: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if arg == "verbose":
			_verbose = true
		elif parts.size() == 2 and parts[0] == "world":
			_world = parts[1]
		elif parts.size() == 2 and parts[0] == "floor_group":
			_floor_group = parts[1]
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.handle_input_locally = true
	root.add_child(_viewport)
	_main = load("res://scenes/app/main.tscn").instantiate()
	_main.name = "Main"
	_viewport.add_child(_main)
	_build_cases()


func _build_cases() -> void:
	# Run-and-jump over a standing P2 with the jump pressed at different distances.
	for gap in [20, 35, 50, 65, 80, 100]:
		_cases.append({"name": "hop_over gap=%d" % gap, "p1": Vector2(-140, 0), "p2": Vector2(0, 0), "frames": 150,
			"p1_right": [0, 150], "p1_jump_at_dx": -gap})
	# Land on P2's head and walk off / jump off.
	for dx in [0, 6, 12, 18, 24]:
		_cases.append({"name": "land_on_head dx=%d walk" % dx, "p1": Vector2(dx, -90), "p2": Vector2(0, 0), "frames": 150,
			"p1_right": [40, 150]})
		_cases.append({"name": "land_on_head dx=%d jump+walk" % dx, "p1": Vector2(dx, -90), "p2": Vector2(0, 0), "frames": 150,
			"p1_right": [40, 150], "p1_jump": [45, 60]})
		_cases.append({"name": "land_on_head dx=%d walk_left" % dx, "p1": Vector2(dx, -90), "p2": Vector2(0, 0), "frames": 150,
			"p1_left": [40, 150]})
	# P2 stands on P1's head; P1 tries to jump and to walk out.
	for dx in [0, 10, 20]:
		_cases.append({"name": "p2_on_my_head dx=%d jump" % dx, "p1": Vector2(0, 0), "p2": Vector2(dx, -90), "frames": 150,
			"p1_jump": [40, 55], "p1_right": [60, 150]})
	# Both jump into each other.
	for gap in [30, 60, 90]:
		_cases.append({"name": "both_jump_into gap=%d" % gap, "p1": Vector2(-gap, 0), "p2": Vector2(gap, 0), "frames": 150,
			"p1_right": [0, 150], "p2_left": [0, 150], "p1_jump": [10, 30], "p2_jump": [12, 32]})
	# Jump straight up next to P2 while pushing into it (wall slide on a player).
	for gap in [32, 40]:
		_cases.append({"name": "push_jump_into gap=%d" % gap, "p1": Vector2(-gap, 0), "p2": Vector2(0, 0), "frames": 150,
			"p1_right": [0, 150], "p1_jump": [20, 40]})
	# P1 falls onto P2 while P2 jumps up into P1.
	for dx in [0, 10, 20]:
		_cases.append({"name": "p2_jumps_into_me dx=%d" % dx, "p1": Vector2(dx, -120), "p2": Vector2(0, 0), "frames": 150,
			"p2_jump": [5, 30], "p1_right": [60, 150]})
	# Land on a shoulder while already pushing towards the middle (the reported "stuck").
	for dx in [10, 18, 24]:
		_cases.append({"name": "perch_push_in dx=%d" % dx, "p1": Vector2(dx, -90), "p2": Vector2(0, 0), "frames": 120,
			"p1_left": [0, 120]})
		_cases.append({"name": "perch_push_in_jump dx=%d" % dx, "p1": Vector2(dx, -90), "p2": Vector2(0, 0), "frames": 120,
			"p1_left": [0, 120], "p1_jump": [40, 55]})
	# Bodies inside each other.
	for off in [Vector2(0, 0), Vector2(4, -6), Vector2(-8, 3), Vector2(2, -14)]:
		_cases.append({"name": "overlap %s idle" % off, "p1": off, "p2": Vector2(0, 0), "frames": 90})
		_cases.append({"name": "overlap %s air" % off, "p1": off + Vector2(0, -100), "p2": Vector2(0, -100), "frames": 120})
		_cases.append({"name": "overlap %s jump" % off, "p1": off, "p2": Vector2(0, 0), "frames": 120,
			"p1_jump": [5, 20], "p2_jump": [6, 21]})
	# A remote player is placed straight from snapshots: sweep it through P1, raise it into P1, snap it away.
	_cases.append({"name": "remote_walk_through", "p1": Vector2(0, 0), "p2": Vector2(-120, 0), "frames": 90,
		"remote_path": [Vector2(-120, 0), Vector2(120, 0), 60]})
	_cases.append({"name": "remote_rise_into", "p1": Vector2(0, -60), "p2": Vector2(0, 0), "frames": 90,
		"remote_path": [Vector2(0, 0), Vector2(0, -160), 30]})
	_cases.append({"name": "remote_snap_away", "p1": Vector2(0, -60), "p2": Vector2(0, 0), "frames": 90,
		"remote_path": [Vector2(0, 0), Vector2(0, 0), 40], "remote_snap": [40, Vector2(200, -150)]})
	_cases.append({"name": "remote_jump_into_me", "p1": Vector2(20, 0), "p2": Vector2(-40, 0), "frames": 90,
		"remote_path": [Vector2(-40, 0), Vector2(30, -20), 12], "p1_jump": [6, 20]})
	# P2 runs under P1 who stands on its head.
	_cases.append({"name": "ride_head p2 runs", "p1": Vector2(0, -90), "p2": Vector2(0, 0), "frames": 150,
		"p2_right": [40, 150], "p1_right": [100, 150]})


func _in(range_value: Variant) -> bool:
	if range_value == null:
		return false
	return _case_frame >= int(range_value[0]) and _case_frame < int(range_value[1])


func _set_action(action_name: String, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(action_name):
		Input.action_press(action_name)
	elif not pressed and Input.is_action_pressed(action_name):
		Input.action_release(action_name)


func _release_all() -> void:
	for a in ["p1_move_left", "p1_move_right", "p1_jump", "p2_move_left", "p2_move_right", "p2_jump"]:
		Input.action_release(a)


func _start_case() -> void:
	_release_all()
	_case = _cases[_case_index]
	_case_frame = 0
	_stuck_frames = 0
	_max_stuck = 0
	_trace = PackedStringArray()
	var p1 = _game.get_player_by_slot(1)
	var p2 = _game.get_player_by_slot(2)
	if _case.has("remote_path"):
		p2.configure_remote_control(2)
	else:
		p2.configure_local_control(2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", &"p2_shoot", false)
		p2.set_controls_enabled(true)
	for pair in [[p1, _case["p1"]], [p2, _case["p2"]]]:
		pair[0].global_position = _base + pair[1]
		pair[0].velocity = Vector2.ZERO
		pair[0].health_component.health = pair[0].health_component.max_health
	_last_p1 = p1.global_position


func _drive(p1, p2) -> void:
	var right: bool = _in(_case.get("p1_right"))
	var left: bool = _in(_case.get("p1_left"))
	var jump: bool = _in(_case.get("p1_jump"))
	if _case.has("p1_jump_at_dx"):
		var dx: float = p1.global_position.x - p2.global_position.x
		jump = dx >= float(_case["p1_jump_at_dx"]) and dx < float(_case["p1_jump_at_dx"]) + 14.0
	_set_action("p1_move_right", right)
	_set_action("p1_move_left", left)
	_set_action("p1_jump", jump)
	if _case.has("remote_path"):
		var path: Array = _case["remote_path"]
		var t: float = clampf(float(_case_frame) / float(path[2]), 0.0, 1.0)
		var target: Vector2 = (path[0] as Vector2).lerp(path[1], t)
		if _case.has("remote_snap") and _case_frame >= int(_case["remote_snap"][0]):
			target = _case["remote_snap"][1]
		p2.global_position = _base + target
	_set_action("p2_move_right", _in(_case.get("p2_right")))
	_set_action("p2_move_left", _in(_case.get("p2_left")))
	_set_action("p2_jump", _in(_case.get("p2_jump")))


func _physics_tick() -> void:
	var p1 = _game.get_player_by_slot(1)
	var p2 = _game.get_player_by_slot(2)
	var holding: bool = Input.is_action_pressed("p1_move_right") or Input.is_action_pressed("p1_move_left")
	var moved: float = p1.global_position.distance_to(_last_p1)
	_last_p1 = p1.global_position
	if holding and moved < 0.3 and _case_frame > 2:
		_stuck_frames += 1
		_max_stuck = maxi(_max_stuck, _stuck_frames)
	else:
		_stuck_frames = 0
	var rel: Vector2 = p1.global_position - p2.global_position
	_trace.append(("p1=(%.0f,%.0f) p2=(%.0f,%.0f) " % [p1.global_position.x - _base.x, p1.global_position.y - _base.y, p2.global_position.x - _base.x, p2.global_position.y - _base.y]) + "f%03d %-10s rel=(%5.1f,%6.1f) v=(%6.1f,%6.1f) fl=%d wl=%d ce=%d gr=%d | p2 %-10s v=(%6.1f,%6.1f) fl=%d %s%s%s" % [
		_case_frame, p1._state_machine.current_state.name, rel.x, rel.y, p1.velocity.x, p1.velocity.y,
		int(p1.is_on_floor()), int(p1.is_on_wall()), int(p1.is_on_ceiling()), int(p1.is_grounded()),
		p2._state_machine.current_state.name, p2.velocity.x, p2.velocity.y, int(p2.is_on_floor()),
		"R" if Input.is_action_pressed("p1_move_right") else ("L" if Input.is_action_pressed("p1_move_left") else "-"),
		"J" if Input.is_action_pressed("p1_jump") else "-", " STUCK" if _stuck_frames > 0 else ""])


func _finish_case() -> void:
	var p1 = _game.get_player_by_slot(1)
	var p2 = _game.get_player_by_slot(2)
	var rel: Vector2 = p1.global_position - p2.global_position
	var line: String = "CASE %-34s max_stuck=%3d end_rel=(%4.0f,%4.0f) dist=%3.0f p1_end=(%4.0f,%4.0f) p1_state=%s" % [_case["name"], _max_stuck, rel.x, rel.y, rel.length(), p1.global_position.x - _base.x, p1.global_position.y - _base.y, p1._state_machine.current_state.name]
	_results.append(line)
	print(line)
	if _max_stuck >= 30 or rel.length() < 22.0:
		_failures += 1
	if _verbose or _max_stuck >= 30 or rel.length() < 22.0:
		for t in _trace:
			print("   ", t)


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
		if _frame % 60 == 0:
			print("waiting for players ", _game)
		return false
	if _game.is_round_intro_running() or _frame < 400:
		return false
	var p1 = _game.get_player_by_slot(1)
	var p2 = _game.get_player_by_slot(2)
	if _case_index == -1:
		p2.configure_local_control(2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", &"p2_shoot", false)
		p1.set_controls_enabled(true)
		p2.set_controls_enabled(true)
		# Replace the map's terrain with one long flat floor so every case runs on the same ground.
		var disabled: int = 0
		for node in _game.find_children("*", "", true, false):
			if node is CharacterBody2D:
				continue
			if node is TileMapLayer:
				node.collision_enabled = false
				disabled += 1
			elif node is PhysicsBody2D and (node.collision_layer & 1) != 0:
				node.collision_layer = 0
				disabled += 1
		var floor_body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(2000, 40)
		shape.shape = rect
		floor_body.add_child(shape)
		floor_body.position = Vector2(1140, 620)
		if _floor_group != "":
			floor_body.add_to_group(StringName(_floor_group))
		_game.add_child(floor_body)
		_base = Vector2(1140, 600 - p1.hover_dist)
		print("BASE ", _base, " disabled ", disabled)
		_case_index = -2
		return false
	if _case_index == -2:
		_case_index = 0
		_start_case()
		return false
	_drive(p1, p2)
	_physics_tick()
	_case_frame += 1
	if _case_frame >= int(_case["frames"]):
		_finish_case()
		_case_index += 1
		if _case_index >= _cases.size():
			_release_all()
			print("STUCK %s floor=%s cases=%d failures=%d" % [_world, _floor_group if _floor_group != "" else "plain", _cases.size(), _failures])
			return true
		_start_case()
	return false
