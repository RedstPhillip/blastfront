extends "res://tools/map_builder.gd"

## Builds res://scenes/maps/rimefall/rimefall_arena.tscn, the Rimefall world: a glacier pass at night.
## Run headless: godot --headless --path . -s res://tools/build_rimefall_map.gd
##
## Layout: the other way round from the mesa worlds. The spawns lie low at the edges, each behind a
## stepped snow rampart that climbs to a top and steps down again to the shore. Between the ramparts one
## frozen lake runs from shore to shore with no chasm in it, and out of its middle rises the ice arch: a
## real arch with two feet on the lake, a tunnel of open ice under it (the longest glide on the map) and
## a back you can run up and slide down. A high road of floes leads from the rampart tops over the arch to
## the snow summit above it. Bodies in the ice group (the lake, the arch, the floes) are glassy ice;
## everything else is snow on rock.

const WIDTH: float = 2200.0
const HEIGHT: float = 800.0
const ICE_GROUP: StringName = WorldConditions.ICE_GROUP
## Far-layer coordinates (origin = the arena's centre): the foot of the far range, and the moon.
const FAR_BASELINE: float = 40.0
const MOON: Vector2 = Vector2(380.0, -235.0)


func _configure() -> void:
	output_path = "res://scenes/maps/rimefall/rimefall_arena.tscn"
	root_name = "RimefallArena"
	width = WIDTH
	height = HEIGHT


func _build() -> void:
	_build_profile()
	_build_environment()
	_build_markers()
	_build_geometry()
	_add_airdrops()
	_build_notice()
	_build_weather()
	_build_skin()


# --- Profile & markers -----------------------------------------------------------------------------------

func _build_profile() -> void:
	var profile: MapProfile = MapProfile.new()
	profile.world_id = &"rimefall"
	profile.display_name = "Rimefall"
	profile.ambience = &"ambience_rimefall"
	profile.footstep = &"step_snow"
	profile.dust_color = Color(0.95, 0.97, 1.0, 0.6)
	profile.debris_color = Color(0.82, 0.9, 1.0, 1.0)
	profile.gravity_scale = 1.0
	profile.projectile_gravity_scale = 1.0
	profile.projectile_range_scale = 1.0
	profile.border_color = Color(0.66, 0.84, 1.0)
	_add(_root, profile, "MapProfile")
	_add_bounds()


func _build_markers() -> void:
	_add_markers({
		"Spawn1": Vector2(130.0, 530.0),
		"Spawn2": Vector2(WIDTH - 130.0, 530.0),
		"DummySpawn1": Vector2(1470.0, 598.0),
	}, {
		"AirdropPointCenter": Vector2(WIDTH * 0.5, 250.0),
		"AirdropPointLeft": Vector2(630.0, 360.0),
		"AirdropPointRight": Vector2(WIDTH - 630.0, 360.0),
	})


# --- Geometry --------------------------------------------------------------------------------------------

func _build_geometry() -> void:
	# The rampart: the spawn ledge, two steps up to the top, two steps down to the shore.
	var rampart: Array = [
		Vector2(-80, 960), Vector2(-80, 560), Vector2(226, 560), Vector2(236, 554), Vector2(240, 492),
		Vector2(250, 484), Vector2(334, 484), Vector2(344, 478), Vector2(348, 416), Vector2(358, 408),
		Vector2(446, 408), Vector2(456, 414), Vector2(460, 476), Vector2(470, 484), Vector2(536, 484),
		Vector2(546, 490), Vector2(550, 552), Vector2(560, 560), Vector2(620, 560), Vector2(630, 566),
		Vector2(634, 960),
	]
	# The frozen lake: one deep body of ice from shore to shore.
	var lake: Array = [
		Vector2(630, 634), Vector2(640, 628), Vector2(WIDTH - 640, 628), Vector2(WIDTH - 630, 634),
		Vector2(WIDTH - 630, 960), Vector2(630, 960),
	]
	# The ice arch: the back (left foot to right foot), then the underside of the tunnel back again.
	var back_half: Array = [
		Vector2(780, 634), Vector2(830, 600), Vector2(880, 566), Vector2(930, 530), Vector2(980, 496),
		Vector2(1030, 468), Vector2(1070, 450),
	]
	var tunnel_half: Array = [
		Vector2(900, 634), Vector2(915, 585), Vector2(950, 545), Vector2(1000, 515), Vector2(1050, 498),
	]
	var arch: Array = back_half + [Vector2(WIDTH * 0.5, 444)] + _mirror(back_half)
	var tunnel: Array = tunnel_half + [Vector2(WIDTH * 0.5, 492)] + _mirror(tunnel_half)
	tunnel.reverse()
	arch.append_array(tunnel)
	_add_bodies({
		"LeftRampart": rampart,
		"RightRampart": _mirror(rampart),
		"Lake": lake,
		"IceArch": arch,
		# The high road: rampart top, floe, high floe, summit.
		"LeftFloe": _slab(560, 700, 400, 24),
		"RightFloe": _mirror(_slab(560, 700, 400, 24)),
		"LeftHighFloe": _slab(820, 1000, 372, 24),
		"RightHighFloe": _mirror(_slab(820, 1000, 372, 24)),
		"Summit": _slab(1020, 1180, 300, 28),
	}, {
		"Lake": [ICE_GROUP],
		"IceArch": [ICE_GROUP],
		"LeftFloe": [ICE_GROUP],
		"RightFloe": [ICE_GROUP],
		"LeftHighFloe": [ICE_GROUP],
		"RightHighFloe": [ICE_GROUP],
	})


