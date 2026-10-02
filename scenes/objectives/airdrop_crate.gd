extends Node2D
class_name AirdropCrate

## The supply drop as one event, driven by the manager's phase:
##   warning  - a signal flare starts smoking on the landing spot and the capture ring fades in, while a
##              transport passes high overhead (the manager plays the radio chirp and the flyover)
##   falling  - the canopy snaps open far above and the crate sinks on it, swaying less as it nears;
##              its shadow on the ground grows and its beacon blinks
##   landed   - the crate hits the dirt (squash, dust, debris, shock ring, shake by distance), the canopy
##              collapses and drifts off; standing in the ring fills it in the capturer's colour and the
##              three latches on the lid spring open one by one
##   captured - a pressure seal hisses, the lid flies off, research light pours out and the points fly to
##              the counter; afterwards the open crate stays a moment, then fades
## Everything is drawn here in the same outlined style as the weapon art, so no texture can go stale.

const BODY_HALF: float = 32.0
const BODY_HEIGHT: float = 32.0
const LID_HEIGHT: float = 11.0
const LID_OVERHANG: float = 3.0
const CANOPY_OFFSET: float = -150.0
const CANOPY_SIZE: Vector2 = Vector2(62.0, 50.0)
const DROP_HEIGHT: float = 430.0
const CRATE_SCALE: float = 1.25
const LATCH_X: Array[float] = [-20.0, 0.0, 20.0]
const LATCH_THRESHOLDS: Array[float] = [0.25, 0.5, 0.75]
const OUTLINE: Color = Color(0.035, 0.04, 0.045, 1.0)
const BODY: Color = Color(0.36, 0.41, 0.31, 1.0)
const BODY_DARK: Color = Color(0.28, 0.32, 0.245, 1.0)
const BODY_LIGHT: Color = Color(0.5, 0.56, 0.43, 1.0)
const STEEL: Color = Color(0.15, 0.17, 0.18, 1.0)
const STEEL_LIGHT: Color = Color(0.36, 0.39, 0.41, 1.0)
const CANOPY_A: Color = Color(0.93, 0.88, 0.76, 1.0)
const CANOPY_B: Color = Color(0.86, 0.47, 0.22, 1.0)
const FLARE: Color = Color(1.0, 0.5, 0.22, 1.0)
const DUST: Color = Color(0.74, 0.72, 0.6, 0.55)

var _phase: StringName = &"inactive"
var _descent: float = 0.0
var _capture: float = 0.0
var _capturing_slot: int = 0
var _contested: bool = false
var _radius: float = GameSettings.AIRDROP_BASE_CAPTURE_RADIUS
var _reward: int = GameSettings.AIRDROP_BASE_RESEARCH_REWARD
var _time: float = 0.0
var _zone_alpha: float = 0.0
var _squash: float = 0.0
var _latches: Array[float] = [0.0, 0.0, 0.0]
var _latch_open: Array[bool] = [false, false, false]
var _canopy_attached: bool = true
var _canopy_collapse: float = 0.0
var _canopy_drift: Vector2 = Vector2.ZERO
var _lid_attached: bool = true
var _lid_position: Vector2 = Vector2.ZERO
var _lid_rotation: float = 0.0
var _lid_flight: float = -1.0
var _lid_side: float = 1.0
var _glow: float = 0.0
var _beams: float = 0.0
var _beacon_on: bool = false
var _dismissed: bool = false
var _landed_shown: bool = false
var _opened_shown: bool = false

var _zone: Node2D = null
var _rig: Node2D = null
var _canopy: Node2D = null
var _lid: Node2D = null
var _overlay: Node2D = null
var _flare: CPUParticles2D = null
var _flare_core: Sprite2D = null
var _beacon: Sprite2D = null
var _wind: AudioStreamPlayer2D = null


