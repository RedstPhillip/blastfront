class_name TidewaterTide
extends Node2D

## The tide of Tidewater. Low water (ebb, the sea out of sight below the ruins) alternates with high water.
## Every flood is announced a few seconds ahead: a conch horn sounds, a notice names it and a glowing tide
## line lights up across the ruins at the height the water will reach. Then the sea pours in, holds the
## courtyard and the chasms under water and drains away again. Every few tides a spring tide climbs higher
## and also drowns the courtyard walls, the lower stairs and the capitals; the blocks, the arches, the
## pediment and the spawns always stay dry. In the water players swim (see Player and SwimState) and
## rounds drag to a stop. The level goes through WorldConditions.water_level, so the water you see is
## exactly where the water is.

enum Phase { EBB, WARNING, RISING, FLOOD, FALLING }

const SEA_SHADER: Shader = preload("res://scenes/maps/tidewater/sea.gdshader")
const TIDE_LINE_SHADER: Shader = preload("res://scenes/maps/tidewater/tide_line.gdshader")
const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")

const FIRST_TIDE: float = 9.0
const EBB_TIME: Vector2 = Vector2(14.0, 20.0)
const WARNING_TIME: float = 4.0
const RISE_TIME: float = 5.0
const FLOOD_TIME: Vector2 = Vector2(11.0, 14.0)
const SPRING_FLOOD_TIME: Vector2 = Vector2(8.0, 10.0)
const FALL_TIME: float = 5.5
## Height of the swell on a standing flood (px); slow enough to read as the sea breathing.
const SWELL: float = 3.0
const SURFACE_PAD: float = 16.0

@export var arena_rect: Rect2 = Rect2(0.0, 0.0, 2240.0, 800.0)
## Water surface at low tide: just under the map's bottom edge, so the chasms are open abyss.
@export var ebb_level: float = 812.0
@export var flood_level: float = 600.0
@export var spring_level: float = 506.0
@export var tide_color: Color = Color(0.45, 1.0, 0.9)

var _phase: Phase = Phase.EBB
var _timer: float = FIRST_TIDE
var _phase_length: float = FIRST_TIDE
var _spring: bool = false
var _tide_count: int = 0
var _time: float = 0.0
var _level: float = 812.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Counts phase changes so the online client can tell a new tide from a late copy of the old one.
var _step: int = 0
## Online client: the host's tide drives this one (see WorldSync), so both players swim in the same sea.
var _follow_host: bool = false

var _sea: ColorRect = null
var _sea_material: ShaderMaterial = null
var _tide_line: ColorRect = null
var _tide_line_material: ShaderMaterial = null


func _ready() -> void:
	_rng.randomize()
	_follow_host = NetworkSession.is_client()
	add_to_group(WorldSync.GROUP)
	_level = ebb_level
	_build_sea()
	_build_tide_line()
	_apply_level()


func _exit_tree() -> void:
	WorldConditions.water_level = INF
	WorldConditions.water_forecast = INF


func _build_sea() -> void:
	_sea = ColorRect.new()
	_sea.name = "Sea"
	_sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sea.position = Vector2(arena_rect.position.x - 900.0, 0.0)
	_sea.size = Vector2(arena_rect.size.x + 1800.0, 700.0)
	_sea.z_index = 5
	_sea_material = ShaderMaterial.new()
	_sea_material.shader = SEA_SHADER
	_sea_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	_sea_material.set_shader_parameter(&"surface_pad", SURFACE_PAD)
	_sea.material = _sea_material
	add_child(_sea)


func _build_tide_line() -> void:
	_tide_line = ColorRect.new()
	_tide_line.name = "TideLine"
	_tide_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tide_line.position = Vector2(arena_rect.position.x, flood_level - 12.0)
	_tide_line.size = Vector2(arena_rect.size.x, 24.0)
	_tide_line.z_index = 6
	_tide_line_material = ShaderMaterial.new()
	_tide_line_material.shader = TIDE_LINE_SHADER
	_tide_line_material.set_shader_parameter(&"line_color", tide_color)
	_tide_line.material = _tide_line_material
	_tide_line.visible = false
	add_child(_tide_line)


# --- Director -----------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_timer -= delta
	if _timer <= 0.0 and not _follow_host:
		_advance_phase()
	_level = _compute_level()
	_apply_level()


func _process(_delta: float) -> void:
	var surge: float = 0.0
	if _phase == Phase.RISING or _phase == Phase.FALLING:
		surge = sin(PI * clampf(_progress(), 0.0, 1.0))
	_sea_material.set_shader_parameter(&"surge", surge)
	var line_strength: float = 0.0
	match _phase:
		Phase.WARNING:
			line_strength = smoothstep(0.0, 0.3, _progress())
		Phase.RISING:
			line_strength = 1.0 - smoothstep(0.6, 1.0, _progress())
	_tide_line.visible = line_strength > 0.01
	if _tide_line.visible:
		_tide_line.position.y = target_level() - 12.0
		_tide_line_material.set_shader_parameter(&"strength", line_strength)


