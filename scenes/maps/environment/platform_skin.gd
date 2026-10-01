class_name PlatformSkin
extends Node2D

## Dresses every StaticBody2D polygon in the map: rock shader, silhouette outline, mossy top edges with
## moonlit rim, wind-blown grass, flowers, hanging vines and the odd warm lantern. Grass, vines and lantern
## bodies share one mesh (one draw call); every rock body shares one material so they batch.
## Place this node as the last child of the map root at the origin.

const BODY_SHADER: Shader = preload("res://scenes/maps/environment/platform_body.gdshader")
const GRASS_SHADER: Shader = preload("res://scenes/maps/environment/grass.gdshader")
const LANTERN_GLOW_SHADER: Shader = preload("res://scenes/maps/environment/lantern_glow.gdshader")
const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")
const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/fx/soft_circle.png")
const MAX_LANTERNS: int = 7
const LANTERN_MIN_CHAIN: float = 130.0
const TOP_NORMAL_THRESHOLD: float = -0.55
const BOTTOM_NORMAL_THRESHOLD: float = 0.6
const BLADE_SPACING: float = 3.1
const GEOMETRY_LIGHT_MASK: int = 1 | 4

@export var map_top_y: float = 150.0
@export var map_bottom_y: float = 650.0
@export var high_color: Color = Color(0.105, 0.165, 0.15)
@export var low_color: Color = Color(0.25, 0.37, 0.24)
@export var deep_color: Color = Color(0.045, 0.075, 0.065)
@export var outline_color: Color = Color(0.02, 0.045, 0.04, 0.85)
@export var moss_color: Color = Color(0.29, 0.47, 0.25)
@export var rim_color: Color = Color(0.78, 0.95, 0.66, 0.85)
@export var vine_color: Color = Color(0.13, 0.24, 0.16)
@export var lantern_color: Color = Color(1.0, 0.7, 0.36)
@export var grass_palette: Array[Color] = [
	Color(0.24, 0.44, 0.22),
	Color(0.33, 0.55, 0.27),
	Color(0.42, 0.64, 0.31),
	Color(0.28, 0.5, 0.3),
]
@export var flower_palette: Array[Color] = [
	Color(0.98, 0.93, 0.62),
	Color(0.95, 0.72, 0.82),
	Color(0.82, 0.92, 1.0),
]

var _grass_material: ShaderMaterial = null
var _body_material: ShaderMaterial = null
var _glow_material: ShaderMaterial = null
var _lantern_count: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _verts: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _uvs: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_rng.seed = 90210
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_body_material.set_shader_parameter(&"map_top_y", map_top_y)
	_body_material.set_shader_parameter(&"map_bottom_y", map_bottom_y)
	_body_material.set_shader_parameter(&"high_color", high_color)
	_body_material.set_shader_parameter(&"low_color", low_color)
	_body_material.set_shader_parameter(&"deep_color", deep_color)
	_body_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = LANTERN_GLOW_SHADER
	_build()


func _process(_delta: float) -> void:
	var pushers: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player.is_eliminated() or not player.visible:
			continue
		pushers.append(player.global_position + Vector2(0.0, player.hover_dist))
		if pushers.size() >= 4:
			break
	while pushers.size() < 4:
		pushers.append(Vector2(-100000.0, -100000.0))
	_grass_material.set_shader_parameter(&"pushers", pushers)


func _build() -> void:
	var map_root: Node = get_parent()
	if map_root == null:
		return
	var decorations: Node2D = Node2D.new()
	decorations.name = "Decorations"
	decorations.z_index = 1
	add_child(decorations)
	for body in map_root.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var polygon: Polygon2D = child as Polygon2D
			if polygon == null or polygon.polygon.size() < 3:
				continue
			_skin_polygon(polygon, decorations)
	_commit_mesh(decorations)


func _skin_polygon(polygon: Polygon2D, decorations: Node2D) -> void:
	var world_points: PackedVector2Array = polygon.global_transform * polygon.polygon
	var bounds: Rect2 = _bounds_of(world_points)
	var height: float = maxf(bounds.size.y, 1.0)
	var seed_value: float = _rng.randf()
	var vertex_colors: PackedColorArray = PackedColorArray()
	vertex_colors.resize(world_points.size())
	for index in range(world_points.size()):
		var depth: float = (world_points[index].y - bounds.position.y) / height
		vertex_colors[index] = Color(depth, seed_value, height / 1000.0, 1.0)
	polygon.color = Color.WHITE
	polygon.vertex_colors = vertex_colors
	polygon.material = _body_material
	polygon.light_mask = GEOMETRY_LIGHT_MASK

	var outline: Line2D = _make_line(world_points, outline_color, 2.2)
	outline.closed = true
	outline.z_index = -1
	outline.z_as_relative = true
	decorations.add_child(outline)

	var edges: Array[Dictionary] = _classify_edges(world_points)
	for chain in _chains(edges, &"top"):
		_decorate_top_chain(chain, decorations)
		_maybe_add_lantern(chain, decorations)
	for chain in _chains(edges, &"bottom"):
		_decorate_bottom_chain(chain, bounds)


