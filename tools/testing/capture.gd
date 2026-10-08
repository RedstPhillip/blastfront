extends SceneTree

## Scenario-driven test harness. Instantiates res://scenes/app/main.tscn inside a SubViewport, then plays a
## timed script of actions (mouse moves, input actions, direct calls into game code) and screenshots.
##
## Usage (see tools/testing/README.md; run_capture.sh / run_headless.sh wrap this):
##   godot --path <project copy> --audio-driver Dummy --fixed-fps 60 -s <this file> -- scenario=<name> out=<dir>
## Headless runs skip screenshots and are used for error checks (regress.sh greps the output).
## Environment knobs: BF_FULLHD / BF_SMALL (viewport size), BF_ONSCREEN (park the 1px window at the screen
## corner instead of off-screen; off-screen windows get throttled), BF_OPAQUE, BF_WORLD (verdant|mars),
## BF_STRESS_SECONDS, BF_UNCAPPED, BF_NOHITCH, BF_SIZE (e.g. 1280x800).
## Each scenario is a case in _build_script(); _at(time_seconds, kind, arg) queues an action.

var _scenario: String = "menu"
var _out_dir: String = ""
var _frame: int = 0
var _time: float = 0.0
var _main: Node = null
var _shots: Array = []
var _actions: Array = []
var _done: bool = false
var _viewport: SubViewport = null
var _flags: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	Engine.set_meta(&"prof", {})
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2:
			if parts[0] == "scenario":
				_scenario = parts[1]
			elif parts[0] == "out":
				_out_dir = parts[1]
			elif parts[0] == "flags":
				_flags = parts[1].split(",")
			elif parts[0] == "seed":
				seed(int(parts[1]))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_hide_os_window()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080) if OS.has_environment("BF_FULLHD") else (Vector2i(640, 360) if OS.has_environment("BF_SMALL") else Vector2i(1280, 720))
	if OS.has_environment("BF_SMALL"):
		_viewport.size_2d_override = Vector2i(1280, 720)
		_viewport.size_2d_override_stretch = true
	if OS.has_environment("BF_FULLHD"):
		_viewport.size_2d_override = Vector2i(1280, 720)
		_viewport.size_2d_override_stretch = true
	# BF_SIZE=1280x800 renders the logical size the game gets on other aspect ratios (16:10 with the
	# "expand" stretch aspect, e.g. Steam Deck).
	if OS.has_environment("BF_SIZE"):
		var parts: PackedStringArray = OS.get_environment("BF_SIZE").split("x")
		_viewport.size = Vector2i(int(parts[0]), int(parts[1]))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = true
	root.add_child(_viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	var main_scene: PackedScene = load("res://scenes/app/main.tscn")
	_main = main_scene.instantiate()
	_main.name = "Main"
	_viewport.add_child(_main)
	_build_script()
	_actions.sort_custom(func(a, b): return a["t"] < b["t"])


func _hide_os_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	if not OS.has_environment("BF_OPAQUE"):
		root.transparent_bg = true
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	if OS.has_environment("BF_BIGWIN"):
		DisplayServer.window_set_size(Vector2i(1280, 720))
	else:
		DisplayServer.window_set_min_size(Vector2i(1, 1))
		DisplayServer.window_set_size(Vector2i(1, 1))
	if OS.has_environment("BF_ONSCREEN"):
		var screen: int = DisplayServer.get_primary_screen()
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + DisplayServer.screen_get_size(screen) - Vector2i(1, 1))
	else:
		DisplayServer.window_set_position(Vector2i(-32000, -32000))