func _ready() -> void:
	# Level with the players (who are drawn after it), so whoever captures stays visible in front of the crate.
	z_index = 0
	_zone = _layer(-3, _draw_zone)
	_flare = _make_flare()
	_flare_core = _glow_sprite(FLARE, 70.0, -1)
	_flare_core.position = Vector2(0.0, -4.0)
	_rig = _layer(0, _draw_rig)
	_canopy = _layer(-1, _draw_canopy)
	_lid = _layer(1, _draw_lid)
	_beacon = _glow_sprite(Color(1.0, 0.55, 0.2, 1.0), 64.0, 2)
	_overlay = _layer(6, _draw_overlay)
	_wind = AudioStreamPlayer2D.new()
	_wind.bus = &"SFX"
	_wind.stream = load("res://assets/audio/sfx/airdrop_descent.ogg")
	_wind.volume_db = -4.0
	_wind.max_distance = 2200.0
	_wind.attenuation = 0.6
	add_child(_wind)
	_flare.emitting = false
	_flare_core.visible = false
	_rig.visible = false
	_canopy.visible = false
	_lid.visible = false
	_beacon.visible = false


func _layer(z: int, painter: Callable) -> Node2D:
	var layer: Node2D = Node2D.new()
	layer.z_index = z
	layer.draw.connect(painter)
	add_child(layer)
	return layer


