extends "res://tools/map_builder.gd"

## Builds res://scenes/maps/rimefall/rimefall_arena.tscn, the Rimefall world: a glacier pass at night.
## Run headless: godot --headless --path . -s res://tools/build_rimefall_map.gd
##
## Layout: two snowy cliffs (spawns) with a lower step each, chasms with a rock crag above them, and a
## frozen lake between two rock banks with a snow-capped rock island in its middle. Ice floes and a
## broad ice arch float above the lake. Bodies in the ice group (the lake, the floes, the arch) are glassy
## ice; everything else is snow on rock.

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
		"Spawn1": Vector2(150.0, 390.0),
		"Spawn2": Vector2(WIDTH - 150.0, 390.0),
		"DummySpawn1": Vector2(1300.0, 600.0),
	}, {
		"AirdropPointCenter": Vector2(WIDTH * 0.5, 306.0),
		"AirdropPointLeft": Vector2(777.0, 392.0),
		"AirdropPointRight": Vector2(WIDTH - 777.0, 392.0),
	})


# --- Geometry --------------------------------------------------------------------------------------------

func _build_geometry() -> void:
	var cliff: Array = [
		Vector2(-80, 960), Vector2(-80, 420), Vector2(296, 420), Vector2(310, 424), Vector2(318, 436),
		Vector2(322, 500), Vector2(440, 500), Vector2(454, 506), Vector2(460, 524), Vector2(464, 960),
	]
	# Rock crag over the chasm: the stepping stone from the cliff top out to the floes.
	var crag: Array = [
		Vector2(466, 438), Vector2(478, 432), Vector2(544, 432), Vector2(556, 440), Vector2(548, 458),
		Vector2(512, 466), Vector2(480, 458),
	]
	# Rock banks either side of the lake, sloping down to its shore.
	var bank: Array = [
		Vector2(600, 960), Vector2(600, 556), Vector2(612, 548), Vector2(690, 548), Vector2(704, 556),
		Vector2(728, 594), Vector2(756, 630), Vector2(782, 642), Vector2(782, 960),
	]
	# The frozen lake: one deep body of ice from shore to shore.
	var lake: Array = [
		Vector2(778, 640), Vector2(788, 634), Vector2(WIDTH - 788, 634), Vector2(WIDTH - 778, 640),
		Vector2(WIDTH - 778, 960), Vector2(778, 960),
	]
	# Snow-capped rock island standing in the ice: grip and cover in the middle of the rink.
	var island: Array = [
		Vector2(1030, 640), Vector2(1060, 612), Vector2(1090, 586), Vector2(1110, 582), Vector2(1130, 586),
		Vector2(1160, 612), Vector2(1190, 640),
	]
	var floe: Array = [
		Vector2(704, 472), Vector2(716, 466), Vector2(838, 466), Vector2(850, 472), Vector2(842, 486),
		Vector2(780, 494), Vector2(716, 486),
	]
	var arch: Array = [
		Vector2(950, 392), Vector2(962, 386), Vector2(1238, 386), Vector2(1250, 392), Vector2(1236, 408),
		Vector2(1100, 420), Vector2(964, 408),
	]
	_add_bodies({
		"LeftCliff": cliff,
		"LeftBank": bank,
		"RightBank": _mirror(bank),
		"RightCliff": _mirror(cliff),
		"Lake": lake,
		"Island": island,
		"LeftCrag": crag,
		"RightCrag": _mirror(crag),
		"LeftFloe": floe,
		"RightFloe": _mirror(floe),
		"IceArch": arch,
	}, {
		"Lake": [ICE_GROUP],
		"LeftFloe": [ICE_GROUP],
		"RightFloe": [ICE_GROUP],
		"IceArch": [ICE_GROUP],
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
		&"map_top_y": 360.0,
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