func _build_script() -> void:
	match _scenario:
		"menu":
			_at(0.2, "mouse", Vector2(900, 300))
			_at(0.4, "shot", "menu_0")
			_at(1.8, "shot", "menu_1")
			_at(2.0, "call", func(): _main.get_node("SceneRoot").get_child(0)._open_bot_panel())
			_at(2.5, "shot", "menu_bot")
			_at(2.6, "call", func(): _main.get_node("SceneRoot").get_child(0)._close_bot_panel())
			_at(2.8, "call", func(): _main.get_node("SceneRoot").get_child(0)._on_settings_pressed())
			_at(3.4, "shot", "menu_settings")
			_at(3.6, "quit")
		"sandbox":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(820, 400))
			_at(1.2, "shot", "sandbox_0")
			_at(1.3, "press", "p1_move_right")
			_at(1.9, "shot", "sandbox_run")
			_at(2.0, "release", "p1_move_right")
			_at(2.05, "press", "p1_jump")
			_at(2.25, "shot", "sandbox_jump")
			_at(2.3, "release", "p1_jump")
			_at(2.8, "press", "p1_shoot")
			_at(2.82, "shot", "sandbox_shoot0")
			_at(2.86, "shot", "sandbox_shoot1")
			_at(2.9, "release", "p1_shoot")
			_at(2.95, "shot", "sandbox_shoot2")
			_at(3.1, "shot", "sandbox_shoot3")
			_at(3.4, "press", "p1_block")
			_at(3.45, "shot", "sandbox_block")
			_at(3.5, "release", "p1_block")
			_at(3.6, "action", "pause")
			_at(3.9, "shot", "sandbox_pause")
			_at(4.0, "quit")
		"bot":
			_at(0.3, "call", func(): root.get_node("NetworkSession").start_bot_duel(); _main.start_game())
			_at(0.5, "mouse", Vector2(900, 380))
			for i in range(12):
				_at(1.0 + i * 1.0, "shot", "bot_%02d" % i)
			_at(1.0, "call", func(): _log_state())
			for i in range(90):
				_at(1.0 + i * 0.5, "call", func(): _log_state())
			_at(46.2, "quit")
		"online_pages":
			_at(0.3, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(1.5, "shot", "inter_status")
			_at(1.6, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(-1))
			_at(2.4, "shot", "inter_loadout")
			_at(2.5, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(1))
			_at(3.3, "shot", "inter_research")
			_at(3.4, "quit")
		"ui_quests":
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "shot", "hint_sandbox")
			_at(2.2, "call", func():
				var tracker = get_first_node_in_group(&"game_world").find_child("@Control*", true, false)
				for n in get_first_node_in_group(&"game_world").get_node("HUD").find_children("*", "", true, false):
					if n.get_script() != null and n.get_script().get_global_name() == "HudQuestTracker":
						_tracker = n
				_tracker.visible = true
				var qm = root.get_node("ResearchQuestManager")
				qm._assignments_by_slot[1] = [
					{"id": "jump_5", "title": "Jump 5 times", "tier": "easy", "event": "jump", "target": 5.0, "reward": 1, "progress": 2.0, "completed": false, "failed": false},
					{"id": "hit_4", "title": "Hit the opponent 4 times", "tier": "medium", "event": "hits", "target": 4.0, "reward": 2, "progress": 3.0, "completed": false, "failed": false},
					{"id": "no_hit", "title": "Win the set without being hit", "tier": "hard", "event": "no_hit", "target": 1.0, "reward": 4, "progress": 0.0, "completed": false, "failed": false},
				]
				qm.quests_changed.emit())
			_at(2.8, "shot", "quests_a")
			_at(3.0, "call", func():
				var qm = root.get_node("ResearchQuestManager")
				qm._assignments_by_slot[1][0]["progress"] = 3.0
				qm._assignments_by_slot[1][1]["progress"] = 4.0
				qm._assignments_by_slot[1][1]["completed"] = true
				qm.quests_changed.emit())
			_at(3.15, "shot", "quests_b")
			_at(3.6, "shot", "quests_c")
			_at(3.7, "call", func(): get_first_node_in_group(&"hud_toasts").push("PERFECT ROUND", "Won without taking a single hit", Color(1.0, 0.84, 0.5), &"reward"))
			_at(4.3, "shot", "quests_d")
			_at(4.4, "quit")
		"look":
			_at(0.3, "call", func(): root.get_node("NetworkSession").start_bot_duel(); _main.start_game())
			_at(0.6, "call", func(): get_first_node_in_group(&"game_world").get_player_by_slot(1).configure_ai_control(1, 1))
			_at(6.0, "shot", "look_a")
			_at(9.0, "shot", "look_b")
			_at(9.1, "quit")
		"victory":
			_at(0.3, "call", func(): root.get_node("NetworkSession").start_bot_duel(); _main.start_game())
			_at(3.5, "call", func():
				var g = get_first_node_in_group(&"game_world")
				g._offline_score[1] = 5
				g._offline_score[2] = 3
				g.point_awarded.emit(1)
				g._offline_match_over = true
				g.match_finished.emit(1))
			_at(4.0, "shot", "victory_banner")
			_at(6.2, "shot", "victory_a")
			_at(6.3, "call", func(): _log_focus("victory"))
			_at(7.5, "shot", "victory_b")
			_at(7.6, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(8.2, "shot", "pause_restart")
			_at(8.3, "quit")
		"gamepad":
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func():
				for axis_value in [[2, 0.9], [3, -0.35]]:
					var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
					m.device = 0
					m.axis = axis_value[0]
					m.axis_value = axis_value[1]
					Input.parse_input_event(m))
			_at(2.6, "call", func():
				var p1 = get_first_node_in_group(&"game_world").get_player_by_slot(1)
				print("PAD using=", root.get_node("InputDevice").using_gamepad, " aimdir=", root.get_node("InputDevice").aim_direction, " aim=", p1.get_aim_world_position() - p1.global_position, " ammo=", p1.get_gun().get_current_ammo()))
			_at(2.7, "call", func():
				var t: InputEventJoypadMotion = InputEventJoypadMotion.new()
				t.device = 0
				t.axis = 5
				t.axis_value = 1.0
				Input.parse_input_event(t))
			_at(3.0, "call", func():
				var p1 = get_first_node_in_group(&"game_world").get_player_by_slot(1)
				print("PAD after trigger ammo=", p1.get_gun().get_current_ammo()))
			_at(3.1, "call", func():
				var r: InputEventJoypadButton = InputEventJoypadButton.new()
				r.device = 0
				r.button_index = 2
				r.pressed = true
				Input.parse_input_event(r))
			_at(3.3, "call", func():
				var p1 = get_first_node_in_group(&"game_world").get_player_by_slot(1)
				print("PAD after X reloading=", p1.get_gun().is_reloading()))
			_at(3.4, "call", func():
				var mm: InputEventMouseMotion = InputEventMouseMotion.new()
				mm.relative = Vector2(20, 5)
				mm.position = Vector2(500, 300)
				Input.parse_input_event(mm))
			_at(3.6, "call", func(): print("PAD after mouse using=", root.get_node("InputDevice").using_gamepad))
			_at(3.7, "quit")
		"controls_tab":
			_at(1.5, "call", func(): _main.get_node("SceneRoot").get_child(0)._on_settings_pressed())
			_at(2.0, "call", func():
				var sm = _main.get_node("SceneRoot").get_child(0).find_children("*", "TabContainer", true, false)
				if sm.size() > 0:
					sm[0].current_tab = 3)
			_at(2.6, "shot", "controls_tab")
			for tab in [1, 2]:
				_at(2.7 + tab * 0.4, "call", func():
					var tabs = _main.get_node("SceneRoot").get_child(0).find_children("*", "TabContainer", true, false)
					if tabs.size() > 0:
						tabs[0].current_tab = tab)
				_at(2.9 + tab * 0.4, "shot", "settings_tab_%d" % tab)
			_at(3.8, "quit")
		"settings_reset":
			_at(1.5, "call", func(): _main.get_node("SceneRoot").get_child(0)._on_settings_pressed())
			_at(2.0, "call", func():
				var settings = _main.get_node("SceneRoot").get_child(0)._settings_instance
				settings._tabs.current_tab = 3
				settings._on_reset_pressed())
			_at(2.4, "call", func():
				var tabs: TabContainer = _main.get_node("SceneRoot").get_child(0)._settings_instance._tabs
				var titles: PackedStringArray = PackedStringArray()
				for i in range(tabs.get_tab_count()):
					titles.append(tabs.get_tab_title(i))
				print("TABS ", ",".join(titles), " current=", tabs.current_tab))
			_at(2.6, "shot", "settings_after_reset")
			_at(2.7, "quit")
		"pad_nav":
			# Menus driven only by ui_* actions (d-pad / stick + A / B): prints the focused control after each step.
			var steps: Array = [
				"ui_down", "ui_down", "ui_up", "ui_up", "ui_accept",
				"ui_up", "ui_up", "ui_right", "ui_up", "ui_down", "ui_down", "ui_down", "ui_cancel",
				"ui_down", "ui_down", "ui_down", "ui_accept", "ui_up", "ui_up", "ui_up", "ui_up", "ui_right",
				"ui_up", "ui_up", "ui_up", "ui_up", "ui_up", "ui_right", "ui_down", "ui_cancel",
			]
			_at(1.2, "call", func(): _log_focus("start"))
			for i in range(steps.size()):
				var step: String = steps[i]
				_at(1.4 + i * 0.35, "action", step)
				_at(1.55 + i * 0.35, "call", func(): _log_focus(step))
				_at(1.6 + i * 0.35, "shot", "pad_%02d" % i)
			_at(1.6 + steps.size() * 0.35, "shot", "pad_nav_end")
			_at(1.8 + steps.size() * 0.35, "quit")
		"pad_nav_game":
			# Pause menu and the sandbox loadout driven only by ui_* actions.
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.8, "call", func(): root.get_node("InputDevice")._set_gamepad(true))
			_at(2.0, "action", "pause")
			var game_steps: Array = [
				"ui_down", "ui_down", "ui_accept", "ui_down", "ui_right", "ui_right", "ui_down", "ui_accept",
				"ui_left", "ui_up", "ui_up", "ui_up", "ui_cancel", "ui_down", "ui_down", "ui_right", "ui_cancel",
			]
			_at(2.4, "call", func(): _log_focus("paused"))
			for i in range(game_steps.size()):
				var game_step: String = game_steps[i]
				_at(2.6 + i * 0.35, "action", game_step)
				_at(2.75 + i * 0.35, "call", func(): _log_focus(game_step))
				_at(2.8 + i * 0.35, "shot", "padg_%02d" % i)
			_at(3.0 + game_steps.size() * 0.35, "quit")
		"pad_nav_inter":
			# Between sets as a pad user: LB / RB switch pages, the d-pad moves inside each page, B goes back.
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true)
				_main._on_bot_requested(1))
			_at(2.0, "call", func():
				root.get_node("InputDevice")._set_gamepad(true)
				root.get_node("OnlineMatch").coin_balances[1] = 40
				root.get_node("OnlineMatch").match_points[1] = 1
				_main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			var inter_steps: Array = [
				"start", "LB", "ui_down", "ui_right", "RB", "RB", "ui_down", "ui_right", "ui_up", "ui_cancel",
				"ui_down", "LB", "ui_up", "ui_cancel",
			]
			for i in range(inter_steps.size()):
				var inter_step: String = inter_steps[i]
				_at(4.0 + i * 0.4, "call", func():
					if inter_step == "LB" or inter_step == "RB":
						_push_pad_button(JOY_BUTTON_LEFT_SHOULDER if inter_step == "LB" else JOY_BUTTON_RIGHT_SHOULDER)
					elif inter_step != "start":
						_push_action(inter_step))
				_at(4.2 + i * 0.4, "call", func():
					var menu = _main.get_node("SceneRoot").get_child(-1)
					_log_focus("%s p%d" % [inter_step, menu._page_index if "_page_index" in menu else 99]))
				_at(4.25 + i * 0.4, "shot", "padi_%02d" % i)
			_at(4.5 + inter_steps.size() * 0.4, "quit")
		"botshop":
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true)
				root.get_node("OnlineMatch").phase_changed.connect(func(ph): print("PHASE t=%.1f %s sets=%s kills=%s coins=%s" % [_time, ph, root.get_node("OnlineMatch").match_points, root.get_node("OnlineMatch").set_kills, root.get_node("OnlineMatch").coin_balances]))
				_main._on_bot_requested(1))
			for i in range(60):
				_at(2.0 + i * 3.0, "call", func(): _botshop_tick())
			_at(182.0, "quit")
		"shoptour":
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true)
				_main._on_bot_requested(1))
			_at(1.0, "call", func(): get_first_node_in_group(&"game_world").get_player_by_slot(1).configure_ai_control(1, 2))
			_at(2.4, "shot", "tour_set_intro")
			_at(8.0, "shot", "tour_fight")
			for i in range(60):
				_at(10.0 + i * 1.5, "call", func(): _tour_tick())
			_at(100.0, "quit")
		"locker_esc":
			_at(0.5, "call", func(): _main._show_locker_room())
			_at(1.5, "call", func(): print("SCENE before=", _main.get_node("SceneRoot").get_child(-1).name))
			_at(1.6, "call", func(): _push_action("ui_cancel"))
			_at(1.8, "call", func(): print("SCENE after1=", _main.get_node("SceneRoot").get_child(-1).name))
			_at(1.9, "call", func(): _push_action("ui_cancel"))
			_at(3.0, "call", func(): print("SCENE after2=", _main.get_node("SceneRoot").get_child(-1).name, " mouse=", Input.mouse_mode))
			_at(3.1, "quit")
		"stress":
			var total: float = float(OS.get_environment("BF_STRESS_SECONDS")) if OS.has_environment("BF_STRESS_SECONDS") else 240.0
			_at(0.3, "call", func(): _stress_start())
			var t: float = 2.0
			while t < total:
				_at(t, "call", func(): _stress_tick())
				t += 1.0
			_at(3.0, "call", func():
				if OS.has_environment("BF_UNCAPPED"):
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
					Engine.max_fps = 0
				_stress_recording = true)
			_at(total - 0.05, "call", func(): _stress_recording = false; _stress_frame_report())
			_at(total, "call", func():
				print("STRESS done rounds=%d shots=%d loadouts=%d" % [_stress_rounds, _stress_shots, _stress_loadouts])
				for line in _stress_deaths:
					print("  DEATH ", line))
			_at(total + 0.1, "quit")
		"stress_sandbox":
			var total2: float = float(OS.get_environment("BF_STRESS_SECONDS")) if OS.has_environment("BF_STRESS_SECONDS") else 180.0
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant"))
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "call", func(): _stress_hook())
			_at(1.5, "press", "p1_shoot")
			var t2: float = 1.6
			while t2 < total2:
				_at(t2, "call", func(): _stress_sandbox_tick())
				t2 += 0.1
			_at(3.0, "call", func():
				if OS.has_environment("BF_UNCAPPED"):
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
					Engine.max_fps = 0
				_stress_recording = true)
			_at(total2 - 0.05, "call", func(): _stress_recording = false; _stress_frame_report())
			_at(total2, "call", func(): print("STRESS done loadouts=%d maxproj=%d stats=%s" % [_stress_loadouts, _stress_shots, _stress_game().get_match_stats(1)]))
			_at(total2 + 0.1, "quit")
		"mars_storm":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(1.6, "mouse", Vector2(900, 330))
			_at(1.8, "shot", "calm")
			_at(2.0, "call", func(): _weather().skip_to_storm(false, 1.0, true))
			_at(3.0, "shot", "buildup_early")
			_at(6.2, "shot", "buildup_late")
			# Exposed on the left mesa top, idle: how far does the storm shove the player?
			_at(8.5, "call", func(): _place_p1(Vector2(150, 380)))
			_at(9.0, "call", func(): _probe_mark("idle_exposed"))
			_at(10.0, "call", func(): _probe_report("idle_exposed"))
			_at(10.05, "shot", "storm_mesa")
			# Running against and with the wind on the mesa top.
			_at(10.1, "call", func(): _place_p1(Vector2(230, 380)); Input.action_press("p1_move_left"))
			_at(10.35, "call", func(): _probe_mark("run_against"))
			_at(10.65, "call", func(): _probe_report("run_against"); Input.action_release("p1_move_left"))
			_at(10.7, "call", func(): _place_p1(Vector2(-40, 380)); Input.action_press("p1_move_right"))
			_at(10.95, "call", func(): _probe_mark("run_with"))
			_at(11.25, "call", func(): _probe_report("run_with"); Input.action_release("p1_move_right"))
			# Airborne drift: a jump from the mesa top without input.
			_at(11.3, "call", func(): _place_p1(Vector2(120, 380)))
			_at(11.5, "press", "p1_jump")
			_at(11.52, "call", func(): _probe_mark("jump_idle"))
			_at(11.9, "release", "p1_jump")
			_at(12.2, "call", func(): _probe_report("jump_idle"))
			# Sheltered in the crater behind the left slope / behind the spire.
			_at(12.3, "call", func(): _place_p1(Vector2(905, 640)))
			_at(12.8, "call", func(): _probe_mark("idle_crater"))
			_at(13.8, "call", func(): _probe_report("idle_crater"))
			_at(13.85, "shot", "storm_crater")
			_at(13.9, "call", func(): _place_p1(Vector2(1200, 650)))
			_at(14.4, "call", func(): _probe_mark("idle_lee_spire"))
			_at(15.4, "call", func(): _probe_report("idle_lee_spire"))
			# Shots: aimed fire from the mesa, watch the drift.
			_at(15.5, "call", func(): _place_p1(Vector2(150, 380)))
			_at(15.8, "mouse", Vector2(1100, 300))
			_at(15.9, "press", "p1_shoot")
			_at(15.95, "release", "p1_shoot")
			_at(16.2, "shot", "storm_shot")
			_at(17.0, "call", func(): _weather().skip_to_storm(true, -1.0, false))
			_at(23.0, "call", func(): _place_p1(Vector2(1300, 650)))
			_at(23.5, "shot", "severe_1")
			_at(25.0, "call", func(): _place_p1(Vector2(640, 520)))
			_at(25.5, "shot", "severe_2")
			_at(25.6, "call", func(): print("SEVERE wind=%.0f vis=%.2f storm=%.2f" % [WorldConditions.wind.x, WorldConditions.visibility, WorldConditions.storm]))
			_at(26.0, "quit")
		"shelter_probe":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): _weather().skip_to_storm(false, 1.0, false))
			_at(4.0, "call", func(): _place_p1(Vector2(950, 650)))
			_at(5.0, "call", func():
				var g = _stress_game()
				var p1 = g.get_player_by_slot(1)
				var space = p1.get_world_2d().direct_space_state
				print("P1 at ", p1.global_position, " wind ", WorldConditions.wind)
				for y in [0.0, -18.0]:
					var from: Vector2 = p1.global_position + Vector2(0, y)
					var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(-170, 0), 1)
					q.exclude = [p1.get_rid()]
					print("  ray y=", from.y, " hit=", space.intersect_ray(q))
				print("  exposure fn=", WorldConditions.wind_exposure_at(space, p1.global_position, [p1.get_rid()])))
			_at(5.2, "quit")
		"dash_probe":
			# Dashing per mark on flat Verdant ground: burst distance, cooldown (dash spammed every 0.1 s, the
			# DASH start lines show when it actually fires), an air dash, Mk IV protection against a real round
			# (with a control shot outside the dash) and the Mk III shockwave against a parked dummy (with a
			# Mk II control). Shots only in render runs.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.6, "call", func():
				_dash_spot = _build_test_floor(Vector2(300.0, 100.0), 800.0)
				_freeze_camera_keep_players(Vector2(700.0, 120.0), 1.25)
				var dummy = _stress_game().get_player_by_slot(2)
				dummy.set_controls_enabled(false)
				dummy.global_position = Vector2(_dash_spot.x + 1400.0, _dash_spot.y - 60.0)
				_set_dash_mark(1)
				_hooks.append(_watch_dashes))
			# Mk I: one dash from standstill (facing right), then spammed; cooldown 2.4 s.
			_at(2.0, "call", func(): _dash_reset_p1())
			_at(2.2, "call", func(): print("PROBE mk1 ratio_before=%.2f" % _p1().get_dash_cooldown_ratio()))
			for i in range(28):
				_at(2.2 + i * 0.1, "press", "p1_dash")
				_at(2.25 + i * 0.1, "release", "p1_dash")
			_at(2.3, "crop", ["dash_mid", Rect2(120, 200, 420, 180), 2.5])
			_at(2.36, "crop", ["dash_mid2", Rect2(120, 200, 420, 180), 2.5])
			_at(2.42, "crop", ["dash_end", Rect2(120, 200, 420, 180), 2.5])
			_at(2.9, "call", func(): print("PROBE mk1 t=2.9 ratio=%.2f x_after_glide=%.0f" % [_p1().get_dash_cooldown_ratio(), _p1().global_position.x - _dash_spot.x]); _dash_reset_p1())
			_at(2.95, "crop", ["dash_hud", Rect2(0, 630, 340, 90), 3.0])
			_at(2.15, "crop", ["dash_hud_ready", Rect2(0, 630, 340, 90), 3.0])
			_at(4.75, "crop", ["dash_hud_pop", Rect2(0, 630, 340, 90), 3.0])
			_at(4.45, "call", func(): _dash_reset_p1())
			# Mk II: cooldown 1.4 s.
			_at(5.2, "call", func(): _set_dash_mark(2); _dash_reset_p1())
			# The Mk I cooldown from the 4.6 s dash runs out at 7.0 s: spam from there.
			for i in range(19):
				_at(7.0 + i * 0.1, "press", "p1_dash")
				_at(7.05 + i * 0.1, "release", "p1_dash")
			_at(8.4, "call", func(): _dash_reset_p1())
			# Air dash: jump, then dash at the apex region; the burst should be flat.
			_at(9.6, "call", func(): _dash_reset_p1())
			_at(10.15, "press", "p1_jump")
			_at(10.4, "press", "p1_dash")
			_at(10.45, "release", "p1_dash")
			_at(10.5, "release", "p1_jump")
			_at(10.5, "crop", ["dash_air", Rect2(120, 120, 420, 260), 2.0])
			# Mk IV protection: a round fired into the dash flies through; the same round later hits.
			_at(11, "call", func(): _set_dash_mark(4); _dash_reset_p1(); _p1().health_component.health = 100)
			_at(12, "press", "p1_dash")
			_at(12.05, "release", "p1_dash")
			_at(12.02, "call", func(): _fire_at_p1(110.0))
			_at(12.06, "crop", ["dash_protected", Rect2(120, 200, 420, 180), 2.5])
			_at(12.5, "call", func(): print("PROBE protected hp=%d (100 = no damage) round_alive=%s" % [_p1().health_component.health, is_instance_valid(_probe_round) and _probe_round.is_inside_tree()]))
			_at(12.8, "call", func(): _dash_reset_p1(); _p1().health_component.health = 100)
			_at(13, "call", func(): _fire_at_p1(110.0))
			_at(13.4, "call", func(): print("PROBE control hp=%d (round fired while standing)" % _p1().health_component.health); _p1().health_component.health = 100)
			_at(13.5, "call", func():
				var hp_before: int = _p1().health_component.health
				var applied: int = _p1().apply_incoming_damage(25, 2, _p1().global_position)
				print("PROBE direct_damage_outside_dash applied=%d hp %d->%d" % [applied, hp_before, _p1().health_component.health])
				_p1().health_component.health = 100)
			# Mk III shockwave: dummy parked 130 px ahead on the same floor.
			_at(14.5, "call", func(): _set_dash_mark(3); _dash_reset_p1(); _park_dummy(130.0))
			_at(15, "press", "p1_dash")
			_at(15.05, "release", "p1_dash")
			_at(15.12, "crop", ["dash_shockwave", Rect2(120, 160, 520, 220), 2.0])
			_at(15.2, "crop", ["dash_shockwave2", Rect2(120, 160, 520, 220), 2.0])
			_at(15.6, "call", func(): _report_dummy("shockwave_mk3"))
			# Mk II control: same setup, no shockwave.
			_at(16.5, "call", func(): _set_dash_mark(2); _dash_reset_p1(); _park_dummy(130.0))
			_at(17, "press", "p1_dash")
			_at(17.05, "release", "p1_dash")
			_at(17.6, "call", func(): _report_dummy("no_shockwave_mk2"))
			# Wall: dash into the dummy without a shockwave stops at the body.
			_at(18, "call", func(): print("PROBE done dashes=%d" % _dash_count))
			_at(18.2, "quit")
		"dash_online":
			# The dash's online path without Steam (sends are no-ops): the sandbox is flipped into a hosted
			# set with P2 as the remote client, and the movement module gets the packets a peer would send.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.6, "call", func():
				_dash_spot = _build_test_floor(Vector2(300.0, 100.0), 800.0)
				var g = _stress_game()
				var session = root.get_node("NetworkSession")
				session.mode = &"host"
				session._match_active = true
				session.local_player_slot = 1
				root.get_node("OnlineMatch")._reset_current_set_stats()
				root.get_node("OnlineMatch").phase = &"playing_set"
				g.get_player_by_slot(2).configure_remote_control(2)
				root.get_node("ResearchManager")._remote_marks_by_player[2] = {"dashing": 4}
				g._game_sync.setup(g)
				_hooks.append(_watch_dashes)
				_dash_reset_p1()
				_park_dummy(200.0)
				g.get_player_by_slot(2).reset_network_state_to_current_transform())
			# Host gets the client's dash: protection window on the host's copy, cooldown for the HUD.
			_at(2.0, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				_movement_packet(&"dash", 2, {"slot": 2, "direction": -1.0, "protected": true, "shockwave": true})
				print("ONLINE host got dash: protected=%s cooldown_ratio=%.2f trail=%s" % [p2.is_dash_protected(), p2.get_dash_cooldown_ratio(), p2.is_dashing()])
				var combat = _stress_game()._game_sync.get_module(&"combat")
				combat.apply_hit(2, 1, 0, 25)
				print("ONLINE hit during client's protected dash: hp=%d (100 = dodged)" % p2.health_component.health))
			_at(2.6, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				_stress_game()._game_sync.get_module(&"combat").apply_hit(2, 1, 0, 25)
				print("ONLINE hit after the window: protected=%s hp=%d (75 = landed)" % [p2.is_dash_protected(), p2.health_component.health])
				p2.health_component.health = 100)
			# The client's shockwave goes off next to the host's player: the host throws its own player.
			_at(3.0, "call", func():
				var p1 = _p1()
				_dash_reset_p1()
				_movement_packet(&"dash_shockwave", 2, {"slot": 2, "origin": p1.global_position + Vector2(40.0, 0.0), "direction": -1.0})
				print("ONLINE client's shockwave threw host player: velocity=%s stunned=%s" % [p1.velocity.round(), p1._stun_timer > 0.0]))
			# A spoofed slot: the client claims to be slot 1; the host still applies it to slot 2.
			_at(3.6, "call", func():
				_dash_reset_p1()
				_movement_packet(&"dash", 2, {"slot": 1, "direction": 1.0, "protected": true, "shockwave": false})
				print("ONLINE spoofed dash: host player protected=%s (false = ignored)" % _p1().is_dash_protected()))
			# The host's own dash with a shockwave next to the remote player: only feedback on the host's copy.
			_at(4.0, "call", func():
				_set_dash_mark(3)
				_dash_reset_p1()
				_park_dummy(130.0)
				_stress_game().get_player_by_slot(2).reset_network_state_to_current_transform())
			_at(4.2, "press", "p1_dash")
			_at(4.25, "release", "p1_dash")
			_at(4.6, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				print("ONLINE host's shockwave on the client's copy: moved dx=%+.0f (0 = the client moves it)" % (p2.global_position.x - _dummy_start.x)))
			# Client side: the host's knockback packet throws the local player.
			_at(5.0, "call", func():
				root.get_node("NetworkSession").mode = &"client"
				_dash_reset_p1()
				_movement_packet(&"knockback", 2, {"target_slot": 1, "velocity": Vector2(470.0, -290.0), "origin": _p1().global_position})
				print("ONLINE client got knockback: velocity=%s" % _p1().velocity.round()))
			# Wall moves ride on the player snapshot: the remote copy shows the wall contact, the cling and kicks.
			_at(5.2, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				var snapshot: Dictionary = {"slot": 2, "position": p2.global_position, "velocity": Vector2(0.0, 40.0), "wall": -1.0, "cling": true, "wall_jumps": 3}
				p2.apply_remote_snapshot(snapshot)
				print("ONLINE remote wall state: wall_x=%.0f clinging=%s wall_jumps_seen=%d" % [p2.get_wall_contact_x(), p2.is_wall_clinging(), p2._wall_jump_count]))
			_at(5.5, "call", func():
				var session = root.get_node("NetworkSession")
				session.mode = &"training"
				session._match_active = false
				root.get_node("OnlineMatch").phase = &"locker"
				print("ONLINE done"))
			_at(5.7, "quit")
		"wall_probe":
			# Wall Jumps per mark on a private rig (the arena's own collision is switched off): a 400 px wall
			# climbed by holding into it and holding jump 0.2 s of every 0.25 s; the climb height, wall jumps and
			# cling time are printed per mark. Then the stuck checks: over the wall top, under a platform lip,
			# and a cling that must end in a slide.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func():
				_build_wall_rig()
				_freeze_camera_keep_players(Vector2(760.0, 440.0), 1.0)
				var dummy = _stress_game().get_player_by_slot(2)
				dummy.set_controls_enabled(false)
				dummy.global_position = Vector2(300.0, 600.0)
				_hooks.append(_watch_wall))
			var marks: Array = [0, 1, 2, 3]
			for i in range(marks.size()):
				var mark: int = marks[i]
				var t0: float = 2.0 + i * 4.0
				_at(t0, "call", func(): _set_wall_mark(mark); _wall_reset(Vector2(770.0, 616.0)))
				_at(t0 + 0.2, "press", "p1_move_right")
				for k in range(12):
					_at(t0 + 0.3 + k * 0.25, "press", "p1_jump")
					_at(t0 + 0.5 + k * 0.25, "release", "p1_jump")
				_at(t0 + 0.9, "crop", ["wall_mk%d_a" % mark, Rect2(440, 60, 520, 600), 1.0])
				_at(t0 + 1.6, "crop", ["wall_mk%d_b" % mark, Rect2(440, 60, 520, 600), 1.0])
				_at(t0 + 3.4, "call", func(): _report_wall("mk%d" % mark))
				_at(t0 + 3.45, "release", "p1_move_right")
			# Over the top: from Mk II, keep holding into the wall until standing on top of it.
			_at(18.0, "call", func(): _set_wall_mark(2); _wall_reset(Vector2(770.0, 616.0)))
			_at(18.2, "press", "p1_move_right")
			for k in range(16):
				_at(18.3 + k * 0.25, "press", "p1_jump")
				_at(18.5 + k * 0.25, "release", "p1_jump")
			_at(22.5, "call", func(): _report_wall("over_top"))
			_at(22.55, "release", "p1_move_right")
			# Under a platform lip: jump into the underside corner while holding towards it, for 2 s.
			_at(23.0, "call", func(): _set_wall_mark(3); _wall_reset(Vector2(330.0, 616.0)))
			_at(23.2, "press", "p1_move_right")
			for k in range(30):
				_at(23.3 + k * 0.06, "press", "p1_jump")
				_at(23.32 + k * 0.06, "release", "p1_jump")
			_at(25.4, "release", "p1_move_right")
			_at(26.2, "call", func(): _report_wall("platform_lip"); print("WALL platform_lip end grounded=%s state=%s" % [_p1().is_grounded(), _p1()._state_machine.current_state.name]))
			# A cling ends in a slide: jump onto the wall once, hold into it, never press again.
			_at(27.0, "call", func(): _set_wall_mark(3); _wall_reset(Vector2(770.0, 616.0)))
			_at(27.2, "press", "p1_move_right")
			_at(27.3, "press", "p1_jump")
			_at(27.6, "release", "p1_jump")
			_at(27.75, "crop", ["wall_cling", Rect2(600, 300, 200, 300), 2.5])
			_at(28.6, "crop", ["wall_slide", Rect2(600, 300, 200, 300), 2.5])
			_at(29.6, "call", func(): _report_wall("cling_only"); print("WALL cling_only end grounded=%s state=%s" % [_p1().is_grounded(), _p1()._state_machine.current_state.name]))
			_at(29.65, "release", "p1_move_right")
			_at(30.0, "quit")
		"bot_climb":
			# A bot (BF_BOT_LEVEL 0-2, default hard) sent up a 160 px step, then a 400 px wall, on the climb rig.
			# Hard (Wall Jumps Mk III) climbs both, normal (Mk I) only the step, easy (none) neither.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func():
				_build_climb_rig()
				_freeze_camera_keep_players(Vector2(760.0, 440.0), 1.0)
				var dummy = _stress_game().get_player_by_slot(2)
				dummy.set_controls_enabled(false)
				dummy.global_position = Vector2(160.0, 600.0)
				var level: int = int(OS.get_environment("BF_BOT_LEVEL")) if OS.has_environment("BF_BOT_LEVEL") else 2
				_p1().configure_ai_control(1, level)
				_wall_reset(Vector2(300.0, 616.0))
				_hooks.append(_hold_bot_goals)
				_hooks.append(_watch_wall))
			_at(2.0, "call", func(): _bot_goal(_p1(), Vector2(560.0, 480.0)))
			_at(4.0, "crop", ["climb_step", Rect2(140, 60, 1000, 640), 1.0])
			_at(8.0, "call", func():
				var p1 = _p1()
				print("CLIMB step: on_top=%s at %s most_wall_jumps=%d longest_stuck=%.2f s" % [p1.is_grounded() and p1.global_position.y < 470.0, p1.global_position.round(), int(_wall_stats.get("used_max", 0)), float(_wall_stats["stuck_max"])])
				_wall_reset(Vector2(800.0, 616.0)))
			_at(8.5, "call", func(): _bot_goal(_p1(), Vector2(1030.0, 240.0)))
			_at(10.0, "crop", ["climb_wall", Rect2(140, 60, 1000, 640), 1.0])
			_at(16.0, "call", func():
				var p1 = _p1()
				print("CLIMB wall: on_top=%s at %s most_wall_jumps=%d longest_stuck=%.2f s" % [p1.is_grounded() and p1.global_position.y < 230.0, p1.global_position.round(), int(_wall_stats.get("used_max", 0)), float(_wall_stats["stuck_max"])]))
			_at(16.2, "quit")
		"bot_dash":
			# Two bots (BF_BOT_LEVEL, default hard: Dashing Mk IV) fight on BF_WORLD; every dash is logged.
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_difficulty", int(OS.get_environment("BF_BOT_LEVEL")) if OS.has_environment("BF_BOT_LEVEL") else 2)
				root.get_node("UserSettings").set_value(&"progress_bot_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant")
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(0.8, "call", func():
				_stress_game().get_player_by_slot(1).configure_ai_control(1, int(OS.get_environment("BF_BOT_LEVEL")) if OS.has_environment("BF_BOT_LEVEL") else 2)
				_hooks.append(_watch_dashes))
			for i in range(30):
				_at(2.0 + i * 2.0, "call", func():
					var g = _stress_game()
					var parts: PackedStringArray = PackedStringArray()
					for slot in [1, 2]:
						var p = g.get_player_by_slot(slot)
						parts.append("P%d %s hp=%d" % [slot, p.global_position.round(), p.health_component.health])
					print("t=%.1f %s | score %d-%d dashes=%d" % [_time, " | ".join(parts), g.get_score_for_slot(1), g.get_score_for_slot(2), _dash_count]))
			_at(3.0, "call", func():
				var research = root.get_node("ResearchManager")
				for slot in [1, 2]:
					var p = _stress_game().get_player_by_slot(slot)
					print("BOTDASH slot=%d mark=%d can_dash=%s grounded=%s local_slot=%d" % [slot, research.get_mark(&"dashing", slot), p.can_dash(), p.is_grounded(), root.get_node("NetworkSession").local_player_slot]))
			_at(62.0, "call", func(): print("BOTDASH total dashes=%d" % _dash_count))
			_at(62.2, "quit")
		"bot_watch":
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"progress_bot_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant")
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(0.8, "call", func(): _stress_game().get_player_by_slot(1).configure_ai_control(1, 2))
			for i in range(60):
				_at(2.0 + i * 1.5, "call", func():
					var g = _stress_game()
					var parts: PackedStringArray = PackedStringArray()
					for slot in [1, 2]:
						var p = g.get_player_by_slot(slot)
						var b = p.ai_brain
						parts.append("P%d %s hp=%d tgt=%s goal=%s vis=%.1f clear=%s" % [slot, p.global_position.round(), p.health_component.health, b._target != null, str(b._goal_point), b._visible_time, b._solution_direction != Vector2.ZERO])
					print("t=%.1f wind=%.0f vis=%.2f | %s | score %d-%d" % [_time, WorldConditions.wind.x, WorldConditions.visibility, " | ".join(parts), g.get_score_for_slot(1), g.get_score_for_slot(2)]))
			_at(92.0, "quit")
		"bot_spawn_look":
			# Two hard bots; the camera stays on the left spawn, where bot 1 used to bounce for seconds.
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"progress_bot_world", "verdant")
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(0.8, "call", func(): _stress_game().get_player_by_slot(1).configure_ai_control(1, 2))
			_at(1.0, "call", func(): _freeze_camera_keep_players(Vector2(330, 470), 1.6))
			for i in range(80):
				_at(1.5 + i * 0.5, "shot", "spawn_%02d" % i)
				_at(1.5 + i * 0.5, "call", func():
					var p = _stress_game().get_player_by_slot(1)
					print("t=%.1f P1 %s v=%s floor=%s goal=%s" % [_time, p.global_position.round(), p.velocity.round(), p.is_on_floor(), str(p.ai_brain._goal_point)]))
			_at(41.5, "quit")
		"gunfeel":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func(): _equip(["shotgun_mk1"]))
			_at(1.6, "mouse", Vector2(900, 470))
			_at(2.0, "press", "p1_shoot")
			_at(2.02, "release", "p1_shoot")
			for i in range(6):
				_at(2.03 + i * 0.05, "shot", "sg_%02d" % i)
			_at(1.9, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("ATTR ", gun._extension_stats.attributes)
				print("DIRS ", gun._build_shot_directions(Vector2.RIGHT))
				_stress_game().get_projectiles_root().child_entered_tree.connect(func(n):
					n.despawn_requested.connect(func(pr, reason, col): print("DESPAWN t=%.3f %s at %s collider=%s" % [_time, reason, pr.global_position.round(), col]))))
			_at(2.08, "call", func():
				var pr = _stress_game().get_projectiles_root()
				var desc: PackedStringArray = PackedStringArray()
				for c in pr.get_children():
					desc.append(str(c.global_position.round()))
				print("PELLETS ", pr.get_child_count(), " ", " ".join(desc)))
			_at(3.0, "call", func(): _equip(["sniper_barrel_mk1"]))
			_at(3.5, "press", "p1_shoot")
			_at(3.52, "release", "p1_shoot")
			for i in range(4):
				_at(3.53 + i * 0.05, "shot", "sn_%02d" % i)
			_at(4.5, "quit")
		"mars_duel_look":
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"progress_bot_world", "mars")
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(0.8, "call", func(): _stress_game().get_player_by_slot(1).configure_ai_control(1, 2))
			_at(5.0, "call", func(): _weather().skip_to_storm(false, -1.0, true))
			_at(26.0, "call", func(): _weather().skip_to_storm(true, 1.0, false))
			for i in range(22):
				_at(4.0 + i * 1.6, "shot", "d_%02d" % i)
			_at(40.0, "quit")
		"mars_close":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func(): _weather().skip_to_storm(false, 1.0, false))
			_at(5.0, "call", func(): _place_p1(Vector2(180, 380)))
			_at(5.5, "call", func(): _freeze_camera_keep_players(Vector2(240, 360), 2.0))
			_at(5.6, "call", func(): Input.action_press("p1_move_left"))
			_at(6.2, "shot", "close_against")
			_at(6.3, "call", func(): Input.action_release("p1_move_left"))
			_at(6.9, "shot", "close_idle")
			_at(7.0, "call", func(): _place_p1(Vector2(905, 640)); _freeze_camera_keep_players(Vector2(905, 600), 2.0))
			_at(7.8, "shot", "close_shelter")
			_at(8.0, "call", func(): _freeze_camera_keep_players(Vector2(560, 540), 2.4))
			_at(8.4, "shot", "close_pennant")
			_at(8.5, "quit")
		"ledge_test":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.3, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func(): _weather().skip_to_storm(true, 1.0, false))
			_at(4.0, "call", func(): _place_p1(Vector2(400, 480)))
			for i in range(8):
				_at(4.5 + i * 0.6, "call", func():
					var p1 = _stress_game().get_player_by_slot(1)
					print("LEDGE t=%.1f x=%.0f y=%.0f wind=%.0f grounded=%s hp=%d" % [_time, p1.global_position.x, p1.global_position.y, WorldConditions.wind.x, p1.is_grounded(), p1.health_component.health]))
			_at(9.5, "quit")
		"airdrop_look":
			_at(0.1, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true)
				root.get_node("UserSettings").set_value(&"progress_bot_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant")
				_main._on_bot_requested(0))
			_at(3.0, "call", func():
				var g = _stress_game()
				for slot in [1, 2]:
					g.get_player_by_slot(slot).set_controls_enabled(false)
				var m = g.get_node("Arena/AirdropManager")
				m._target_position = m._choose_target_position()
				print("AIRDROP target ", m._target_position, " marker ", m._choose_marker_position())
				m._descent_progress = 0.0
				m._set_phase(&"warning")
				m._send_state(true))
			for i in range(6):
				_at(5.5 + i * 0.9, "shot", "drop_%02d" % i)
			_at(5.5 + 6 * 0.9, "call", func():
				var g = _stress_game()
				var m = g.get_node("Arena/AirdropManager")
				var c = m._airdrop
				print("CRATE phase ", m._phase, " pos ", c.global_position if c != null else null))
			_at(11.5, "quit")
		"summary_look":
			_at(0.5, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(2.0, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(0))
			_at(3.0, "shot", "summary")
			_at(3.2, "quit")
		"research_look":
			_at(0.5, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(2.0, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(1))
			_at(3.0, "shot", "research")
			_at(3.05, "call", func(): _viewport.find_children("*", "ResearchPage", true, false)[0]._select(&"time_control"))
			_at(3.15, "shot", "research_time_control")
			_at(3.2, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(-1))
			_at(4.2, "shot", "inter_loadout")
			_at(4.5, "quit")
		"research_movement":
			# The research page's Movement lane: Dashing selected fresh (four marks in the dock), then at Mk II.
			_at(0.5, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(2.0, "call", func(): _main.get_node("SceneRoot").get_child(-1)._set_page(1))
			_at(2.3, "call", func(): _main.get_node("SceneRoot").get_child(-1).get("_research_page")._select(&"dashing"))
			_at(3.0, "shot", "research_dash")
			_at(3.1, "call", func():
				var research = root.get_node("ResearchManager")
				research.research_points = 30
				research._local_marks["dashing"] = 2
				research.research_changed.emit()
				research.research_points_changed.emit(30)
				_main.get_node("SceneRoot").get_child(-1).get("_research_page")._select(&"dashing"))
			_at(3.8, "shot", "research_dash_mk2")
			_at(3.9, "call", func(): _main.get_node("SceneRoot").get_child(-1).get("_research_page")._select(&"wall_jumps"))
			_at(4.4, "shot", "research_wall_jumps")
			_at(4.6, "quit")
		"aim_stability":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func(): _equip(["shotgun_mk1"]))
			_at(2.0, "mouse", Vector2(1000, 300))
			_at(2.5, "call", func(): _aim_samples.clear(); _aim_sampling = true)
			for i in range(4):
				_at(2.6 + i * 0.8, "press", "p1_shoot")
				_at(2.62 + i * 0.8, "release", "p1_shoot")
			_at(5.8, "call", func():
				_aim_sampling = false
				var lo: Vector2 = Vector2(INF, INF)
				var hi: Vector2 = Vector2(-INF, -INF)
				for v in _aim_samples:
					lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
					hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
				print("AIM samples=%d spread x=%.1f y=%.1f" % [_aim_samples.size(), hi.x - lo.x, hi.y - lo.y]))
			_at(6.0, "quit")
		"sell_test":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true); root.get_node("UserSettings").set_value(&"progress_bot_world", "verdant"))
			_at(0.3, "call", func(): _main._on_bot_requested(1))
			_at(2.0, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(3.0, "call", func():
				root.get_node("ExtensionInventory").add_all_definitions_for_local()
				root.get_node("ArmorInventory").add_all_definitions_for_local()
				root.get_node("RoundRewardInventory").prepare_for_round(7)
				_main.get_node("SceneRoot").get_child(-1)._set_page(-1)
				_sell_log("start"))
			_at(3.6, "call", func(): _lo_mouse_to_tile("heavy_barrel_mk1", Vector2.ZERO))
			_at(3.8, "call", func(): _lo_press(true))
			_at(3.85, "call", func(): _lo_mouse_to_tile("heavy_barrel_mk1", Vector2(14, 10)))
			_at(3.9, "call", func(): _lo_mouse_to(_recycler_center() + Vector2(-60, -40)))
			_at(4.1, "shot", "sell_drag_near")
			_at(4.15, "call", func(): _lo_mouse_to(_recycler_center()))
			_at(4.35, "shot", "sell_drag_over")
			_at(4.4, "call", func(): _lo_press(false))
			_at(4.6, "call", func(): _sell_log("after selling heavy barrel"))
			_at(4.65, "shot", "sell_done")
			_at(4.8, "call", func(): _lo_mouse_to(_offer_center()))
			_at(5.0, "call", func(): _lo_press(true))
			_at(5.05, "call", func(): _lo_mouse_to(_offer_center() + Vector2(10, 10)))
			_at(5.1, "call", func(): _lo_mouse_to(_recycler_center()))
			_at(5.3, "shot", "offer_drag_blocked")
			_at(5.35, "call", func(): _lo_press(false))
			_at(5.5, "call", func(): _sell_log("after offer without research"))
			_at(5.6, "call", func(): root.get_node("ResearchManager")._local_marks[&"recycling"] = 1; _sell_log("research set"))
			_at(5.7, "call", func(): _lo_mouse_to(_offer_center()))
			_at(5.9, "call", func(): _lo_press(true))
			_at(5.95, "call", func(): _lo_mouse_to(_offer_center() + Vector2(10, 10)))
			_at(6.0, "call", func(): _lo_mouse_to(_recycler_center()))
			_at(6.2, "shot", "offer_drag_ok")
			_at(6.25, "call", func(): _lo_press(false))
			_at(6.45, "call", func(): _sell_log("after offer with research"))
			_at(6.6, "quit")
		"sell_equipped":
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true))
			_at(0.3, "call", func(): _main._on_bot_requested(1))
			_at(2.0, "call", func():
				var inv = root.get_node("ExtensionInventory")
				var rri = root.get_node("RoundRewardInventory")
				var arm = root.get_node("ArmorInventory")
				inv.add_all_definitions_for_local()
				arm.add_all_definitions_for_local()
				var item = null
				for it in inv.get_inventory_for_local():
					if str(it.get_definition_id()) == "sniper_barrel_mk1":
						item = it
				inv.equip_item_for_local(item)
				print("EQ before: ", inv.get_equipped_item_for_local(&"front") != null, " coins=", root.get_node("OnlineMatch").get_local_coin_balance(), " inv=", inv.get_inventory_for_local().size())
				var refund: int = rri.sell_item(item)
				print("EQ after: refund=", refund, " equipped=", inv.get_equipped_item_for_local(&"front"), " coins=", root.get_node("OnlineMatch").get_local_coin_balance(), " inv=", inv.get_inventory_for_local().size(), " still_owned=", inv.get_inventory_for_local().has(item))
				var armor = arm.inventory[0]
				arm.equip_item(armor)
				var cat = armor.category
				var r2: int = rri.sell_item(armor)
				print("ARMOR sold refund=", r2, " equipped=", arm.get_equipped_item(cat), " owned=", arm.inventory.has(armor)))
			_at(2.5, "quit")
		"explosive":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func(): _equip(["explosive_bullet_mk1"]))
			_at(1.6, "mouse", Vector2(470, 470))
			_at(2.0, "press", "p1_shoot")
			_at(2.05, "release", "p1_shoot")
			for i in range(8):
				_at(2.15 + i * 0.05, "shot", "explo_%02d" % i)
			_at(3.0, "call", func(): _equip(["grenades_mk1"]))
			_at(3.6, "press", "p1_shoot")
			_at(3.65, "release", "p1_shoot")
			for i in range(10):
				_at(3.8 + i * 0.1, "shot", "gren_%02d" % i)
			_at(5.0, "quit")
		"time_probe":
			# Time Control Mk I in a bot duel: P2 is driven by the p2 keys so its run speed can be measured, P1
			# casts with the real key. Measures run and projectile speed before, during and after the slow,
			# and checks the refusals (round intro, cooldown). Prints TIME_PROBE lines and PASS/FAIL checks.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_bot_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant"))
			_at(0.3, "call", func():
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(1.0, "call", func():
				root.get_node("ResearchManager")._local_marks["time_control"] = 1
				var g = _stress_game()
				var p2 = g.get_player_by_slot(2)
				p2.configure_local_control(2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", &"p2_block", false)
				p2.time_control_action = &"")
			_at(1.2, "key_down", "p1_time_control")
			_at(1.3, "key_up", "p1_time_control")
			_at(1.4, "call", func(): _tp_check("cast refused during intro", not TimeFlow.active and _stress_game().get_player_by_slot(1).get_time_control_cooldown_left() == 0.0))
			# Baseline (t 4-5), slowed (t 6.2-7), restored (t 9.8-10.6).
			for phase in [["normal", 4.0], ["slowed", 6.2], ["after", 9.8]]:
				var tag: String = phase[0]
				var t0: float = phase[1]
				_at(t0, "call", func(): _tp_reset_positions())
				_at(t0 + 0.1, "press", "p2_move_left")
				_at(t0 + 0.1, "press", "p1_move_right")
				_at(t0 + 0.1, "call", func():
					_tp_spawn_round(2, Vector2(-200, -140), tag + "_p2round")
					_tp_spawn_round(1, Vector2(-200, -200), tag + "_p1round"))
				_at(t0 + 0.3, "call", func(): _tp_mark(tag))
				_at(t0 + 0.5, "call", func(): _tp_measure(tag))
				_at(t0 + 0.55, "release", "p2_move_left")
				_at(t0 + 0.55, "release", "p1_move_right")
			_at(5.8, "key_down", "p1_time_control")
			_at(5.95, "key_up", "p1_time_control")
			_at(6.05, "call", func():
				var g = _stress_game()
				_tp_check("cast went through", TimeFlow.active and g.get_player_by_slot(1).get_time_control_cooldown_left() > 30.0)
				_tp_check("caster keeps normal time", g.get_player_by_slot(1).time_scale == 1.0))
			_at(6.12, "shot", "time_0_cast")
			_at(6.5, "shot", "time_1_slowed")
			_at(7.4, "shot", "time_2_slowed")
			_at(7.1, "key_down", "p1_time_control")
			_at(7.25, "key_up", "p1_time_control")
			_at(7.35, "call", func():
				var left: float = _stress_game().get_player_by_slot(1).get_time_control_cooldown_left()
				_tp_check("recast refused on cooldown (%.1f s left)" % left, left < 34.0 and left > 30.0))
			_at(8.7, "shot", "time_3_late")
			_at(9.25, "shot", "time_4_release")
			_at(9.6, "call", func(): _tp_check("slow wore off", not TimeFlow.active and _stress_game().get_player_by_slot(2).time_scale == 1.0))
			# The other way round: the opponent casts, the local player is the slowed one (full-screen grade).
			_at(10.7, "call", func():
				root.get_node("ResearchManager")._remote_marks_by_player[2] = {"time_control": 1}
				var g = _stress_game()
				_tp_check("opponent's cast slows the local player", g.request_time_control(g.get_player_by_slot(2)) and g.get_player_by_slot(1).is_time_slowed()))
			_at(11.4, "shot", "time_5_self_slowed")
			_at(11.5, "call", func(): _tp_report())
			_at(11.6, "quit")
		"time_freeze":
			# Time Control Mk III: the opponent and their rounds stop dead for 1.5 s, then run slow. Checks the
			# hang, the blocked inputs, the damage cap (35% of max health, never the last point) and that nobody
			# casts while the kill banner is up.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_bot_world", "verdant"))
			_at(0.3, "call", func():
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(1.0, "call", func():
				root.get_node("ResearchManager")._local_marks["time_control"] = 3
				var p2 = _stress_game().get_player_by_slot(2)
				p2.configure_local_control(2, &"p2_move_left", &"p2_move_right", &"p2_jump", &"p2_shoot", &"p2_block", false)
				p2.time_control_action = &"")
			_at(4.0, "call", func(): _tp_reset_positions())
			_at(4.1, "call", func(): _tp_spawn_round(2, Vector2(-200, -140), "freeze_p2round"))
			_at(4.3, "key_down", "p1_time_control")
			_at(4.45, "key_up", "p1_time_control")
			_at(4.5, "press", "p2_move_left")
			_at(4.6, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				_tp_check("Mk III freezes the opponent", p2.is_time_frozen())
				_tp_marks["freeze"] = {"round": _tp_rounds["freeze_p2round"].global_position, "p2": p2.global_position})
			_at(4.7, "shot", "freeze_0")
			_at(4.8, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				for i in range(3):
					p2.apply_incoming_damage(40, 1, p2.global_position + Vector2(-60, 0))
				_tp_check("frozen player loses at most 35%% (health %d)" % p2.health_component.health, p2.health_component.health == 65))
			_at(5.5, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				var m: Dictionary = _tp_marks["freeze"]
				var round_moved: float = (_tp_rounds["freeze_p2round"].global_position - (m["round"] as Vector2)).length()
				var p2_moved: float = (p2.global_position - (m["p2"] as Vector2)).length()
				print("TIME_PROBE frozen 0.9 s: round moved %.2f px, P2 moved %.2f px" % [round_moved, p2_moved])
				_tp_check("frozen round hangs in the air", round_moved < 0.5)
				_tp_check("frozen player cannot move", p2_moved < 0.5))
			_at(5.55, "release", "p2_move_left")
			_at(5.6, "shot", "freeze_1")
			_at(6.3, "call", func():
				var p2 = _stress_game().get_player_by_slot(2)
				_tp_check("freeze ends into the slow", not p2.is_time_frozen() and p2.is_time_slowed())
				_tp_marks["thaw"] = _tp_rounds["freeze_p2round"].global_position.x)
			_at(6.5, "call", func():
				var speed: float = (_tp_rounds["freeze_p2round"].global_position.x - float(_tp_marks["thaw"])) / 0.2
				_tp_check("round flies on slowed after the freeze (%.0f px/s)" % speed, absf(speed - 315.0) < 25.0))
			_at(6.55, "shot", "freeze_2")
			# The last point: a fresh freeze on a nearly dead player.
			_at(10.5, "call", func():
				var g = _stress_game()
				var p1 = g.get_player_by_slot(1)
				var p2 = g.get_player_by_slot(2)
				p1._time_control_cooldown = 0.0
				p2.health_component.health = 10
				_tp_check("second cast", g.request_time_control(p1))
				p2.apply_incoming_damage(60, 1, p2.global_position)
				_tp_check("a freeze never takes the last point (health %d)" % p2.health_component.health, p2.health_component.health == 1 and not p2.is_eliminated()))
			_at(12.5, "call", func():
				var g = _stress_game()
				var p1 = g.get_player_by_slot(1)
				var p2 = g.get_player_by_slot(2)
				_tp_check("cap lifts when the freeze ends", p2.health_component.damage_floor == 0)
				p2.apply_incoming_damage(60, 1, p2.global_position)
				p1._time_control_cooldown = 0.0
				_tp_check("no cast while the kill banner is up", p2.is_eliminated() and not g.request_time_control(p1)))
			_at(12.7, "call", func(): _tp_report())
			_at(12.8, "quit")
		"time_bot":
			# Hard bot with Time Control Mk III: it casts when it is low and the player is reloading, and backs
			# off when the player slows it.
			_at(0.1, "call", func():
				root.get_node("UserSettings").set_value(&"progress_bot_world", "verdant")
				root.get_node("UserSettings").set_value(&"gameplay_bot_difficulty", 2))
			_at(0.3, "call", func():
				root.get_node("NetworkSession").start_bot_duel()
				_main.start_game())
			_at(3.5, "call", func():
				var g = _stress_game()
				_tp_check("hard bot has Time Control Mk III", root.get_node("ResearchManager").get_time_control_mark(2) == 3)
				_tp_reset_positions()
				g.get_player_by_slot(2).health_component.health = 30
				g.get_player_by_slot(1).get_gun()._start_reload())
			for i in range(123):
				_at(3.6 + i * 0.1, "call", func():
					var g = _stress_game()
					var p1 = g.get_player_by_slot(1)
					var p2 = g.get_player_by_slot(2)
					# Keep the fight going: the probe is about the decision, not who wins.
					p1.health_component.health = p1.health_component.max_health
					if i < 80:
						p2.health_component.health = 30
					if i % 10 == 0 and i < 80:
						print("TIME_PROBE bot t=%.1f vis=%.2f reloading=%s intro=%s elim=%s/%s can_cast=%s" % [_time, p2.ai_brain._visible_time, p1.get_gun().is_reloading(), g.is_round_intro_running(), p1.is_eliminated(), p2.is_eliminated(), p2.can_cast_time_control()])
					if not _tp_marks.has("bot_cast") and p1.is_time_slowed():
						_tp_marks["bot_cast"] = _time
						print("TIME_PROBE bot cast after %.1f s" % (_time - 3.5)))
			_at(11.5, "call", func(): _tp_check("low bot casts once it sees the player", _tp_marks.has("bot_cast")))
			_at(14.0, "call", func():
				var g = _stress_game()
				root.get_node("ResearchManager")._local_marks["time_control"] = 1
				var p1 = g.get_player_by_slot(1)
				var p2 = g.get_player_by_slot(2)
				p1.health_component.health = p1.health_component.max_health
				p2.health_component.health = p2.health_component.max_health
				p1._time_control_cooldown = 0.0
				p1._clear_time_slow()
				p2._clear_time_slow()
				p2._time_control_cooldown = 99.0
				_tp_reset_positions()
				# On the right-hand flat, with about 95 px of floor behind the bot to back off over.
				p2.global_position.x -= 80.0
				_tp_marks["gap"] = absf(p2.global_position.x - p1.global_position.x)
				_tp_check("player slows the bot", g.request_time_control(p1)))
			_at(15.8, "call", func():
				var g = _stress_game()
				var gap: float = absf(g.get_player_by_slot(2).global_position.x - g.get_player_by_slot(1).global_position.x)
				print("TIME_PROBE slowed bot gap %.0f -> %.0f px" % [float(_tp_marks["gap"]), gap])
				_tp_check("slowed bot backs off", gap > float(_tp_marks["gap"]) + 25.0))
			_at(15.9, "call", func(): _tp_report())
			_at(16.0, "quit")
		"time_sandbox":
			# Time Control in the sandbox: free to try, slows every dummy, nobody else.
			_at(0.1, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(900, 400))
			_at(1.4, "key_down", "p1_time_control")
			_at(1.55, "key_up", "p1_time_control")
			_at(1.6, "press", "p1_shoot")
			_at(1.75, "release", "p1_shoot")
			_at(1.8, "call", func():
				var g = _stress_game()
				var slowed: int = 0
				var dummies: int = 0
				for node in g.get_tree().get_nodes_in_group(&"players"):
					if node.player_slot == 1:
						_tp_check("sandbox caster keeps normal time", node.time_scale == 1.0)
					else:
						dummies += 1
						if node.time_scale < 1.0:
							slowed += 1
				_tp_check("sandbox slows every dummy (%d/%d)" % [slowed, dummies], dummies > 0 and slowed == dummies))
			_at(1.9, "shot", "time_sandbox_0")
			_at(2.6, "shot", "time_sandbox_1")
			_at(5.0, "call", func(): _tp_check("sandbox slow wore off", not TimeFlow.active))
			_at(5.1, "call", func(): _tp_report())
			_at(5.2, "quit")
		"online_ui":
			_at(0.5, "call", func(): _main._show_locker_room())
			_at(2.0, "shot", "locker")
			_at(2.2, "call", func(): _main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(3.5, "shot", "intermission")
			_at(3.6, "quit")
		"terrain":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): _freeze_camera(Vector2(1140, 400), 0.56))
			_at(2.4, "shot", "terrain_overview")
			var spots: Array = [Vector2(600, 560), Vector2(1000, 590), Vector2(1270, 590), Vector2(1700, 590), Vector2(140, 560), Vector2(2140, 560), Vector2(764, 470), Vector2(1140, 300), Vector2(1140, 680), Vector2(975, 400), Vector2(1516, 330)]
			for i in range(spots.size()):
				var spot: Vector2 = spots[i]
				_at(2.6 + i * 0.3, "call", func(): _freeze_camera(spot, 3.0))
				_at(2.8 + i * 0.3, "shot", "terrain_%02d" % i)
			_at(2.8 + spots.size() * 0.3 + 0.2, "quit")
		"loadout2":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(2.3, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_loadout_pressed())
			_at(2.4, "mouse", Vector2(640, 700))
			_at(3.4, "shot", "loadout_sandbox")
			_at(3.5, "call", func(): _equip(["laser_scope_mk1", "poison_rounds_mk1", "heavy_barrel_mk1"]))
			_at(3.9, "shot", "loadout_equipped")
			_at(4.0, "quit")
		"merge_look":
			# The merge band in the sandbox loadout: first without coins (inspector says why), then with.
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(2.3, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_loadout_pressed())
			_at(3.0, "call", func():
				var inv = root.get_node("ExtensionInventory")
				var first = null
				for item in inv.get_inventory_for_player(1):
					if str(item.get_definition_id()) == "heavy_barrel_mk1" and item.mark == 1:
						first = item
				var twin = WeaponExtensionItem.create(first.definition, 64.0, 1)
				inv.add_item_for_player(1, twin)
				_merge_pair = [first, twin]
				root.get_node("OnlineMatch").coin_balances[1] = 0)
			_at(3.4, "call", func(): _loadout_page()._on_merge_requested(_merge_pair[0], _merge_pair[1]))
			_at(3.9, "shot", "merge_no_coins")
			_at(4.0, "call", func():
				root.get_node("OnlineMatch").coin_balances[1] = 99
				_loadout_page()._on_merge_requested(_merge_pair[0], _merge_pair[1]))
			_at(4.6, "shot", "merge_band")
			_at(4.65, "call", func(): _log_focus("merge"))
			_at(4.7, "call", func(): _loadout_page()._merge_dialog.confirm())
			_at(5.6, "shot", "merge_done")
			_at(5.7, "quit")
		"loadout_inter":
			_at(0.3, "call", func():
				root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", true)
				_main._on_bot_requested(1))
			_at(2.0, "call", func():
				var om = root.get_node("OnlineMatch")
				om.coin_balances[1] = 40
				_main.change_scene(_main.get_scene("res://scenes/menus/intermission_menu.tscn")))
			_at(4.5, "shot", "inter_summary")
			_at(4.6, "call", func(): _main.get_node("SceneRoot").get_child(-1).call("_set_page", -1))
			_at(5.4, "shot", "inter_loadout")
			_at(5.5, "quit")
		"armor_art":
			_at(0.3, "call", func(): _main.queue_free())
			_at(0.5, "call", func():
				var canvas: Control = Control.new()
				canvas.size = Vector2(1280, 720)
				_viewport.add_child(canvas)
				var armor = load("res://scenes/items/armor/armor_art.gd")
				var ids: Array = ["training_shield", "frosty_shield", "healing_shield", "pull_shield", "tactical_reload_shield", "scout_vest", "light_kevlar_vest", "arctic_jacket", "delayed_armor", "reflective_armor", "stationary_armor", "light_boots", "jump_boots", "adrenaline_boots", "chasing_boots", "escape_boots"]
				canvas.draw.connect(func():
					canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.07, 0.1, 0.11))
					for i in range(ids.size()):
						for mark in [1, 3]:
							var rect: Rect2 = Rect2(Vector2(20 + (i % 8) * 156, 20 + (i / 8) * 340 + (mark - 1) * 80), Vector2(140, 150))
							armor.draw_icon(canvas, rect, StringName(ids[i]), mark, {"team": Color(0.32, 0.67, 1.0), "flash": 0.3 if mark == 3 and i % 3 == 0 else 0.0, "desaturate": 0.5 if i % 4 == 1 else 0.0}))
				canvas.queue_redraw())
			_at(1.2, "shot", "armor_sheet")
			_at(1.3, "quit")
		"art":
			_at(0.3, "call", func(): _main.queue_free())
			_at(0.5, "call", func(): _build_art_sheet())
			_at(1.2, "shot", "art_sheet")
			_at(1.3, "quit")
		"lo_interact":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(2.3, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_loadout_pressed())
			_at(2.32, "shot", "open_a")
			_at(2.45, "shot", "open_b")
			_at(3.2, "call", func(): _lo_mouse_to_tile("standard_scope_mk1", Vector2.ZERO))
			_at(3.6, "shot", "hover_scope")
			_at(3.7, "call", func(): _lo_press(true))
			_at(3.75, "call", func(): _lo_mouse_to_tile("standard_scope_mk1", Vector2(12, -8)))
			_at(3.8, "call", func(): _lo_mouse_to_tile("standard_scope_mk1", Vector2(40, -30)))
			_at(3.9, "call", func(): _lo_mouse_to(Vector2(330, 260)))
			_at(4.1, "shot", "drag_mid")
			_at(4.2, "call", func(): _lo_mouse_to(Vector2(250, 160)))
			_at(4.45, "shot", "drag_over_gun")
			_at(4.5, "call", func(): _lo_press(false))
			_at(4.56, "shot", "drop_snap_a")
			_at(4.7, "shot", "drop_snap_b")
			_at(5.2, "shot", "after_drop")
			_at(5.3, "call", func(): _lo_mouse_to_tile("arctic_jacket_mk1", Vector2.ZERO))
			_at(5.5, "shot", "hover_armor")
			_at(5.55, "call", func(): _lo_press(true))
			_at(5.6, "call", func(): _lo_mouse_to_tile("arctic_jacket_mk1", Vector2(-20, -20)))
			_at(5.7, "call", func(): _lo_mouse_to(Vector2(1010, 150)))
			_at(5.95, "shot", "drag_armor")
			_at(6.0, "call", func(): _lo_press(false))
			_at(6.12, "shot", "armor_snap")
			_at(6.8, "shot", "armor_done")
			_at(6.9, "quit")
		"mars":
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(820, 400))
			_at(3.0, "shot", "mars_game")
			_at(3.2, "call", func(): _freeze_camera(Vector2(1080, 400), 0.59))
			_at(3.5, "shot", "mars_overview")
			var mars_spots: Array = [Vector2(300, 470), Vector2(800, 600), Vector2(1080, 520), Vector2(1080, 300), Vector2(1800, 470)]
			for i in range(mars_spots.size()):
				var spot: Vector2 = mars_spots[i]
				_at(3.7 + i * 0.4, "call", func(): _freeze_camera(spot, 2.2))
				_at(3.95 + i * 0.4, "shot", "mars_close_%d" % i)
			_at(6.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(6.3, "quit")
		"mars_play":
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "mars"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.5, "call", func():
				var g = get_first_node_in_group(&"game_world")
				var p1 = g.get_player_by_slot(1)
				p1.global_position = g.get_node("Arena/Geyser1").global_position + Vector2(0, -24)
				p1.velocity = Vector2.ZERO
				print("GRAVITY scale=", WorldConditions.gravity_scale, " proj=", WorldConditions.projectile_gravity_scale))
			for i in range(40):
				_at(2.6 + i * 0.2, "call", func():
					var g = get_first_node_in_group(&"game_world")
					var geyser = g.get_node("Arena/Geyser1")
					print("t=%.1f p1=%s phase=%d wind=%s" % [_time, g.get_player_by_slot(1).global_position.round(), geyser._phase, WorldConditions.wind.round()]))
			_at(3.0, "call", func(): get_first_node_in_group(&"game_world").get_node("Arena/Weather").skip_to_storm(false, 1.0, false))
			_at(3.4, "shot", "mars_warn")
			_at(6.2, "shot", "mars_gust")
			_at(6.0, "mouse", Vector2(1200, 300))
			_at(6.1, "press", "p1_shoot")
			_at(6.15, "release", "p1_shoot")
			_at(6.45, "shot", "mars_gust_shot")
			_at(6.5, "call", func():
				var w = get_first_node_in_group(&"game_world").get_node("Arena/Weather")
				print("WEATHER phase=", w._phase, " storm=", w._storm, " emitting=", w._streaks.emitting, " vis=", w._streaks.is_visible_in_tree(), " veil=", w._veil.visible, " gpos=", w._streaks.global_position, " z=", w.z_index))
			_at(7.4, "shot", "mars_gust_peak")
			_at(8.2, "shot", "mars_gust_late")
			_at(10.6, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(10.7, "quit")
		"world_switch":
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "call", func(): _equip(["sniper_barrel_mk1", "poison_rounds_mk1"]))
			_at(2.2, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(2.6, "shot", "pause_world")
			_at(2.7, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_world_pressed(&"mars"))
			_at(4.5, "call", func():
				var g = get_first_node_in_group(&"game_world")
				print("SWITCH arena=", g.get_node("Arena").name if g != null else "none", " children0=", g.get_child(0).name, " paused=", paused, " equipped=", root.get_node("ExtensionInventory").get_equipped_item_for_local(&"front").get_definition_id(), " grav=", WorldConditions.gravity_scale))
			_at(4.6, "shot", "after_switch")
			_at(4.8, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu").pause_game())
			_at(5.2, "shot", "pause_world_mars")
			_at(5.3, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_world_pressed(&"verdant"))
			_at(7.2, "call", func(): print("BACK arena_bounds=", get_first_node_in_group(&"map_bounds").bounds, " grav=", WorldConditions.gravity_scale, " wind=", WorldConditions.wind))
			_at(7.3, "quit")
		"scope_check":
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.5, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("SCOPE stock ", gun.get_ballistics(), " dmg=", gun._get_modified_damage(), " interval=", gun._get_modified_fire_interval()))
			_at(1.6, "call", func(): _equip(["standard_scope_mk1"]))
			_at(1.7, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("SCOPE standard ", gun.get_ballistics(), " dmg=", gun._get_modified_damage(), " interval=", gun._get_modified_fire_interval()))
			_at(1.8, "call", func(): _equip(["laser_scope_mk1"]))
			_at(1.9, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("SCOPE laser ", gun.get_ballistics(), " dmg=", gun._get_modified_damage(), " interval=", gun._get_modified_fire_interval(), " laser=", gun._has_laser_scope))
			_at(2.0, "quit")
		"bg_look":
			_at(0.6, "shot", "menu_bg")
			_at(0.8, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(1.0, "call", func(): _main._on_sandbox_requested())
			_at(3.0, "call", func(): _freeze_camera(Vector2(1140, 300), 0.8))
			_at(3.5, "shot", "arena_bg")
			_at(3.6, "quit")
		"laser_look":
			var world_name: String = OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant"
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", world_name))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(1000, 300))
			_at(1.5, "call", func(): _equip(["laser_scope_mk1"]))
			_at(1.6, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("LASER has=", gun._has_laser_scope, " can=", gun._can_show_laser_sight(), " src=", gun._get_source_extensions()))
			_at(2.4, "call", func():
				var gun = _stress_game().get_player_by_slot(1).get_gun()
				print("LASER vis=", gun._laser_sight.is_visible_in_tree(), " pts=", gun._laser_sight.points.size(), " pos=", gun._laser_sight.global_position.round()))
			_at(2.5, "shot", "laser_up")
			_at(2.6, "mouse", Vector2(1150, 420))
			_at(3.2, "shot", "laser_flat")
			_at(3.3, "mouse", Vector2(200, 500))
			_at(3.9, "shot", "laser_left")
			_at(4.0, "quit")
		"gun_ingame":
			_at(0.2, "call", func(): root.get_node("UserSettings").set_value(&"progress_sandbox_world", "verdant"))
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(900, 330))
			_at(2.0, "call", func(): _freeze_camera_keep_players(get_first_node_in_group(&"game_world").get_player_by_slot(1).global_position + Vector2(20, -10), 3.2))
			_at(2.3, "shot", "gun_stock")
			_at(2.4, "call", func(): _equip(["sniper_barrel_mk1", "standard_scope_mk1", "poison_rounds_mk1"]))
			_at(2.7, "shot", "gun_sniper")
			_at(2.8, "call", func(): _equip(["shotgun_mk1", "laser_scope_mk1", "big_bullets_mk1"]))
			_at(3.1, "shot", "gun_shotgun")
			_at(3.2, "call", func(): _equip(["kinetic_amplifier_mk1", "reload_improver_mk1", "grenades_mk1"]))
			_at(3.5, "shot", "gun_kinetic")
			_at(3.6, "call", func(): _freeze_camera_keep_players(Vector2(640, 420), 1.0))
			_at(3.9, "shot", "gun_normal_zoom")
			_at(4.0, "quit")
		"loadout":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(2.0, "action", "pause")
			_at(2.4, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_loadout_pressed())
			_at(3.2, "shot", "loadout")
			_at(3.3, "quit")
		"pause":
			_at(1.0, "call", func(): _main.get_node("SceneRoot").get_child(0)._open_bot_panel())
			_at(1.5, "call", func(): _main.get_node("SceneRoot").get_child(0)._on_bot_start_pressed())
			_at(1.62, "shot", "transition_cover")
			_at(2.05, "shot", "transition_reveal")
			_at(6.0, "action", "pause")
			_at(6.6, "shot", "pause")
			_at(6.8, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_settings_pressed())
			_at(7.3, "shot", "pause_settings")
			_at(7.4, "quit")
		"flow":
			_at(1.0, "call", func(): _main.get_node("SceneRoot").get_child(0)._open_bot_panel())
			_at(1.5, "call", func(): _main.get_node("SceneRoot").get_child(0)._on_bot_start_pressed())
			_at(2.5, "call", func(): get_first_node_in_group(&"game_world").get_player_by_slot(1).configure_ai_control(1, 2))
			_at(6.0, "action", "pause")
			_at(6.5, "shot", "flow_pause")
			_at(6.8, "call", func(): get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._on_settings_pressed())
			_at(7.3, "shot", "flow_pause_settings")
			_at(7.5, "action", "ui_cancel")
			_at(7.8, "action", "ui_cancel")
			for i in range(30):
				_at(8.0 + i * 3.0, "call", func(): _log_state())
			_at(98.0, "shot", "flow_end")
			_at(99.0, "quit")
		"hud":
			_at(0.3, "call", func(): root.get_node("NetworkSession").start_bot_duel(); _main.start_game())
			_at(0.6, "call", func(): get_first_node_in_group(&"game_world").get_player_by_slot(1).configure_ai_control(1, 1))
			_at(0.5, "mouse", Vector2(700, 380))
			_at(0.9, "shot", "hud_intro_a")
			_at(2.0, "shot", "hud_intro_b")
			_at(3.15, "shot", "hud_fight")
			_at(5.5, "call", func():
				var g = get_first_node_in_group(&"game_world")
				print("LOCAL ", g.get_local_player().name if g.get_local_player() else "none")
				for n in get_nodes_in_group(&"players"):
					print("PL ", n.get_path(), " pos=", n.global_position, " vis=", n.visible, " elim=", n.is_eliminated(), " screen=", g.get_viewport().get_canvas_transform() * n.global_position))
			for i in range(12):
				_at(5.0 + i * 1.5, "shot", "hud_play_%02d" % i)
			_at(24.0, "quit")
		"combat":
			_at(0.5, "call", func(): _main._on_sandbox_requested())
			_at(1.0, "mouse", Vector2(440, 430))
			_at(1.5, "shot", "combat_idle")
			for i in range(3):
				var t0: float = 1.6 + i * 0.7
				_at(t0, "press", "p1_shoot")
				_at(t0 + 0.017, "shot", "combat_fire%d" % i)
				_at(t0 + 0.05, "release", "p1_shoot")
				_at(t0 + 0.12, "shot", "combat_hit%d" % i)
				_at(t0 + 0.3, "shot", "combat_after%d" % i)
			_at(4.0, "mouse", Vector2(700, 200))
			_at(4.2, "press", "p1_block")
			_at(4.25, "shot", "combat_block")
			_at(4.3, "release", "p1_block")
			_at(4.6, "quit")
		_:
			_at(0.5, "quit")


func _build_art_sheet() -> void:
	var canvas: Control = Control.new()
	canvas.size = Vector2(1280, 720)
	_viewport.add_child(canvas)
	var art = load("res://scenes/ui/loadout/weapon_art.gd")
	var configs: Array = [
		{},
		{&"front": {"id": &"sniper_barrel_mk1", "mark": 3}, &"middle": {"id": &"standard_scope_mk1", "mark": 2}, &"ammo": {"id": &"freeze_rounds_mk1", "mark": 1}},
		{&"front": {"id": &"heavy_barrel_mk1", "mark": 1}, &"middle": {"id": &"laser_scope_mk1", "mark": 1}, &"ammo": {"id": &"poison_rounds_mk1", "mark": 2}},
		{&"front": {"id": &"shotgun_mk1", "mark": 1}, &"middle": {"id": &"reload_improver_mk1", "mark": 1}, &"ammo": {"id": &"explosive_bullet_mk1", "mark": 1}},
		{&"front": {"id": &"kinetic_amplifier_mk1", "mark": 2}, &"middle": {"id": &"ground_hover_mk1", "mark": 1}, &"ammo": {"id": &"shocking_rounds_mk1", "mark": 1}},
		{&"front": {"id": &"multi_barrel_mk1", "mark": 1}, &"ammo": {"id": &"grenades_mk1", "mark": 1}},
		{&"front": {"id": &"lighter_barrel_mk1", "mark": 1}, &"ammo": {"id": &"big_bullets_mk1", "mark": 1}},
		{&"front": {"id": &"extended_barrel_mk1", "mark": 1}, &"ammo": {"id": &"drill_bullets_mk1", "mark": 1}, &"middle": {"id": &"standard_scope_mk1", "mark": 1}},
	]
	var ids: Array = ["extended_barrel_mk1", "heavy_barrel_mk1", "kinetic_amplifier_mk1", "lighter_barrel_mk1", "multi_barrel_mk1", "shotgun_mk1", "sniper_barrel_mk1", "standard_scope_mk1", "laser_scope_mk1", "reload_improver_mk1", "ground_hover_mk1", "poison_rounds_mk1", "freeze_rounds_mk1", "shocking_rounds_mk1", "explosive_bullet_mk1", "grenades_mk1", "drill_bullets_mk1", "bouncy_bullets_mk1", "big_bullets_mk1"]
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.07, 0.1, 0.11))
		for i in range(configs.size()):
			var origin: Vector2 = Vector2(250 + (i % 2) * 620, 70 + (i / 2) * 135)
			art.draw_weapon(canvas, Transform2D(0.0, Vector2(1.75, 1.75), 0.0, origin), configs[i], {"accent": Color(0.32, 0.67, 1.0)})
			art.draw_fx(canvas, Transform2D(0.0, Vector2(1.75, 1.75), 0.0, origin), configs[i], 1.3)
		for j in range(ids.size()):
			var rect: Rect2 = Rect2(Vector2(20 + j * 65, 645), Vector2(58, 58))
			canvas.draw_rect(rect, Color(0.12, 0.16, 0.17))
			art.draw_part_icon(canvas, rect.grow(-6), StringName(ids[j]), {"mark": 2}))
	canvas.queue_redraw()


