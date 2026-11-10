class_name TidewaterWeather
extends Node2D

## The weather that comes in with Tidewater's tide. At low water the night is clear: moon, stars, a few
## clouds. As a flood is announced the cloud cover closes and the sea darkens; rain falls while the water
## is up, and a spring tide brings the full storm with sheet lightning far out over the sea. It clears
## again as the tide drains. Looks and sound only: nothing here changes how the match plays, and since it
## follows the (synced) tide both players of an online match see the same sky.

const RAIN_SHADER: Shader = preload("res://scenes/maps/environment/rain.gdshader")
const RAIN_LOOP: AudioStream = preload("res://assets/audio/music/rain_loop.ogg")
const GATHER_SPEED: float = 0.2
const CLEAR_SPEED: float = 0.09
const RAIN_SILENT_DB: float = -46.0
const RAIN_FULL_DB: float = -12.0

@export var arena_rect: Rect2 = Rect2(0.0, 0.0, 2240.0, 800.0)
@export var tide_path: NodePath = ^"../Tide"

var _tide: TidewaterTide = null
var _storm: float = 0.0
var _flash: float = 0.0
var _flash_timer: float = 6.0
var _thunder_delay: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sky_material: ShaderMaterial = null
var _sea_material: ShaderMaterial = null
var _haze_materials: Array[ShaderMaterial] = []
var _haze_base: Array[float] = []
var _moon: PointLight2D = null
var _moon_energy: float = 0.0
var _rain: ColorRect = null
var _rain_material: ShaderMaterial = null
var _audio: AudioStreamPlayer = null
## The rain is drawn (too thin to see) for the first frames so its shader is compiled before the first
## squall instead of hitching when it starts.
var _warm_frames: int = 4


func _ready() -> void:
	_rng.randomize()
	_tide = get_node_or_null(tide_path) as TidewaterTide
	_bind_environment()
	_build_rain()
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Ambience"
	(RAIN_LOOP as AudioStreamOggVorbis).loop = true
	_audio.stream = RAIN_LOOP
	_audio.volume_db = RAIN_SILENT_DB
	add_child(_audio)


func _bind_environment() -> void:
	var arena: Node = get_parent()
	_sky_material = _material_of(arena.get_node_or_null(^"Environment/FarLayer/Sky"))
	_sea_material = _material_of(arena.get_node_or_null(^"Environment/FarLayer/Sea"))
	for path in [^"Environment/FarLayer/FarHaze", ^"Environment/MidLayer/MidHaze"]:
		var material: ShaderMaterial = _material_of(arena.get_node_or_null(path))
		if material != null:
			_haze_materials.append(material)
			_haze_base.append(float(material.get_shader_parameter(&"density")))
	_moon = arena.get_node_or_null(^"Environment/MoonLight") as PointLight2D
	if _moon != null:
		_moon_energy = _moon.energy


func _material_of(node: Node) -> ShaderMaterial:
	var item: CanvasItem = node as CanvasItem
	return item.material as ShaderMaterial if item != null else null


func _build_rain() -> void:
	_rain = ColorRect.new()
	_rain.name = "Rain"
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.position = arena_rect.position - Vector2(700.0, 500.0)
	_rain.size = arena_rect.size + Vector2(1400.0, 700.0)
	_rain.z_index = 15
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain.material = _rain_material
	_rain.visible = false
	add_child(_rain)


func _process(delta: float) -> void:
	var target: float = _tide.weather_target() if _tide != null else 0.0
	_storm = move_toward(_storm, target, delta * (GATHER_SPEED if target > _storm else CLEAR_SPEED))
	var rain: float = smoothstep(0.3, 0.95, _storm) * clampf(GameJuice.particles_multiplier, 0.0, 1.0)
	_update_lightning(delta)
	if _sky_material != null:
		_sky_material.set_shader_parameter(&"storm", _storm)
		_sky_material.set_shader_parameter(&"flash", _flash)
	if _sea_material != null:
		_sea_material.set_shader_parameter(&"storm", _storm)
	for index in range(_haze_materials.size()):
		_haze_materials[index].set_shader_parameter(&"density", _haze_base[index] * (1.0 + _storm * 0.9))
	if _moon != null:
		_moon.energy = _moon_energy * (1.0 - _storm * 0.35) + _flash * 0.5
	_warm_frames = maxi(_warm_frames - 1, 0)
	_rain.visible = rain > 0.01 or _warm_frames > 0
	if _rain.visible:
		_rain_material.set_shader_parameter(&"intensity", maxf(rain, 0.011))
		_rain_material.set_shader_parameter(&"floor_y", WorldConditions.water_level)
	if _tide != null:
		_tide.set_rain(rain)
	_update_audio(smoothstep(0.3, 0.95, _storm))


## Sheet lightning: only in the storm of a spring tide, far away, with its thunder arriving late.
func _update_lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.2, 0.0)
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0:
			AudioDirector.play(&"thunder")
	if _tide == null or not _tide.is_spring_tide_up() or _storm < 0.8:
		_flash_timer = minf(_flash_timer, 3.0)
		return
	_flash_timer -= delta
	if _flash_timer > 0.0:
		return
	_flash_timer = _rng.randf_range(4.5, 9.0)
	_flash = _rng.randf_range(0.6, 1.0) * UserSettings.get_float(UserSettings.SCREEN_FLASH)
	_thunder_delay = _rng.randf_range(0.9, 2.2)
	if _sky_material != null:
		_sky_material.set_shader_parameter(&"flash_x", 3400.0 + _rng.randf_range(-900.0, 900.0))


func _update_audio(rain: float) -> void:
	if rain <= 0.01:
		if _audio.playing:
			_audio.stop()
		return
	if not _audio.playing:
		_audio.play(_rng.randf_range(0.0, 10.0))
	_audio.volume_db = lerpf(RAIN_SILENT_DB, RAIN_FULL_DB, sqrt(rain))


## Tests: jump straight to a weather state.
func force_storm(amount: float) -> void:
	_storm = amount
