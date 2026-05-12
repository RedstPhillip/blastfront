class_name HealthBar
extends Node2D

@export var bar_width: float = GameSettings.HEALTH_BAR_WIDTH
@export var bar_height: float = GameSettings.HEALTH_BAR_HEIGHT
@export var offset_y: float = GameSettings.HEALTH_BAR_OFFSET_Y

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

	var pos := Vector2(-bar_width * GameSettings.HALF, offset_y)
	var ratio := float(_health.health) / float(_health.max_health)

	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), GameSettings.HEALTH_BAR_BACKGROUND_COLOR)

	if ratio > 0.0:
		var col: Color = GameSettings.HEALTH_BAR_LOW_COLOR if ratio <= GameSettings.HEALTH_BAR_LOW_RATIO else GameSettings.HEALTH_BAR_HEALTHY_COLOR
		draw_rect(Rect2(pos, Vector2(bar_width * ratio, bar_height)), col)

	draw_rect(
		Rect2(pos, Vector2(bar_width, bar_height)),
		GameSettings.HEALTH_BAR_BORDER_COLOR,
		false,
		GameSettings.HEALTH_BAR_BORDER_WIDTH
	)
