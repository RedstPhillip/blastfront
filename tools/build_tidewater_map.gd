extends "res://tools/map_builder.gd"

## Builds res://scenes/maps/tidewater/tidewater_arena.tscn, the Tidewater world: a drowned temple.
## Run headless: godot --headless --path . -s res://tools/build_tidewater_map.gd
##
## Layout: two colonnades (spawns) with a lower stair each, a chasm on either side and the sunken
## courtyard between them with a low altar dais in the middle. Ruin blocks, broken arches and fallen
## column capitals step up to the temple pediment floating above the dais. The tide (TidewaterTide) floods
## the courtyard and the chasms at high tide (FLOOD_LEVEL) and also the lower stairs, the courtyard walls
## and the capitals at a spring tide (SPRING_LEVEL); the blocks, arches, pediment and spawns stay dry.

const WIDTH: float = 2240.0
const HEIGHT: float = 800.0
const FLOOD_LEVEL: float = 600.0
const SPRING_LEVEL: float = 506.0


func _configure() -> void:
	output_path = "res://scenes/maps/tidewater/tidewater_arena.tscn"
	root_name = "TidewaterArena"
	width = WIDTH
	height = HEIGHT


func _build() -> void:
	_build_profile()
	_build_environment()
	_build_markers()
	_build_geometry()
	_add_airdrops()
	_build_tide()
	_build_skin()


# --- Profile & markers -----------------------------------------------------------------------------------

func _build_profile() -> void:
	var profile: MapProfile = MapProfile.new()
	profile.world_id = &"tidewater"
	profile.display_name = "Tidewater"
	profile.ambience = &"ambience_tidewater"
	profile.gravity_scale = 1.0
	profile.projectile_gravity_scale = 1.0
	profile.projectile_range_scale = 1.0
	profile.border_color = Color(0.42, 0.96, 0.88)
	_add(_root, profile, "MapProfile")
	_add_bounds()


func _build_markers() -> void:
	_add_markers({
		"Spawn1": Vector2(150.0, 400.0),
		"Spawn2": Vector2(WIDTH - 150.0, 400.0),
		"DummySpawn1": Vector2(1300.0, 630.0),
	}, {
		"AirdropPointCenter": Vector2(WIDTH * 0.5, 282.0),
		"AirdropPointLeft": Vector2(815.0, 362.0),
		"AirdropPointRight": Vector2(WIDTH - 815.0, 362.0),
	})


# --- Geometry --------------------------------------------------------------------------------------------

func _build_geometry() -> void:
	# Spawn colonnade with its lower stair; the chasm opens at x 470.
	var colonnade: Array = [
		Vector2(-80, 960), Vector2(-80, 430), Vector2(296, 430), Vector2(310, 434), Vector2(318, 446),
		Vector2(322, 512), Vector2(446, 512), Vector2(460, 518), Vector2(466, 536), Vector2(470, 960),
	]
	# The sunken courtyard: walls at 548, slopes down to the floor at 664 and the altar dais at 620.
	var courtyard_half: Array = [
		Vector2(590, 960), Vector2(590, 556), Vector2(602, 548), Vector2(688, 548), Vector2(702, 556),
		Vector2(720, 590), Vector2(744, 632), Vector2(770, 660), Vector2(790, 664), Vector2(1000, 664),
		Vector2(1050, 622), Vector2(1080, 620),
	]
	var courtyard: Array = courtyard_half + _mirror(courtyard_half)
	# A fallen ruin block over the chasm: the step from the stair up towards the arches.
	var block: Array = [
		Vector2(500, 476), Vector2(512, 470), Vector2(574, 470), Vector2(586, 478), Vector2(578, 494),
		Vector2(540, 500), Vector2(508, 494),
	]
	var arch: Array = [
		Vector2(720, 438), Vector2(732, 432), Vector2(898, 432), Vector2(910, 440), Vector2(900, 458),
		Vector2(860, 466), Vector2(760, 466), Vector2(728, 456),
	]
	# Column capitals beside the dais: the way out of the courtyard towards the arches.
	var capital: Array = [
		Vector2(930, 546), Vector2(940, 540), Vector2(1000, 540), Vector2(1010, 546), Vector2(1004, 562),
		Vector2(980, 570), Vector2(960, 570), Vector2(936, 562),
	]
	var pediment: Array = [
		Vector2(1010, 362), Vector2(1022, 356), Vector2(1218, 356), Vector2(1230, 362), Vector2(1214, 376),
		Vector2(1120, 394), Vector2(1026, 376),
	]
	_add_bodies({
		"LeftColonnade": colonnade,
		"Courtyard": courtyard,
		"RightColonnade": _mirror(colonnade),
		"LeftBlock": block,
		"RightBlock": _mirror(block),
		"LeftArch": arch,
		"RightArch": _mirror(arch),
		"LeftCapital": capital,
		"RightCapital": _mirror(capital),
		"Pediment": pediment,
	})


