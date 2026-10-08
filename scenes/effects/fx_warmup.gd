class_name FxWarmup
extends Node2D

## Draws every one-shot effect once, almost fully transparent, while the scene transition still covers
## the screen. Shader variants, particle buffers, gradient/curve caches and glyphs are then ready before
## the first shot, so the first hit, explosion or pause never stalls a frame.

const BURST_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/burst_effect.tscn")
const MUZZLE_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/muzzle_effect.tscn")
const PAUSE_BLUR_SHADER: Shader = preload("res://scenes/menus/pause_blur.gdshader")
const BURST_KINDS: Array[StringName] = [
	&"run_dust", &"wall_dust", &"jump", &"land", &"hit", &"hit_heavy", &"impact", &"block", &"reflect",
	&"freeze", &"shock", &"poison", &"spawn", &"death", &"explosion", &"capture", &"border",
	&"ice_spray", &"splash", &"ripple",
]
const FRAMES_ALIVE: int = 4

var _frames: int = 0


static func run(world: Node2D, at: Vector2) -> void:
	var warmup: FxWarmup = FxWarmup.new()
	warmup.name = "FxWarmup"
	warmup.global_position = at
	world.add_child(warmup)


func _ready() -> void:
	modulate = Color(1.0, 1.0, 1.0, 0.02)
	z_index = 40
	for kind in BURST_KINDS:
		var burst: Node2D = BURST_EFFECT_SCENE.instantiate() as Node2D
		burst.configure(kind, Vector2.UP, Color.WHITE, 1.0)
		add_child(burst)
	var muzzle: Node2D = MUZZLE_EFFECT_SCENE.instantiate() as Node2D
	muzzle.configure(Vector2.RIGHT, Color(1.0, 0.82, 0.38), 1.0)
	add_child(muzzle)
	var casing: ShellCasing = ShellCasing.new()
	casing.launch(Vector2.UP)
	add_child(casing)
	var number: Label = Label.new()
	number.text = "0123456789+"
	GameJuice.style_damage_label(number, 30, Color(1.0, 0.3, 0.3), false)
	add_child(number)
	var blur: ColorRect = ColorRect.new()
	blur.size = Vector2(8.0, 8.0)
	var blur_material: ShaderMaterial = ShaderMaterial.new()
	blur_material.shader = PAUSE_BLUR_SHADER
	blur.material = blur_material
	add_child(blur)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > FRAMES_ALIVE:
		queue_free()