func _glow_sprite(color: Color, size: float, z: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = FxLib.TEX_GLOW
	sprite.material = FxLib.additive_material()
	sprite.modulate = color
	sprite.scale = Vector2.ONE * size / float(FxLib.TEX_GLOW.get_width())
	sprite.z_index = z
	add_child(sprite)
	return sprite


## The signal flare: a thin column of amber smoke that leans with the wind.
func _make_flare() -> CPUParticles2D:
	var smoke: CPUParticles2D = CPUParticles2D.new()
	smoke.texture = FxLib.TEX_SMOKE
	smoke.amount = maxi(8, int(28.0 * maxf(GameJuice.particles_multiplier, 0.3)))
	smoke.lifetime = 2.8
	smoke.preprocess = 0.0
	smoke.local_coords = false
	smoke.direction = Vector2(0.12, -1.0)
	smoke.spread = 9.0
	smoke.initial_velocity_min = 26.0
	smoke.initial_velocity_max = 44.0
	smoke.gravity = Vector2(7.0, -6.0)
	smoke.damping_min = 4.0
	smoke.damping_max = 10.0
	smoke.scale_amount_min = 0.16
	smoke.scale_amount_max = 0.3
	smoke.scale_amount_curve = FxLib.curve(&"grow")
	smoke.color = Color(0.9, 0.74, 0.6, 0.24)
	smoke.color_ramp = FxLib.fade_ramp(&"late")
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.angular_velocity_min = -20.0
	smoke.angular_velocity_max = 20.0
	smoke.position = Vector2(0.0, -4.0)
	smoke.z_index = -2
	add_child(smoke)
	return smoke


# --- State -----------------------------------------------------------------------------------------------

func apply_state(state: Dictionary) -> void:
	if _dismissed:
		return
	var previous: StringName = _phase
	_phase = StringName(str(state.get("phase", str(_phase))))
	_descent = clampf(float(state.get("descent_progress", _descent)), 0.0, 1.0)
	_capture = clampf(float(state.get("capture_progress", _capture)), 0.0, 1.0)
	_capturing_slot = int(state.get("capturing_slot", _capturing_slot))
	_contested = bool(state.get("contested", false))
	_radius = maxf(float(state.get("local_capture_radius", _radius)), 24.0)
	_reward = int(state.get("local_reward", _reward))
	if previous != _phase:
		_on_phase(previous, _phase)
	_update_latches()


func _on_phase(previous: StringName, next: StringName) -> void:
	match next:
		&"warning":
			_flare.emitting = true
			_flare_core.visible = true
			_flare_core.modulate.a = 0.0
		&"falling":
			_flare.emitting = true
			_flare_core.visible = true
			_rig.visible = true
			_canopy.visible = true
			_lid.visible = true
			_beacon_on = true
			AudioDirector.play_at(&"airdrop_chute", global_position + Vector2(0.0, -DROP_HEIGHT), 0.0)
			_wind.play()
		&"landed":
			_rig.visible = true
			_lid.visible = true
			_beacon_on = true
			if previous == &"falling":
				_land()
			else:
				_canopy.visible = false
		&"captured":
			_rig.visible = true
			_lid.visible = true
			_open()


## Called by the manager when the drop is cleared. A captured crate stays open on the ground for a moment
## before it fades; anything else (the round ended) fades straight away.
func dismiss(captured: bool) -> void:
	if _dismissed:
		return
	_dismissed = true
	_flare.emitting = false
	_beacon_on = false
	var tween: Tween = create_tween()
	if captured:
		tween.tween_interval(3.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.8 if captured else 0.35)
	tween.parallel().tween_property(_wind, "volume_db", -40.0, 0.3)
	tween.tween_callback(queue_free)


func _land() -> void:
	if _landed_shown:
		return
	_landed_shown = true
	_squash = 1.0
	_canopy_attached = false
	_canopy_drift = Vector2(randf_range(0.6, 1.0) * (1.0 if randf() < 0.5 else -1.0), 0.0)
	_flare.emitting = false
	_wind.stop()
	AudioDirector.play_at(&"airdrop_land", global_position, 0.0)
	var strength: float = _distance_falloff()
	GameJuice.shake(3.4 * strength, 0.22)
	FxLib.ring(self, Color(1.0, 0.96, 0.86, 0.32), 26.0, 170.0, 0.45, false, -1)
	FxLib.light_flash(self, Color(1.0, 0.82, 0.55), 0.9, 140.0, 0.35)
	for side in [-1.0, 1.0]:
		FxLib.emit(self, {"texture": FxLib.TEX_SMOKE, "amount": 10, "lifetime": 0.9, "direction": Vector2(side, -0.25), "spread": 22.0,
			"speed": Vector2(90.0, 230.0), "gravity": Vector2(0, -24), "damping": Vector2(160, 260), "size": Vector2(0.16, 0.34),
			"curve": &"grow", "color": DUST, "fade": &"out", "radius": 10.0, "spin": Vector2(-60, 60), "z": 2})
	FxLib.emit(self, {"texture": FxLib.TEX_DEBRIS, "amount": 9, "lifetime": 0.7, "direction": Vector2.UP, "spread": 65.0,
		"speed": Vector2(140.0, 300.0), "gravity": Vector2(0, 980), "size": Vector2(0.14, 0.26), "color": Color(0.32, 0.36, 0.27, 1.0),
		"spin": Vector2(-500, 500), "z": 3})


func _open() -> void:
	if _opened_shown:
		return
	_opened_shown = true
	if not _landed_shown:
		_land()
	_lid_attached = false
	_lid_flight = 0.0
	_lid_side = 1.0 if randf() < 0.5 else -1.0
	_glow = 1.0
	_beams = 1.0
	_beacon_on = false
	for index in range(3):
		_latch_open[index] = true
	AudioDirector.play_at(&"airdrop_open", global_position, 0.0)
	GameJuice.shake(1.6 * _distance_falloff(), 0.12)
	FxLib.glow_flash(self, Color(0.45, 1.0, 0.88, 0.9), 220.0, 0.7, 5).position = _crate_point(Vector2(0.0, -BODY_HEIGHT))
	FxLib.light_flash(self, Color(0.5, 1.0, 0.9), 1.2, 180.0, 0.6)
	FxLib.emit(self, {"texture": FxLib.TEX_SQUARE, "amount": 18, "lifetime": 1.1, "direction": Vector2.UP, "spread": 30.0,
		"speed": Vector2(60.0, 170.0), "gravity": Vector2(0, -40), "damping": Vector2(40, 80), "size": Vector2(0.18, 0.4),
		"color": Color(0.5, 1.0, 0.88, 0.95), "fade": &"out", "additive": true, "radius": 14.0, "spin": Vector2(-200, 200), "z": 5,
		"offset": _crate_point(Vector2(0.0, -BODY_HEIGHT))})
	var local_won: bool = _capturing_slot == NetworkSession.local_player_slot
	if local_won:
		HudRewardFlight.launch(global_position + _crate_point(Vector2(0.0, -BODY_HEIGHT - 10.0)), _reward)


## 1 when the local player is close, falling off towards the edge of the screen and beyond.
func _distance_falloff() -> float:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	var local: Node2D = world.get_local_player() if world != null and world.has_method(&"get_local_player") else null
	if local == null:
		return 0.6
	return clampf(1.25 - local.global_position.distance_to(global_position) / 900.0, 0.25, 1.0)


func _update_latches() -> void:
	if _phase != &"landed":
		return
	for index in range(3):
		var open: bool = _capture >= LATCH_THRESHOLDS[index]
		if open == _latch_open[index]:
			continue
		_latch_open[index] = open
		var at: Vector2 = global_position + _crate_point(Vector2(LATCH_X[index], -BODY_HEIGHT))
		if open:
			AudioDirector.play_at(&"airdrop_latch", at, 0.0, 1.0 + 0.09 * float(index))
			FxLib.emit(self, {"texture": FxLib.TEX_SPARK, "amount": 5, "lifetime": 0.25, "direction": Vector2.UP, "spread": 70.0,
				"speed": Vector2(60.0, 140.0), "gravity": Vector2(0, 500), "size": Vector2(0.12, 0.22), "align": true,
				"color": Color(1.0, 0.8, 0.45, 1.0), "z": 7, "offset": _crate_point(Vector2(LATCH_X[index], -BODY_HEIGHT))})
		else:
			AudioDirector.play_at(&"airdrop_latch", at, -8.0, 0.78)


# --- Animation -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var zone_target: float = 1.0 if _phase in [&"warning", &"falling", &"landed"] and not _dismissed else 0.0
	_zone_alpha = move_toward(_zone_alpha, zone_target, delta * (2.5 if zone_target > 0.0 else 4.0))
	_squash = move_toward(_squash, 0.0, delta * 3.2)
	_glow = move_toward(_glow, 0.0, delta * 1.3)
	_beams = move_toward(_beams, 0.0, delta * 0.9)
	for index in range(3):
		_latches[index] = move_toward(_latches[index], 1.0 if _latch_open[index] else 0.0, delta * 9.0)

	# The crate sinks at a steady rate, swaying less the lower it gets.
	var height: float = 0.0
	if _phase == &"falling":
		height = (1.0 - _descent) * DROP_HEIGHT
	var sway: float = (1.0 - _descent) if _phase == &"falling" else 0.0
	_rig.position = Vector2(sin(_time * 1.15) * 9.0 * sway, -height)
	_rig.rotation = sin(_time * 1.7) * 0.05 * sway
	# Damped squash: widest and flattest at the moment of impact, then a couple of settling wobbles.
	var squash: float = _squash * cos((1.0 - _squash) * 14.0) if _squash > 0.0 else 0.0
	_rig.scale = Vector2(1.0 + squash * 0.16, 1.0 - squash * 0.2) * CRATE_SCALE
	if _canopy_attached:
		_canopy.position = _rig.position
		_canopy.rotation = _rig.rotation
		_canopy.scale = Vector2(1.0 + sin(_time * 8.0) * 0.015, 1.0 - sin(_time * 8.0) * 0.01) * CRATE_SCALE
	elif _canopy.visible:
		_canopy_collapse = move_toward(_canopy_collapse, 1.0, delta / 1.3)
		var c: float = _canopy_collapse
		var fall: float = 1.0 - (1.0 - c) * (1.0 - c)
		_canopy.position = Vector2(_canopy_drift.x * 70.0 * fall, -CANOPY_OFFSET * CRATE_SCALE * fall * 0.85)
		_canopy.rotation = _canopy_drift.x * 1.1 * fall
		_canopy.scale = Vector2(1.0 + 0.2 * fall, maxf(1.0 - 0.8 * fall, 0.12)) * CRATE_SCALE
		_canopy.modulate.a = 1.0 - smoothstep(0.55, 1.0, c)
		if c >= 1.0:
			_canopy.visible = false
	if not _lid_attached:
		_update_lid_flight(delta)
	_lid.position = _rig.position if _lid_attached else _lid_position
	_lid.rotation = _rig.rotation if _lid_attached else _lid_rotation
	_lid.scale = _rig.scale if _lid_attached else Vector2.ONE * CRATE_SCALE

	# Beacon: a short amber flash every second while the crate is closed.
	var blink: float = 1.0 if fmod(_time, 1.0) < 0.12 else 0.18
	_beacon.visible = _beacon_on and _lid_attached
	_beacon.position = _rig.position + Vector2(0.0, -BODY_HEIGHT - LID_HEIGHT - 4.0).rotated(_rig.rotation) * Vector2(_rig.scale.x, _rig.scale.y)
	_beacon.modulate.a = blink
	var flare_target: float = 0.8 + 0.2 * sin(_time * 23.0) * sin(_time * 7.0) if _flare.emitting else 0.0
	_flare_core.modulate.a = move_toward(_flare_core.modulate.a, flare_target, delta * 3.0)
	_flare_core.visible = _flare_core.modulate.a > 0.01
	_zone.queue_redraw()
	_rig.queue_redraw()
	_lid.queue_redraw()
	_canopy.queue_redraw()
	_overlay.queue_redraw()


# --- Drawing ---------------------------------------------------------------------------------------------

func _capturer_color() -> Color:
	if _capturing_slot <= 0:
		return Color(1, 1, 1, 1)
	return UiStyle.player_color(_capturing_slot)


## Ground shadow, the capture ring and its progress. The ring is the progress bar: it fills around in the
## colour of whoever stands inside, and flickers white and red while both players contest it.
func _draw_zone() -> void:
	var a: float = _zone_alpha
	if a <= 0.0 and _phase != &"falling":
		return
	var shadow: float = _descent if _phase == &"falling" else (1.0 if _phase in [&"landed", &"captured"] else 0.0)
	if shadow > 0.0:
		var rx: float = lerpf(10.0, 40.0 * CRATE_SCALE, shadow)
		_zone.draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.2))
		_zone.draw_circle(Vector2.ZERO, rx, Color(0.0, 0.0, 0.0, lerpf(0.06, 0.4, shadow)), true, -1.0, true)
		_zone.draw_set_transform(Vector2.ZERO)
	if a <= 0.0:
		return
	var center: Vector2 = _crate_point(Vector2(0.0, -BODY_HEIGHT * 0.5))
	var radius: float = _radius * lerpf(0.6, 1.0, smoothstep(0.0, 1.0, a))
	_zone.draw_circle(center, radius, Color(1.0, 1.0, 1.0, 0.035 * a), true, -1.0, true)
	if _phase != &"landed":
		var segments: int = 28
		var turn: float = _time * 0.25
		for index in range(segments):
			var from: float = turn + TAU * float(index) / float(segments)
			_zone.draw_arc(center, radius, from, from + TAU / float(segments) * 0.55, 6, Color(1.0, 0.9, 0.75, 0.32 * a), 1.5, true)
		return
	var ring: Color = Color(1.0, 1.0, 1.0, 0.22 * a)
	if _contested:
		ring = Color(1.0, 0.4, 0.38, 0.75 * a) if fmod(_time, 0.3) < 0.15 else Color(1.0, 1.0, 1.0, 0.6 * a)
	_zone.draw_arc(center, radius, 0.0, TAU, 72, ring, 2.0, true)
	if _capture > 0.0:
		var color: Color = _capturer_color()
		var to: float = -PI * 0.5 + TAU * _capture
		_zone.draw_arc(center, radius, -PI * 0.5, to, maxi(8, int(72.0 * _capture)), Color(color.r, color.g, color.b, 0.95 * a), 4.0, true)
		_zone.draw_circle(center + Vector2.from_angle(to) * radius, 4.0, Color(color.r, color.g, color.b, a), true, -1.0, true)