func _classify_edges(points: PackedVector2Array) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var count: int = points.size()
	for index in range(count):
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % count]
		if a.distance_squared_to(b) < 0.25:
			continue
		var tangent: Vector2 = (b - a).normalized()
		var normal: Vector2 = Vector2(tangent.y, -tangent.x)
		var mid: Vector2 = (a + b) * 0.5
		if Geometry2D.is_point_in_polygon(mid + normal * 1.5, points):
			normal = -normal
		var kind: StringName = &"side"
		if normal.y <= TOP_NORMAL_THRESHOLD:
			kind = &"top"
		elif normal.y >= BOTTOM_NORMAL_THRESHOLD:
			kind = &"bottom"
		edges.append({"a": a, "b": b, "normal": normal, "kind": kind})
	return edges


func _chains(edges: Array[Dictionary], kind: StringName) -> Array:
	var chains: Array = []
	if edges.is_empty():
		return chains
	var start: int = 0
	for index in range(edges.size()):
		if edges[index]["kind"] != kind:
			start = (index + 1) % edges.size()
			break
	var current: Array[Dictionary] = []
	for offset in range(edges.size()):
		var edge: Dictionary = edges[(start + offset) % edges.size()]
		if edge["kind"] == kind:
			if not current.is_empty() and (current.back()["b"] as Vector2).distance_to(edge["a"]) > 1.0:
				chains.append(current)
				current = []
			current.append(edge)
		elif not current.is_empty():
			chains.append(current)
			current = []
	if not current.is_empty():
		chains.append(current)
	return chains


func _decorate_top_chain(chain: Array, decorations: Node2D) -> void:
	var path: PackedVector2Array = PackedVector2Array()
	var rim_path: PackedVector2Array = PackedVector2Array()
	path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 1.2)
	rim_path.append((chain[0]["a"] as Vector2) + (chain[0]["normal"] as Vector2) * 3.4)
	for edge in chain:
		var normal: Vector2 = edge["normal"]
		path.append((edge["b"] as Vector2) + normal * 1.2)
		rim_path.append((edge["b"] as Vector2) + normal * 3.4)
	var moss: Line2D = _make_line(path, moss_color, 6.0)
	decorations.add_child(moss)
	var rim: Line2D = _make_line(rim_path, rim_color, 1.5)
	decorations.add_child(rim)

	var total_length: float = 0.0
	for edge in chain:
		total_length += (edge["a"] as Vector2).distance_to(edge["b"])
	var travelled: float = 0.0
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var tangent: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var distance: float = _rng.randf_range(0.0, BLADE_SPACING)
		while distance < length:
			var along: float = (travelled + distance) / maxf(total_length, 1.0)
			var edge_falloff: float = clampf(minf(along, 1.0 - along) * 8.0, 0.25, 1.0)
			var base: Vector2 = a + tangent * distance + normal * 1.0
			_add_blade(base, normal, tangent, _rng.randf_range(4.0, 11.0) * edge_falloff)
			if _rng.randf() < 0.035:
				_add_flower(base + normal * _rng.randf_range(5.0, 9.0) * edge_falloff)
			distance += BLADE_SPACING * _rng.randf_range(0.7, 1.3)
		travelled += length


## A warm lantern at one end of longer ledges: post and lamp go into the shared mesh, the glow and the
## light pool on the ground are additive sprites that flicker in their shader.
func _maybe_add_lantern(chain: Array, decorations: Node2D) -> void:
	if _lantern_count >= MAX_LANTERNS:
		return
	var start: Vector2 = chain[0]["a"]
	var finish: Vector2 = chain.back()["b"]
	if start.distance_to(finish) < LANTERN_MIN_CHAIN or _rng.randf() > 0.55:
		return
	var at_start: bool = _rng.randf() < 0.5
	var edge: Dictionary = chain[0] if at_start else chain.back()
	if absf((edge["normal"] as Vector2).y) < 0.85:
		return
	var tangent: Vector2 = ((edge["b"] as Vector2) - (edge["a"] as Vector2)).normalized()
	var base: Vector2 = (start + tangent * 16.0) if at_start else (finish - tangent * 16.0)
	_lantern_count += 1
	var post_color: Color = Color(0.06, 0.08, 0.07)
	var top: Vector2 = base + Vector2(0.0, -34.0)
	_push_quad(base + Vector2(-1.3, 1.0), base + Vector2(1.3, 1.0), top + Vector2(1.3, 0.0), top + Vector2(-1.3, 0.0), post_color)
	var arm_end: Vector2 = top + Vector2(8.0 * (1.0 if at_start else -1.0), 0.0)
	_push_quad(top + Vector2(0.0, -1.2), arm_end + Vector2(0.0, -1.2), arm_end + Vector2(0.0, 1.2), top + Vector2(0.0, 1.2), post_color)
	var lamp: Vector2 = arm_end + Vector2(0.0, 8.0)
	_push_quad(lamp + Vector2(-4.4, -6.0), lamp + Vector2(4.4, -6.0), lamp + Vector2(3.6, 6.0), lamp + Vector2(-3.6, 6.0), post_color)
	_push_quad(lamp + Vector2(-2.8, -4.2), lamp + Vector2(2.8, -4.2), lamp + Vector2(2.2, 4.4), lamp + Vector2(-2.2, 4.4), lantern_color.lightened(0.45))
	decorations.add_child(_glow_sprite(GLOW_TEXTURE, lamp, Vector2(1.0, 1.0), Color(lantern_color.r, lantern_color.g, lantern_color.b, 0.85)))
	decorations.add_child(_glow_sprite(SOFT_TEXTURE, base + Vector2(0.0, -2.0), Vector2(2.2, 0.5), Color(lantern_color.r, lantern_color.g, lantern_color.b, 0.38)))


