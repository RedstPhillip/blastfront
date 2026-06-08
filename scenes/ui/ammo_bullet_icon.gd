class_name AmmoBulletIcon
extends Control

@onready var _outline: Polygon2D = %Outline
@onready var _fill: Polygon2D = %Fill


func set_loaded(loaded: bool) -> void:
	if not is_node_ready():
		await ready
	_fill.color = Color("#ff9f2e") if loaded else Color(0.12, 0.14, 0.17, 0.82)
	_outline.color = Color(0.01, 0.012, 0.016, 1.0)
	modulate.a = 1.0 if loaded else 0.72
