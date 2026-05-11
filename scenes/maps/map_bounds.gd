class_name MapBounds
extends Node

@export var bounds := Rect2(0.0, 0.0, 2262.0, 720.0)

func _enter_tree() -> void:
	add_to_group("map_bounds")
