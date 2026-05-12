class_name MapBounds
extends Node

@export var bounds: Rect2 = GameSettings.DEFAULT_MAP_BOUNDS

func _enter_tree() -> void:
	add_to_group(GameSettings.MAP_BOUNDS_GROUP)
