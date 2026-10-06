extends SceneTree

# Blastfront performance suite.
#   mode=cpu    (run headless with --fixed-fps 60): the engine never sleeps, so wall time per frame is the
#               CPU cost of one 60 Hz frame (one physics tick + process + deferred draws).
#   mode=render (hidden 1px window, SubViewport 1920x1080, vsync off): GPU and render-CPU time per frame.
# Prints "R <metric> <value>" lines; compare runs with perfcompare.py (see tools/testing/README.md).

var _mode: String = "cpu"
var _main: Node = null
var _viewport: SubViewport = null
var _phases: Array = []
var _phase: Dictionary = {}
var _phase_frame: int = 0
var _frames: Array = []
var _gpu: Array = []
var _rcpu: Array = []
var _draws: Array = []
var _prev_usec: int = 0
var _time: float = 0.0
var _seeded: Dictionary = {}
var _next_loadout: float = 0.0
var _move: String = ""
var _wait_until: Callable = Callable()
var _wait_started: int = 0
var _boot_reported: bool = false
var _prof: Dictionary = {}
var _short: bool = OS.has_environment("BF_SHORT")


func _initialize() -> void:
	if OS.has_environment("BF_PROF"):
		Engine.set_meta(&"prof", {})
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2 and parts[0] == "mode":
			_mode = parts[1]
		elif parts.size() == 2 and parts[0] == "seed":
			seed(int(parts[1]))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		if not OS.has_environment("BF_OPAQUE"):
			root.transparent_bg = true
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
		DisplayServer.window_set_min_size(Vector2i(1, 1))
		DisplayServer.window_set_size(Vector2i(1, 1))
		var screen: int = DisplayServer.get_primary_screen()
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + DisplayServer.screen_get_size(screen) - Vector2i(1, 1))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080) if _mode == "render" else Vector2i(1280, 720)
	_viewport.size_2d_override = Vector2i(1280, 720)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = true
	root.add_child(_viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	_main = load("res://scenes/app/main.tscn").instantiate()
	_main.name = "Main"
	_viewport.add_child(_main)
	_build()


func _build() -> void:
	var settings: Node = root.get_node("UserSettings")
	settings.set_value(&"gameplay_bot_phase_shop", false)
	if _mode == "render":
		_add({"name": "start", "frames": 30, "measure": false, "setup": func() -> void:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0})
	_add({"name": "boot_full", "load": true, "until": func() -> bool: return not _main.has_method("is_warm") or _main.is_warm()})
	_add({"name": "menu", "frames": 600, "warmup": 60})
	_add({"name": "load_duel", "load": true, "setup": func() -> void:
		settings.set_value(&"progress_bot_world", "verdant")
		root.get_node("NetworkSession").start_bot_duel(false)
		_main.start_game(),
		"until": func() -> bool: return _game() != null})
	_add({"name": "duel_verdant", "frames": _len(2700), "warmup": 120, "setup": func() -> void: _ai_both(), "tick": _duel_tick})
	_add({"name": "load_mars", "load": true, "setup": func() -> void:
		settings.set_value(&"progress_bot_world", "mars")
		root.get_node("NetworkSession").start_bot_duel(false)
		_main.start_game(),
		"until": func() -> bool: return _game() != null and _game().has_node("Arena/Weather")})
	_add({"name": "duel_mars", "frames": _len(2700), "warmup": 120, "setup": func() -> void:
		_ai_both()
		_game().get_node("Arena/Weather").skip_to_storm(true, 1.0, false), "tick": _mars_tick})
	if _mode == "cpu":
		_add({"name": "load_sandbox", "load": true, "setup": func() -> void:
			settings.set_value(&"progress_sandbox_world", "verdant")
			root.get_node("NetworkSession").start_training()
			_main.start_game(),
			"until": func() -> bool: return _game() != null})
		_add({"name": "sandbox_stress", "frames": _len(1800), "warmup": 60, "setup": func() -> void:
			_seeded.clear()
			_next_loadout = 0.0
			Input.action_press("p1_shoot"), "tick": _sandbox_tick, "teardown": func() -> void:
			Input.action_release("p1_shoot")
			if _move != "":
				Input.action_release(_move)
			_move = ""})
	_add({"name": "load_loadout", "load": true, "setup": func() -> void:
		_main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn") if _main.has_method("get_scene") else _main.INTERMISSION_MENU_SCENE),
		"until": func() -> bool: return _main.get_node("SceneRoot").get_child_count() > 0 and _main.get_node("SceneRoot").get_child(-1).has_method("_set_page")})
	_add({"name": "loadout", "frames": 900 if _mode == "cpu" else 600, "warmup": 60, "setup": func() -> void:
		_main.get_node("SceneRoot").get_child(-1)._set_page(-1), "tick": _ui_tick})
	_add({"name": "research", "frames": 600, "warmup": 60, "setup": func() -> void:
		_main.get_node("SceneRoot").get_child(-1)._set_page(1), "tick": _ui_tick})
	_add({"name": "done", "frames": 1, "measure": false, "setup": func() -> void:
		print("R mem_static_mb %.2f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
		print("R mem_peak_mb %.2f" % (Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0))
		print("R objects %d" % Performance.get_monitor(Performance.OBJECT_COUNT))
		print("R vram_textures_mb %.2f" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0))
		print("R vram_total_mb %.2f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
		print("R resources %d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		print("R total_s %.2f" % (Time.get_ticks_msec() / 1000.0))
		quit()})
	_next_phase()


func _len(frames: int) -> int:
	if _short:
		return 600
	return frames if _mode == "cpu" else 900


func _add(phase: Dictionary) -> void:
	_phases.append(phase)


func _game() -> Node:
	return get_first_node_in_group(&"game_world")


func _next_phase() -> void:
	if not _phase.is_empty():
		_report()
		var teardown: Variant = _phase.get("teardown")
		if teardown is Callable:
			teardown.call()
	if _phases.is_empty():
		return
	_phase = _phases.pop_front()
	_phase_frame = 0
	_frames.clear()
	_gpu.clear()
	_rcpu.clear()
	_draws.clear()
	_prof.clear()
	_wait_started = Time.get_ticks_usec()
	var setup: Variant = _phase.get("setup")
	if setup is Callable:
		setup.call()


func _report() -> void:
	var name: String = str(_phase["name"])
	if _phase.get("load", false):
		var since: int = 0 if name == "boot_full" else _wait_started
		print("R %s_ms %.1f" % [name, (Time.get_ticks_usec() - since) / 1000.0])
		return
	if not _phase.get("measure", true) or _frames.is_empty():
		return
	var sorted: Array = _frames.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	print("R %s_mean %.3f" % [name, _avg(_frames)])
	print("R %s_p95 %.3f" % [name, sorted[int(n * 0.95)]])
	print("R %s_p99 %.3f" % [name, sorted[int(n * 0.99)]])
	print("R %s_max %.3f" % [name, sorted[n - 1]])
	if _mode == "cpu":
		print("R %s_nodes %d" % [name, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	else:
		print("R %s_gpu %.3f" % [name, _avg(_gpu)])
		print("R %s_rcpu %.3f" % [name, _avg(_rcpu)])
		print("R %s_draws %.1f" % [name, _avg(_draws)])
	if not _prof.is_empty():
		var keys: Array = _prof.keys().filter(func(k): return not str(k).ends_with("#"))
		keys.sort_custom(func(a, b): return _prof[a] > _prof[b])
		for key in keys.slice(0, 40):
			print("P %s %-55s %.3f ms/f  %.2f calls/f" % [name, key, _prof[key] / 1000.0 / float(n), float(_prof.get(str(key) + "#", 0)) / float(n)])


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _process(delta: float) -> bool:
	_time += delta
	if _mode == "render" and OS.has_environment("BF_UNCAPPED"):
		# The game applies its own frame cap and vsync from the settings; keep both off while measuring.
		if Engine.max_fps != 0:
			Engine.max_fps = 0
		if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var now: int = Time.get_ticks_usec()
	if not _boot_reported and _main != null and _main.get("_current_scene") != null:
		_boot_reported = true
		print("R boot_ms %.1f" % (now / 1000.0))
	if _phase.is_empty():
		return false
	if _phase.get("load", false):
		if (_phase["until"] as Callable).call():
			# Count the frame that finished the load, then move on.
			_next_phase()
		_prev_usec = now
		return false
	var tick: Variant = _phase.get("tick")
	if tick is Callable:
		tick.call()
	var warmup: int = int(_phase.get("warmup", 0))
	if _phase_frame >= warmup and _prev_usec > 0:
		_frames.append((now - _prev_usec) / 1000.0)
		if Engine.has_meta(&"prof"):
			var frame_prof: Dictionary = Engine.get_meta(&"prof")
			for key in frame_prof.keys():
				_prof[key] = int(_prof.get(key, 0)) + int(frame_prof[key])
		if _mode == "render":
			_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid()))
			_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_viewport.get_viewport_rid()))
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prev_usec = now
	if Engine.has_meta(&"prof"):
		(Engine.get_meta(&"prof") as Dictionary).clear()
	_phase_frame += 1
	if _phase_frame >= int(_phase.get("frames", 1)) + warmup:
		_next_phase()
	return false


# --- Drivers ---------------------------------------------------------------------------------------------

func _ai_both() -> void:
	var game: Node = _game()
	if game == null:
		return
	for slot in [1, 2]:
		var player = game.get_player_by_slot(slot)
		if player != null and player.control_mode != &"ai":
			player.configure_ai_control(slot, 2)
	_seeded.clear()
	_next_loadout = _time


func _duel_tick() -> void:
	var game: Node = _game()
	if game == null:
		return
	if game.is_match_over():
		root.get_node("NetworkSession").start_bot_duel(false)
		_main.start_game()
		_ai_both.call_deferred()
		return
	var p1 = game.get_player_by_slot(1)
	if p1 != null and p1.control_mode != &"ai":
		p1.configure_ai_control(1, 2)
	if _time >= _next_loadout:
		_next_loadout = _time + 6.0
		for slot in [1, 2]:
			_random_loadout(slot)


func _mars_tick() -> void:
	_duel_tick()
	var game: Node = _game()
	if game != null and _phase_frame % 900 == 450 and game.has_node("Arena/Weather"):
		game.get_node("Arena/Weather").skip_to_storm(true, 1.0, false)


func _sandbox_tick() -> void:
	var game: Node = _game()
	if game == null:
		return
	if _time >= _next_loadout:
		_next_loadout = _time + 5.0
		_random_loadout(1)
	var angle: float = _time * 2.3 + sin(_time * 0.7) * 2.0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(640, 360) + Vector2(cos(angle), sin(angle) * 0.6) * 300.0
	motion.global_position = motion.position
	_viewport.push_input(motion, true)
	if randf() < 0.08:
		if _move != "":
			Input.action_release(_move)
		_move = ["p1_move_left", "p1_move_right", "", "p1_jump"][randi() % 4]
		if _move != "":
			Input.action_press(_move)


## Sweeps the pointer across the page so hover, inspector and tooltips all work.
func _ui_tick() -> void:
	var t: float = float(_phase_frame) / 60.0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(640.0 + cos(t * 0.9) * 560.0, 380.0 + sin(t * 1.7) * 300.0)
	motion.global_position = motion.position
	_viewport.push_input(motion, true)


func _random_loadout(slot: int) -> void:
	var inv: Node = root.get_node("ExtensionInventory")
	if not _seeded.has(slot):
		_seeded[slot] = true
		inv.add_all_definitions_for_player(slot)
	var by_slot: Dictionary = {}
	for item in inv.get_inventory_for_player(slot):
		var key: StringName = item.get_slot()
		if not by_slot.has(key):
			by_slot[key] = []
		by_slot[key].append(item)
	for key in [&"front", &"middle", &"ammo"]:
		var options: Array = by_slot.get(key, [])
		if options.is_empty() or randf() < 0.15:
			inv.unequip_for_player(slot, key)
			continue
		var choice = options[randi() % options.size()]
		choice.mark = randi_range(1, 3)
		inv.equip_item_for_player(slot, choice)
