class_name Searchlight
extends Node2D

## Slowly sweeping light beam mounted on a distant watchtower.

const CONE_TEXTURE: Texture2D = preload("res://assets/fx/light_cone.png")
const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")

@export var sweep_degrees: float = 32.0
@export var sweep_speed: float = 0.22
@export var base_angle_degrees: float = 0.0
@export var phase: float = 0.0
@export var beam_length: float = 760.0
@export var beam_width: float = 1.4
@export var color: Color = Color(0.86, 1.0, 0.86, 0.11)

var _beam: Sprite2D = null
var _time: float = 0.0


func _ready() -> void:
	_beam = Sprite2D.new()
	_beam.texture = CONE_TEXTURE
	_beam.material = FxLib.additive_material()
	_beam.centered = true
	_beam.offset = Vector2(0.0, float(CONE_TEXTURE.get_height()) * 0.5)
	_beam.scale = Vector2(beam_width, beam_length / float(CONE_TEXTURE.get_height()))
	_beam.modulate = color
	add_child(_beam)
	var lamp: Sprite2D = Sprite2D.new()
	lamp.texture = GLOW_TEXTURE
	lamp.material = FxLib.additive_material()
	lamp.scale = Vector2.ONE * 0.22
	lamp.modulate = Color(color.r, color.g, color.b, 0.55)
	add_child(lamp)
	_time = phase


func _process(delta: float) -> void:
	_time += delta
	var sweep: float = sin(_time * sweep_speed * TAU * 0.25) * deg_to_rad(sweep_degrees)
	_beam.rotation = PI + deg_to_rad(base_angle_degrees) + sweep
	_beam.modulate.a = color.a * (0.85 + 0.15 * sin(_time * 3.1 + phase))
