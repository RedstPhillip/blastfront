class_name MarsActivity
extends Node2D

## Life in the distance on Mars: a small research outpost with lit windows and a blinking mast, a rover
## crawling along the ridge, dust devils wandering across the plain and now and then a supply rocket
## climbing out of the haze. Everything stands on the silhouette of the layer it belongs to.

const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")
const BEACON_SHADER: Shader = preload("res://scenes/maps/mars/beacon_blink.gdshader")
const DEVIL_SHADER: Shader = preload("res://scenes/maps/mars/dust_devil.gdshader")

@export var ground_path: NodePath
@export var devil_ground_path: NodePath
@export var outpost_x: float = 760.0
@export var rover_range: Vector2 = Vector2(-900.0, 300.0)
@export var devil_range: Vector2 = Vector2(-1500.0, 1500.0)
@export var silhouette_color: Color = Color(0.2, 0.1, 0.08)
@export var window_color: Color = Color(1.0, 0.82, 0.55)

var _ground: MarsBackdrop = null
var _devil_ground: MarsBackdrop = null
var _rover: Node2D = null
var _rover_light: Sprite2D = null
var _rover_x: float = 0.0
var _rover_dir: float = 1.0
var _devils: Array[Dictionary] = []
var _rocket: Node2D = null
var _rocket_trail: Line2D = null
var _rocket_time: float = -1.0
var _next_rocket: float = 14.0
var _pad: Vector2 = Vector2.ZERO
var _blink: ShaderMaterial = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 314
	_ground = get_node_or_null(ground_path) as MarsBackdrop
	_devil_ground = get_node_or_null(devil_ground_path) as MarsBackdrop
	_blink = ShaderMaterial.new()
	_blink.shader = BEACON_SHADER
	_build_outpost.call_deferred()
	_build_rover.call_deferred()
	_build_devils.call_deferred()


func _surface(ground: MarsBackdrop, x: float) -> float:
	return ground.surface_y(x) + ground.position.y if ground != null else 0.0


func _build_outpost() -> void:
	var base: Vector2 = Vector2(outpost_x, _surface(_ground, outpost_x) + 2.0)
	var outpost: Node2D = Node2D.new()
	outpost.position = base
	add_child(outpost)
	# Two habitat domes, a connecting tube, a mast with a blinking light and a solar array.
	_add_poly(outpost, _dome(Vector2(0.0, 0.0), 26.0, 18.0), silhouette_color)
	_add_poly(outpost, _dome(Vector2(42.0, 0.0), 17.0, 12.0), silhouette_color)
	_add_poly(outpost, PackedVector2Array([Vector2(20, -6), Vector2(30, -6), Vector2(30, 0), Vector2(20, 0)]), silhouette_color)
	_add_poly(outpost, PackedVector2Array([Vector2(-44, 0), Vector2(-41, 0), Vector2(-41, -58), Vector2(-44, -58)]), silhouette_color)
	_add_poly(outpost, PackedVector2Array([Vector2(-52, -46), Vector2(-33, -46), Vector2(-33, -44), Vector2(-52, -44)]), silhouette_color)
	for panel in range(3):
		var x: float = 64.0 + float(panel) * 13.0
		_add_poly(outpost, PackedVector2Array([Vector2(x, -9), Vector2(x + 11, -12), Vector2(x + 11, -10), Vector2(x, -7)]), Color(0.16, 0.14, 0.2))
		_add_poly(outpost, PackedVector2Array([Vector2(x + 5, -8), Vector2(x + 6, -8), Vector2(x + 6, 0), Vector2(x + 5, 0)]), silhouette_color)
	for window in range(4):
		_add_poly(outpost, PackedVector2Array([Vector2(-14 + window * 7, -7), Vector2(-10 + window * 7, -7), Vector2(-10 + window * 7, -4), Vector2(-14 + window * 7, -4)]), window_color)
	_add_glow(outpost, Vector2(0.0, -6.0), GLOW_TEXTURE, 1.2, Color(window_color.r, window_color.g, window_color.b, 0.18), null)
	_add_glow(outpost, Vector2(-42.5, -60.0), GLOW_TEXTURE, 0.42, Color(1.0, 0.25, 0.18, 0.9), _blink)
	_add_glow(outpost, Vector2(-42.5, -60.0), SOFT_TEXTURE, 0.08, Color(1.0, 0.8, 0.7, 1.0), _blink)
	var sock: WindPennant = WindPennant.new()
	sock.anchors = PackedVector2Array([Vector2(-42.5, -54.0)])
	sock.length = 12.0
	sock.width = 4.0
	sock.cloth_color = silhouette_color.lerp(Color(1.0, 0.5, 0.2), 0.45)
	outpost.add_child(sock)
	_pad = base + Vector2(130.0, 0.0)
	_pad.y = _surface(_ground, _pad.x)
	var tower: Node2D = Node2D.new()
	tower.position = _pad
	add_child(tower)
	_add_poly(tower, PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(10, -4), Vector2(-10, -4)]), silhouette_color)
	_add_poly(tower, PackedVector2Array([Vector2(8, -4), Vector2(11, -4), Vector2(11, -40), Vector2(8, -40)]), silhouette_color)
	_add_glow(tower, Vector2(9.5, -42.0), GLOW_TEXTURE, 0.3, Color(1.0, 0.85, 0.4, 0.8), _blink)


