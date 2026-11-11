extends "res://tools/map_builder.gd"

## Builds res://scenes/maps/tidewater/tidewater_arena.tscn, the Tidewater world: a drowned temple.
## Run headless: godot --headless --path . -s res://tools/build_tidewater_map.gd
##
## Layout: unlike the other worlds this one is built upwards. Two stair towers (spawns on top, two steps
## down towards the middle) stand at the sides with a chasm at their feet; between them lies the sunken
## plaza with its altar dais, and over the plaza the temple hangs in floors of fallen stone: drums and
## steps out of the plaza, the docks and the bridge, the galleries, the cella with the crown and the apex
## on top, and a high road of arch, span and capital from the tower tops to the cella. The water column
## under the floors is open from tower to tower, which is where the sharks hunt.
## The tide (TidewaterTide) floods the plaza, the drums and the steps at high tide (FLOOD_LEVEL, the docks
## and the bridge stay just dry) and also the docks, the bridge, the galleries and the towers' steps at a
## spring tide (SPRING_LEVEL); the tower tops, the cella and everything above always stay dry.

const WIDTH: float = 2240.0
const HEIGHT: float = 800.0
const FLOOD_LEVEL: float = 500.0
const SPRING_LEVEL: float = 348.0
## Far-layer coordinates (origin = the arena's centre): where the sea meets the sky, and the moon.
const HORIZON: float = 30.0
const MOON: Vector2 = Vector2(-430.0, -215.0)


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
	_build_columns()
	_add_airdrops()
	_build_tide()
	_build_sharks()
	_build_weather()
	_build_skin()


# --- Profile & markers -----------------------------------------------------------------------------------

func _build_profile() -> void:
	var profile: MapProfile = MapProfile.new()
	profile.world_id = &"tidewater"
	profile.display_name = "Tidewater"
	profile.ambience = &"ambience_tidewater"
	profile.footstep = &"step_stone"
	profile.dust_color = Color(0.7, 0.82, 0.82, 0.42)
	profile.debris_color = Color(0.33, 0.39, 0.4, 1.0)
	profile.gravity_scale = 1.0
	profile.projectile_gravity_scale = 1.0
	profile.projectile_range_scale = 1.0
	profile.border_color = Color(0.42, 0.96, 0.88)
	_add(_root, profile, "MapProfile")
	_add_bounds()


func _build_markers() -> void:
	_add_markers({
		"Spawn1": Vector2(150.0, 270.0),
		"Spawn2": Vector2(WIDTH - 150.0, 270.0),
		# The sandbox target stands on the bridge: dry at high tide, so the sharks leave it alone.
		"DummySpawn1": Vector2(1190.0, 458.0),
	}, {
		# Under the cella and the spans, so the crates land on the bridge and the docks.
		"AirdropPointCenter": Vector2(WIDTH * 0.5, 400.0),
		"AirdropPointLeft": Vector2(680.0, 310.0),
		"AirdropPointRight": Vector2(WIDTH - 680.0, 310.0),
	})


# --- Geometry --------------------------------------------------------------------------------------------

