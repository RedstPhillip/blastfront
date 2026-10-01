extends Node
class_name Main

## App root: owns the active top-level scene, stylised wipe transitions and per-scene music.

const DISPLAY_FONT_FILE: FontFile = preload("res://assets/fonts/russo_one/RussoOne-Regular.ttf")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")
const ONLINE_LOCKER_ROOM_SCENE: PackedScene = preload("res://scenes/menus/online_locker_room.tscn")
const INTERMISSION_MENU_SCENE: PackedScene = preload("res://scenes/menus/intermission_menu.tscn")
const TRANSITION_SHADER: Shader = preload("res://scenes/app/transition.gdshader")
const COVER_SECONDS: float = 0.32
const REVEAL_SECONDS: float = 0.42
const REVEAL_SETTLE_FRAMES: int = 4

static var instance: Main = null

@onready var _scene_root: Node = %SceneRoot
@onready var _transition_fade: ColorRect = %TransitionFade

var _current_scene: Node = null
var _reveal_serial: int = 0
var _transition_tween: Tween = null
var _transition_material: ShaderMaterial = null
var _transitioning: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
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
	change_scene(GAME_SCENE)


func _on_sandbox_requested() -> void:
	transition_to(func() -> void:
		NetworkSession.start_training()
		start_game()
	)


func _on_bot_requested(difficulty: int) -> void:
	UserSettings.set_value(UserSettings.BOT_DIFFICULTY, difficulty)
	transition_to(func() -> void:
		NetworkSession.start_bot_duel()
		start_game()
	)


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
	show_menu()


func _on_online_phase_changed(next_phase: StringName) -> void:
	if next_phase == GameSettings.MATCH_PHASE_LOCKER:
		_show_locker_room()
	elif next_phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		if _current_scene == null or _current_scene.name != "Game":
			start_game()
	elif next_phase == GameSettings.MATCH_PHASE_INTERMISSION:
		change_scene(INTERMISSION_MENU_SCENE)
		AudioDirector.play_music(&"locker")


func _show_locker_room() -> void:
	if _current_scene != null and _current_scene.name == "OnlineLockerRoom":
		return
	change_scene(ONLINE_LOCKER_ROOM_SCENE)
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
