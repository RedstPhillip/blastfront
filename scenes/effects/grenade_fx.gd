class_name GrenadeFx
extends Node2D

## Visual for a primed grenade: blinking charge with a shrinking danger ring that accelerates its beeps,
## then a full explosion. Purely cosmetic; damage is resolved by gameplay code.

const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const RING_TEXTURE: Texture2D = preload("res://assets/fx/ring.png")

var fuse: float = 0.5
var radius: float = 80.0
var tint: Color = Color(1.0, 0.45, 0.12, 1.0)

var _elapsed: float = 0.0
var _next_beep: float = 0.0
var _core: Sprite2D = null
var _ring: Sprite2D = null


func _ready() -> void:
	z_index = 8
	_ring = Sprite2D.new()
	_ring.texture = RING_TEXTURE
	_ring.material = FxLib.additive_material()
	_ring.modulate = Color(tint.r, tint.g, tint.b, 0.55)
	add_child(_ring)
	_core = Sprite2D.new()
	_core.texture = GLOW_TEXTURE
	_core.material = FxLib.additive_material()
	_core.modulate = tint
	_core.scale = Vector2.ONE * 0.22
	add_child(_core)
	_beep()


func _process(delta: float) -> void:
	_elapsed += delta
	var progress: float = clampf(_elapsed / maxf(fuse, 0.01), 0.0, 1.0)
	var ring_size: float = lerpf(radius * 2.2, radius * 0.4, progress)
	_ring.scale = Vector2.ONE * ring_size / float(RING_TEXTURE.get_width())
	_ring.modulate.a = 0.25 + 0.5 * progress
	var blink: float = 0.5 + 0.5 * sin(_elapsed * lerpf(14.0, 46.0, progress))
	_core.scale = Vector2.ONE * (0.16 + 0.12 * blink + progress * 0.1)
	_core.modulate.a = 0.5 + 0.5 * blink
	if _elapsed >= _next_beep and progress < 0.95:
		_beep()
	if _elapsed >= fuse:
		GameJuice.spawn_explosion(global_position, radius, tint)
		queue_free()


func _beep() -> void:
	var remaining: float = maxf(fuse - _elapsed, 0.0)
	_next_beep = _elapsed + clampf(remaining * 0.35, 0.07, 0.3)
	AudioDirector.play_at(&"grenade_arm", global_position, 0.0, 1.0 + (1.0 - remaining / maxf(fuse, 0.01)) * 0.4)