## The ice is always there, so no warning ever teaches it: name it once when the match starts.
func _build_notice() -> void:
	var notice: Node = Node.new()
	notice.set_script(load("res://scenes/maps/world_notice.gd"))
	notice.set(&"title", "GLARE ICE")
	notice.set(&"detail", "Ice slides  ·  snow grips")
	notice.set(&"color", Color(0.66, 0.88, 1.0))
	_add(_root, notice, "IceNotice")


func _build_weather() -> void:
	var weather: Node2D = Node2D.new()
	weather.set_script(load("res://scenes/maps/rimefall/rimefall_weather.gd"))
	weather.set(&"arena_rect", Rect2(0.0, 0.0, WIDTH, HEIGHT))
	_add(_root, weather, "Weather")


func _build_skin() -> void:
	var skin: Node2D = Node2D.new()
	skin.set_script(load("res://scenes/maps/rimefall/rimefall_skin.gd"))
	var settings: Dictionary = {
		&"map_top_y": 300.0,
		&"map_bottom_y": 720.0,
		&"high_color": Color(0.22, 0.25, 0.32),
		&"low_color": Color(0.3, 0.34, 0.42),
		&"deep_color": Color(0.05, 0.06, 0.1),
		&"outline_color": Color(0.03, 0.04, 0.08, 0.9),
		&"moss_color": Color(0.88, 0.93, 1.0),
		&"rim_color": Color(0.9, 0.97, 1.0, 0.85),
		&"rock_tint": Color(0.42, 0.44, 0.5),
		&"soil_top_color": Color(0.9, 0.94, 1.0),
		&"soil_deep_color": Color(0.62, 0.7, 0.82),
	}
	for key in settings.keys():
		skin.set(key, settings[key])
	_add(_root, skin, "PlatformSkin")


# --- Environment -----------------------------------------------------------------------------------------

func _build_environment() -> void:
	var noise: Texture2D = load(NOISE)
	var environment: Node2D = Node2D.new()
	environment.z_index = -10
	_add(_root, environment, "Environment")
	# Far: the night sky with the aurora, and the pale range under it.
	var far: Node2D = _layer(environment, "FarLayer", Vector2(0.18, 0.12))
	var sky_rect: Rect2 = Rect2(-3400.0, -700.0, 6800.0, 700.0 + FAR_BASELINE)
	_shader_rect(far, "Sky", sky_rect, "res://scenes/maps/rimefall/rimefall_sky.gdshader", {
		&"noise_tex": noise, &"moon_px": MOON - sky_rect.position, &"moon_radius": 22.0,
	})
	_backdrop(far, "FarRange", 0, FAR_BASELINE, {
		&"rock_shadow": Color(0.13, 0.17, 0.32), &"rock_lit": Color(0.18, 0.23, 0.4),
		&"snow_shadow": Color(0.26, 0.33, 0.55), &"snow_lit": Color(0.47, 0.56, 0.8),
		&"ground_color": Color(0.3, 0.37, 0.56), &"ground_deep": Color(0.2, 0.26, 0.44), &"seed_value": 21,
	})
	_shader_rect(far, "FarHaze", Rect2(-3400.0, FAR_BASELINE - 150.0, 6800.0, 230.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.62, 0.72, 0.92), &"density": 0.3, &"speed": 0.01,
		&"scale": 0.8, &"top_softness": 0.6, &"bottom_softness": 0.35,
	})
	# Mid: nearer, darker peaks over the frozen plain.
	var mid: Node2D = _layer(environment, "MidLayer", Vector2(0.36, 0.3))
	_backdrop(mid, "MidRange", 1, FAR_BASELINE + 62.0, {
		&"ground_color": Color(0.24, 0.3, 0.5), &"ground_deep": Color(0.12, 0.16, 0.32), &"seed_value": 34,
	})
	_shader_rect(mid, "MidHaze", Rect2(-3400.0, FAR_BASELINE - 30.0, 6800.0, 180.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.58, 0.68, 0.9), &"density": 0.22, &"speed": 0.016,
		&"scale": 1.1, &"top_softness": 0.5, &"bottom_softness": 0.4,
	})
	# Near: the pine forest on its snow ridge.
	var near: Node2D = _layer(environment, "NearLayer", Vector2(0.62, 0.55))
	_backdrop(near, "Forest", 2, 205.0, {
		&"ground_color": Color(0.16, 0.21, 0.38), &"ground_deep": Color(0.05, 0.07, 0.16), &"seed_value": 47,
	})
	_abyss(environment, Color(0.03, 0.04, 0.09), Color(0.55, 0.62, 0.8), 0.45)
	_sky_light(environment, "MoonLight", Vector2(WIDTH * 0.5 + MOON.x, -160.0), Color(0.78, 0.86, 1.0), 0.5, Color(0.02, 0.03, 0.08, 0.55))


func _backdrop(parent: Node, backdrop_name: String, kind: int, baseline: float, settings: Dictionary) -> void:
	var backdrop: Node2D = Node2D.new()
	backdrop.set_script(load("res://scenes/maps/rimefall/rimefall_backdrop.gd"))
	backdrop.set(&"kind", kind)
	backdrop.set(&"baseline", baseline)
	backdrop.set(&"moon_side", signf(MOON.x))
	for key in settings.keys():
		backdrop.set(key, settings[key])
	_add(parent, backdrop, backdrop_name)