func _draw_rig() -> void:
	_draw_lines()
	_draw_body()


## Suspension lines from the canopy rim to the lid corners (only while the canopy carries the crate).
func _draw_lines() -> void:
	if not _canopy_attached or not _canopy.visible:
		return
	var top: float = -BODY_HEIGHT - LID_HEIGHT
	for rim in [-54.0, -28.0, 28.0, 54.0]:
		var anchor: Vector2 = Vector2(-BODY_HALF + 4.0 if rim < 0.0 else BODY_HALF - 4.0, top)
		_rig.draw_line(Vector2(rim, CANOPY_OFFSET + 4.0), anchor, Color(0.08, 0.08, 0.07, 0.75), 1.2, true)


func _draw_body() -> void:
	var w: float = BODY_HALF
	var h: float = BODY_HEIGHT
	# Skids.
	for x in [-26.0, 18.0]:
		_rig.draw_rect(Rect2(x - 1.5, -1.5, 11.0, 5.0), OUTLINE)
		_rig.draw_rect(Rect2(x, 0.0, 8.0, 2.5), STEEL)
	var body: Rect2 = Rect2(-w, -h, w * 2.0, h)
	_rig.draw_rect(body.grow(2.0), OUTLINE)
	_rig.draw_rect(body, BODY)
	_rig.draw_rect(body.grow(-4.0), BODY_DARK)
	_rig.draw_rect(Rect2(body.position.x + 4.0, body.position.y + 4.0, body.size.x - 8.0, 1.5), BODY_LIGHT)
	for x in [-11.0, 11.0]:
		_rig.draw_rect(Rect2(x - 2.0, -h + 4.0, 4.0, h - 8.0), BODY)
		_rig.draw_rect(Rect2(x - 2.0, -h + 4.0, 1.0, h - 8.0), BODY_LIGHT)
	# Steel corner brackets.
	for corner in [Vector2(-w, -h), Vector2(w, -h), Vector2(-w, 0.0), Vector2(w, 0.0)]:
		var sx: float = 1.0 if corner.x < 0.0 else -1.0
		var sy: float = 1.0 if corner.y < -1.0 else -1.0
		_rig.draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(9.0 * sx, 0.0), corner + Vector2(9.0 * sx, 3.0 * sy),
			corner + Vector2(3.0 * sx, 3.0 * sy), corner + Vector2(3.0 * sx, 9.0 * sy), corner + Vector2(0.0, 9.0 * sy)]), STEEL)
		_rig.draw_circle(corner + Vector2(4.5 * sx, 4.5 * sy) - Vector2(0.0, 0.0), 1.0, STEEL_LIGHT)
	# Stencilled research cell: the crate says what is inside.
	var stencil: Vector2 = Vector2(0.0, -h * 0.5)
	var hex: PackedVector2Array = PackedVector2Array()
	for index in range(7):
		hex.append(stencil + Vector2.from_angle(TAU * float(index) / 6.0 + PI / 6.0) * 7.5)
	_rig.draw_polyline(hex, Color(0.74, 0.92, 0.86, 0.7), 2.0, true)
	_rig.draw_circle(stencil, 2.2, Color(0.74, 0.92, 0.86, 0.7), true, -1.0, true)
	# Latches on the seam: closed clasps bridge it; open ones hang down with an amber tongue.
	for index in range(3):
		var x: float = LATCH_X[index]
		var t: float = _latches[index]
		var pivot: Vector2 = Vector2(x, -h + 2.0)
		var angle: float = lerpf(0.0, PI * 0.92, t)
		var points: PackedVector2Array = PackedVector2Array([Vector2(-3.0, -6.0), Vector2(3.0, -6.0), Vector2(3.0, 4.0), Vector2(-3.0, 4.0)])
		var outline: PackedVector2Array = PackedVector2Array([Vector2(-4.5, -7.5), Vector2(4.5, -7.5), Vector2(4.5, 5.5), Vector2(-4.5, 5.5)])
		for i in range(4):
			points[i] = pivot + points[i].rotated(angle)
			outline[i] = pivot + outline[i].rotated(angle)
		_rig.draw_colored_polygon(outline, OUTLINE)
		_rig.draw_colored_polygon(points, STEEL.lerp(STEEL_LIGHT, 0.3))
		var tongue: Vector2 = pivot + Vector2(0.0, -5.0).rotated(angle)
		_rig.draw_circle(tongue, 1.6, UiStyle.ACCENT.lerp(Color(1, 1, 1), t * 0.3), true, -1.0, true)
	# Light pouring out of the open crate.
	if not _lid_attached and _beams > 0.0:
		var b: float = _beams
		for index in range(4):
			var x: float = lerpf(-20.0, 20.0, float(index) / 3.0) + sin(_time * 2.0 + float(index)) * 2.0
			var height: float = 90.0 + 40.0 * float(index % 2)
			var beam_color: Color = Color(0.55, 1.0, 0.9, 0.16 * b)
			_rig.draw_polygon(PackedVector2Array([Vector2(x - 5.0, -h), Vector2(x + 5.0, -h), Vector2(x + 9.0, -h - height), Vector2(x - 9.0, -h - height)]),
				PackedColorArray([beam_color, beam_color, Color(beam_color, 0.0), Color(beam_color, 0.0)]))
		_rig.draw_rect(Rect2(-w + 4.0, -h - 1.0, w * 2.0 - 8.0, 3.0), Color(0.6, 1.0, 0.92, 0.6 * b))


