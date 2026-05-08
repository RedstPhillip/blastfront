class_name HealthBar
extends Node2D

@export var bar_width := 28.0
@export var bar_height := 4.0
@export var offset_y := -26.0

@onready var _health: HealthComponent = get_parent().get_node("HealthComponent") as HealthComponent


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)
	_health.max_health_changed.connect(_on_health_changed)
	queue_redraw()

	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat


func _on_health_changed(_old: int, _new: int) -> void:
	queue_redraw()


func _draw() -> void:
	if _health == null:
		return

	var pos := Vector2(-bar_width * 0.5, offset_y)
	var ratio := float(_health.health) / float(_health.max_health)

	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), Color8(40, 40, 40, 180))

	if ratio > 0.0:
		var col := Color8(220, 50, 50, 230) if ratio <= 0.34 else Color8(70, 200, 70, 230)
		draw_rect(Rect2(pos, Vector2(bar_width * ratio, bar_height)), col)

	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), Color8(0, 0, 0, 120), false, 1.0)
