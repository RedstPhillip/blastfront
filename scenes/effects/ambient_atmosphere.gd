extends Node2D

@onready var _back_motes: CPUParticles2D = $BackMotes
@onready var _front_motes: CPUParticles2D = $FrontMotes
@onready var _light_band: Polygon2D = $LightBand

var _time: float = 0.0


func _ready() -> void:
	_back_motes.emitting = true
	_front_motes.emitting = true


func _process(delta: float) -> void:
	_time += delta
	_back_motes.position.x = sin(_time * 0.18) * 18.0
	_front_motes.position.x = cos(_time * 0.24) * 28.0
	_light_band.modulate.a = 0.10 + sin(_time * 0.45) * 0.025
