extends Node2D

const GAME_SCENE := preload("res://scenes/Game.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/menus/MainMenu.tscn")
const ONLINE_LOCKER_ROOM_SCENE := preload("res://scenes/menus/OnlineLockerRoom.tscn")
const INTERMISSION_MENU_SCENE := preload("res://scenes/menus/IntermissionMenu.tscn")

@onready var scene_root: Node = %SceneRoot
@onready var _transition_fade: ColorRect = %TransitionFade
var current_scene: Node = null
var _transition_tween: Tween = null

func _ready() -> void:
	NetworkSession.lobby_ready.connect(_on_lobby_ready)
	NetworkSession.lobby_left.connect(_on_lobby_left)
	OnlineMatch.phase_changed.connect(_on_online_phase_changed)
	if NetworkSession.is_steam_match_active():
		_show_locker_room()
	else:
		show_menu()

func show_menu() -> void:
	var menu: Node = change_scene(MAIN_MENU_SCENE)
	if menu.has_signal("sandbox_requested"):
		menu.connect("sandbox_requested", Callable(self, "_on_sandbox_requested"))
	if menu.has_signal("online_requested"):
		menu.connect("online_requested", Callable(self, "_on_online_requested"))
	if menu.has_signal("exit_requested"):
		menu.connect("exit_requested", Callable(self, "_on_exit_requested"))


func change_scene(scene: PackedScene) -> Node:
	if current_scene:
		current_scene.queue_free()

	current_scene = scene.instantiate()
	scene_root.add_child(current_scene)
	_play_transition_pulse()
	return current_scene


func _on_sandbox_requested() -> void:
	NetworkSession.start_offline()
	_start_game()


func _on_online_requested() -> void:
	OnlineMatch.enter_locker(true)
	NetworkSession.host_invite_round()
	_show_locker_room()


func _on_exit_requested() -> void:
	get_tree().quit()


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
		if current_scene == null or current_scene.name != "Game":
			_start_game()
	elif next_phase == GameSettings.MATCH_PHASE_INTERMISSION:
		change_scene(INTERMISSION_MENU_SCENE)


func _start_game() -> void:
	change_scene(GAME_SCENE)


func _show_locker_room() -> void:
	if current_scene != null and current_scene.name == "OnlineLockerRoom":
		return
	change_scene(ONLINE_LOCKER_ROOM_SCENE)


func _play_transition_pulse() -> void:
	if _transition_fade == null:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_fade.modulate.a = 0.42
	_transition_tween = create_tween()
	_transition_tween.tween_property(_transition_fade, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
