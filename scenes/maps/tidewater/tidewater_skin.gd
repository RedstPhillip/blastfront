class_name TidewaterSkin
extends PlatformSkin

## Ruin dressing for Tidewater. The terrain is temple masonry (ruin_body.gdshader) under a worn cornice
## slab instead of topsoil. What grows on it depends on how often the sea reaches it: ledges above the
## spring-tide line carry moss cushions, grass and the odd flower in patches between bare stone; ledges the
## spring tide drowns only keep sparse salt grass; the courtyard that floods on every tide grows seaweed.
## Kelp hangs from undersides the sea reaches, vines from the dry ones. The skin also tells the masonry how
## high the water stood last, so drained stone stays wet for a while.

const RUIN_SHADER: Shader = preload("res://scenes/maps/tidewater/ruin_body.gdshader")
## How fast the wet mark on the stone sinks after the water has gone (px/s).
const DRY_SPEED: float = 9.0

@export var flood_level: float = 600.0
@export var spring_level: float = 506.0
@export var cornice_color: Color = Color(0.5, 0.58, 0.56)
@export var cornice_shadow: Color = Color(0.03, 0.06, 0.07, 0.6)
@export var moss_palette: Array[Color] = [
	Color(0.17, 0.33, 0.22),
	Color(0.22, 0.4, 0.25),
	Color(0.14, 0.28, 0.21),
]
@export var kelp_palette: Array[Color] = [
	Color(0.1, 0.27, 0.2),
	Color(0.14, 0.33, 0.22),
	Color(0.2, 0.34, 0.16),
]

var _wet_line: float = 100000.0


func _body_shader() -> Shader:
	return RUIN_SHADER


func _configure_body_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"flood_y", flood_level)
	material.set_shader_parameter(&"spring_y", spring_level)
	material.set_shader_parameter(&"wet_line", _wet_line)


func _process(delta: float) -> void:
	super._process(delta)
	# The wet mark follows the water up at once and sinks slowly after it.
	var water: float = WorldConditions.water_level
	_wet_line = minf(_wet_line + DRY_SPEED * delta, minf(water, 100000.0))
	_body_material.set_shader_parameter(&"wet_line", _wet_line)


## No topsoil on dressed stone.
func _add_soil_band(_chain: Array, _body_points: PackedVector2Array) -> void:
	pass


func _decorate_top_chain(chain: Array, decorations: Node2D) -> void:
	# The cornice: a pale slab along the walkable edge, its shadow on the wall under it, a moonlit rim.
	decorations.add_child(_make_line(_offset_chain(chain, -5.6), cornice_shadow, 2.4))
	decorations.add_child(_make_line(_offset_chain(chain, -1.7), cornice_color, 4.4))
	decorations.add_child(_make_line(_offset_chain(chain, 0.5), rim_color, 1.1))
	_add_slab_seams(chain)
	var height: float = INF
	for edge in chain:
		height = minf(height, minf((edge["a"] as Vector2).y, (edge["b"] as Vector2).y))
	var drowned: bool = height > flood_level - 4.0
	var salted: bool = not drowned and height > spring_level - 4.0
	# Growth comes in patches with bare stone between them.
	var overgrown: bool = _rng.randf() < 0.5
	var run_left: float = _rng.randf_range(20.0, 70.0)
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var tangent: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var distance: float = _rng.randf_range(0.0, BLADE_SPACING)
		while distance < length:
			var step: float = BLADE_SPACING * _rng.randf_range(0.7, 1.3)
			run_left -= step
			if run_left <= 0.0:
				overgrown = not overgrown
				if overgrown:
					run_left = _rng.randf_range(34.0, 120.0) * (0.6 if salted else 1.0)
				else:
					run_left = _rng.randf_range(18.0, 64.0) * (2.2 if salted else 1.0)
			if overgrown:
				# Thin out towards both ends of a patch so it does not start like a hedge.
				var fade: float = clampf(run_left / 14.0, 0.25, 1.0)
				var base: Vector2 = a + tangent * distance + normal * 0.8
				if drowned:
					_add_frond(base, normal, tangent, _rng.randf_range(5.0, 13.0) * fade)
				else:
					if _rng.randf() < 0.22:
						_push_fan(_mound(base, normal, tangent, _rng.randf_range(4.0, 9.0), _rng.randf_range(1.6, 3.2)), moss_palette[_rng.randi() % moss_palette.size()])
					_add_blade(base, normal, tangent, _rng.randf_range(3.5, 10.0) * fade * (0.7 if salted else 1.0))
					if not salted and _rng.randf() < 0.03:
						_add_flower(base + normal * _rng.randf_range(5.0, 8.5) * fade)
			elif _rng.randf() < 0.012:
				# A chip of fallen stone on the bare slab.
				var r: float = _rng.randf_range(1.6, 3.4)
				_push_fan(_mound(a + tangent * distance + normal * 0.6, normal, tangent, r, r * 0.7), cornice_color.darkened(_rng.randf_range(0.25, 0.5)))
			distance += step