var _lo_mouse_pos: Vector2 = Vector2.ZERO


func _lo_find_tile(id: String) -> Control:
	for node in _viewport.find_children("*", "LoadoutItemTile", true, false):
		var tile = node
		if tile.visible and tile.item != null:
			var item_id: String = str(tile.item.get_definition_id()) if tile.item is WeaponExtensionItem else str(tile.item.item_id)
			if item_id == id:
				return tile
	return null


func _lo_mouse_to_tile(id: String, offset: Vector2) -> void:
	var tile: Control = _lo_find_tile(id)
	if tile == null:
		print("TILE NOT FOUND ", id)
		return
	_lo_mouse_to(tile.get_global_rect().get_center() + offset)


func _lo_mouse_to(pos: Vector2) -> void:
	var steps: int = 4
	var start: Vector2 = _lo_mouse_pos
	for i in range(1, steps + 1):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = start.lerp(pos, float(i) / steps)
		motion.global_position = motion.position
		motion.relative = (pos - start) / steps
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _lo_down else 0
		_viewport.push_input(motion, true)
	_lo_mouse_pos = pos


var _lo_down: bool = false


func _lo_press(down: bool) -> void:
	_lo_down = down
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = down
	button.position = _lo_mouse_pos
	button.global_position = _lo_mouse_pos
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_viewport.push_input(button, true)