func _draw_lid() -> void:
	var w: float = BODY_HALF + LID_OVERHANG
	var rect: Rect2 = Rect2(-w, -LID_HEIGHT * 0.5, w * 2.0, LID_HEIGHT) if not _lid_attached else Rect2(-w, -BODY_HEIGHT - LID_HEIGHT, w * 2.0, LID_HEIGHT)
	_lid.draw_rect(rect.grow(2.0), OUTLINE)
	_lid.draw_rect(rect, Color(0.33, 0.38, 0.3, 1.0))
	_lid.draw_rect(Rect2(rect.position + Vector2(2.0, 1.5), Vector2(rect.size.x - 4.0, 1.5)), BODY_LIGHT)
	_lid.draw_rect(Rect2(rect.position.x + 2.0, rect.end.y - 2.5, rect.size.x - 4.0, 1.5), BODY_DARK)
	for x in [-w + 6.0, w - 14.0]:
		_lid.draw_rect(Rect2(x, rect.position.y + 3.5, 8.0, 4.0), STEEL)
	# Beacon housing on top of the closed lid.
	if _lid_attached:
		var base: Vector2 = Vector2(0.0, rect.position.y)
		_lid.draw_rect(Rect2(base + Vector2(-6.0, -4.0), Vector2(12.0, 4.0)), OUTLINE)
		_lid.draw_circle(base + Vector2(0.0, -4.0), 4.5, OUTLINE, true, -1.0, true)
		var lit: bool = _beacon_on and fmod(_time, 1.0) < 0.12
		_lid.draw_circle(base + Vector2(0.0, -4.0), 3.0, Color(1.0, 0.62, 0.25) if lit else Color(0.45, 0.24, 0.12), true, -1.0, true)