func _build_tide() -> void:
	var tide: Node2D = Node2D.new()
	tide.set_script(load("res://scenes/maps/tidewater/tidewater_tide.gd"))
	tide.set(&"arena_rect", Rect2(0.0, 0.0, WIDTH, HEIGHT))
	tide.set(&"ebb_level", HEIGHT + 12.0)
	tide.set(&"flood_level", FLOOD_LEVEL)
	tide.set(&"spring_level", SPRING_LEVEL)
	_add(_root, tide, "Tide")


func _build_skin() -> void:
	var skin: Node2D = Node2D.new()
	skin.set_script(load("res://scenes/maps/environment/platform_skin.gd"))
	var settings: Dictionary = {
		&"map_top_y": 340.0,
		&"map_bottom_y": 720.0,
		&"high_color": Color(0.16, 0.2, 0.22),
		&"low_color": Color(0.2, 0.3, 0.3),
		&"deep_color": Color(0.03, 0.06, 0.07),
		&"outline_color": Color(0.02, 0.05, 0.06, 0.9),
		&"moss_color": Color(0.24, 0.42, 0.34),
		&"rim_color": Color(0.7, 0.95, 0.9, 0.7),
		&"rock_tint": Color(0.44, 0.47, 0.46),
		&"soil_top_color": Color(0.22, 0.4, 0.32),
		&"soil_deep_color": Color(0.1, 0.17, 0.16),
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
	var far: Node2D = _layer(environment, "FarLayer", Vector2(0.18, 0.12))
	var sky: TextureRect = TextureRect.new()
	sky.position = Vector2(-3400.0, -700.0)
	sky.size = Vector2(6800.0, 1000.0)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.03, 0.06, 0.1), Color(0.08, 0.18, 0.22), Color(0.2, 0.36, 0.38)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	sky.texture = texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_add(far, sky, "Sky")
	_fill(far, "FarFill", Rect2(-3400.0, 300.0, 6800.0, 1600.0), Color(0.2, 0.36, 0.38))
	_shader_rect(far, "FarHaze", Rect2(-3400.0, 60.0, 6800.0, 240.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.5, 0.72, 0.72), &"density": 0.3, &"speed": 0.015,
		&"scale": 0.8, &"top_softness": 0.5, &"bottom_softness": 0.3,
	})
	_abyss(environment, Color(0.02, 0.07, 0.09), Color(0.32, 0.6, 0.6), 0.4)
	_sky_light(environment, "MoonLight", Vector2(WIDTH * 0.3, -160.0), Color(0.7, 0.92, 1.0), 0.5, Color(0.0, 0.04, 0.06, 0.55))
	_motes(environment, "Spray", 50, Vector2(1.0, 0.2), Vector2(4.0, 6.0), Vector2(8.0, 20.0), Vector2(0.04, 0.09), Color(0.8, 1.0, 0.96, 0.28))