func _freeze_camera_keep_players(at: Vector2, zoom_level: float) -> void:
	var g = get_first_node_in_group(&"game_world")
	var cam: Camera2D = g.get_node("Camera2D")
	cam.set_process(false)
	cam.zoom = Vector2.ONE * zoom_level
	cam.global_position = at
	cam.offset = Vector2.ZERO


func _freeze_camera(at: Vector2, zoom_level: float) -> void:
	var g = get_first_node_in_group(&"game_world")
	var cam: Camera2D = g.get_node("Camera2D")
	cam.set_process(false)
	cam.zoom = Vector2.ONE * zoom_level
	cam.global_position = at
	cam.offset = Vector2.ZERO
	for p in g.get_tree().get_nodes_in_group(&"players"):
		p.visible = false
	var hud = g.get_node_or_null("HUD")
	if hud != null:
		hud.visible = false


func _equip(ids: Array) -> void:
	var inv = root.get_node("ExtensionInventory")
	for item in inv.get_inventory_for_player(1).duplicate():
		if ids.has(str(item.get_definition_id())):
			inv.equip_item_for_player(1, item)
			print("equipped ", item.get_definition_id())


var _tracker = null
var _merge_pair: Array = []


func _push_pad_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		_viewport.push_input(event)


func _log_focus(label: String) -> void:
	var owner: Control = _viewport.gui_get_focus_owner()
	var text: String = "none"
	if owner != null:
		var label_text: String = str(owner.get("text")) if owner.get("text") != null else ""
		if owner.get("research_id") != null:
			label_text = str(owner.get("research_id"))
		elif owner.get("item") != null:
			label_text = str(owner.get("item").get("item_id") if owner.get("item").get("item_id") != null else owner.get("item").call("get_definition_id"))
		text = "%s '%s' in %s" % [owner.get_class(), label_text, owner.get_parent().name]
	print("FOCUS %-10s -> %s" % [label, text])


