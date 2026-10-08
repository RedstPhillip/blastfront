extends Node
class_name Main

## App root: owns the active top-level scene, stylised wipe transitions and per-scene music.
##
## Only the main menu is loaded at start-up. The heavy scenes (the match, the between-sets menu, the online
## lobby, the loadout and settings pages) load one after another on a worker thread while the menu is up,
## so the menu appears seconds sooner and starting a match still swaps instantly. The worker only runs
## while the menu is the active scene, and every scene swap first waits for the load in flight: the main
## thread never loads resources while the worker does (concurrent loads of shared scripts can fail).

const DISPLAY_FONT_FILE: FontFile = preload("res://assets/fonts/russo_one/RussoOne-Regular.ttf")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"
const INTERMISSION_MENU_SCENE_PATH: String = "res://scenes/menus/intermission_menu.tscn"
const ONLINE_LOCKER_ROOM_SCENE_PATH: String = "res://scenes/menus/online_locker_room.tscn"
const LOADOUT_PAGE_SCENE_PATH: String = "res://scenes/ui/loadout/loadout_page.tscn"
const SETTINGS_MENU_SCENE_PATH: String = "res://scenes/menus/settings_menu.tscn"
## Background load order: the small settings page first (so opening it right away never waits on the
## match), then the match and the other worlds' maps, then everything reached from a match.
const BACKGROUND_SCENES: Array[String] = [
	SETTINGS_MENU_SCENE_PATH, GAME_SCENE_PATH, "res://scenes/maps/mars/mars_arena.tscn",
	"res://scenes/maps/tidewater/tidewater_arena.tscn", "res://scenes/maps/rimefall/rimefall_arena.tscn",
	LOADOUT_PAGE_SCENE_PATH, INTERMISSION_MENU_SCENE_PATH, ONLINE_LOCKER_ROOM_SCENE_PATH,
]
const TRANSITION_SHADER: Shader = preload("res://scenes/app/transition.gdshader")
const COVER_SECONDS: float = 0.32
const REVEAL_SECONDS: float = 0.42
const REVEAL_SETTLE_FRAMES: int = 4

static var instance: Main = null

@onready var _scene_root: Node = %SceneRoot
@onready var _transition_fade: ColorRect = %TransitionFade

var _current_scene: Node = null
var _reveal_serial: int = 0
var _screen_covered: bool = false
var _transition_tween: Tween = null
var _transition_material: ShaderMaterial = null
var _transitioning: bool = false
var _scenes: Dictionary = {}
var _background_queue: Array[String] = []
var _background_loading: String = ""


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	# Quitting while a scene still loads on the worker would tear the loader down under it.
	_finish_background_load()
	if instance == self:
		instance = null


func _ready() -> void:
	_transition_material = ShaderMaterial.new()
	_transition_material.shader = TRANSITION_SHADER
	_transition_fade.material = _transition_material
	_transition_fade.color = Color.WHITE
	_transition_fade.modulate.a = 1.0
	_set_transition_progress(1.0, 1.0)
	NetworkSession.lobby_ready.connect(_on_lobby_ready)
	NetworkSession.lobby_left.connect(_on_lobby_left)
	OnlineMatch.phase_changed.connect(_on_online_phase_changed)
	_prepare_font_caches()
	if NetworkSession.is_steam_match_active():
		_show_locker_room()
	else:
		show_menu()
	_background_queue = BACKGROUND_SCENES.duplicate()


## A scene by path: instant once the background load has it, otherwise loaded (or waited for) now.
static func get_scene(path: String) -> PackedScene:
	if instance == null:
		return load(path) as PackedScene
	return instance._get_scene(path)


## True once every background scene is loaded.
func is_warm() -> bool:
	return _background_queue.is_empty() and _background_loading == ""


func _get_scene(path: String) -> PackedScene:
	_finish_background_load()
	var scene: PackedScene = _scenes.get(path, null)
	if scene == null:
		_background_queue.erase(path)
		scene = load(path) as PackedScene
		_scenes[path] = scene
	return scene


## Blocks until the scene loading on the worker (if any) is done and keeps it.
func _finish_background_load() -> void:
	if _background_loading == "":
		return
	var scene: PackedScene = ResourceLoader.load_threaded_get(_background_loading) as PackedScene
	if scene != null:
		_scenes[_background_loading] = scene
	_background_loading = ""


