class_name SkyDressing
extends Node2D

## Crepuscular rays fanning out of the sunset and a few slow cloud banks. Rays breathe in their shader
## (no per-frame CPU work); clouds drift by moving a handful of sprites.

const RAY_TEXTURE: Texture2D = preload("res://assets/fx/light_ray.png")
const CLOUD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/fx/cloud_0.png"),
	preload("res://assets/fx/cloud_1.png"),
	preload("res://assets/fx/cloud_2.png"),
]
const RAY_SHADER: Shader = preload("res://scenes/maps/environment/sky_ray.gdshader")

@export var sun_position: Vector2 = Vector2(-6.0, -95.0)
@export var ray_color: Color = Color(1.0, 0.93, 0.7, 0.085)
@export var ray_count: int = 7
@export var cloud_band: Vector2 = Vector2(-470.0, -250.0)
@export var cloud_span: float = 2600.0
@export var cloud_color: Color = Color(0.32, 0.47, 0.42, 0.55)
@export var cloud_count: int = 6

var _clouds: Array[Sprite2D] = []
var _cloud_speeds: Array[float] = []


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4711
	var ray_material: ShaderMaterial = ShaderMaterial.new()
	ray_material.shader = RAY_SHADER
	for index in range(ray_count):
		var ray: Sprite2D = Sprite2D.new()
		ray.texture = RAY_TEXTURE
		ray.centered = false
		ray.offset = Vector2(-RAY_TEXTURE.get_width() * 0.5, -RAY_TEXTURE.get_height())
		ray.position = sun_position
		var spread: float = lerpf(-1.25, 1.25, (float(index) + rng.randf_range(-0.3, 0.3)) / maxf(float(ray_count - 1), 1.0))
		ray.rotation = spread
		var length: float = rng.randf_range(1.5, 2.3)
		ray.scale = Vector2(rng.randf_range(0.9, 2.0), length)
		ray.modulate = Color(ray_color.r, ray_color.g, ray_color.b, ray_color.a * rng.randf_range(0.6, 1.2))
		ray.material = ray_material
		add_child(ray)
	for index in range(cloud_count):
		var cloud: Sprite2D = Sprite2D.new()
		cloud.texture = CLOUD_TEXTURES[index % CLOUD_TEXTURES.size()]
		cloud.position = Vector2(rng.randf_range(-cloud_span * 0.5, cloud_span * 0.5), rng.randf_range(cloud_band.x, cloud_band.y))
		var size_factor: float = rng.randf_range(0.9, 1.8)
		cloud.scale = Vector2(size_factor * (1.0 if rng.randf() > 0.5 else -1.0), size_factor * rng.randf_range(0.7, 1.0))
		var depth_tint: float = clampf((cloud.position.y - cloud_band.x) / maxf(cloud_band.y - cloud_band.x, 1.0), 0.0, 1.0)
		cloud.modulate = Color(cloud_color.r, cloud_color.g, cloud_color.b, cloud_color.a * lerpf(0.55, 1.0, depth_tint))
		add_child(cloud)
		_clouds.append(cloud)
		_cloud_speeds.append(rng.randf_range(4.0, 11.0))


func _process(delta: float) -> void:
	var half_span: float = cloud_span * 0.5 + 300.0
	for index in range(_clouds.size()):
		var cloud: Sprite2D = _clouds[index]
		cloud.position.x += _cloud_speeds[index] * delta
		if cloud.position.x > half_span:
			cloud.position.x = -half_span