func _loadout_page() -> Node:
	return get_first_node_in_group(&"game_world").get_node("HUD/PauseMenu")._loadout_instance
var _last_tick: int = 0


func _botshop_tick() -> void:
	var om = root.get_node("OnlineMatch")
	var g = get_first_node_in_group(&"game_world")
	if om.phase == &"intermission":
		var ext = root.get_node("ExtensionInventory").get_equipped_for_player(2)
		var names: Array = []
		for k in ext.keys():
			if ext[k] != null:
				names.append(str(ext[k].get_definition_id()))
		var arm: Array = []
		for c in [&"boots", &"vest", &"shield"]:
			var it = root.get_node("ArmorInventory").get_equipped_item_for_player(2, c)
			if it != null:
				arm.append(str(it.item_id))
		print("INTER bot ext=%s armor=%s coins=%s scene=%s" % [names, arm, om.coin_balances, _main.get_node("SceneRoot").get_child(-1).name])
		om.set_local_intermission_ready(true)
		return
	if g != null and g.get_player_by_slot(1) != null and g.get_player_by_slot(1).control_mode != &"ai":
		g.get_player_by_slot(1).configure_ai_control(1, 2)
	if g != null:
		var p1 = g.get_player_by_slot(1)
		var p2 = g.get_player_by_slot(2)
		print("t=%.0f phase=%s hp=%d/%d sets=%s kills=%s" % [_time, om.phase, p1.health_component.health, p2.health_component.health, om.match_points, om.set_kills])