func _process(_delta: float) -> void:
	if _background_loading != "":
		if ResourceLoader.load_threaded_get_status(_background_loading) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		_finish_background_load()
	if _current_scene == null or _current_scene.name != "MainMenu":
		return
	while not _background_queue.is_empty():
		var path: String = _background_queue.pop_front()
		if _scenes.has(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_background_loading = path
			return
	set_process(false)


## Generates the display font's distance-field glyphs up front; otherwise the first banner or damage
## number has to build them mid-fight.
func _prepare_font_caches() -> void:
	var display_font: FontFile = DISPLAY_FONT_FILE
	if display_font != null and display_font.multichannel_signed_distance_field:
		display_font.render_range(0, Vector2i(display_font.msdf_size, 0), 32, 126)


## Covers the screen, runs `action` (usually a scene swap) and reveals the result.
func transition_to(action: Callable) -> void:
	if _transitioning:
		action.call()
		return
	_transitioning = true
	_kill_transition()
	AudioDirector.play(&"ui_whoosh")
	_transition_tween = create_tween().set_ignore_time_scale(true)
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_method(_set_transition_progress.bind(1.0), 0.0, 1.0, COVER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _transition_tween.finished
	_transitioning = false
	_screen_covered = true
	action.call()


func show_menu() -> void:
	var menu: MainMenu = change_scene(MAIN_MENU_SCENE) as MainMenu
	if menu == null:
		return
	menu.sandbox_requested.connect(_on_sandbox_requested)
	menu.online_requested.connect(_on_online_requested)
	menu.bot_requested.connect(_on_bot_requested)
	menu.exit_requested.connect(_on_exit_requested)
	AudioDirector.play_music(&"menu")
	AudioDirector.stop_ambience()


## Swaps the active scene immediately and plays the reveal half of the wipe.
func change_scene(scene: PackedScene) -> Node:
	_finish_background_load()
	get_tree().paused = false
	GameJuice.reset_time_scale()
	AudioDirector.set_muffled(false, 0.2)
	if _current_scene != null:
		_current_scene.queue_free()
	_current_scene = scene.instantiate()
	_scene_root.add_child(_current_scene)
	_play_reveal()
	return _current_scene


func start_game() -> void:
	change_scene(get_scene(GAME_SCENE_PATH))


func _on_sandbox_requested() -> void:
	transition_to(func() -> void:
		NetworkSession.start_training()
		start_game()
	)


func _on_bot_requested(difficulty: int) -> void:
	UserSettings.set_value(UserSettings.BOT_DIFFICULTY, difficulty)
	transition_to(start_bot_match)


## Starts a duel against the bot using the menu's choices. With the phase shop the match runs in sets
## (the first set's phase change brings up the game scene), otherwise it is a straight first-to-N duel.
func start_bot_match() -> void:
	var with_shop: bool = UserSettings.get_bool(UserSettings.BOT_PHASE_SHOP)
	NetworkSession.start_bot_duel(with_shop)
	if with_shop:
		OnlineMatch.begin_bot_match()
		if _current_scene == null or _current_scene.name != "Game":
			start_game()
	else:
		start_game()


func _on_online_requested() -> void:
	transition_to(func() -> void:
		OnlineMatch.enter_locker(true)
		NetworkSession.host_invite_round()
		_show_locker_room()
	)


func _on_exit_requested() -> void:
	transition_to(func() -> void: get_tree().quit())


func _on_lobby_ready() -> void:
	if NetworkSession.mode == GameSettings.NETWORK_MODE_CLIENT and OnlineMatch.phase != GameSettings.MATCH_PHASE_LOCKER:
		OnlineMatch.enter_locker(true)
	if OnlineMatch.phase == GameSettings.MATCH_PHASE_LOCKER:
		_show_locker_room()


func _on_lobby_left() -> void:
	if _current_scene != null and _current_scene.name == "MainMenu":
		return
	_cover_then(show_menu)


## Leaves any lobby or match and returns to the main menu behind the wipe.
func leave_to_menu() -> void:
	transition_to(func() -> void:
		get_tree().paused = false
		NetworkSession.leave_round()
		if _current_scene == null or _current_scene.name != "MainMenu":
			show_menu()
	)


func _on_online_phase_changed(next_phase: StringName) -> void:
	if next_phase == GameSettings.MATCH_PHASE_LOCKER:
		_show_locker_room()
	elif next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		if _current_scene == null or _current_scene.name != "Game":
			_cover_then(start_game)
	elif next_phase == GameSettings.MATCH_PHASE_INTERMISSION:
		_cover_then(func() -> void:
			change_scene(get_scene(INTERMISSION_MENU_SCENE_PATH))
			AudioDirector.play_music(&"locker")
		)


## Runs a scene swap behind the wipe; if the screen is already covered it swaps right away.
func _cover_then(action: Callable) -> void:
	if _screen_covered or _transitioning:
		action.call()
	else:
		transition_to(action)


func _show_locker_room() -> void:
	if _current_scene != null and _current_scene.name == "OnlineLockerRoom":
		return
	change_scene(get_scene(ONLINE_LOCKER_ROOM_SCENE_PATH))
	AudioDirector.play_music(&"locker")
	AudioDirector.stop_ambience()


## Keeps the screen covered until the new scene has drawn a few frames (first-frame shader compiles,
## navigation and effect warm-up happen there), then wipes it open smoothly.
func _play_reveal() -> void:
	_kill_transition()
	_set_transition_progress(1.0, -1.0)
	var serial: int = _reveal_serial
	for _frame in range(REVEAL_SETTLE_FRAMES):
		await get_tree().process_frame
		if serial != _reveal_serial:
			return
	_screen_covered = false
	_transition_tween = create_tween().set_ignore_time_scale(true)
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_method(_set_transition_progress.bind(-1.0), 1.0, 0.0, REVEAL_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_transition_progress(progress: float, direction: float) -> void:
	if _transition_material == null:
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	_transition_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
	_transition_material.set_shader_parameter(&"progress", progress)
	_transition_material.set_shader_parameter(&"direction", direction)
	_transition_fade.visible = progress > 0.0


func _kill_transition() -> void:
	_reveal_serial += 1
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
