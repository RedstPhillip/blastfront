extends Node2D


@onready var scene_root: Node = %SceneRoot;
var current_scene: Node = null;

func _ready() -> void:
	show_menu();

func show_menu() -> void:
	change_scene("res://scenes/Game.tscn");


func change_scene(path: String) -> void:
	if current_scene: 
		current_scene.queue_free();
	
	current_scene = load(path).instantiate();
	scene_root.add_child(current_scene);
