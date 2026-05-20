class_name HealthBar
extends Node2D

@export var bar_width: float = GameSettings.HEALTH_BAR_WIDTH
@export var bar_height: float = GameSettings.HEALTH_BAR_HEIGHT
@export var offset_y: float = GameSettings.HEALTH_BAR_OFFSET_Y

@onready var _health: HealthComponent = get_parent().get_node("HealthComponent") as HealthComponent

var _display_ratio: float = 1.0
var _target_ratio: float = 1.0
var _flash_timer: float = 0.0
var _shake_timer: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	_health.health_changed.connect(_on_health_changed)
	_health.max_health_changed.connect(_on_health_changed)
	_target_ratio = _health_ratio()
	_display_ratio = _target_ratio
	queue_redraw()

	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat


func _process(delta: float) -> void:
	_target_ratio = _health_ratio()
	_display_ratio = move_toward(_display_ratio, _target_ratio, delta * GameSettings.HEALTH_BAR_LAG_SPEED)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	_shake_timer = maxf(_shake_timer - delta, 0.0)

	if _target_ratio <= GameSettings.HEALTH_BAR_LOW_RATIO:
		_pulse_time += delta
	else:
		_pulse_time = 0.0

	queue_redraw()


func _on_health_changed(old_health: int, new_health: int) -> void:
	_target_ratio = _health_ratio()
	if new_health < old_health:
		_flash_timer = GameSettings.HEALTH_BAR_DAMAGE_FLASH_TIME
		_shake_timer = GameSettings.HEALTH_BAR_DAMAGE_SHAKE_TIME
	else:
		_display_ratio = maxf(_display_ratio, _target_ratio)
	queue_redraw()


func _draw() -> void:
	if _health == null:
		return

	var shake_offset: Vector2 = _damage_shake_offset()
	var pos: Vector2 = Vector2(-bar_width * GameSettings.HALF, offset_y) + shake_offset
	var ratio: float = _health_ratio()
	var displayed_ratio: float = maxf(_display_ratio, ratio)

	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), GameSettings.HEALTH_BAR_BACKGROUND_COLOR)

	if displayed_ratio > ratio:
		var trail_x: float = pos.x + bar_width * ratio
		var trail_width: float = bar_width * (displayed_ratio - ratio)
		draw_rect(Rect2(Vector2(trail_x, pos.y), Vector2(trail_width, bar_height)), GameSettings.HEALTH_BAR_DAMAGE_TRAIL_COLOR)

	if ratio > 0.0:
		var col: Color = GameSettings.HEALTH_BAR_LOW_COLOR if ratio <= GameSettings.HEALTH_BAR_LOW_RATIO else GameSettings.HEALTH_BAR_HEALTHY_COLOR
		if ratio <= GameSettings.HEALTH_BAR_LOW_RATIO:
			var pulse: float = (sin(_pulse_time * GameSettings.HEALTH_BAR_LOW_PULSE_SPEED) + 1.0) * 0.5
			col = col.lerp(GameSettings.HEALTH_BAR_FLASH_COLOR, pulse * 0.35)
		draw_rect(Rect2(pos, Vector2(bar_width * ratio, bar_height)), col)

	if _flash_timer > 0.0:
		var flash_ratio: float = clampf(_flash_timer / GameSettings.HEALTH_BAR_DAMAGE_FLASH_TIME, 0.0, 1.0)
		draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), Color(GameSettings.HEALTH_BAR_FLASH_COLOR, GameSettings.HEALTH_BAR_FLASH_COLOR.a * flash_ratio))

	draw_rect(
		Rect2(pos, Vector2(bar_width, bar_height)),
		GameSettings.HEALTH_BAR_BORDER_COLOR,
		false,
		GameSettings.HEALTH_BAR_BORDER_WIDTH
	)


func _health_ratio() -> float:
	if _health == null or _health.max_health <= 0:
		return 0.0
	return clampf(float(_health.health) / float(_health.max_health), 0.0, 1.0)


func _damage_shake_offset() -> Vector2:
	if _shake_timer <= 0.0:
		return Vector2.ZERO
	var ratio: float = _shake_timer / maxf(GameSettings.HEALTH_BAR_DAMAGE_SHAKE_TIME, 0.001)
	var strength: float = GameSettings.HEALTH_BAR_DAMAGE_SHAKE * ratio
	return Vector2(
		sin(_shake_timer * 95.0) * strength,
		cos(_shake_timer * 77.0) * strength * 0.45
	)