var _tour_shots: int = 0


func _tour_tick() -> void:
	var om = root.get_node("OnlineMatch")
	if om.phase == &"intermission" and _tour_shots < 3:
		var scene = _main.get_node("SceneRoot").get_child(-1)
		if scene.name != "IntermissionMenu":
			return
		if _tour_shots == 0:
			_shot_now("tour_inter_summary")
			scene._set_page(-1)
		elif _tour_shots == 1:
			_shot_now("tour_inter_shop")
			om.set_local_intermission_ready(true)
		_tour_shots += 1
	elif om.phase == &"playing_set" and _tour_shots >= 2 and _tour_shots < 4:
		_shot_now("tour_set2_%d" % _tour_shots)
		_tour_shots += 1
	elif om.phase == &"kill_banner":
		_shot_now("tour_banner_%d" % int(_time))
	if om.phase == &"playing_set" and _tour_shots < 2:
		var g = get_first_node_in_group(&"game_world")
		if g != null and not g.is_round_intro_running():
			var p2 = g.get_player_by_slot(2)
			if p2 != null and not p2.is_eliminated():
				p2.apply_resolved_damage(40, g.get_player_by_slot(1).global_position)


func _shot_now(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = _viewport.get_texture().get_image()
	image.save_png(_out_dir.path_join(label + ".png"))
	print("CAPTURED ", label)


func _push_action(action_name: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = StringName(action_name)
	event.pressed = true
	_viewport.push_input(event)
	var release: InputEventAction = InputEventAction.new()
	release.action = StringName(action_name)
	release.pressed = false
	_viewport.push_input(release)


func _log_state() -> void:
	var game: Node = get_first_node_in_group(&"game_world")
	if game == null:
		print("no game")
		return
	var p1 = game.get_player_by_slot(1)
	var p2 = game.get_player_by_slot(2)
	print("t=%.1f P1 %s hp=%d | P2 %s hp=%d v=%s elim=%s | score %d-%d intro=%s" % [_time, p1.global_position.round(), p1.health_component.health, p2.global_position.round(), p2.health_component.health, p2.velocity.round(), p2.is_eliminated(), game.get_score_for_slot(1), game.get_score_for_slot(2), game.is_round_intro_running()])


func _at(time: float, kind: String, arg: Variant = null) -> void:
	_actions.append({"t": time, "k": kind, "a": arg})


func _process(delta: float) -> bool:
	_time += delta
	if _aim_sampling:
		var g = get_first_node_in_group(&"game_world")
		if g != null:
			_aim_samples.append(g.get_player_by_slot(1).get_aim_world_position())
	if _stress_recording:
		var now_usec: int = Time.get_ticks_usec()
		if _stress_prev_usec > 0:
			var ms: float = (now_usec - _stress_prev_usec) / 1000.0
			_stress_frames.append(ms)
			var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			if ms > 6.0:
				var g = get_first_node_in_group(&"game_world")
				_stress_spikes.append([_time, ms, g.get_projectiles_root().get_child_count() if g != null else -1, node_count, node_count - _stress_prev_nodes, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _stress_events + " prev=" + str(_stress_added_prev) + " cur=" + str(_stress_added)])
			_stress_prev_nodes = node_count
			if Engine.has_meta(&"prof"):
				var prof: Dictionary = Engine.get_meta(&"prof")
				if ms > 9.0 and not prof.is_empty():
					var keys: Array = prof.keys()
					keys.sort_custom(func(x, y): return prof[x] > prof[y])
					var parts: PackedStringArray = PackedStringArray()
					for k in keys.slice(0, 9):
						parts.append("%s=%.1f" % [k, prof[k] / 1000.0])
					_stress_spikes[-1].append(" | ".join(parts))
				for k in prof.keys():
					_stress_prof_total[k] = int(_stress_prof_total.get(k, 0)) + int(prof[k])
				prof.clear()
		_stress_prev_usec = now_usec
		_stress_events = ""
		_stress_added_prev = _stress_added.duplicate()
		_stress_added.clear()
	for hook in _hooks:
		(hook as Callable).call()
	_frame += 1
	var now: int = Time.get_ticks_usec()
	if _last_tick > 0:
		if now - _last_tick > 34000 and _frame > 30 and not OS.has_environment("BF_NOHITCH"):
			print("HITCH t=%.2f ms=%.1f" % [_time, (now - _last_tick) / 1000.0])
	_last_tick = now
	if _frame == 3 and DisplayServer.get_name() != "headless":
		print("WINDOW pos=", DisplayServer.window_get_position(), " size=", DisplayServer.window_get_size())
	while not _actions.is_empty() and _actions[0]["t"] <= _time:
		var action: Dictionary = _actions.pop_front()
		_run(action)
	return _done


func _run(action: Dictionary) -> void:
	match action["k"]:
		"shot":
			if DisplayServer.get_name() == "headless":
				return
			var image: Image = _viewport.get_texture().get_image()
			var path: String = _out_dir.path_join(str(action["a"]) + ".png")
			image.save_png(path)
			print("CAPTURED ", path)
		"crop":
			# [name, Rect2 in viewport pixels, scale]: a close-up of one region, upscaled.
			if DisplayServer.get_name() == "headless":
				return
			var spec: Array = action["a"]
			var region: Image = _viewport.get_texture().get_image().get_region(Rect2i(spec[1]))
			region.resize(int(region.get_width() * float(spec[2])), int(region.get_height() * float(spec[2])), Image.INTERPOLATE_LANCZOS)
			var crop_path: String = _out_dir.path_join(str(spec[0]) + ".png")
			region.save_png(crop_path)
			print("CAPTURED ", crop_path)
		"call":
			(action["a"] as Callable).call()
		"mouse":
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position = action["a"]
			motion.global_position = action["a"]
			_viewport.push_input(motion, true)
		"action":
			var event: InputEventAction = InputEventAction.new()
			event.action = StringName(action["a"])
			event.pressed = true
			_viewport.push_input(event)
			var release: InputEventAction = InputEventAction.new()
			release.action = StringName(action["a"])
			release.pressed = false
			_viewport.push_input(release)
		"key_down", "key_up":
			# Through the input queue like a real key, so is_action_just_pressed sees it in the next physics
			# step even when rendering runs frames at a different pace than physics.
			var key_event: InputEventAction = InputEventAction.new()
			key_event.action = StringName(action["a"])
			key_event.pressed = action["k"] == "key_down"
			Input.parse_input_event(key_event)
		"press":
			Input.action_press(StringName(action["a"]))
		"release":
			Input.action_release(StringName(action["a"]))
		"quit":
			_done = true


var _stress_rounds: int = 0
var _stress_deaths: PackedStringArray = PackedStringArray()
var _stress_log: PackedStringArray = PackedStringArray()
var _stress_frames: PackedFloat32Array = PackedFloat32Array()
var _stress_spikes: Array = []
var _stress_prev_usec: int = 0
var _stress_recording: bool = false
var _stress_prev_nodes: int = 0
var _stress_events: String = ""
var _stress_added_prev: Dictionary = {}
var _stress_prof_total: Dictionary = {}
var _stress_shots: int = 0
var _stress_loadouts: int = 0
var _stress_seeded: Dictionary = {}
var _stress_next_loadout: float = 0.0
var _stress_focus: String = ""


func _stress_frame_report() -> void:
	_stress_recording = false
	var frames: Array = _stress_frames.duplicate()
	frames.sort()
	if frames.is_empty():
		return
	var n: int = frames.size()
	var over8: int = 0
	var over16: int = 0
	for v in frames:
		if v > 8.0:
			over8 += 1
		if v > 16.7:
			over16 += 1
	print("FRAMES n=%d p50=%.2f p95=%.2f p99=%.2f p999=%.2f max=%.2f >8ms=%d >16.7ms=%d" % [n, frames[n / 2], frames[int(n * 0.95)], frames[int(n * 0.99)], frames[mini(n - 1, int(n * 0.999))], frames[n - 1], over8, over16])
	_stress_spikes.sort_custom(func(x, y): return x[1] > y[1])
	for i in range(mini(25, _stress_spikes.size())):
		var sp: Array = _stress_spikes[i]
		print("  SPIKE t=%.2f %.2fms proj=%d nodes=%d dnodes=%+d ev=%s" % [sp[0], sp[1], sp[2], sp[3], sp[4], sp[7]])
		if sp.size() > 8:
			print("      ", sp[8])
	if not _stress_prof_total.is_empty():
		var keys: Array = _stress_prof_total.keys()
		keys.sort_custom(func(x, y): return _stress_prof_total[x] > _stress_prof_total[y])
		print("PROF TOTAL (ms per frame avg over %d frames)" % n)
		for k in keys.slice(0, 40):
			print("   %-55s %.3f" % [k, _stress_prof_total[k] / 1000.0 / n])


func _stress_start() -> void:
	_stress_focus = OS.get_environment("BF_STRESS_FOCUS") if OS.has_environment("BF_STRESS_FOCUS") else ""
	root.get_node("UserSettings").set_value(&"progress_bot_world", OS.get_environment("BF_WORLD") if OS.has_environment("BF_WORLD") else "verdant")
	root.get_node("NetworkSession").start_bot_duel()
	_main.start_game()
	_stress_seeded.clear()
	_stress_hook.call_deferred()


func _stress_hook() -> void:
	var g = get_first_node_in_group(&"game_world")
	if g == null:
		return
	if not node_added.is_connected(_stress_node_added):
		node_added.connect(_stress_node_added)
	g.get_projectiles_root().child_entered_tree.connect(func(_n): _stress_events += "s")
	for slot in [1, 2]:
		var p = g.get_player_by_slot(slot)
		if p != null:
			p.health_component.health_changed.connect(func(a = null, b = null, c = null): _stress_events += "h%d" % slot)
			p.health_component.health_depleted.connect(func(a = null):
				_stress_events += "D%d" % slot
				_stress_deaths.append("t=%.0f slot%d at %s wind=%.0f" % [_time, slot, p.global_position.round(), WorldConditions.wind.x]))


func _stress_game() -> Node:
	return get_first_node_in_group(&"game_world")


func _stress_tick() -> void:
	var game: Node = _stress_game()
	if game == null or game.is_match_over():
		_stress_rounds += 1
		print("STRESS t=%.0f restart (match over or left)" % _time)
		_stress_start()
		return
	var p1 = game.get_player_by_slot(1)
	if p1 != null and p1.control_mode != &"ai":
		p1.configure_ai_control(1, 2)
	if _time >= _stress_next_loadout:
		_stress_next_loadout = _time + 6.0
		for slot in [1, 2]:
			_stress_random_loadout(slot)
		_stress_loadouts += 1
	var proj: Node = game.get_projectiles_root()
	_stress_shots = maxi(_stress_shots, proj.get_child_count())
	if int(_time) % 20 == 0 and not _stress_recording:
		var p2 = game.get_player_by_slot(2)
		print("STRESS t=%.0f nodes=%d objs=%d proj=%d fps=%d score=%d-%d hp=%d/%d" % [_time, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), proj.get_child_count(), Performance.get_monitor(Performance.TIME_FPS), game.get_score_for_slot(1), game.get_score_for_slot(2), p1.health_component.health, p2.health_component.health])


func _stress_random_loadout(slot: int) -> void:
	var inv = root.get_node("ExtensionInventory")
	if not _stress_seeded.has(slot):
		_stress_seeded[slot] = true
		inv.add_all_definitions_for_player(slot)
		inv.add_all_definitions_for_player(slot)
	var by_slot: Dictionary = {}
	for item in inv.get_inventory_for_player(slot):
		var key: StringName = item.get_slot()
		if not by_slot.has(key):
			by_slot[key] = []
		by_slot[key].append(item)
	var picked: Array = []
	for key in [&"front", &"middle", &"ammo"]:
		var options: Array = by_slot.get(key, [])
		if _stress_focus != "" and key == &"front":
			for item in options:
				if str(item.get_definition_id()) == _stress_focus:
					item.mark = randi_range(1, 3)
					inv.equip_item_for_player(slot, item)
					picked.append("%s%d" % [item.get_definition_id(), item.mark])
					break
			continue
		if options.is_empty() or randf() < 0.15:
			inv.unequip_for_player(slot, key)
			continue
		var choice = options[randi() % options.size()]
		choice.mark = randi_range(1, 3)
		inv.equip_item_for_player(slot, choice)
		picked.append("%s%d" % [choice.get_definition_id(), choice.mark])
	_stress_log.append("t=%.0f p%d %s" % [_time, slot, ", ".join(PackedStringArray(picked))])


var _stress_move: String = ""


func _stress_sandbox_tick() -> void:
	var game: Node = _stress_game()
	if game == null:
		print("STRESS no game at t=%.1f" % _time)
		return
	var p1 = game.get_player_by_slot(1)
	if _time >= _stress_next_loadout:
		_stress_next_loadout = _time + 5.0
		_stress_random_loadout(1)
		_stress_loadouts += 1
	# Sweep the aim around the player, mostly towards the dummies.
	var center: Vector2 = Vector2(640, 360)
	var angle: float = _time * 2.3 + sin(_time * 0.7) * 2.0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center + Vector2(cos(angle), sin(angle) * 0.6) * 300.0
	motion.global_position = motion.position
	_viewport.push_input(motion, true)
	if randf() < 0.08:
		if _stress_move != "":
			Input.action_release(_stress_move)
		_stress_move = ["p1_move_left", "p1_move_right", "", "p1_jump"][randi() % 4]
		if _stress_move != "":
			Input.action_press(_stress_move)
	if randf() < 0.02:
		Input.action_press("p1_block")
	elif randf() < 0.1:
		Input.action_release("p1_block")
	var proj: Node = game.get_projectiles_root()
	_stress_shots = maxi(_stress_shots, proj.get_child_count())
	if int(_time * 10.0) % 200 == 0 and not _stress_recording:
		print("STRESS t=%.0f nodes=%d objs=%d proj=%d fps=%d pos=%s" % [_time, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), proj.get_child_count(), Performance.get_monitor(Performance.TIME_FPS), p1.global_position.round()])


