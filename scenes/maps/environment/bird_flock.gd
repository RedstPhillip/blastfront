class_name BirdFlock
extends Node2D

## Occasional distant flocks crossing the sky to keep the backdrop alive.

@export var sky_band: Vector2 = Vector2(-430.0, -200.0)
@export var span: float = 1300.0
@export var interval_range: Vector2 = Vector2(14.0, 30.0)
@export var color: Color = Color(0.07, 0.15, 0.13, 0.75)

var _birds: Array[Dictionary] = []
var _cooldown: float = 4.0
var _time: float = 0.0
var _drawn_birds: bool = false


func _process(delta: float) -> void:
	_time += delta
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = randf_range(interval_range.x, interval_range.y)
		_spawn_flock()
	var index: int = _birds.size() - 1
	while index >= 0:
		var bird: Dictionary = _birds[index]
		bird["pos"] = (bird["pos"] as Vector2) + (bird["vel"] as Vector2) * delta
		if absf((bird["pos"] as Vector2).x) > span * 0.5 + 200.0:
			_birds.remove_at(index)
		index -= 1
	if not _birds.is_empty() or _drawn_birds:
		queue_redraw()
	_drawn_birds = not _birds.is_empty()


func _spawn_flock() -> void:
	var direction: float = 1.0 if randf() > 0.5 else -1.0
	var origin: Vector2 = Vector2(-direction * (span * 0.5 + 120.0), randf_range(sky_band.x, sky_band.y))
	var speed: float = randf_range(38.0, 60.0)
	var flock_size: int = randi_range(3, 7)
	for index in range(flock_size):
		var row: int = (index + 1) / 2
		var side: float = -1.0 if index % 2 == 0 else 1.0
		_birds.append({
			"pos": origin + Vector2(-direction * row * 16.0, side * row * 9.0 + randf_range(-3.0, 3.0)),
			"vel": Vector2(direction * speed * randf_range(0.95, 1.05), randf_range(-3.0, 3.0)),
			"phase": randf() * TAU,
			"size": randf_range(4.0, 6.5),
		})


func _draw() -> void:
	for bird in _birds:
		var pos: Vector2 = bird["pos"]
		var size: float = bird["size"]
		var flap: float = sin(_time * 9.0 + float(bird["phase"]))
		var wing_y: float = -flap * size * 0.7
		draw_polyline(PackedVector2Array([
			pos + Vector2(-size, wing_y),
			pos + Vector2(-size * 0.35, -wing_y * 0.2 - 0.5),
			pos,
			pos + Vector2(size * 0.35, -wing_y * 0.2 - 0.5),
			pos + Vector2(size, wing_y),
		]), color, 1.4, true)