func _build_rover() -> void:
	_rover = Node2D.new()
	add_child(_rover)
	_add_poly(_rover, PackedVector2Array([Vector2(-9, -9), Vector2(8, -9), Vector2(10, -5), Vector2(-10, -5)]), silhouette_color)
	_add_poly(_rover, PackedVector2Array([Vector2(-2, -9), Vector2(0, -9), Vector2(0, -16), Vector2(-2, -16)]), silhouette_color)
	_add_poly(_rover, PackedVector2Array([Vector2(-5, -17), Vector2(3, -17), Vector2(3, -15), Vector2(-5, -15)]), silhouette_color)
	for wheel in [-7.0, 0.0, 7.0]:
		var w: Polygon2D = _add_poly(_rover, _circle(Vector2(wheel, -3.0), 2.6, 8), silhouette_color)
		w.name = "Wheel"
	_rover_light = _add_glow(_rover, Vector2(9.0, -8.0), GLOW_TEXTURE, 0.22, Color(0.75, 0.9, 1.0, 0.85), null)
	_rover_x = lerpf(rover_range.x, rover_range.y, 0.3)


func _build_devils() -> void:
	for index in range(3):
		var rect: ColorRect = ColorRect.new()
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = DEVIL_SHADER
		material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
		material.set_shader_parameter(&"spin", _rng.randf_range(1.2, 2.2))
		material.set_shader_parameter(&"strength", _rng.randf_range(0.4, 0.62))
		rect.material = material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var height: float = _rng.randf_range(150.0, 260.0)
		rect.size = Vector2(height * 0.32, height)
		add_child(rect)
		var devil: Dictionary = {
			"node": rect,
			"x": lerpf(devil_range.x, devil_range.y, _rng.randf()),
			"speed": _rng.randf_range(10.0, 22.0) * (1.0 if _rng.randf() > 0.4 else -1.0),
			"life": _rng.randf_range(0.0, 1.0),
			"duration": _rng.randf_range(26.0, 48.0),
		}
		_devils.append(devil)


func _process(delta: float) -> void:
	_update_rover(delta)
	_update_devils(delta)
	_update_rocket(delta)


func _update_rover(delta: float) -> void:
	if _rover == null:
		return
	_rover_x += _rover_dir * 7.0 * delta
	if _rover_x > rover_range.y:
		_rover_dir = -1.0
	elif _rover_x < rover_range.x:
		_rover_dir = 1.0
	var y: float = _surface(_ground, _rover_x)
	var ahead: float = _surface(_ground, _rover_x + 6.0)
	_rover.position = Vector2(_rover_x, y + 1.0)
	_rover.rotation = atan2(ahead - y, 6.0) * 0.8
	_rover.scale = Vector2(_rover_dir, 1.0)


func _update_devils(delta: float) -> void:
	for devil in _devils:
		var rect: ColorRect = devil["node"]
		# Storm winds drag the dust devils along with them.
		devil["x"] = float(devil["x"]) + (float(devil["speed"]) + WorldConditions.wind.x * 0.35) * delta
		devil["life"] = float(devil["life"]) + delta / float(devil["duration"])
		if float(devil["life"]) >= 1.0:
			devil["life"] = 0.0
			devil["x"] = lerpf(devil_range.x, devil_range.y, _rng.randf())
			devil["duration"] = _rng.randf_range(26.0, 48.0)
		var life: float = float(devil["life"])
		var x: float = float(devil["x"])
		rect.position = Vector2(x - rect.size.x * 0.5, _surface(_devil_ground, x) - rect.size.y + 6.0)
		rect.modulate.a = smoothstep(0.0, 0.18, life) * (1.0 - smoothstep(0.78, 1.0, life))


func _update_rocket(delta: float) -> void:
	if _rocket_time < 0.0:
		_next_rocket -= delta
		if _next_rocket <= 0.0 and _pad != Vector2.ZERO:
			_launch_rocket()
		return
	_rocket_time += delta
	var t: float = _rocket_time
	var height: float = 18.0 * t * t + 6.0 * t
	var drift: float = t * t * 2.2
	_rocket.position = _pad + Vector2(drift, -40.0 - height)
	if int(t * 20.0) != _rocket_trail.get_point_count():
		_rocket_trail.add_point(_rocket.position)
	_rocket.modulate.a = 1.0 - smoothstep(9.0, 13.0, t)
	_rocket_trail.modulate.a = 1.0 - smoothstep(10.0, 16.0, t)
	if t > 16.0:
		_rocket.queue_free()
		_rocket_trail.queue_free()
		_rocket_time = -1.0
		_next_rocket = _rng.randf_range(38.0, 60.0)


func _launch_rocket() -> void:
	_rocket = Node2D.new()
	add_child(_rocket)
	_add_poly(_rocket, PackedVector2Array([Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(1.5, -8), Vector2(0, -11), Vector2(-1.5, -8)]), Color(0.85, 0.82, 0.78))
	_add_glow(_rocket, Vector2(0.0, 2.0), GLOW_TEXTURE, 0.35, Color(1.0, 0.75, 0.4, 0.95), null)
	_add_glow(_rocket, Vector2(0.0, 2.0), SOFT_TEXTURE, 0.06, Color(1.0, 0.95, 0.85, 1.0), null)
	_rocket_trail = Line2D.new()
	_rocket_trail.width = 3.0
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(0.95, 0.85, 0.75, 0.0), Color(0.95, 0.85, 0.75, 0.35)])
	_rocket_trail.gradient = gradient
	_rocket_trail.antialiased = true
	add_child(_rocket_trail)
	move_child(_rocket_trail, 0)
	_rocket_time = 0.0


func _dome(center: Vector2, radius: float, height: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(13):
		var angle: float = PI * float(index) / 12.0
		points.append(center + Vector2(-cos(angle) * radius, -sin(angle) * height))
	return points


func _circle(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(sides):
		var angle: float = TAU * float(index) / float(sides)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _add_poly(parent: Node2D, points: PackedVector2Array, color: Color) -> Polygon2D:
	var polygon: Polygon2D = Polygon2D.new()
	polygon.polygon = points
	polygon.color = color
	parent.add_child(polygon)
	return polygon


func _add_glow(parent: Node2D, at: Vector2, texture: Texture2D, size: float, color: Color, material: Material) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	sprite.scale = Vector2.ONE * size
	sprite.modulate = color
	if material != null:
		sprite.material = material
	else:
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = additive
	parent.add_child(sprite)
	return sprite
