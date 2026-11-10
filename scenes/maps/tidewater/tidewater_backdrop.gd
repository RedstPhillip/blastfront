class_name TidewaterBackdrop
extends Node2D

## The drowned coast behind Tidewater, one node per parallax layer. FAR: hazy headlands on the horizon with
## a lighthouse. MID: what is left of the temple city standing in the sea (colonnades, a temple front, the
## broken run of an aqueduct), each with its reflection and a line of foam at the waterline. NEAR: dark
## rocks and the darker water close to the ruins. Every layer is one mesh, built once.

enum Kind { FAR, MID, NEAR }

const GLOW_TEXTURE: Texture2D = preload("res://assets/fx/glow.png")
const LAMP_SHADER: Shader = preload("res://scenes/maps/tidewater/lighthouse_lamp.gdshader")

@export var kind: Kind = Kind.MID
@export var span: float = 4200.0
## Local y of the sea surface this layer stands in.
@export var waterline: float = 68.0
## Local x of the moon: faces turned to it get a lit rim.
@export var moon_x: float = -430.0
@export var top_color: Color = Color(0.045, 0.12, 0.155)
@export var base_color: Color = Color(0.075, 0.175, 0.21)
@export var rim_color: Color = Color(0.52, 0.8, 0.78, 0.5)
@export var reflection_color: Color = Color(0.015, 0.07, 0.095, 0.5)
@export var foam_color: Color = Color(0.78, 0.96, 0.92, 0.3)
@export var water_color: Color = Color(0.025, 0.1, 0.135)
@export var lamp_color: Color = Color(1.0, 0.86, 0.58)
@export var seed_value: int = 5

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _mesh: BackdropMesh = BackdropMesh.new()
var _mirror: BackdropMesh = BackdropMesh.new()
var _top_y: float = 0.0
## Lights and other nodes that sit on top of the mesh.
var _extras: Array[Node] = []


func _ready() -> void:
	_rng.seed = seed_value
	match kind:
		Kind.FAR:
			_build_far()
		Kind.MID:
			_build_mid()
		Kind.NEAR:
			_build_near()
	_mirror.commit(self, "Reflections")
	_mesh.commit(self, "Silhouettes")
	for extra in _extras:
		add_child(extra)


# --- Layers -------------------------------------------------------------------------------------------------

func _build_far() -> void:
	_top_y = waterline - 70.0
	var islands: Array = [
		{"x": -1500.0, "w": 520.0, "h": 34.0}, {"x": -820.0, "w": 300.0, "h": 22.0},
		{"x": 520.0, "w": 620.0, "h": 46.0}, {"x": 1560.0, "w": 420.0, "h": 28.0},
	]
	for island in islands:
		_headland(float(island["x"]), float(island["w"]), float(island["h"]))
	# Sea stacks off the big headland.
	for offset in [-350.0, -396.0, 372.0]:
		var x: float = 520.0 + float(offset)
		var h: float = _rng.randf_range(10.0, 20.0)
		_shape(PackedVector2Array([
			Vector2(x - 7.0, waterline), Vector2(x - 4.0, waterline - h * 0.7), Vector2(x - 1.0, waterline - h),
			Vector2(x + 3.0, waterline - h * 0.85), Vector2(x + 6.0, waterline),
		]))
	_lighthouse(Vector2(640.0, waterline - 43.0), 1.0)


func _build_mid() -> void:
	_top_y = waterline - 180.0
	_aqueduct(-1720.0, 6, 118.0, [4])
	_colonnade(-930.0, 6, 142.0, [true, true, true, true, false, false], 3)
	_stump(-470.0, 26.0)
	_stump(-392.0, 14.0)
	_rubble(-430.0, 70.0)
	_leaning_column(-150.0, 112.0)
	_rubble(-120.0, 90.0)
	_temple(300.0, 6, 168.0)
	_colonnade(860.0, 4, 120.0, [true, false, true, false], 0)
	_arch_fragment(1010.0, 104.0)
	_aqueduct(1300.0, 5, 112.0, [1, 2])


