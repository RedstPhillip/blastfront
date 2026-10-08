extends SceneTree

## Shared plumbing for the world generators (build_tidewater_map.gd, build_rimefall_map.gd): packs a root
## node into a .tscn, and helpers for terrain bodies, parallax layers and shader rects. A generator
## extends this file by path, sets output_path and the arena size in _configure() and fills the root in
## _build().
## Run headless: godot --headless --path . -s res://tools/build_<world>_map.gd

const NOISE: String = "res://assets/fx/noise_fbm.png"
## The border sits this far above the top of the arena so big jumps have headroom (as on Verdant and Mars).
const TOP_HEADROOM: float = 60.0
## The abyss fades in over this many px above the map's bottom and is opaque from there down.
const ABYSS_FADE: float = 48.0

var output_path: String = ""
var root_name: String = "Arena"
var width: float = 2200.0
var height: float = 800.0
var _root: Node2D = null


func _initialize() -> void:
	_configure()
	_root = Node2D.new()
	_root.name = root_name
	_build()
	_set_owner(_root)
	var packed: PackedScene = PackedScene.new()
	var error: Error = packed.pack(_root)
	if error != OK:
		push_error("pack failed: %s" % error)
	else:
		error = ResourceSaver.save(packed, output_path)
		_strip_unset_shader_parameters()
		print("saved %s (%s)" % [output_path, error])
	_root.free()
	quit()


func _configure() -> void:
	pass


func _build() -> void:
	pass


## Headless runs have no renderer to report shader defaults, so unset uniforms are saved as null and
## would override the shader's own defaults. Drop those lines.
func _strip_unset_shader_parameters() -> void:
	var file: FileAccess = FileAccess.open(output_path, FileAccess.READ)
	var kept: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.begins_with("shader_parameter/") and line.ends_with(" = null"):
			continue
		kept.append(line)
	file.close()
	file = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string("\n".join(kept).strip_edges() + "\n")
	file.close()


func _set_owner(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		_set_owner(child)


func _add(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	return node


# --- Profile & markers -----------------------------------------------------------------------------------

func _add_bounds() -> void:
	var bounds: Node = Node.new()
	bounds.set_script(load("res://scenes/maps/map_bounds.gd"))
	bounds.set(&"bounds", Rect2(0.0, -TOP_HEADROOM, width, height + TOP_HEADROOM))
	_add(_root, bounds, "MapBounds")


func _add_markers(markers: Dictionary, drops: Dictionary) -> void:
	for marker_name in markers.keys():
		var marker: Marker2D = Marker2D.new()
		marker.position = markers[marker_name]
		_add(_root, marker, marker_name)
	for drop_name in drops.keys():
		var marker: Marker2D = Marker2D.new()
		marker.position = drops[drop_name]
		marker.add_to_group(&"airdrop_spawn", true)
		_add(_root, marker, drop_name)


# --- Geometry --------------------------------------------------------------------------------------------

## The same outline reflected across the arena's centre line (winding kept).
func _mirror(points: Array) -> Array:
	var result: Array = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		result.append(Vector2(width - point.x, point.y))
	return result


## One terrain body per entry; `groups` tags bodies (e.g. the ice surfaces) for the world's rules and skin.
func _add_bodies(bodies: Dictionary, groups: Dictionary = {}) -> void:
	for body_name in bodies.keys():
		var points: PackedVector2Array = PackedVector2Array(bodies[body_name])
		var body: StaticBody2D = StaticBody2D.new()
		for group in groups.get(body_name, []):
			body.add_to_group(group, true)
		_add(_root, body, body_name)
		var polygon: Polygon2D = Polygon2D.new()
		polygon.polygon = points
		_add(body, polygon, "Polygon2D")
		var collision: CollisionPolygon2D = CollisionPolygon2D.new()
		collision.polygon = points
		_add(body, collision, "CollisionPolygon2D")
		var occluder: LightOccluder2D = LightOccluder2D.new()
		var shape: OccluderPolygon2D = OccluderPolygon2D.new()
		shape.polygon = points
		occluder.occluder = shape
		_add(body, occluder, "LightOccluder2D")


func _add_airdrops() -> void:
	var airdrops: Node2D = Node2D.new()
	airdrops.set_script(load("res://scenes/objectives/airdrop_manager.gd"))
	_add(_root, airdrops, "AirdropManager")


# --- Environment -----------------------------------------------------------------------------------------

func _shader_rect(parent: Node, rect_name: String, rect: Rect2, shader_path: String, params: Dictionary) -> ColorRect:
	var color_rect: ColorRect = ColorRect.new()
	color_rect.position = rect.position
	color_rect.size = rect.size
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(shader_path)
	for key in params.keys():
		material.set_shader_parameter(key, params[key])
	color_rect.material = material
	_add(parent, color_rect, rect_name)
	return color_rect


func _fill(parent: Node, fill_name: String, rect: Rect2, color: Color) -> ColorRect:
	var fill: ColorRect = ColorRect.new()
	fill.position = rect.position
	fill.size = rect.size
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, fill, fill_name)
	return fill


func _layer(parent: Node, layer_name: String, factor: Vector2) -> Node2D:
	var layer: Node2D = Node2D.new()
	layer.set_script(load("res://scenes/maps/environment/parallax_depth.gd"))
	layer.set(&"factor", factor)
	layer.set(&"anchor", Vector2(width * 0.5, 400.0))
	_add(parent, layer, layer_name)
	return layer


func _abyss(parent: Node, abyss_color: Color, mist_color: Color, mist_strength: float) -> ColorRect:
	var abyss: ColorRect = _shader_rect(parent, "Abyss", Rect2(-900.0, height - ABYSS_FADE, width + 1800.0, 590.0 + ABYSS_FADE), "res://scenes/maps/environment/abyss.gdshader", {
		&"noise_tex": load(NOISE), &"abyss_color": abyss_color, &"mist_color": mist_color, &"mist_strength": mist_strength,
	})
	abyss.z_index = 12
	return abyss


## A big soft directional light high above the arena (the shadows of the terrain fall away from it).
func _sky_light(parent: Node, light_name: String, at: Vector2, color: Color, energy: float, shadow: Color) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = at
	light.scale = Vector2(70.0, 40.0)
	light.color = color
	light.energy = energy
	light.range_item_cull_mask = 4
	light.shadow_enabled = true
	light.shadow_color = shadow
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 6.0
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.7])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0, 0, 0, 1)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	light.texture = texture
	_add(parent, light, light_name)
	return light


## Slow drifting specks over the whole arena (dust, spray, snow): additive soft dots that fade in and out.
func _motes(parent: Node, motes_name: String, amount: int, direction: Vector2, gravity: Vector2, speed: Vector2, size: Vector2, color: Color, additive: bool = true) -> CPUParticles2D:
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.z_index = 16
	motes.position = Vector2(width * 0.5, 400.0)
	motes.amount = amount
	motes.lifetime = 10.0
	motes.preprocess = 10.0
	motes.randomness = 0.8
	motes.texture = load("res://assets/fx/soft_circle.png")
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(width * 0.58, 380.0)
	motes.direction = direction
	motes.spread = 30.0
	motes.gravity = gravity
	motes.initial_velocity_min = speed.x
	motes.initial_velocity_max = speed.y
	motes.scale_amount_min = size.x
	motes.scale_amount_max = size.y
	motes.color = color
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	motes.color_ramp = ramp
	if additive:
		var material: CanvasItemMaterial = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		motes.material = material
	_add(parent, motes, motes_name)
	return motes
