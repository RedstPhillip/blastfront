class_name BackdropMesh
extends RefCounted

## Collects flat-shaded triangles for a backdrop layer and commits them as one MeshInstance2D, so a whole
## layer of silhouettes (mountains, ruins, trees) costs a single draw call however many shapes it holds.

var _verts: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()


func is_empty() -> bool:
	return _verts.is_empty()


func tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	tri_colors(a, b, c, color, color, color)


func tri_colors(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_colors.append(ca)
	_colors.append(cb)
	_colors.append(cc)


## A quad a-b-c-d (in order around the outline) in one colour.
func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	quad_colors(a, b, c, d, color, color, color, color)


func quad_colors(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	tri_colors(a, b, c, ca, cb, cc)
	tri_colors(a, c, d, ca, cc, cd)


## An axis-aligned box with a vertical gradient.
func box(rect: Rect2, top: Color, bottom: Color) -> void:
	var a: Vector2 = rect.position
	var b: Vector2 = Vector2(rect.end.x, rect.position.y)
	quad_colors(a, b, rect.end, Vector2(rect.position.x, rect.end.y), top, top, bottom, bottom)


## Any simple polygon in one colour.
func polygon(points: PackedVector2Array, color: Color) -> void:
	polygon_shaded(points, color, color, 0.0, 1.0)


## Any simple polygon with a vertical gradient: `top` at y_top, `bottom` at y_bottom.
func polygon_shaded(points: PackedVector2Array, top: Color, bottom: Color, y_top: float, y_bottom: float) -> void:
	if points.size() < 3:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	var span: float = maxf(y_bottom - y_top, 0.001)
	for index in indices:
		var point: Vector2 = points[index]
		_verts.append(point)
		_colors.append(top.lerp(bottom, clampf((point.y - y_top) / span, 0.0, 1.0)))


## The filled area between a profile (left to right) and a level line below it, shaded top to bottom.
func skirt(profile: PackedVector2Array, floor_y: float, top: Color, bottom: Color, y_top: float) -> void:
	var span: float = maxf(floor_y - y_top, 0.001)
	for index in range(profile.size() - 1):
		var a: Vector2 = profile[index]
		var b: Vector2 = profile[index + 1]
		var ca: Color = top.lerp(bottom, clampf((a.y - y_top) / span, 0.0, 1.0))
		var cb: Color = top.lerp(bottom, clampf((b.y - y_top) / span, 0.0, 1.0))
		quad_colors(a, b, Vector2(b.x, floor_y), Vector2(a.x, floor_y), ca, cb, bottom, bottom)


## A filled ellipse (half circle upwards when `half` is set), as a fan.
func ellipse(center: Vector2, radius: Vector2, color: Color, half: bool = false, steps: int = 14) -> void:
	var sweep: float = PI if half else TAU
	for index in range(steps):
		var a0: float = PI + sweep * float(index) / float(steps)
		var a1: float = PI + sweep * float(index + 1) / float(steps)
		tri(center, center + Vector2(cos(a0), sin(a0)) * radius, center + Vector2(cos(a1), sin(a1)) * radius, color)


func commit(parent: Node, mesh_name: String, material: Material = null) -> MeshInstance2D:
	if _verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance2D = MeshInstance2D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material = material
	parent.add_child(instance)
	_verts = PackedVector2Array()
	_colors = PackedColorArray()
	return instance
