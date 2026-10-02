class_name MarsSkin
extends PlatformSkin

## Desert dressing for the Mars world, on top of the shared rock/soil build: a fine dust rim on every
## walkable edge, scattered pebbles and basalt rocks with little wind-blown dust drifts, clusters of tiny
## dark spherules, rock drips under overhangs and blinking survey beacons on the long ledges. All static
## pieces share one mesh with a plain material.

const BEACON_SHADER: Shader = preload("res://scenes/maps/mars/beacon_blink.gdshader")
const MAX_BEACONS: int = 5
const BEACON_MIN_CHAIN: float = 150.0

@export var pebble_palette: Array[Color] = [
	Color(0.52, 0.26, 0.16),
	Color(0.62, 0.33, 0.2),
	Color(0.42, 0.21, 0.14),
	Color(0.3, 0.17, 0.13),
]
@export var basalt_color: Color = Color(0.2, 0.15, 0.14)
@export var drift_color: Color = Color(0.9, 0.6, 0.38)
@export var beacon_color: Color = Color(1.0, 0.25, 0.18)

var _beacon_count: int = 0
var _beacon_material: ShaderMaterial = null


func _ready() -> void:
	_beacon_material = ShaderMaterial.new()
	_beacon_material.shader = BEACON_SHADER
	_rng.seed = 4242
	super._ready()
	set_process(false)


func _process(_delta: float) -> void:
	pass


func _decorate_top_chain(chain: Array, decorations: Node2D) -> void:
	var path: PackedVector2Array = PackedVector2Array()
	var rim_path: PackedVector2Array = PackedVector2Array()
	path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 0.8)
	rim_path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 2.2)
	for edge in chain:
		var normal: Vector2 = edge["normal"]
		path.append((edge["b"] as Vector2) + normal * 0.8)
		rim_path.append((edge["b"] as Vector2) + normal * 2.2)
	decorations.add_child(_make_line(path, moss_color, 4.0))
	decorations.add_child(_make_line(rim_path, rim_color, 1.2))

	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var tangent: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var distance: float = _rng.randf_range(2.0, 10.0)
		while distance < length - 2.0:
			var base: Vector2 = a + tangent * distance
			var roll: float = _rng.randf()
			if roll < 0.1:
				_add_rock(base, normal, tangent, _rng.randf_range(4.5, 9.5))
				if _rng.randf() < 0.5:
					_add_rock(base + tangent * _rng.randf_range(6.0, 11.0), normal, tangent, _rng.randf_range(2.5, 4.5))
			elif roll < 0.12:
				_add_spherules(base, normal, tangent)
			elif roll < 0.6:
				_add_pebble(base, normal, tangent, _rng.randf_range(1.0, 2.4))
			distance += _rng.randf_range(5.0, 12.0)


func _add_rock(base: Vector2, normal: Vector2, tangent: Vector2, radius: float) -> void:
	var color: Color = basalt_color.lerp(pebble_palette[_rng.randi() % pebble_palette.size()], _rng.randf_range(0.0, 0.7))
	var center: Vector2 = base + normal * radius * 0.42
	var points: PackedVector2Array = _blob(center, normal, tangent, radius, 0.62)
	# Wind-blown dust piles up on the windward side.
	var drift_center: Vector2 = base - tangent * radius * 0.9 + normal * 0.6
	_push_fan(_blob(drift_center, normal, tangent, radius * 0.9, 0.22), drift_color.darkened(0.08))
	_push_fan(_scaled(points, center, 1.0 + 1.6 / radius), outline_color)
	_push_fan(points, color)
	var cap: PackedVector2Array = PackedVector2Array()
	for point in points:
		if (point - center).dot(normal) > -radius * 0.05:
			cap.append(center + (point - center) * 0.78 + normal * radius * 0.08)
	if cap.size() >= 3:
		_push_fan(cap, color.lightened(0.16))


func _add_pebble(base: Vector2, normal: Vector2, tangent: Vector2, radius: float) -> void:
	var color: Color = pebble_palette[_rng.randi() % pebble_palette.size()]
	_push_fan(_blob(base + normal * radius * 0.35, normal, tangent, radius, 0.6), color.lightened(_rng.randf_range(-0.05, 0.12)))


## Hematite "blueberries": a handful of tiny dark beads half sunk into the dust.
func _add_spherules(base: Vector2, normal: Vector2, tangent: Vector2) -> void:
	for index in range(_rng.randi_range(3, 6)):
		var at: Vector2 = base + tangent * _rng.randf_range(-6.0, 6.0) + normal * _rng.randf_range(0.2, 1.2)
		_push_fan(_blob(at, normal, tangent, _rng.randf_range(0.7, 1.2), 1.0, 6), Color(0.18, 0.15, 0.17))