func _apply_level() -> void:
	WorldConditions.water_level = _level
	WorldConditions.water_forecast = forecast_level()
	_sea.position.y = _level - SURFACE_PAD
	# The sea is out of sight under the abyss at low tide; skip drawing it there.
	_sea.visible = _level < arena_rect.end.y + 4.0


func _progress() -> float:
	return 1.0 - clampf(_timer / maxf(_phase_length, 0.01), 0.0, 1.0)


func _compute_level() -> float:
	var high: float = target_level()
	match _phase:
		Phase.RISING:
			return lerpf(ebb_level, high, smoothstep(0.0, 1.0, _progress()))
		Phase.FLOOD:
			# A slow swell that starts and ends level, so the flood joins the rise and the fall smoothly.
			return high + SWELL * sin(TAU * (_phase_length - _timer) / 6.0) * sin(PI * _progress())
		Phase.FALLING:
			return lerpf(high, ebb_level, smoothstep(0.0, 1.0, _progress()))
	return ebb_level


## How high the current (or announced) tide climbs.
func target_level() -> float:
	return spring_level if _spring else flood_level


## Where the water will stand at its highest before it next drains: what a bot avoids.
func forecast_level() -> float:
	match _phase:
		Phase.WARNING, Phase.RISING, Phase.FLOOD:
			return target_level() - SWELL
	return _level


func get_level() -> float:
	return _level


func _advance_phase() -> void:
	match _phase:
		Phase.EBB:
			_begin_warning()
		Phase.WARNING:
			_enter_phase(Phase.RISING, RISE_TIME)
		Phase.RISING:
			var hold: Vector2 = SPRING_FLOOD_TIME if _spring else FLOOD_TIME
			_enter_phase(Phase.FLOOD, _rng.randf_range(hold.x, hold.y))
		Phase.FLOOD:
			_enter_phase(Phase.FALLING, FALL_TIME)
		Phase.FALLING:
			_enter_phase(Phase.EBB, _rng.randf_range(EBB_TIME.x, EBB_TIME.y))


func _enter_phase(next_phase: Phase, length: float) -> void:
	_phase = next_phase
	_phase_length = length
	_timer = length
	_step += 1
	_play_phase_cue()


func _begin_warning(forced_spring: int = -1) -> void:
	_tide_count += 1
	_spring = _tide_count % 3 == 0 or _rng.randf() < 0.12
	if forced_spring >= 0:
		_spring = forced_spring == 1
	_enter_phase(Phase.WARNING, WARNING_TIME)


func _play_phase_cue() -> void:
	match _phase:
		Phase.WARNING:
			AudioDirector.play(&"tide_horn")
			if _spring:
				HudToasts.notify("SPRING TIDE", "▲▲  Only the heights stay dry", Color(0.5, 0.92, 1.0), &"")
			else:
				HudToasts.notify("HIGH TIDE", "▲  Low ground floods", tide_color, &"")
		Phase.RISING:
			AudioDirector.play(&"tide_surge")
		Phase.FALLING:
			AudioDirector.play(&"tide_drain")


# --- Online ---------------------------------------------------------------------------------------------------

func net_state() -> Dictionary:
	return {
		"step": _step,
		"phase": int(_phase),
		"timer": _timer,
		"length": _phase_length,
		"spring": _spring,
		"count": _tide_count,
		"time": _time,
	}


func apply_net_state(state: Dictionary) -> void:
	var step: int = int(state.get("step", _step))
	var next_phase: Phase = int(state.get("phase", _phase)) as Phase
	var changed: bool = step != _step and next_phase != _phase
	_step = step
	_phase = next_phase
	_timer = float(state.get("timer", _timer))
	_phase_length = float(state.get("length", _phase_length))
	_spring = state.get("spring", _spring) == true
	_tide_count = int(state.get("count", _tide_count))
	_time = float(state.get("time", _time))
	if changed:
		_play_phase_cue()


# --- Tests -----------------------------------------------------------------------------------------------------

## Tests: announce a tide now (or skip straight to the rising water).
func skip_to_tide(spring: bool = false, with_warning: bool = true) -> void:
	_begin_warning(1 if spring else 0)
	if not with_warning:
		_timer = 0.02


## Tests: hold the water at the top of a flood (or a spring tide) until told otherwise.
func hold_flood(spring: bool = false) -> void:
	_spring = spring
	_phase = Phase.FLOOD
	_phase_length = 100000.0
	_timer = 100000.0
	_step += 1
