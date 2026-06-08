class_name RoundScoreDot
extends Control

@onready var _fill: Polygon2D = %Fill


func set_state(filled: bool, player_color: Color) -> void:
	if not is_node_ready():
		await ready
	_fill.color = player_color.lightened(0.12) if filled else Color(0.16, 0.18, 0.22, 0.9)
	modulate.a = 1.0 if filled else 0.72
