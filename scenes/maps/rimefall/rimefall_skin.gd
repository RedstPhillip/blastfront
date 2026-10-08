class_name RimefallSkin
extends PlatformSkin

## Glacier dressing for Rimefall. Two surfaces that must never be confused: bodies in the ice group are
## glassy blue ice (ice_body.gdshader: fracture lines, bubbles, a glint sweeping along) with a polished
## white top edge and icicles underneath; every other body is dark rock under an even layer of snow (the
## shared soil band, tinted white), with a soft snow cap, little drifts and stones, and icicles under its
## overhangs. All static pieces share one mesh with a plain material.

const ICE_SHADER: Shader = preload("res://scenes/maps/rimefall/ice_body.gdshader")

@export var ice_outline_color: Color = Color(0.06, 0.12, 0.26, 0.9)
@export var ice_edge_color: Color = Color(0.94, 0.99, 1.0, 0.95)
@export var icicle_color: Color = Color(0.7, 0.88, 1.0, 0.9)
@export var drift_color: Color = Color(0.95, 0.97, 1.0)
@export var stone_palette: Array[Color] = [
	Color(0.2, 0.22, 0.28),
	Color(0.28, 0.3, 0.36),
	Color(0.16, 0.17, 0.22),
]

var _ice_material: ShaderMaterial = null


func _ready() -> void:
	_ice_material = ShaderMaterial.new()
	_ice_material.shader = ICE_SHADER
	_ice_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	super._ready()
	set_process(false)


func _process(_delta: float) -> void:
	pass


func _skin_polygon(polygon: Polygon2D, decorations: Node2D) -> void:
	if polygon.get_parent() != null and polygon.get_parent().is_in_group(WorldConditions.ICE_GROUP):
		_skin_ice(polygon, decorations)
	else:
		super._skin_polygon(polygon, decorations)


func _skin_ice(polygon: Polygon2D, decorations: Node2D) -> void:
	var world_points: PackedVector2Array = polygon.global_transform * polygon.polygon
	var bounds: Rect2 = _bounds_of(world_points)
	var height: float = maxf(bounds.size.y, 1.0)
	var seed_value: float = _rng.randf()
	var vertex_colors: PackedColorArray = PackedColorArray()
	vertex_colors.resize(world_points.size())
	for index in range(world_points.size()):
		vertex_colors[index] = Color((world_points[index].y - bounds.position.y) / height, seed_value, 0.0, 1.0)
	polygon.color = Color.WHITE
	polygon.vertex_colors = vertex_colors
	polygon.material = _ice_material
	polygon.light_mask = GEOMETRY_LIGHT_MASK
	var outline: Line2D = _make_line(world_points, ice_outline_color, 1.8)
	outline.closed = true
	outline.z_index = -1
	outline.z_as_relative = true
	decorations.add_child(outline)
	var edges: Array[Dictionary] = _classify_edges(world_points)
	for chain in _chains(edges, &"top"):
		# The polished top: a crisp white edge with a thin cold rim above it.
		var path: PackedVector2Array = PackedVector2Array([(chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 0.6])
		for edge in chain:
			path.append((edge["b"] as Vector2) + (edge["normal"] as Vector2) * 0.6)
		decorations.add_child(_make_line(path, ice_edge_color, 2.4))
		_add_ice_sparkles(chain)
	for chain in _chains(edges, &"bottom"):
		_add_icicles(chain, 16.0, 1.0)


## Glints frozen into the polished top: tiny four-point stars along the edge.
func _add_ice_sparkles(chain: Array) -> void:
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var count: int = int(a.distance_to(b) / 46.0)
		for index in range(count):
			var at: Vector2 = a.lerp(b, _rng.randf_range(0.1, 0.9)) - normal * _rng.randf_range(2.0, 6.0)
			var r: float = _rng.randf_range(1.4, 2.6)
			var color: Color = Color(1.0, 1.0, 1.0, 0.85)
			_push_tri(at + Vector2(-r, 0), at + Vector2(0, -0.5), at + Vector2(r, 0), color, color, color, 0.0, 0.0, 0.0)
			_push_tri(at + Vector2(-r, 0), at + Vector2(r, 0), at + Vector2(0, 0.5), color, color, color, 0.0, 0.0, 0.0)
			_push_tri(at + Vector2(0, -r), at + Vector2(0.5, 0), at + Vector2(0, r), color, color, color, 0.0, 0.0, 0.0)
			_push_tri(at + Vector2(0, -r), at + Vector2(0, r), at + Vector2(-0.5, 0), color, color, color, 0.0, 0.0, 0.0)


func _add_icicles(chain: Array, spacing: float, length_scale: float) -> void:
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var count: int = int(a.distance_to(b) / spacing)
		for index in range(count):
			var root: Vector2 = a.lerp(b, _rng.randf_range(0.06, 0.94)) + Vector2(0.0, -1.5)
			var width: float = _rng.randf_range(2.0, 5.0)
			var length: float = _rng.randf_range(5.0, 18.0) * length_scale
			var tip: Color = Color(icicle_color.r, icicle_color.g, icicle_color.b, 0.35)
			_push_tri(root + Vector2(-width * 0.5, 0.0), root + Vector2(width * 0.5, 0.0), root + Vector2(_rng.randf_range(-1.0, 1.0), length), icicle_color, icicle_color.lightened(0.3), tip, 0.0, 0.0, 0.0)


func _decorate_top_chain(chain: Array, decorations: Node2D) -> void:
	# Snow cap: a soft white line over the snow layer and a faint moonlit rim.
	var path: PackedVector2Array = PackedVector2Array()
	var rim_path: PackedVector2Array = PackedVector2Array()
	path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 1.0)
	rim_path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 3.0)
	for edge in chain:
		var normal: Vector2 = edge["normal"]
		path.append((edge["b"] as Vector2) + normal * 1.0)
		rim_path.append((edge["b"] as Vector2) + normal * 3.0)
	decorations.add_child(_make_line(path, moss_color, 5.0))
	decorations.add_child(_make_line(rim_path, rim_color, 1.2))
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var tangent: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var distance: float = _rng.randf_range(4.0, 14.0)
		while distance < length - 3.0:
			var base: Vector2 = a + tangent * distance
			var roll: float = _rng.randf()
			if roll < 0.18:
				# A wind-shaped drift: a long low mound.
				_push_fan(_mound(base + normal * 0.5, normal, tangent, _rng.randf_range(7.0, 16.0), _rng.randf_range(2.0, 4.0)), drift_color)
			elif roll < 0.26:
				var stone: Color = stone_palette[_rng.randi() % stone_palette.size()]
				var r: float = _rng.randf_range(2.5, 5.0)
				_push_fan(_mound(base + normal * r * 0.3, normal, tangent, r, r * 0.7), stone)
				_push_fan(_mound(base + normal * r * 0.95, normal, tangent, r * 0.8, r * 0.3), drift_color)
			distance += _rng.randf_range(10.0, 26.0)


func _decorate_bottom_chain(chain: Array, bounds: Rect2) -> void:
	if bounds.end.y > map_bottom_y + 40.0:
		return
	_add_icicles(chain, 26.0, 0.8)


## Half-ellipse standing on the surface: `rise` tall along the normal, `half_width` along the tangent.
func _mound(base: Vector2, normal: Vector2, tangent: Vector2, half_width: float, rise: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(7):
		var angle: float = PI * float(index) / 6.0
		points.append(base + tangent * cos(angle) * half_width + normal * sin(angle) * rise)
	return points


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