func _build_near() -> void:
	_top_y = waterline - 70.0
	# The darker water close to the ruins, with a soft upper edge and a broken line of foam.
	var left: float = -span * 0.5
	var right: float = span * 0.5
	var clear: Color = Color(water_color.r, water_color.g, water_color.b, 0.0)
	_mesh.quad_colors(Vector2(left, waterline - 70.0), Vector2(right, waterline - 70.0), Vector2(right, waterline + 30.0), Vector2(left, waterline + 30.0), clear, clear, water_color, water_color)
	_mesh.box(Rect2(left, waterline + 30.0, span, 1400.0), water_color, water_color.darkened(0.45))
	var x: float = left + _rng.randf_range(40.0, 160.0)
	while x < right:
		var width: float = _rng.randf_range(34.0, 96.0)
		var height: float = _rng.randf_range(18.0, 58.0)
		_rock(x, width, height)
		x += width + _rng.randf_range(90.0, 330.0)


# --- Pieces -------------------------------------------------------------------------------------------------

## A low island: a smooth hump with a little roughness, its far side fading into the haze.
func _headland(center: float, width: float, height: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 28
	var phase: float = _rng.randf() * TAU
	points.append(Vector2(center - width * 0.5, waterline))
	for index in range(1, steps):
		var t: float = float(index) / float(steps)
		var x: float = center + (t - 0.5) * width
		var hump: float = pow(sin(PI * t), 0.8) * (0.72 + 0.28 * sin(t * 9.0 + phase)) + sin(t * 31.0 + phase * 2.0) * 0.04
		points.append(Vector2(x, waterline - maxf(hump, 0.02) * height))
	points.append(Vector2(center + width * 0.5, waterline))
	_shape(points)


func _lighthouse(top: Vector2, size: float) -> void:
	var foot: float = top.y + 34.0 * size
	_mesh.quad(Vector2(top.x - 2.6 * size, top.y + 7.0 * size), Vector2(top.x + 2.6 * size, top.y + 7.0 * size), Vector2(top.x + 4.4 * size, foot), Vector2(top.x - 4.4 * size, foot), top_color.darkened(0.12))
	_mesh.box(Rect2(top.x - 4.2 * size, top.y + 5.4 * size, 8.4 * size, 1.8 * size), top_color.darkened(0.2), top_color.darkened(0.2))
	_mesh.box(Rect2(top.x - 2.4 * size, top.y + 1.2 * size, 4.8 * size, 4.4 * size), lamp_color, lamp_color)
	_mesh.tri(Vector2(top.x - 3.4 * size, top.y + 1.4 * size), Vector2(top.x + 3.4 * size, top.y + 1.4 * size), Vector2(top.x, top.y - 2.6 * size), top_color.darkened(0.25))
	var lamp: Sprite2D = Sprite2D.new()
	lamp.name = "Lamp"
	lamp.texture = GLOW_TEXTURE
	lamp.position = top + Vector2(0.0, 3.4 * size)
	lamp.scale = Vector2.ONE * 0.5 * size
	lamp.modulate = lamp_color
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = LAMP_SHADER
	lamp.material = material
	_extras.append(lamp)


## A row of columns on a common step; `standing[i]` false leaves a broken shaft. The first `beam` columns
## still carry their entablature.
func _colonnade(left: float, count: int, height: float, standing: Array, beam: int) -> void:
	var spacing: float = 36.0
	var width: float = 13.0
	_step(left - 14.0, left + float(count - 1) * spacing + 14.0)
	for index in range(count):
		var x: float = left + float(index) * spacing
		if standing[index]:
			_column(x, height, width, false)
		else:
			_column(x, height * _rng.randf_range(0.28, 0.7), width, true)
	if beam >= 2:
		_entablature(left - 11.0, left + float(beam - 1) * spacing + 11.0, waterline - height - 6.0, true)


## A temple front: columns, the entablature across all of them and a pediment whose far corner has fallen.
func _temple(left: float, count: int, height: float) -> void:
	var spacing: float = 38.0
	var right: float = left + float(count - 1) * spacing
	_step(left - 20.0, right + 20.0)
	_shape(_box_points(Rect2(left - 16.0, waterline - 10.0, right - left + 32.0, 5.0)))
	for index in range(count):
		_column(left + float(index) * spacing, height, 14.0, false)
	var beam_y: float = waterline - height - 6.0
	_entablature(left - 13.0, right + 13.0, beam_y, false)
	var apex: Vector2 = Vector2((left + right) * 0.5, beam_y - 16.0 - 44.0)
	var cut: float = lerpf(apex.x, right + 17.0, 0.42)
	var cut_y: float = lerpf(apex.y, beam_y - 16.0, 0.42)
	_shape(PackedVector2Array([
		Vector2(left - 17.0, beam_y - 16.0), apex, Vector2(cut, cut_y), Vector2(cut + 7.0, cut_y + 13.0),
		Vector2(cut + 22.0, cut_y + 9.0), Vector2(cut + 30.0, beam_y - 16.0),
	]))
	_rim_line(Vector2(left - 17.0, beam_y - 16.0), apex)


func _column(x: float, height: float, width: float, broken: bool) -> void:
	var foot: float = waterline - 5.0
	var top: float = waterline - height
	var half: float = width * 0.5
	var half_top: float = half * 0.86
	_shape(_box_points(Rect2(x - half - 2.5, foot - 4.0, width + 5.0, 4.0 + 5.0)))
	if broken:
		_shape(PackedVector2Array([
			Vector2(x - half, foot - 4.0), Vector2(x - half_top, top + _rng.randf_range(2.0, 9.0)),
			Vector2(x - half_top * 0.3, top), Vector2(x + half_top * 0.2, top + _rng.randf_range(5.0, 11.0)),
			Vector2(x + half_top, top + _rng.randf_range(1.0, 6.0)), Vector2(x + half, foot - 4.0),
		]))
	else:
		_shape(PackedVector2Array([Vector2(x - half, foot - 4.0), Vector2(x - half_top, top + 8.0), Vector2(x + half_top, top + 8.0), Vector2(x + half, foot - 4.0)]))
		_shape(_box_points(Rect2(x - half - 1.5, top + 4.0, width + 3.0, 4.0)))
		_shape(_box_points(Rect2(x - half - 3.5, top, width + 7.0, 4.0)))
	# Flutes and the moonlit side.
	var flute: Color = Color(base_color.r * 0.7, base_color.g * 0.7, base_color.b * 0.7, 0.55)
	for offset in [-0.28, 0.22]:
		var fx: float = x + width * float(offset)
		_mesh.box(Rect2(fx, top + 14.0, 1.1, maxf(foot - top - 22.0, 2.0)), flute, flute)
	var lit: float = signf(moon_x - x)
	var clear: Color = Color(rim_color.r, rim_color.g, rim_color.b, 0.0)
	var edge: float = x + lit * half_top
	_mesh.quad_colors(Vector2(edge, top + 12.0), Vector2(edge - lit * 1.8, top + 12.0), Vector2(edge - lit * 1.8, foot - 6.0), Vector2(edge, foot - 6.0), rim_color, clear, clear, rim_color)
	_foam_run(x - half - 8.0, x + half + 8.0, waterline, 0.9)


func _entablature(left: float, right: float, top: float, ragged_end: bool) -> void:
	if ragged_end:
		_shape(PackedVector2Array([
			Vector2(left, top), Vector2(right - 3.0, top), Vector2(right + 5.0, top + 5.0),
			Vector2(right - 1.0, top + 9.0), Vector2(right + 3.0, top + 12.0), Vector2(left, top + 12.0),
		]))
	else:
		_shape(_box_points(Rect2(left, top, right - left, 12.0)))
	_shape(_box_points(Rect2(left - 4.0, top - 4.0, right - left + (4.0 if ragged_end else 8.0), 4.0)))
	_shape(_box_points(Rect2(left - 2.0, top - 10.0, right - left + (0.0 if ragged_end else 4.0), 6.0)))
	_rim_line(Vector2(left - 2.0, top - 10.0), Vector2(right, top - 10.0))


## The step the columns stand on, half under water.
func _step(left: float, right: float) -> void:
	_shape(_box_points(Rect2(left, waterline - 5.0, right - left, 9.0)))


func _stump(x: float, height: float) -> void:
	_column(x, height + 5.0, 13.0, true)


func _leaning_column(x: float, height: float) -> void:
	var lean: float = 26.0
	var half: float = 7.0
	_shape(PackedVector2Array([
		Vector2(x - half, waterline + 3.0), Vector2(x - half + lean, waterline - height + 3.0),
		Vector2(x - 1.0 + lean, waterline - height - 4.0), Vector2(x + half + lean, waterline - height + 5.0), Vector2(x + half, waterline + 3.0),
	]))
	_rim_line(Vector2(x - half, waterline), Vector2(x - half + lean, waterline - height + 3.0))
	_foam_run(x - 16.0, x + 18.0, waterline, 0.9)


func _rubble(center: float, width: float) -> void:
	var x: float = center - width * 0.5
	while x < center + width * 0.5:
		var w: float = _rng.randf_range(9.0, 22.0)
		var h: float = _rng.randf_range(4.0, 11.0)
		_shape(PackedVector2Array([
			Vector2(x, waterline + 2.0), Vector2(x + w * 0.15, waterline - h * 0.8), Vector2(x + w * 0.6, waterline - h),
			Vector2(x + w, waterline - h * 0.4), Vector2(x + w + 2.0, waterline + 2.0),
		]))
		x += w + _rng.randf_range(4.0, 20.0)
	_foam_run(center - width * 0.5 - 6.0, center + width * 0.5 + 6.0, waterline, 0.7)


## A run of the aqueduct: piers, round arches and the water channel on top. Arches listed in `fallen` are
## gone, and the channel breaks off ragged at the gap.
func _aqueduct(left: float, arches: int, height: float, fallen: Array) -> void:
	var opening: float = 54.0
	var pier: float = 16.0
	var pitch: float = opening + pier
	var deck_top: float = waterline - height
	var spring_y: float = deck_top + 16.0 + opening * 0.5
	for index in range(arches + 1):
		var x: float = left + float(index) * pitch
		var gone_left: bool = fallen.has(index - 1) or index == 0
		var gone_right: bool = fallen.has(index) or index == arches
		var pier_top: float = spring_y if (gone_left and gone_right) else deck_top
		if gone_left and gone_right and index > 0 and index < arches:
			pier_top = spring_y + _rng.randf_range(6.0, 30.0)
		_shape(_box_points(Rect2(x, pier_top, pier, waterline + 4.0 - pier_top)))
		_shape(_box_points(Rect2(x - 2.0, spring_y - 2.0, pier + 4.0, 4.0)))
		var lit: float = signf(moon_x - x)
		var edge: float = x + (pier if lit > 0.0 else 0.0)
		var clear: Color = Color(rim_color.r, rim_color.g, rim_color.b, 0.0)
		_mesh.quad_colors(Vector2(edge, pier_top + 4.0), Vector2(edge - lit * 1.8, pier_top + 4.0), Vector2(edge - lit * 1.8, waterline - 3.0), Vector2(edge, waterline - 3.0), rim_color, clear, clear, rim_color)
		_foam_run(x - 8.0, x + pier + 8.0, waterline, 0.9)
		if index == arches or fallen.has(index):
			continue
		# The spandrel over one opening: the deck minus a half circle.
		var a: float = x + pier
		var b: float = a + opening
		var points: PackedVector2Array = PackedVector2Array([Vector2(a, deck_top), Vector2(b, deck_top), Vector2(b, spring_y)])
		for step in range(1, 12):
			var angle: float = PI * float(step) / 12.0
			points.append(Vector2((a + b) * 0.5 + cos(angle) * opening * 0.5, spring_y - sin(angle) * opening * 0.5))
		points.append(Vector2(a, spring_y))
		_shape(points)
	# The channel: one slab per standing stretch.
	var run_start: int = -1
	for index in range(arches + 1):
		var standing: bool = index < arches and not fallen.has(index)
		if standing and run_start < 0:
			run_start = index
		if not standing and run_start >= 0:
			var a: float = left + float(run_start) * pitch - 3.0
			var b: float = left + float(index) * pitch + pier + 3.0
			_shape(_box_points(Rect2(a, deck_top - 7.0, b - a, 7.0)))
			_rim_line(Vector2(a, deck_top - 7.0), Vector2(b, deck_top - 7.0))
			run_start = -1


## Two piers and the half of an arch that still springs from one of them.
func _arch_fragment(left: float, height: float) -> void:
	var opening: float = 62.0
	var top: float = waterline - height
	var spring_y: float = top + 14.0 + opening * 0.5
	_shape(_box_points(Rect2(left, top, 18.0, height + 4.0)))
	_shape(_box_points(Rect2(left + 18.0 + opening, spring_y + 20.0, 18.0, waterline + 4.0 - spring_y - 20.0)))
	var a: float = left + 18.0
	var points: PackedVector2Array = PackedVector2Array([Vector2(a, top), Vector2(a + opening * 0.56, top), Vector2(a + opening * 0.5, top + 14.0)])
	for step in range(6, 12):
		var angle: float = PI * float(step) / 12.0
		points.append(Vector2(a + opening * 0.5 + cos(angle) * opening * 0.5, spring_y - sin(angle) * opening * 0.5))
	points.append(Vector2(a, spring_y))
	_shape(points)
	_rim_line(Vector2(left, top), Vector2(a + opening * 0.56, top))
	_foam_run(left - 8.0, left + 26.0, waterline, 0.9)
	_foam_run(left + 10.0 + opening, left + 44.0 + opening, waterline, 0.9)


func _rock(x: float, width: float, height: float) -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2(x, waterline + 6.0)])
	var steps: int = 6
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var hump: float = pow(sin(PI * clampf(t * 0.9 + 0.05, 0.0, 1.0)), 0.7) * _rng.randf_range(0.7, 1.0)
		points.append(Vector2(x + t * width, waterline - hump * height))
	points.append(Vector2(x + width, waterline + 6.0))
	_mesh.polygon_shaded(points, top_color, base_color, waterline - height, waterline)
	# The faces turned to the moon catch a thin line of light.
	var lit: float = signf(moon_x - x)
	for index in range(1, points.size() - 2):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		if (b.y - a.y) * lit > 0.5:
			_rim_line(a, b)
	_foam_run(x - 8.0, x + width + 8.0, waterline + 1.0, 0.45)