var _stress_added: Dictionary = {}


func _stress_node_added(node: Node) -> void:
	if not _stress_recording:
		return
	var label: String = node.get_class()
	var sc: Script = node.get_script()
	if sc != null:
		label = sc.resource_path.get_file().get_basename()
	_stress_added[label] = int(_stress_added.get(label, 0)) + 1


var _probe_marks: Dictionary = {}
var _tp_marks: Dictionary = {}
var _tp_rounds: Dictionary = {}
var _tp_results: Dictionary = {}
var _tp_failures: int = 0


func _tp_check(label: String, ok: bool) -> void:
	if not ok:
		_tp_failures += 1
	print("TIME_PROBE %s %s" % ["PASS" if ok else "FAIL", label])


## Puts both fighters on the flat ground either side of the pit in the arena's middle (Verdant: 125 px of
## level ground each), so the short measured run stays on the flat.
func _tp_reset_positions() -> void:
	var g = _stress_game()
	g._set_spawn_positions()
	var middle: float = (g.get_player_by_slot(1).global_position.x + g.get_player_by_slot(2).global_position.x) * 0.5
	var space: PhysicsDirectSpaceState2D = g.get_world_2d().direct_space_state
	for slot in [1, 2]:
		var x: float = middle + (-260.0 if slot == 1 else 260.0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(x, 420.0), Vector2(x, 3000.0), 1))
		var p = g.get_player_by_slot(slot)
		p.global_position = Vector2(x, float(hit["position"].y) - 40.0) if not hit.is_empty() else p.global_position
		p.velocity = Vector2.ZERO


## A probe round with no collision, flying flat above the arena, so only time changes its speed.
func _tp_spawn_round(slot: int, offset: Vector2, key: String) -> void:
	var g = _stress_game()
	var projectile = g.PROJECTILE_SCENE.instantiate()
	projectile.configure_from_data(0, slot, Vector2.RIGHT, {"muzzle_speed": 900.0, "gravity": 0.0, "linear_damping": 0.0, "max_distance": 100000.0})
	projectile.collision_mask = 0
	projectile.collision_layer = 0
	g.spawn_projectile(projectile, g.get_player_by_slot(1).global_position + offset)
	_tp_rounds[key] = projectile


func _tp_mark(tag: String) -> void:
	var g = _stress_game()
	_tp_marks[tag] = {"t": _time, "p1": g.get_player_by_slot(1).global_position.x, "p2": g.get_player_by_slot(2).global_position.x,
		"r2": _tp_rounds[tag + "_p2round"].global_position.x, "r1": _tp_rounds[tag + "_p1round"].global_position.x}


