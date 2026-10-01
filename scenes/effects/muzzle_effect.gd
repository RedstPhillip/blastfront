extends Node2D

## Muzzle flash: star-shaped flash, hot core, glow, sparks, lingering smoke and a brief light.

var _direction: Vector2 = Vector2.LEFT
var _tint: Color = Color(1.0, 0.82, 0.38, 1.0)
var _power: float = 1.0


func configure(direction: Vector2, tint: Color = Color(1.0, 0.82, 0.38, 1.0), power: float = 1.0) -> void:
	_direction = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.LEFT
	_tint = tint
	_power = clampf(power, 0.4, 2.5)


func _ready() -> void:
	rotation = _direction.angle()
	var flash: Polygon2D = _make_flash_polygon(34.0 * _power, 9.0 * _power, _tint)
	var core: Polygon2D = _make_flash_polygon(18.0 * _power, 4.5 * _power, Color(1.0, 0.98, 0.85, 1.0))
	flash.material = FxLib.additive_material()
	core.material = FxLib.additive_material()
	add_child(flash)
	add_child(core)
	flash.scale = Vector2(0.6, 0.8)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(1.2, 1.1), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, 0.07).set_delay(0.015)
	tween.tween_property(core, "modulate:a", 0.0, 0.05)

	FxLib.glow_flash(self, Color(_tint.r, _tint.g, _tint.b, 0.85), 70.0 * _power, 0.1)
	FxLib.light_flash(self, _tint, 1.5 * _power, 150.0 * _power, 0.09)
	FxLib.emit(self, {"texture": FxLib.TEX_SPARK, "amount": 6, "lifetime": 0.16, "direction": Vector2.RIGHT, "spread": 16.0,
		"speed": Vector2(260.0, 520.0), "gravity": Vector2(0, 260), "size": Vector2(0.22, 0.4), "align": true,
		"color": Color(1.0, 0.8, 0.4, 1.0), "additive": true, "local": false})
	FxLib.emit(self, {"texture": FxLib.TEX_SMOKE, "amount": 4, "lifetime": 0.75, "direction": Vector2.RIGHT, "spread": 22.0,
		"speed": Vector2(30.0, 90.0), "gravity": Vector2(0, -45), "size": Vector2(0.12, 0.22) * _power, "curve": &"puff",
		"color": Color(0.72, 0.72, 0.68, 0.45), "fade": &"smoke", "damping": Vector2(60, 110), "spin": Vector2(-40, 40)})
	get_tree().create_timer(1.1, false).timeout.connect(queue_free)


func _make_flash_polygon(length: float, width: float, color: Color) -> Polygon2D:
	var polygon: Polygon2D = Polygon2D.new()
	polygon.color = color
	polygon.polygon = PackedVector2Array([
		Vector2(-2, 0),
		Vector2(length * 0.12, -width * 0.8),
		Vector2(length * 0.3, -width),
		Vector2(length * 0.48, -width * 0.32),
		Vector2(length, 0),
		Vector2(length * 0.48, width * 0.32),
		Vector2(length * 0.3, width),
		Vector2(length * 0.12, width * 0.8),
	])
	return polygon