func _maybe_add_lantern(chain: Array, decorations: Node2D) -> void:
	if _beacon_count >= MAX_BEACONS:
		return
	var start: Vector2 = chain[0]["a"]
	var finish: Vector2 = chain.back()["b"]
	if start.distance_to(finish) < BEACON_MIN_CHAIN or _rng.randf() > 0.7:
		return
	var at_start: bool = _rng.randf() < 0.5
	var edge: Dictionary = chain[0] if at_start else chain.back()
	if absf((edge["normal"] as Vector2).y) < 0.9:
		return
	var tangent: Vector2 = ((edge["b"] as Vector2) - (edge["a"] as Vector2)).normalized()
	var base: Vector2 = (start + tangent * 22.0) if at_start else (finish - tangent * 22.0)
	_beacon_count += 1
	var metal: Color = Color(0.11, 0.1, 0.11)
	var top: Vector2 = base + Vector2(0.0, -26.0)
	_push_quad(base + Vector2(-4.0, 1.0), base + Vector2(4.0, 1.0), base + Vector2(2.5, -3.0), base + Vector2(-2.5, -3.0), metal)
	_push_quad(base + Vector2(-1.0, -2.0), base + Vector2(1.0, -2.0), top + Vector2(1.0, 0.0), top + Vector2(-1.0, 0.0), metal)
	for stripe in range(3):
		var y: float = -8.0 - float(stripe) * 6.0
		_push_quad(base + Vector2(-1.4, y), base + Vector2(1.4, y), base + Vector2(1.4, y - 2.6), base + Vector2(-1.4, y - 2.6), Color(0.86, 0.84, 0.8))
	_push_quad(top + Vector2(-2.6, -4.0), top + Vector2(2.6, -4.0), top + Vector2(2.6, 0.5), top + Vector2(-2.6, 0.5), metal)
	_push_quad(top + Vector2(-1.5, -3.2), top + Vector2(1.5, -3.2), top + Vector2(1.5, -0.4), top + Vector2(-1.5, -0.4), beacon_color.lightened(0.3))
	var light: Vector2 = top + Vector2(0.0, -1.8)
	decorations.add_child(_beacon_sprite(GLOW_TEXTURE, light, 0.55, Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.95)))
	decorations.add_child(_beacon_sprite(SOFT_TEXTURE, light, 0.12, Color(1.0, 0.8, 0.7, 1.0)))


func _beacon_sprite(texture: Texture2D, at: Vector2, size: float, color: Color) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	sprite.scale = Vector2.ONE * size
	sprite.modulate = color
	sprite.material = _beacon_material
	return sprite


func _decorate_bottom_chain(chain: Array, bounds: Rect2) -> void:
	if bounds.end.y > map_bottom_y + 40.0:
		return
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var count: int = int(a.distance_to(b) / 22.0)
		for index in range(count):
			var root: Vector2 = a.lerp(b, _rng.randf_range(0.08, 0.92)) + Vector2(0.0, -1.0)
			var width: float = _rng.randf_range(2.5, 6.0)
			var length: float = _rng.randf_range(4.0, 13.0)
			var color: Color = high_color.darkened(_rng.randf_range(0.1, 0.35))
			_push_tri(root + Vector2(-width * 0.5, 0.0), root + Vector2(width * 0.5, 0.0), root + Vector2(_rng.randf_range(-1.5, 1.5), length), color, color, color.darkened(0.3), 0.0, 0.0, 0.0)


func _blob(center: Vector2, normal: Vector2, tangent: Vector2, radius: float, flatten: float, count: int = 0) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var sides: int = count if count > 0 else _rng.randi_range(5, 8)
	var offset: float = _rng.randf() * TAU
	for index in range(sides):
		var angle: float = offset + TAU * float(index) / float(sides)
		var r: float = radius * _rng.randf_range(0.78, 1.08)
		points.append(center + tangent * cos(angle) * r + normal * sin(angle) * r * flatten)
	return points


func _scaled(points: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in points:
		result.append(center + (point - center) * factor)
	return result


func _push_fan(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var center: Vector2 = Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())
	for index in range(points.size()):
		_push_tri(center, points[index], points[(index + 1) % points.size()], color, color, color, 0.0, 0.0, 0.0)


func _commit_mesh(decorations: Node2D) -> void:
	if _verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance2D = MeshInstance2D.new()
	instance.name = "DetailMesh"
	instance.mesh = mesh
	instance.light_mask = GEOMETRY_LIGHT_MASK
	decorations.add_child(instance)