# --- Plumbing -----------------------------------------------------------------------------------------------

## A solid piece of the silhouette, plus its squashed, fading reflection in the water below.
func _shape(points: PackedVector2Array) -> void:
	_mesh.polygon_shaded(points, top_color, base_color, _top_y, waterline)
	if kind == Kind.FAR:
		return
	var mirrored: PackedVector2Array = PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		mirrored.append(Vector2(point.x, waterline + (waterline - point.y) * 0.5))
	var clear: Color = Color(reflection_color.r, reflection_color.g, reflection_color.b, 0.0)
	_mirror.polygon_shaded(mirrored, reflection_color, clear, waterline, waterline + 78.0)


func _rim_line(a: Vector2, b: Vector2) -> void:
	var clear: Color = Color(rim_color.r, rim_color.g, rim_color.b, 0.0)
	var normal: Vector2 = (b - a).normalized().orthogonal()
	if normal.y < 0.0:
		normal = -normal
	_mesh.quad_colors(a, b, b + normal * 1.8, a + normal * 1.8, rim_color, rim_color, clear, clear)


## Short dashes of foam along the waterline between two x.
func _foam_run(left: float, right: float, y: float, density: float) -> void:
	var x: float = left
	while x < right:
		var length: float = _rng.randf_range(5.0, 16.0)
		if _rng.randf() < density:
			var color: Color = Color(foam_color.r, foam_color.g, foam_color.b, foam_color.a * _rng.randf_range(0.5, 1.0))
			var wobble: float = _rng.randf_range(-1.0, 1.0)
			_mesh.box(Rect2(x, y + wobble, minf(length, right - x), 1.3), color, color)
		x += length + _rng.randf_range(3.0, 12.0)


func _box_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
