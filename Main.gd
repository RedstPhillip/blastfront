extends Node2D

const GAME_SCENE := preload("res://scenes/Game.tscn")
const INVITE_MENU_SCENE := preload("res://scenes/menus/invite_menu.tscn")

@onready var scene_root: Node = %SceneRoot;
var current_scene: Node = null;

func _ready() -> void:
	NetworkSession.match_started.connect(_on_match_started)
	show_menu();

func show_menu() -> void:
	var menu := change_scene(INVITE_MENU_SCENE)
	if menu.has_signal("offline_requested"):
		menu.connect("offline_requested", Callable(self, "_start_game"))


func change_scene(scene: PackedScene) -> Node:
	if current_scene: 
		current_scene.queue_free();
	
	current_scene = scene.instantiate();
	scene_root.add_child(current_scene);
	return current_scene


func _on_match_started() -> void:
	_start_game()


func _start_game() -> void:
	change_scene(GAME_SCENE)