## The cargo canopy: gores in bone and burnt orange under a dome, scalloped hem, dark outline.
func _draw_canopy() -> void:
	var rx: float = CANOPY_SIZE.x
	var ry: float = CANOPY_SIZE.y
	var base_y: float = CANOPY_OFFSET + 6.0
	var dome: PackedVector2Array = PackedVector2Array()
	var steps: int = 28
	for index in range(steps + 1):
		var angle: float = PI + PI * float(index) / float(steps)
		dome.append(Vector2(cos(angle) * rx, base_y + sin(angle) * ry))
	var hem: PackedVector2Array = PackedVector2Array()
	var lobes: int = 6
	for index in range(lobes * 6 + 1):
		var u: float = float(index) / float(lobes * 6)
		var x: float = lerpf(rx, -rx, u)
		hem.append(Vector2(x, base_y + 4.0 + sin(u * PI * float(lobes)) * 3.5))
	var shape: PackedVector2Array = dome.duplicate()
	shape.append_array(hem)
	var outline: PackedVector2Array = PackedVector2Array()
	for point in shape:
		outline.append(Vector2(point.x * 1.035, base_y + (point.y - base_y) * 1.04 + 1.0))
	_canopy.draw_colored_polygon(outline, OUTLINE)
	_canopy.draw_colored_polygon(shape, CANOPY_A)
	# Gores as vertical bands, every other one orange, following the dome.
	var gores: int = 6
	for gore in range(gores):
		if gore % 2 == 0:
			continue
		var x0: float = lerpf(-rx, rx, float(gore) / float(gores))
		var x1: float = lerpf(-rx, rx, float(gore + 1) / float(gores))
		var band: PackedVector2Array = PackedVector2Array()
		var slices: int = 6
		for s in range(slices + 1):
			var x: float = lerpf(x0, x1, float(s) / float(slices))
			band.append(Vector2(x, base_y - ry * sqrt(maxf(0.0, 1.0 - (x * x) / (rx * rx)))))
		for s in range(slices, -1, -1):
			var x: float = lerpf(x0, x1, float(s) / float(slices))
			band.append(Vector2(x, base_y + 4.0 + sin((rx - x) / (2.0 * rx) * PI * float(lobes)) * 3.5))
		_canopy.draw_colored_polygon(band, CANOPY_B)
	# Underside in shadow along the hem, a highlight on the crown.
	_canopy.draw_polyline(hem, Color(0.25, 0.16, 0.1, 0.55), 3.0, true)
	_canopy.draw_arc(Vector2(-rx * 0.18, base_y - ry * 0.52), rx * 0.42, PI * 1.12, PI * 1.55, 12, Color(1, 1, 1, 0.35), 2.0, true)


