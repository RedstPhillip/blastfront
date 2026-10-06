extends SceneTree

# GPU ablation on a running AI duel: switches one visual group off at a time and reports the measured GPU
# time and wall frame time for each configuration (uncapped, hidden 1px window).

var _main: Node = null
var _viewport: SubViewport = null
var _frame: int = 0
var _configs: Array = []
var _config_index: int = -1
var _gpu: Array = []
var _wall: Array = []
var _draws: Array = []
var _rcpu: Array = []
var _prev: int = 0
var _hidden: Array = []
var _world: String = "mars"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("world="):
			_world = arg.substr(6)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_min_size(Vector2i(1, 1))
	DisplayServer.window_set_size(Vector2i(1, 1))
	var screen: int = DisplayServer.get_primary_screen()
	DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + DisplayServer.screen_get_size(screen) - Vector2i(1, 1))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.size_2d_override = Vector2i(1280, 720)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	_main = load("res://scenes/app/main.tscn").instantiate()
	_viewport.add_child(_main)
	if OS.has_environment("BF_HUD_ABLATE"):
		_configs = [
			["all", []],
			["no_cards", ["@HudPlayerCard"]],
			["no_scoreboard", ["@HudScoreboard"]],
			["no_quest", ["@HudQuestTracker"]],
			["no_indicators", ["@HudOffscreenIndicators"]],
			["no_crosshair", ["@HudCrosshair"]],
			["no_hint", ["@HudControlsHint"]],
			["no_toasts", ["@HudToasts"]],
			["no_banner", ["@HudRoundBanner"]],
			["no_victory", ["@HudVictoryScreen"]],
			["no_screenfx", ["ScreenFx"]],
			["all_again", []],
		]
		return
	if OS.has_environment("BF_DRAW_ABLATE"):
		_configs = [
			["all", []],
			["no_players", ["Player1", "Player2"]],
			["no_hud", ["HUD"]],
			["no_screenfx", ["ScreenFx"]],
			["no_env", ["Arena/Environment", "Arena/ArenaEnvironment"]],
			["no_arena", ["Arena"]],
			["no_border", ["MapBorder"]],
			["no_projectiles", ["Projectiles"]],
			["all_again", []],
		]
		return
	_configs = [
		["all", []],
		["no_sunlight", ["Arena/Environment/SunLight", "Arena/Environment/MoonLight", "Arena/MoonLight"]],
		["no_screenfx", ["ScreenFx"]],
		["no_far", ["Arena/Environment/FarLayer"]],
		["no_mid", ["Arena/Environment/MidLayer"]],
		["no_near", ["Arena/Environment/NearLayer"]],
		["no_abyss", ["Arena/Environment/Abyss"]],
		["no_dust", ["Arena/Environment/DustMotes"]],
		["no_weather", ["Arena/Weather"]],
		["no_hud", ["HUD", "MatchOverlay"]],
		["all_again", []],
	]


func _process(_delta: float) -> bool:
	_frame += 1
	if Engine.max_fps != 0:
		Engine.max_fps = 0
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _frame == 30:
		root.get_node("UserSettings").set_value(&"progress_bot_world", _world)
		root.get_node("UserSettings").set_value(&"gameplay_bot_phase_shop", false)
		root.get_node("NetworkSession").start_bot_duel(false)
		_main.start_game()
	if _frame == 200:
		var game: Node = get_first_node_in_group(&"game_world")
		for slot in [1, 2]:
			game.get_player_by_slot(slot).configure_ai_control(slot, 2)
		if game.has_node("Arena/Weather"):
			game.get_node("Arena/Weather").skip_to_storm(true, 1.0, false)
		_next_config()
	if _config_index >= 0:
		var now: int = Time.get_ticks_usec()
		if (_frame - 200) % 600 > 60:
			_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid()))
			_wall.append((now - _prev) / 1000.0)
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_viewport.get_viewport_rid()))
		_prev = now
		if (_frame - 200) % 600 == 599:
			_report()
			_next_config()
	return _config_index >= _configs.size()


func _next_config() -> void:
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()
	_config_index += 1
	_gpu.clear()
	_wall.clear()
	_draws.clear()
	_rcpu.clear()
	if _config_index >= _configs.size():
		return
	var game: Node = get_first_node_in_group(&"game_world")
	for path in _configs[_config_index][1]:
		if str(path).begins_with("@"):
			for child in game.get_node("HUD/MatchOverlay").get_children():
				if child.get_script() != null and child.get_script().get_global_name() == str(path).substr(1):
					child.visible = false
					_hidden.append(child)
			continue
		var node: Node = game.get_node_or_null(path)
		if node == null:
			node = game.find_child(path.get_file(), true, false)
		if node is CanvasItem or node is CanvasLayer:
			node.visible = false
			_hidden.append(node)
	if _configs[_config_index][0] == "no_weather" and game.has_node("Arena/Weather"):
		var weather: Node = game.get_node("Arena/Weather")
		var layer: Variant = weather.get("_screen_layer")
		if layer != null:
			layer.visible = false
			_hidden.append(layer)


func _report() -> void:
	var gpu: float = 0.0
	for v in _gpu:
		gpu += v
	var wall: float = 0.0
	for v in _wall:
		wall += v
	var draws: float = 0.0
	for v in _draws:
		draws += v
	var rcpu: float = 0.0
	for v in _rcpu:
		rcpu += v
	print("ABL %-14s draws=%6.1f rcpu=%.3f gpu=%.3f wall=%.3f hidden=%d" % [_configs[_config_index][0], draws / maxf(_draws.size(), 1), rcpu / maxf(_rcpu.size(), 1), gpu / maxf(_gpu.size(), 1), wall / maxf(_wall.size(), 1), _hidden.size()])
