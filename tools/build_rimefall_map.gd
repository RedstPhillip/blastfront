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
	_build_skin()


# --- Profile & markers -----------------------------------------------------------------------------------

func _build_profile() -> void:
	var profile: MapProfile = MapProfile.new()
	profile.world_id = &"rimefall"
	profile.display_name = "Rimefall"
	profile.ambience = &"ambience_rimefall"
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
	notice.set(&"detail", "Blue ice keeps your momentum, snow grips")
	notice.set(&"color", Color(0.66, 0.88, 1.0))
	_add(_root, notice, "IceNotice")


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
	var far: Node2D = _layer(environment, "FarLayer", Vector2(0.18, 0.12))
	var sky: TextureRect = TextureRect.new()
	sky.position = Vector2(-3400.0, -700.0)
	sky.size = Vector2(6800.0, 1000.0)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.02, 0.03, 0.08), Color(0.08, 0.12, 0.22), Color(0.3, 0.36, 0.5)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	sky.texture = texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_add(far, sky, "Sky")
	_fill(far, "FarFill", Rect2(-3400.0, 300.0, 6800.0, 1600.0), Color(0.3, 0.36, 0.5))
	_shader_rect(far, "FarHaze", Rect2(-3400.0, 60.0, 6800.0, 240.0), "res://scenes/maps/environment/fog.gdshader", {
		&"noise_tex": noise, &"fog_color": Color(0.7, 0.78, 0.92), &"density": 0.3, &"speed": 0.01,
		&"scale": 0.8, &"top_softness": 0.5, &"bottom_softness": 0.3,
	})
	_abyss(environment, Color(0.03, 0.04, 0.09), Color(0.55, 0.62, 0.8), 0.45)
	_sky_light(environment, "MoonLight", Vector2(WIDTH * 0.66, -160.0), Color(0.78, 0.86, 1.0), 0.5, Color(0.02, 0.03, 0.08, 0.55))
	_motes(environment, "Snow", 70, Vector2(0.2, 1.0), Vector2(2.0, 8.0), Vector2(10.0, 24.0), Vector2(0.04, 0.1), Color(0.95, 0.97, 1.0, 0.5))