func _draw_overlay() -> void:
	if _phase != &"landed" or _dismissed:
		return
	var y: float = _crate_point(Vector2(0.0, -BODY_HEIGHT - LID_HEIGHT)).y - 24.0
	var text: String = "+%d" % _reward
	if _contested:
		var label: String = "CONTESTED"
		_overlay.draw_string_outline(UiStyle.FONT_BOLD, Vector2(-60.0, y), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, 5, Color(0, 0, 0, 0.75))
		_overlay.draw_string(UiStyle.FONT_BOLD, Vector2(-60.0, y), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, Color(1.0, 0.55, 0.5))
		return
	var width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
	var x: float = -width * 0.5
	ResearchNodeButton.draw_rp_glyph(_overlay, Vector2(x + 5.0, y - 5.0), 6.0, Color(0, 0, 0, 0.6))
	ResearchNodeButton.draw_rp_glyph(_overlay, Vector2(x + 5.0, y - 5.0), 4.6, UiStyle.TEAL)
	_overlay.draw_string_outline(UiStyle.FONT_BOLD, Vector2(x + 14.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.7))
	_overlay.draw_string(UiStyle.FONT_BOLD, Vector2(x + 14.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEAL.lerp(Color.WHITE, 0.25))


## The lid's way off: popped up and over in one flip, landing on its edge, leaning against the crate's
## side (so it rests on any platform, however narrow), with a small settle at the end.
func _update_lid_flight(delta: float) -> void:
	_lid_flight = minf(_lid_flight + delta / 0.6, 1.4)
	var f: float = clampf(_lid_flight, 0.0, 1.0)
	var start: Vector2 = _crate_point(Vector2(0.0, -BODY_HEIGHT - LID_HEIGHT * 0.5))
	var lean: float = 1.35
	var rest: Vector2 = _crate_point(Vector2(_lid_side * (BODY_HALF + 6.0), -(BODY_HALF + LID_OVERHANG) * sin(lean)))
	var control: Vector2 = _crate_point(Vector2(_lid_side * 30.0, -175.0))
	_lid_position = start.lerp(control, f).lerp(control.lerp(rest, f), f)
	var spin: float = f * f * (3.0 - 2.0 * f)
	_lid_rotation = lerpf(0.0, _lid_side * (TAU + lean), spin)
	if _lid_flight > 1.0:
		var settle: float = _lid_flight - 1.0
		_lid_rotation += _lid_side * sin(settle * 38.0) * exp(-settle * 12.0) * 0.12


func _crate_point(local: Vector2) -> Vector2:
	return local * CRATE_SCALE


## Where the HUD should point while the drop is off screen: the crate while it falls, else the landing spot.
func get_focus_position() -> Vector2:
	if _rig != null and _rig.visible:
		return global_position + _rig.position + _crate_point(Vector2(0.0, -BODY_HEIGHT * 0.5))
	return global_position + _crate_point(Vector2(0.0, -BODY_HEIGHT * 0.5))