func _decorate_bottom_chain(chain: Array, bounds: Rect2) -> void:
	if bounds.end.y > map_bottom_y + 40.0:
		return
	if bounds.end.y < spring_level - 30.0:
		super._decorate_bottom_chain(chain, bounds)
		return
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var count: int = int(a.distance_to(b) / 22.0)
		for index in range(count):
			var root: Vector2 = a.lerp(b, _rng.randf_range(0.06, 0.94)) + Vector2(0.0, -1.0)
			_add_kelp(root, _rng.randf_range(8.0, 26.0))


## The cornice is laid in slabs: a dark seam across it every so often, and now and then a chipped corner.
func _add_slab_seams(chain: Array) -> void:
	var seam: Color = Color(cornice_shadow.r, cornice_shadow.g, cornice_shadow.b, 0.7)
	for edge in chain:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var normal: Vector2 = edge["normal"]
		var tangent: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var distance: float = _rng.randf_range(12.0, 30.0)
		while distance < length - 6.0:
			var at: Vector2 = a + tangent * distance
			_push_quad(at + normal * 0.4, at + tangent * 1.1 + normal * 0.4, at + tangent * 1.1 - normal * 3.9, at - normal * 3.9, seam)
			if _rng.randf() < 0.25:
				_push_tri(at + normal * 0.6, at + tangent * _rng.randf_range(3.0, 6.0) + normal * 0.6, at - normal * _rng.randf_range(1.5, 3.0), seam, seam, seam, 0.0, 0.0, 0.0)
			distance += _rng.randf_range(24.0, 46.0)


## A flat seaweed frond standing on a flooded ledge: broader than a grass blade, with a rounded tip.
func _add_frond(base: Vector2, normal: Vector2, tangent: Vector2, height: float) -> void:
	var width: float = _rng.randf_range(2.6, 4.6)
	var lean: float = _rng.randf_range(-3.0, 3.0)
	var color: Color = kelp_palette[_rng.randi() % kelp_palette.size()]
	var tip: Color = color.lightened(0.22)
	var mid: Vector2 = base + normal * height * 0.6 + tangent * lean * 0.5
	var top: Vector2 = base + normal * height + tangent * lean
	_push_tri(base - tangent * width * 0.5, base + tangent * width * 0.5, mid + tangent * width * 0.45, color, color, tip, 0.0, 0.0, 0.6)
	_push_tri(base - tangent * width * 0.5, mid + tangent * width * 0.45, mid - tangent * width * 0.45, color, tip, tip, 0.0, 0.6, 0.6)
	_push_tri(mid - tangent * width * 0.45, mid + tangent * width * 0.45, top, tip, tip, tip, 0.6, 0.6, 1.0)


## A strand of kelp hanging under a ledge the sea reaches: a ribbon with a few leaflets.
func _add_kelp(root: Vector2, length: float) -> void:
	var color: Color = kelp_palette[_rng.randi() % kelp_palette.size()]
	var width: float = _rng.randf_range(2.0, 3.4)
	var curl: float = _rng.randf_range(-4.0, 4.0)
	var segments: int = 4
	var previous: Vector2 = root
	var previous_t: float = 0.0
	for index in range(1, segments + 1):
		var t: float = float(index) / float(segments)
		var center: Vector2 = root + Vector2(sin(t * 2.8) * curl * t, length * t)
		var half: float = width * 0.5 * (1.0 - t * 0.6)
		var shade: Color = color.lerp(color.lightened(0.2), t)
		_push_tri(previous + Vector2(-half, 0.0), previous + Vector2(half, 0.0), center + Vector2(half, 0.0), shade, shade, shade, previous_t, previous_t, t)
		_push_tri(previous + Vector2(-half, 0.0), center + Vector2(half, 0.0), center + Vector2(-half, 0.0), shade, shade, shade, previous_t, t, t)
		if index < segments:
			var side: float = 1.0 if index % 2 == 0 else -1.0
			_push_tri(center, center + Vector2(side * 4.0, 1.0), center + Vector2(side * 1.5, 4.5), shade, shade, shade, t, t, t)
		previous = center
		previous_t = t