func _build_geometry() -> void:
	# Spawn tower: the top at 300, two steps down towards the middle, then the wall into the chasm.
	var tower: Array = [
		Vector2(-80, 960), Vector2(-80, 300), Vector2(268, 300), Vector2(282, 304), Vector2(290, 316),
		Vector2(294, 376), Vector2(398, 376), Vector2(412, 380), Vector2(418, 392), Vector2(422, 452),
		Vector2(500, 452), Vector2(514, 458), Vector2(520, 474), Vector2(524, 960),
	]
	# The sunken plaza: the floor at 716 and the altar dais at 668 in the middle.
	var plaza_half: Array = [
		Vector2(640, 960), Vector2(640, 730), Vector2(652, 718), Vector2(668, 716), Vector2(1004, 716),
		Vector2(1056, 672), Vector2(1084, 668),
	]
	var plaza: Array = plaza_half + _mirror(plaza_half)
	_add_bodies({
		"LeftTower": tower,
		"Plaza": plaza,
		"RightTower": _mirror(tower),
		# Out of the plaza.
		"LeftDrum": _slab(700, 784, 640, 30),
		"RightDrum": _mirror(_slab(700, 784, 640, 30)),
		"LeftStep": _slab(826, 944, 564, 30),
		"RightStep": _mirror(_slab(826, 944, 564, 30)),
		# The first dry floor at high tide.
		# A full channel of water (76 px) is left between each tower's wall and its dock: a narrow slot there
		# was hard to climb out of.
		"LeftDock": _slab(600, 764, 488, 34),
		"RightDock": _mirror(_slab(600, 764, 488, 34)),
		"Bridge": _slab(1000, 1240, 488, 36),
		"LeftGallery": _slab(800, 960, 412, 32),
		"RightGallery": _mirror(_slab(800, 960, 412, 32)),
		# The last dry floor at a spring tide, and what stands on it.
		"Cella": _slab(1010, 1230, 336, 34),
		"Crown": _slab(1056, 1184, 260, 22),
		"Apex": _slab(1092, 1148, 184, 20),
		# The high road from the tower tops.
		"LeftArch": _slab(336, 524, 226, 34),
		"RightArch": _mirror(_slab(336, 524, 226, 34)),
		"LeftSpan": _slab(624, 764, 262, 30),
		"RightSpan": _mirror(_slab(624, 764, 262, 30)),
		"LeftCapital": _slab(838, 922, 300, 28),
		"RightCapital": _mirror(_slab(838, 922, 300, 28)),
	})


## The columns the floors stand on: scenery behind the terrain (see TidewaterColumns), so the temple reads
## as a building and not as loose stones in the air. (x, top y, foot y), left half; the right half mirrors.
func _build_columns() -> void:
	var left: Array = [
		# Docks: out of the chasm and off the plaza.
		Vector3(632, 522, 800), Vector3(724, 522, 720),
		# Galleries on the steps, capitals on the galleries, spans on the docks.
		Vector3(852, 444, 564), Vector3(918, 444, 564), Vector3(880, 328, 412), Vector3(694, 292, 488),
		# The arches on the towers' steps.
		Vector3(380, 260, 376), Vector3(478, 260, 452),
	]
	var middle: Array = [
		# The bridge on the plaza, the cella on the bridge, the crown on the cella.
		Vector3(1040, 524, 720), Vector3(1200, 524, 720), Vector3(1052, 370, 488), Vector3(1188, 370, 488),
		Vector3(1078, 282, 336), Vector3(1162, 282, 336),
	]
	var all: PackedVector3Array = PackedVector3Array(middle)
	for column in left:
		all.append(column)
		all.append(Vector3(WIDTH - column.x, column.y, column.z))
	var columns: Node2D = Node2D.new()
	columns.set_script(load("res://scenes/maps/tidewater/tidewater_columns.gd"))
	columns.z_index = -3
	columns.set(&"columns", all)
	columns.set(&"moon_x", WIDTH * 0.5 + MOON.x)
	_add(_root, columns, "Columns")


func _build_tide() -> void:
	var tide: Node2D = Node2D.new()
	tide.set_script(load("res://scenes/maps/tidewater/tidewater_tide.gd"))
	tide.set(&"arena_rect", Rect2(0.0, 0.0, WIDTH, HEIGHT))
	tide.set(&"ebb_level", HEIGHT + 12.0)
	tide.set(&"flood_level", FLOOD_LEVEL)
	tide.set(&"spring_level", SPRING_LEVEL)
	_add(_root, tide, "Tide")


func _build_sharks() -> void:
	var sharks: Node2D = Node2D.new()
	sharks.set_script(load("res://scenes/maps/tidewater/tidewater_sharks.gd"))
	# The open water between the towers' walls, the chasms they come up from, the plaza they swim over.
	sharks.set(&"lane", Vector2(566.0, WIDTH - 566.0))
	sharks.set(&"homes", PackedFloat32Array([582.0, WIDTH - 582.0]))
	sharks.set(&"floor_y", 716.0)
	_add(_root, sharks, "Sharks")


func _build_weather() -> void:
	var weather: Node2D = Node2D.new()
	weather.set_script(load("res://scenes/maps/tidewater/tidewater_weather.gd"))
	weather.set(&"arena_rect", Rect2(0.0, 0.0, WIDTH, HEIGHT))
	_add(_root, weather, "Weather")