func _glow_sprite(texture: Texture2D, at: Vector2, glow_scale: Vector2, color: Color) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	sprite.scale = glow_scale
	sprite.modulate = color
	sprite.material = _glow_material
	return sprite


func _push_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_push_tri(a, b, c, color, color, color, 0.0, 0.0, 0.0)
	_push_tri(a, c, d, color, color, color, 0.0, 0.0, 0.0)


func _decorate_bottom_chain(chain: Array, bounds: Rect2) -> void:
	if bounds.end.y > map_bottom_y + 40.0:
		return
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var length: float = a.distance_to(b)
		var vine_count: int = int(length / 34.0)
		for index in range(vine_count):
			var t: float = _rng.randf_range(0.08, 0.92)
			_add_vine(a.lerp(b, t) + Vector2(0.0, -1.0), _rng.randf_range(10.0, 34.0))


func _add_blade(base: Vector2, normal: Vector2, tangent: Vector2, height: float) -> void:
	var width: float = _rng.randf_range(2.0, 3.4)
	var lean: float = _rng.randf_range(-2.5, 2.5)
	var color: Color = grass_palette[_rng.randi() % grass_palette.size()]
	var tip_color: Color = color.lightened(0.18)
	_push_tri(
		base - tangent * width * 0.5, base + tangent * width * 0.5, base + normal * height + tangent * lean,
		color, color, tip_color,
		0.0, 0.0, 1.0
	)


func _add_flower(center: Vector2) -> void:
	var color: Color = flower_palette[_rng.randi() % flower_palette.size()]
	var r: float = _rng.randf_range(1.2, 2.0)
	_push_tri(center + Vector2(-r, 0), center + Vector2(0, -r), center + Vector2(r, 0), color, color, color, 0.9, 0.9, 0.9)
	_push_tri(center + Vector2(-r, 0), center + Vector2(r, 0), center + Vector2(0, r), color, color, color, 0.9, 0.9, 0.9)


func _add_vine(root: Vector2, length: float) -> void:
	var segments: int = 5
	var width: float = _rng.randf_range(1.6, 2.6)
	var curl: float = _rng.randf_range(-5.0, 5.0)
	var previous_left: Vector2 = root + Vector2(-width * 0.5, 0.0)
	var previous_right: Vector2 = root + Vector2(width * 0.5, 0.0)
	var previous_t: float = 0.0
	for index in range(1, segments + 1):
		var t: float = float(index) / float(segments)
		var center: Vector2 = root + Vector2(sin(t * 2.4) * curl * t, length * t)
		var half: float = width * 0.5 * (1.0 - t * 0.7)
		var left: Vector2 = center + Vector2(-half, 0.0)
		var right: Vector2 = center + Vector2(half, 0.0)
		var color_a: Color = vine_color.lerp(vine_color.lightened(0.25), previous_t)
		var color_b: Color = vine_color.lerp(vine_color.lightened(0.25), t)
		_push_tri(previous_left, previous_right, right, color_a, color_a, color_b, previous_t, previous_t, t)
		_push_tri(previous_left, right, left, color_a, color_b, color_b, previous_t, t, t)
		if index == segments - 1 and _rng.randf() < 0.5:
			var leaf_color: Color = grass_palette[_rng.randi() % grass_palette.size()]
			_push_tri(center, center + Vector2(4.5, 1.5), center + Vector2(1.5, 4.5), leaf_color, leaf_color, leaf_color, t, t, t)
		previous_left = left
		previous_right = right
		previous_t = t


func _push_tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color, ta: float, tb: float, tc: float) -> void:
	_verts.append_array(PackedVector2Array([a, b, c]))
	_colors.append_array(PackedColorArray([ca, cb, cc]))
	_uvs.append_array(PackedVector2Array([Vector2(0.0, ta), Vector2(0.5, tb), Vector2(1.0, tc)]))


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
	instance.name = "GrassMesh"
	instance.mesh = mesh
	instance.material = _grass_material
	instance.light_mask = GEOMETRY_LIGHT_MASK
	decorations.add_child(instance)


func _make_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line: Line2D = Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.light_mask = GEOMETRY_LIGHT_MASK
	return line


func _bounds_of(points: PackedVector2Array) -> Rect2:
	var rect: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect
