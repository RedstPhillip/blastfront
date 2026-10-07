extends SceneTree

## Builds res://scenes/maps/mars/mars_arena.tscn, the Mars world.
## Run headless: godot --headless --path . -s res://tools/build_mars_map.gd
##
## Layout: two high mesas (spawns) with a lower step each, narrow chasms, and a crater basin between
## them with a hoodoo spire in the middle. Floating slabs and boulders link the levels; two CO2 geysers in
## the crater floor throw players up to the slabs, the spire cap and a high perch above it.

const OUTPUT_PATH: String = "res://scenes/maps/mars/mars_arena.tscn"
const WIDTH: float = 2160.0
const HEIGHT: float = 800.0
## The border sits this far above the top of the arena so big jumps and geyser throws have headroom.
const TOP_HEADROOM: float = 60.0
## The abyss fades in over this many px above HEIGHT and is opaque from HEIGHT down (see abyss.gdshader).
const ABYSS_FADE: float = 48.0
const NOISE: String = "res://assets/fx/noise_fbm.png"

var _root: Node2D = null


func _initialize() -> void:
	_root = Node2D.new()
	_root.name = "MarsArena"
	_build_profile()
	_build_environment()
	_build_markers()
	_build_geometry()
	_build_gameplay()
	_build_skin()
	_set_owner(_root)
	var packed: PackedScene = PackedScene.new()
	var error: Error = packed.pack(_root)
	if error != OK:
		push_error("pack failed: %s" % error)
	else:
		error = ResourceSaver.save(packed, OUTPUT_PATH)
		_strip_unset_shader_parameters()
		print("saved %s (%s)" % [OUTPUT_PATH, error])
	_root.free()
	quit()