func _build_skin() -> void:
	var skin: Node2D = Node2D.new()
	skin.set_script(load("res://scenes/maps/tidewater/tidewater_skin.gd"))
	var settings: Dictionary = {
		&"map_top_y": 180.0,
		&"map_bottom_y": 760.0,
		&"flood_level": FLOOD_LEVEL,
		&"spring_level": SPRING_LEVEL,
		&"outline_color": Color(0.015, 0.04, 0.05, 0.9),
		&"rim_color": Color(0.78, 0.97, 0.93, 0.75),
		&"vine_color": Color(0.1, 0.22, 0.17),
		&"lantern_color": Color(1.0, 0.72, 0.4),
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
	# Far: the sky down to the horizon, the open sea below it, headlands and the lighthouse on the line.
	var far: Node2D = _layer(environment, "FarLayer", Vector2(0.18, 0.12))
	var sky_rect: Rect2 = Rect2(-3400.0, -700.0, 6800.0, 700.0 + HORIZON)
	_shader_rect(far, "Sky", sky_rect, "res://scenes/maps/tidewater/tidewater_sky.gdshader", {
		&"noise_tex": noise, &"moon_px": MOON - sky_rect.position, &"moon_radius": 26.0,
	})
	_shader_rect(far, "Sea", Rect2(-3400.0, HORIZON, 6800.0, 1870.0), "res://scenes/maps/tidewater/far_sea.gdshader", {
		&"noise_tex": noise, &"moon_x": MOON.x + 3400.0, &"center_x": 3400.0,
	})
	_backdrop(far, "Headlands", 0, HORIZON, {
		&"top_color": Color(0.15, 0.31, 0.34), &"base_color": Color(0.2, 0.39, 0.4), &"seed_value": 3,
	})
	_shader_rect(far, "FarHaze", Rect2(-3400.0, HORIZON - 120.0, 6800.0, 190.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.5, 0.72, 0.7), &"density": 0.26, &"speed": 0.015,
		&"scale": 0.8, &"top_softness": 0.55, &"bottom_softness": 0.45,
	})
	# Mid: the drowned city.
	var mid: Node2D = _layer(environment, "MidLayer", Vector2(0.36, 0.3))
	_backdrop(mid, "Ruins", 1, HORIZON + 38.0, {&"seed_value": 5})
	_shader_rect(mid, "MidHaze", Rect2(-3400.0, HORIZON - 60.0, 6800.0, 170.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.42, 0.66, 0.66), &"density": 0.2, &"speed": 0.022,
		&"scale": 1.1, &"top_softness": 0.5, &"bottom_softness": 0.4,
	})
	# Near: rocks and the dark water under the ruins.
	var near: Node2D = _layer(environment, "NearLayer", Vector2(0.62, 0.55))
	_backdrop(near, "Rocks", 2, 215.0, {
		&"top_color": Color(0.05, 0.12, 0.15), &"base_color": Color(0.025, 0.07, 0.09), &"seed_value": 9,
	})
	_abyss(environment, Color(0.012, 0.05, 0.07), Color(0.32, 0.6, 0.6), 0.4)
	_sky_light(environment, "MoonLight", Vector2(WIDTH * 0.5 + MOON.x, -160.0), Color(0.7, 0.92, 1.0), 0.5, Color(0.0, 0.04, 0.06, 0.55))
	_motes(environment, "Spray", 50, Vector2(1.0, 0.2), Vector2(4.0, 6.0), Vector2(8.0, 20.0), Vector2(0.04, 0.09), Color(0.8, 1.0, 0.96, 0.28))


func _backdrop(parent: Node, backdrop_name: String, kind: int, waterline: float, settings: Dictionary) -> void:
	var backdrop: Node2D = Node2D.new()
	backdrop.set_script(load("res://scenes/maps/tidewater/tidewater_backdrop.gd"))
	backdrop.set(&"kind", kind)
	backdrop.set(&"waterline", waterline)
	backdrop.set(&"moon_x", MOON.x)
	for key in settings.keys():
		backdrop.set(key, settings[key])
	_add(parent, backdrop, backdrop_name)