func _tp_measure(tag: String) -> void:
	var g = _stress_game()
	var m: Dictionary = _tp_marks[tag]
	var dt: float = _time - float(m["t"])
	var result: Dictionary = {
		"p1_run": absf(g.get_player_by_slot(1).global_position.x - float(m["p1"])) / dt,
		"p2_run": absf(g.get_player_by_slot(2).global_position.x - float(m["p2"])) / dt,
		"p2_round": absf(_tp_rounds[tag + "_p2round"].global_position.x - float(m["r2"])) / dt,
		"p1_round": absf(_tp_rounds[tag + "_p1round"].global_position.x - float(m["r1"])) / dt,
		"p2_scale": g.get_player_by_slot(2).time_scale,
	}
	_tp_results[tag] = result
	print("TIME_PROBE %-6s P1 run %.0f px/s | P2 run %.0f px/s | P2 round %.0f px/s | P1 round %.0f px/s | P2 time_scale %.2f" % [tag, result["p1_run"], result["p2_run"], result["p2_round"], result["p1_round"], result["p2_scale"]])
	for key in [tag + "_p2round", tag + "_p1round"]:
		if is_instance_valid(_tp_rounds[key]):
			_tp_rounds[key].queue_free()


func _tp_report() -> void:
	if _tp_results.has("normal") and _tp_results.has("slowed"):
		var normal: Dictionary = _tp_results["normal"]
		var slowed: Dictionary = _tp_results["slowed"]
		var run_ratio: float = float(slowed["p2_run"]) / maxf(float(normal["p2_run"]), 1.0)
		var round_ratio: float = float(slowed["p2_round"]) / maxf(float(normal["p2_round"]), 1.0)
		print("TIME_PROBE ratio slowed/normal: P2 run %.2f, P2 round %.2f, P1 run %.2f, P1 round %.2f" % [run_ratio, round_ratio,
			float(slowed["p1_run"]) / maxf(float(normal["p1_run"]), 1.0), float(slowed["p1_round"]) / maxf(float(normal["p1_round"]), 1.0)])
		_tp_check("slowed player runs at ~35%", absf(run_ratio - 0.35) < 0.06)
		_tp_check("slowed player's rounds fly at ~35%", absf(round_ratio - 0.35) < 0.03)
		_tp_check("caster runs at full speed", absf(float(slowed["p1_run"]) - float(normal["p1_run"])) < 8.0)
		_tp_check("caster's rounds fly at full speed", absf(float(slowed["p1_round"]) - float(normal["p1_round"])) < 5.0)
	if _tp_results.has("after") and _tp_results.has("normal"):
		_tp_check("speed back to normal after", absf(float(_tp_results["after"]["p2_run"]) - float(_tp_results["normal"]["p2_run"])) < 8.0)
	print("TIME_PROBE done, %d failure(s)" % _tp_failures)


func _weather() -> Node:
	return _stress_game().get_node("Arena/Weather")


func _place_p1(at: Vector2) -> void:
	var p1 = _stress_game().get_player_by_slot(1)
	p1.global_position = at
	p1.velocity = Vector2.ZERO


func _probe_mark(label: String) -> void:
	var p1 = _stress_game().get_player_by_slot(1)
	_probe_marks[label] = [p1.global_position, _time]


func _probe_report(label: String) -> void:
	var p1 = _stress_game().get_player_by_slot(1)
	var start: Array = _probe_marks[label]
	var dt: float = _time - float(start[1])
	var dx: float = p1.global_position.x - (start[0] as Vector2).x
	print("PROBE %-16s dx=%+.0f over %.2fs (%.0f px/s) wind=%.0f exposure=%.2f grounded=%s" % [label, dx, dt, dx / maxf(dt, 0.01), WorldConditions.wind.x, p1.get_wind_exposure(), p1.is_grounded()])


var _aim_samples: Array = []
var _aim_sampling: bool = false


func _recycler_center() -> Vector2:
	for node in _viewport.find_children("*", "LoadoutRecycler", true, false):
		if node.is_visible_in_tree():
			return node.get_global_rect().get_center()
	print("NO RECYCLER")
	return Vector2(640, 360)


func _offer_center() -> Vector2:
	for node in _viewport.find_children("*", "LoadoutRewardTile", true, false):
		if node.is_visible_in_tree() and node.source_kind == &"offer" and not node.reward.is_empty():
			return node.get_global_rect().get_center()
	print("NO OFFER")
	return Vector2(640, 360)


func _sell_log(tag: String) -> void:
	var inv = root.get_node("ExtensionInventory")
	var rri = root.get_node("RoundRewardInventory")
	var offers: int = 0
	for i in range(6):
		if not rri.get_offer(i).is_empty():
			offers += 1
	print("SELL %-28s coins=%d inventory=%d offers=%d ratio=%.2f" % [tag, root.get_node("OnlineMatch").get_local_coin_balance(), inv.get_inventory_for_local().size(), offers, rri.get_sell_ratio()])


# --- Movement probes (dash) ------------------------------------------------------------------------

## Callables run once per frame (probes that watch state continuously).
var _hooks: Array = []
var _dash_spot: Vector2 = Vector2.ZERO
var _dash_was: Dictionary = {}
var _dash_start: Dictionary = {}
var _dash_count: int = 0
var _probe_round: Variant = null
var _dummy_start: Vector2 = Vector2.ZERO


func _p1() -> Node:
	return _stress_game().get_player_by_slot(1)


func _set_dash_mark(mark: int) -> void:
	root.get_node("ResearchManager")._local_marks["dashing"] = mark
	print("PROBE dashing mark=%d cooldown=%.1f shockwave=%s protection=%s" % [mark, root.get_node("ResearchManager").get_dash_cooldown(1), root.get_node("ResearchManager").has_dash_shockwave(1), root.get_node("ResearchManager").has_dash_protection(1)])


## Puts P1 at the start of the flat stretch, facing right, at rest.
func _dash_reset_p1() -> void:
	var p1 = _p1()
	p1.global_position = Vector2(_dash_spot.x + 60.0, _dash_spot.y - 26.0)
	p1.velocity = Vector2.ZERO
	p1.last_dir = 1.0


func _park_dummy(ahead: float) -> void:
	var dummy = _stress_game().get_player_by_slot(2)
	dummy.global_position = Vector2(_dash_spot.x + 60.0 + ahead, _dash_spot.y - 26.0)
	dummy.velocity = Vector2.ZERO
	_dummy_start = dummy.global_position


func _report_dummy(label: String) -> void:
	var dummy = _stress_game().get_player_by_slot(2)
	var p1 = _p1()
	print("PROBE %s dummy moved dx=%+.0f dy=%+.0f | p1 dx_from_start=%+.0f" % [label, dummy.global_position.x - _dummy_start.x, dummy.global_position.y - _dummy_start.y, p1.global_position.x - (_dash_spot.x + 60.0)])
	dummy.global_position = Vector2(_dash_spot.x + 1400.0, _dash_spot.y - 60.0)


## A straight, gravity-free round from the dummy's side, `ahead` px in front of P1, flying at P1.
func _fire_at_p1(ahead: float) -> void:
	var p1 = _p1()
	var shot = load("res://scenes/projectiles/projectile.tscn").instantiate()
	shot.configure_from_data(0, 2, Vector2.LEFT, {"muzzle_speed": 900.0, "gravity": 0.0, "damage": 25, "max_distance": 700.0})
	_stress_game().spawn_projectile(shot, p1.global_position + Vector2(ahead, 0.0))
	_probe_round = shot


## A plain static floor for movement probes (top-left corner at `top_left`), drawn as a dark slab so it
## shows in captures, and placed in the map so bot navigation sees it. Returns the top-left corner.
func _build_test_floor(top_left: Vector2, width: float, height: float = 24.0) -> Vector2:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	shape.position = Vector2(width, height) * 0.5
	body.add_child(shape)
	var slab: Polygon2D = Polygon2D.new()
	slab.polygon = PackedVector2Array([Vector2.ZERO, Vector2(width, 0.0), Vector2(width, height), Vector2(0.0, height)])
	slab.color = Color(0.16, 0.17, 0.15, 1.0)
	body.add_child(slab)
	body.position = top_left
	var bounds_node = get_first_node_in_group(&"map_bounds")
	var map_root: Node = bounds_node.get_parent() if bounds_node != null and bounds_node.get_parent() != null else _stress_game()
	map_root.add_child(body)
	return top_left


## Hands the movement sync module a packet as if it came from `from_slot`.
func _movement_packet(packet_type: StringName, from_slot: int, payload: Dictionary) -> void:
	var packet: Dictionary = {"type": str(packet_type), "seq": 0, "tick": 0, "from_slot": from_slot, "payload": payload}
	_stress_game()._game_sync.get_module(&"movement").handle_packet(packet)


## Logs every dash of either player: start, and at the end the burst distance and the largest vertical speed.
func _watch_dashes() -> void:
	var game = _stress_game()
	if game == null:
		return
	for slot in [1, 2]:
		var p = game.get_player_by_slot(slot)
		if p == null:
			continue
		var now: bool = p._dashing
		var was: bool = bool(_dash_was.get(slot, false))
		if now and not was:
			_dash_count += 1
			_dash_start[slot] = [p.global_position, _time, 0.0]
			print("DASH start slot=%d t=%.2f dir=%+.0f grounded=%s protected=%s" % [slot, _time, p.get_dash_direction(), p.is_grounded(), p.is_dash_protected()])
		elif now:
			_dash_start[slot][2] = maxf(float(_dash_start[slot][2]), absf(p.velocity.y))
		elif was:
			var start: Array = _dash_start[slot]
			print("DASH end   slot=%d t=%.2f burst_dx=%+.0f dy=%+.0f took=%.3f max_vy=%.0f" % [slot, _time, p.global_position.x - (start[0] as Vector2).x, p.global_position.y - (start[0] as Vector2).y, _time - float(start[1]), float(start[2])])
		_dash_was[slot] = now


# --- Movement probes (wall jumps) -----------------------------------------------------------------

var _wall_stats: Dictionary = {}


## Removes the arena's terrain and builds the wall rig: a long floor (top 640), a 400 px wall block at
## x 800-1060 (top 240) and a low platform at x 360-560 whose underside is 100 px up.
func _build_wall_rig() -> void:
	_clear_terrain()
	_build_test_floor(Vector2(100.0, 640.0), 1300.0, 40.0)
	_build_test_floor(Vector2(800.0, 240.0), 260.0, 400.0)
	_build_test_floor(Vector2(360.0, 520.0), 200.0, 20.0)


func _clear_terrain() -> void:
	for body in _stress_game().find_children("*", "StaticBody2D", true, false):
		body.get_parent().remove_child(body)
		body.queue_free()


## The bot climb rig: floor (top 640), a 160 px step at x 420-660 and a 400 px wall block at x 900-1160.
func _build_climb_rig() -> void:
	_clear_terrain()
	_build_test_floor(Vector2(100.0, 640.0), 1300.0, 40.0)
	_build_test_floor(Vector2(420.0, 480.0), 240.0, 160.0)
	_build_test_floor(Vector2(900.0, 240.0), 260.0, 400.0)


## Sends a bot to the nav point nearest `goal` and keeps it there (no goal searches of its own).
func _bot_goal(player: Node, goal: Vector2) -> void:
	var brain = player.ai_brain
	brain._ensure_navigation()
	brain._goal_point = brain._nav.nearest_point(goal, 120.0)
	brain._plan_path(player.global_position + Vector2(0.0, player.hover_dist))
	var moves: PackedStringArray = PackedStringArray()
	for index in range(brain._path.size() - 1):
		moves.append(str(int(brain._nav.get_move(int(brain._path[index]), int(brain._path[index + 1]))["move"])))
	print("CLIMB slot=%d goal=%s reach=%.0f path=%d moves=%s (3 = climb)" % [player.player_slot, goal, brain._climb_reach(), brain._path.size(), ",".join(moves)])


func _hold_bot_goals() -> void:
	for slot in [1, 2]:
		var p = _stress_game().get_player_by_slot(slot)
		if p != null and p.ai_brain != null:
			p.ai_brain._replan_timer = 999.0
			p.ai_brain._search_queue.clear()


func _set_wall_mark(mark: int) -> void:
	root.get_node("ResearchManager")._local_marks["wall_jumps"] = mark


func _wall_reset(at: Vector2) -> void:
	var p1 = _p1()
	p1.global_position = at
	p1.velocity = Vector2.ZERO
	p1.last_dir = 1.0
	p1._state_machine.change_state("RunState")
	_wall_stats = {"start_y": at.y, "min_y": at.y, "cling": 0.0, "topped": false, "stuck": 0.0, "stuck_max": 0.0, "prev_pos": at}


## Climb height (body centre above the start), most wall jumps in one airtime, time spent clinging, whether
## the player stood on the wall top, and the longest time hung motionless in the air (stuck).
func _watch_wall() -> void:
	if _wall_stats.is_empty():
		return
	var p1 = _p1()
	_wall_stats["min_y"] = minf(float(_wall_stats["min_y"]), p1.global_position.y)
	var grounded: bool = p1.is_grounded()
	var clinging: bool = p1.get("_wall_cling_timer") != null and float(p1.get("_wall_cling_timer")) > 0.0
	if clinging:
		_wall_stats["cling"] = float(_wall_stats["cling"]) + 1.0 / 60.0
	if grounded and p1.global_position.y < 250.0:
		_wall_stats["topped"] = true
	_wall_stats["used_max"] = maxi(int(_wall_stats.get("used_max", 0)), p1.get_wall_jumps_used())
	# Stuck: airborne, not clinging, and not moving for a while (hung on a corner or an edge).
	if not grounded and not clinging and p1.global_position.distance_to(_wall_stats["prev_pos"]) < 0.1:
		_wall_stats["stuck"] = float(_wall_stats["stuck"]) + 1.0 / 60.0
		_wall_stats["stuck_max"] = maxf(float(_wall_stats["stuck_max"]), float(_wall_stats["stuck"]))
	else:
		_wall_stats["stuck"] = 0.0
	_wall_stats["prev_pos"] = p1.global_position
	if OS.has_environment("BF_WALL_TRACE"):
		var used: int = p1.get_wall_jumps_used()
		if used != int(_wall_stats.get("used", 0)):
			print("TRACE t=%.2f used=%d y=%.0f vy=%.0f state=%s on_wall=%s" % [_time, used, p1.global_position.y, p1.velocity.y, p1._state_machine.current_state.name, p1.is_on_wall()])
			_wall_stats["used"] = used


func _report_wall(label: String) -> void:
	print("WALL %s climb=%.0f px wall_jumps=%d cling=%.2f s stood_on_top=%s longest_stuck=%.2f s" % [label, float(_wall_stats["start_y"]) - float(_wall_stats["min_y"]), int(_wall_stats.get("used_max", 0)), float(_wall_stats["cling"]), _wall_stats["topped"], float(_wall_stats["stuck_max"])])