## Headless runs have no renderer to report shader defaults, so unset uniforms are saved as null and
## would override the shader's own defaults. Drop those lines.
func _strip_unset_shader_parameters() -> void:
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.READ)
	var kept: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.begins_with("shader_parameter/") and line.ends_with(" = null"):
			continue
		kept.append(line)
	file.close()
	file = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	file.store_string("
".join(kept).strip_edges() + "
")
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

func _build_profile() -> void:
	var profile: MapProfile = MapProfile.new()
	profile.world_id = &"mars"
	profile.display_name = "Mars"
	profile.ambience = &"ambience_mars"
	profile.gravity_scale = 0.8
	profile.projectile_gravity_scale = 0.72
	profile.projectile_range_scale = 1.3
	profile.border_color = Color(1.0, 0.68, 0.36)
	_add(_root, profile, "MapProfile")
	var bounds: Node = Node.new()
	bounds.set_script(load("res://scenes/maps/map_bounds.gd"))
	bounds.set(&"bounds", Rect2(0.0, -TOP_HEADROOM, WIDTH, HEIGHT + TOP_HEADROOM))
	_add(_root, bounds, "MapBounds")


func _build_markers() -> void:
	var markers: Dictionary = {
		"Spawn1": Vector2(150.0, 380.0),
		"Spawn2": Vector2(WIDTH - 150.0, 380.0),
		"DummySpawn1": Vector2(1300.0, 640.0),
	}
	for marker_name in markers.keys():
		var marker: Marker2D = Marker2D.new()
		marker.position = markers[marker_name]
		_add(_root, marker, marker_name)
	var drops: Dictionary = {
		"AirdropPointCenter": Vector2(WIDTH * 0.5, 262.0),
		"AirdropPointLeft": Vector2(742.0, 352.0),
		"AirdropPointRight": Vector2(WIDTH - 742.0, 352.0),
	}
	for drop_name in drops.keys():
		var marker: Marker2D = Marker2D.new()
		marker.position = drops[drop_name]
		marker.add_to_group(&"airdrop_spawn", true)
		_add(_root, marker, drop_name)


# --- Geometry --------------------------------------------------------------------------------------------

func _mirror(points: Array) -> Array:
	var result: Array = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		result.append(Vector2(WIDTH - point.x, point.y))
	return result


func _build_geometry() -> void:
	var left_mesa: Array = [
		Vector2(-80, 960), Vector2(-80, 418), Vector2(240, 418), Vector2(262, 423), Vector2(298, 427),
		Vector2(318, 440), Vector2(326, 482), Vector2(332, 520), Vector2(466, 520), Vector2(482, 527),
		Vector2(491, 560), Vector2(496, 960),
	]
	var crater: Array = [
		Vector2(590, 960), Vector2(590, 556), Vector2(606, 546), Vector2(650, 548), Vector2(700, 566),
		Vector2(760, 610), Vector2(820, 652), Vector2(880, 680), Vector2(940, 690),
		Vector2(1040, 690), Vector2(1048, 650), Vector2(1056, 600), Vector2(1060, 566), Vector2(1046, 548),
		Vector2(1028, 532), Vector2(1022, 514), Vector2(1032, 500), Vector2(1062, 492), Vector2(1098, 492),
		Vector2(1128, 500), Vector2(1138, 514), Vector2(1132, 532), Vector2(1114, 548), Vector2(1100, 566),
		Vector2(1104, 600), Vector2(1112, 650), Vector2(1120, 690),
		Vector2(1220, 690), Vector2(1280, 680), Vector2(1340, 652), Vector2(1400, 610), Vector2(1460, 566),
		Vector2(1510, 548), Vector2(1554, 546), Vector2(1570, 556), Vector2(1570, 960),
	]
	var slab: Array = [
		Vector2(650, 402), Vector2(668, 388), Vector2(812, 384), Vector2(834, 396), Vector2(820, 418),
		Vector2(760, 432), Vector2(690, 428), Vector2(660, 416),
	]
	var boulder: Array = [
		Vector2(442, 334), Vector2(450, 320), Vector2(472, 314), Vector2(496, 318), Vector2(506, 330),
		Vector2(498, 344), Vector2(470, 350), Vector2(450, 346),
	]
	var perch: Array = [
		Vector2(1004, 306), Vector2(1020, 294), Vector2(1140, 294), Vector2(1156, 306), Vector2(1142, 320),
		Vector2(1110, 332), Vector2(1050, 332), Vector2(1018, 320),
	]
	# Shelves on the spire's flanks: a walkable climb from the crater floor onto the cap (and cover
	# from the side). They stay clear of the geyser columns.
	var shelf: Array = [
		Vector2(988, 612), Vector2(998, 602), Vector2(1030, 599), Vector2(1052, 603), Vector2(1056, 620),
		Vector2(1046, 636), Vector2(1020, 642), Vector2(998, 630),
	]
	var bodies: Dictionary = {
		"LeftShelf": shelf,
		"RightShelf": _mirror(shelf),
		"LeftMesa": left_mesa,
		"Crater": crater,
		"RightMesa": _mirror(left_mesa),
		"LeftSlab": slab,
		"RightSlab": _mirror(slab),
		"LeftBoulder": boulder,
		"RightBoulder": _mirror(boulder),
		"Perch": perch,
	}
	for body_name in bodies.keys():
		var points: PackedVector2Array = PackedVector2Array(bodies[body_name])
		var body: StaticBody2D = StaticBody2D.new()
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


func _build_gameplay() -> void:
	var airdrops: Node2D = Node2D.new()
	airdrops.set_script(load("res://scenes/objectives/airdrop_manager.gd"))
	_add(_root, airdrops, "AirdropManager")
	var vents: Array = [[Vector2(962, 690), 0.0], [Vector2(WIDTH - 962, 690), 2.4]]
	for index in range(vents.size()):
		var geyser: Node2D = Node2D.new()
		geyser.set_script(load("res://scenes/maps/mars/mars_geyser.gd"))
		geyser.position = vents[index][0]
		geyser.set(&"phase_offset", vents[index][1])
		_add(_root, geyser, "Geyser%d" % (index + 1))
	var weather: Node2D = Node2D.new()
	weather.set_script(load("res://scenes/maps/mars/mars_weather.gd"))
	weather.set(&"arena_rect", Rect2(0.0, 0.0, WIDTH, HEIGHT))
	_add(_root, weather, "Weather")
	weather.set(&"storm_wall_path", NodePath("../Environment/FarLayer/StormWall"))


func _build_skin() -> void:
	var skin: Node2D = Node2D.new()
	skin.set_script(load("res://scenes/maps/mars/mars_skin.gd"))
	var settings: Dictionary = {
		&"map_top_y": 280.0,
		&"map_bottom_y": 760.0,
		&"high_color": Color(0.36, 0.15, 0.09),
		&"low_color": Color(0.5, 0.22, 0.12),
		&"deep_color": Color(0.12, 0.045, 0.03),
		&"outline_color": Color(0.13, 0.05, 0.03, 0.9),
		&"moss_color": Color(0.9, 0.6, 0.39),
		&"rim_color": Color(1.0, 0.84, 0.64, 0.75),
		&"rock_tint": Color(0.52, 0.24, 0.14),
		&"crack_strength": 0.16,
		&"warm_light": Color(1.0, 0.72, 0.5),
		&"strata_strength": 0.22,
		&"layer_contrast": 0.3,
		&"warm_strength": 0.06,
		&"soil_top_color": Color(0.93, 0.63, 0.41),
		&"soil_deep_color": Color(0.6, 0.3, 0.17),
		&"soil_fleck_color": Color(0.3, 0.14, 0.09),
		&"soil_depth": 7.0,
		&"soil_depth_variation": 3.0,
	}
	for key in settings.keys():
		skin.set(key, settings[key])
	_add(_root, skin, "PlatformSkin")


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


func _layer(parent: Node, layer_name: String, factor: Vector2) -> Node2D:
	var layer: Node2D = Node2D.new()
	layer.set_script(load("res://scenes/maps/environment/parallax_depth.gd"))
	layer.set(&"factor", factor)
	layer.set(&"anchor", Vector2(WIDTH * 0.5, 400.0))
	_add(parent, layer, layer_name)
	return layer


func _backdrop(parent: Node, backdrop_name: String, kind: int, baseline: float, top: Color, base: Color, seed_value: int) -> Node2D:
	var backdrop: Node2D = Node2D.new()
	backdrop.set_script(load("res://scenes/maps/mars/mars_backdrop.gd"))
	backdrop.set(&"kind", kind)
	backdrop.set(&"baseline", baseline)
	backdrop.set(&"top_color", top)
	backdrop.set(&"base_color", base)
	backdrop.set(&"seed_value", seed_value)
	_add(parent, backdrop, backdrop_name)
	return backdrop


func _build_environment() -> void:
	var noise: Texture2D = load(NOISE)
	var environment: Node2D = Node2D.new()
	environment.z_index = -10
	_add(_root, environment, "Environment")

	var far: Node2D = _layer(environment, "FarLayer", Vector2(0.18, 0.12))
	_shader_rect(far, "Sky", Rect2(-3400.0, -700.0, 6800.0, 920.0), "res://scenes/maps/mars/mars_sky.gdshader", {
		&"noise_tex": noise, &"aspect": 6800.0 / 920.0, &"sun_uv": Vector2(0.62, 0.6),
		&"phobos_uv": Vector2(0.43, 0.435), &"deimos_uv": Vector2(0.58, 0.36),
	})
	_shader_rect(far, "StormWall", Rect2(-2900.0, -260.0, 2700.0, 440.0), "res://scenes/maps/mars/storm_front.gdshader", {
		&"noise_tex": noise, &"aspect": 2700.0 / 440.0,
	})
	_backdrop(far, "FarRidge", 0, 150.0, Color(0.8, 0.55, 0.4), Color(0.74, 0.48, 0.34), 11)
	_shader_rect(far, "FarHaze", Rect2(-3400.0, 60.0, 6800.0, 220.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.88, 0.6, 0.42), &"density": 0.38, &"speed": 0.012,
		&"scale": 0.7, &"top_softness": 0.5, &"bottom_softness": 0.3,
	})
	var fill: ColorRect = ColorRect.new()
	fill.position = Vector2(-3400.0, 300.0)
	fill.size = Vector2(6800.0, 1600.0)
	fill.color = Color(0.7, 0.45, 0.32)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(far, fill, "FarFill")

	var mid: Node2D = _layer(environment, "MidLayer", Vector2(0.36, 0.3))
	var mid_ground: Node2D = _backdrop(mid, "Mesas", 1, 170.0, Color(0.7, 0.42, 0.29), Color(0.56, 0.31, 0.21), 23)
	var activity: Node2D = Node2D.new()
	activity.set_script(load("res://scenes/maps/mars/mars_activity.gd"))
	_add(mid, activity, "Activity")
	activity.set(&"ground_path", NodePath("../Mesas"))
	activity.set(&"devil_ground_path", NodePath("../Mesas"))
	activity.set(&"outpost_x", 640.0)
	activity.set(&"rover_range", Vector2(-1100.0, 380.0))
	activity.set(&"devil_range", Vector2(-1900.0, 1900.0))
	_shader_rect(mid, "MidHaze", Rect2(-3400.0, 60.0, 6800.0, 220.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.82, 0.52, 0.34), &"density": 0.24, &"speed": 0.02,
		&"scale": 1.0, &"top_softness": 0.45, &"bottom_softness": 0.3,
	})

	var near: Node2D = _layer(environment, "NearLayer", Vector2(0.62, 0.55))
	_backdrop(near, "Ridge", 2, 330.0, Color(0.44, 0.22, 0.15), Color(0.3, 0.14, 0.1), 37)
	var near_fill: ColorRect = ColorRect.new()
	near_fill.position = Vector2(-3400.0, 320.0)
	near_fill.size = Vector2(6800.0, 1600.0)
	near_fill.color = Color(0.3, 0.14, 0.1)
	near_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(near, near_fill, "NearFill")

	_shader_rect(environment, "Abyss", Rect2(-900.0, HEIGHT - ABYSS_FADE, WIDTH + 1800.0, 590.0 + ABYSS_FADE), "res://scenes/maps/environment/abyss.gdshader", {
		&"noise_tex": noise, &"abyss_color": Color(0.09, 0.035, 0.025), &"mist_color": Color(0.78, 0.46, 0.3), &"mist_strength": 0.4,
	}).z_index = 12

	var light: PointLight2D = PointLight2D.new()
	light.position = Vector2(WIDTH * 0.72, -140.0)
	light.scale = Vector2(70.0, 40.0)
	light.color = Color(1.0, 0.78, 0.6)
	light.energy = 0.55
	light.range_item_cull_mask = 4
	light.shadow_enabled = true
	light.shadow_color = Color(0.1, 0.02, 0.0, 0.55)
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
	_add(environment, light, "SunLight")

	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.z_index = 16
	motes.position = Vector2(WIDTH * 0.5, 420.0)
	motes.amount = 50
	motes.lifetime = 10.0
	motes.preprocess = 10.0
	motes.randomness = 0.8
	motes.texture = load("res://assets/fx/soft_circle.png")
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(1250.0, 360.0)
	motes.direction = Vector2(1.0, -0.1)
	motes.spread = 30.0
	motes.gravity = Vector2(5.0, -2.0)
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 18.0
	motes.scale_amount_min = 0.04
	motes.scale_amount_max = 0.1
	motes.color = Color(1.0, 0.78, 0.58, 0.32)
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	motes.color_ramp = ramp
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = additive
	_add(environment, motes, "DustMotes")
