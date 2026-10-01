extends Node

## Game feel hub: camera shake/kick/zoom punch, hitstop and slow motion, screen effects,
## combat VFX spawning, damage numbers and UI button feedback.

const BURST_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/burst_effect.tscn")
const MUZZLE_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/muzzle_effect.tscn")
const DAMAGE_FONT: Font = preload("res://assets/fonts/blastfront_combat_font.tres")
const SCREEN_FX_GROUP: StringName = &"screen_fx"

const MAX_SHAKE_OFFSET: float = 26.0
const MAX_SHAKE_ROLL: float = 0.035
const TRAUMA_DECAY: float = 1.35
const KICK_RETURN_SPEED: float = 13.0
const ZOOM_PUNCH_RETURN_SPEED: float = 7.5
const DAMAGE_NUMBER_MERGE_SECONDS: float = 0.42

var shake_multiplier: float = 1.0
var particles_multiplier: float = 1.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _noise: FastNoiseLite = FastNoiseLite.new()
var _noise_time: float = 0.0
var _camera: Camera2D = null
var _camera_base_offset: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _kick_offset: Vector2 = Vector2.ZERO
var _zoom_punch: float = 0.0
var _camera_offset: Vector2 = Vector2.ZERO
var _camera_roll: float = 0.0
var _hitstop_until_usec: int = 0
var _hitstop_scale: float = 1.0
var _slowmo_until_usec: int = 0
var _slowmo_scale: float = 1.0
var _slowmo_recover: float = 0.0
var _time_scale_current: float = 1.0
var _button_tweens: Dictionary = {}
var _damage_numbers: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = _rng.randi()


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001) if Engine.time_scale > 0.0 else delta
	_update_time_scale(real_delta)
	if get_tree().paused:
		return
	_update_camera_juice(real_delta)


# --- Camera -----------------------------------------------------------------

func bind_camera(camera: Camera2D) -> void:
	if _camera != null and is_instance_valid(_camera) and not _camera.has_method(&"uses_juice_values"):
		_camera.offset = _camera_base_offset
	_camera = camera
	_camera_base_offset = camera.offset if camera != null else Vector2.ZERO
	_trauma = 0.0
	_shake_time = 0.0
	_shake_duration = 0.0
	_shake_strength = 0.0
	_kick_offset = Vector2.ZERO
	_zoom_punch = 0.0
	_camera_offset = Vector2.ZERO
	_camera_roll = 0.0


func clear_camera(camera: Camera2D) -> void:
	if camera == null or camera != _camera:
		return
	if is_instance_valid(_camera) and not _camera.has_method(&"uses_juice_values"):
		_camera.offset = _camera_base_offset
	_camera = null
	_camera_offset = Vector2.ZERO
	reset_time_scale()


## Classic short shake: strength in pixels, fades out quadratically over duration.
func shake(strength: float, duration: float) -> void:
	var actual_strength: float = strength * shake_multiplier
	if actual_strength <= 0.0 or duration <= 0.0:
		return
	_shake_strength = maxf(_shake_strength * (_shake_time / maxf(_shake_duration, 0.001)), 0.0) + actual_strength
	_shake_strength = minf(_shake_strength, MAX_SHAKE_OFFSET)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = maxf(_shake_time, duration)


## Trauma drives big, rolling shakes for heavy moments (deaths, explosions). 0..1, squared falloff.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * shake_multiplier, 0.0, 1.0)


## Directional camera push that springs back, e.g. against the recoil direction.
func kick(direction: Vector2, strength: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	_kick_offset += direction.normalized() * strength * shake_multiplier
	_kick_offset = _kick_offset.limit_length(MAX_SHAKE_OFFSET)


## Brief zoom-in pulse. Positive values zoom in.
func zoom_punch(amount: float) -> void:
	_zoom_punch = clampf(_zoom_punch + amount * maxf(shake_multiplier, 0.35), -0.2, 0.25)


func get_camera_offset() -> Vector2:
	return _camera_offset


func get_camera_roll() -> float:
	return _camera_roll


func get_zoom_factor() -> float:
	return 1.0 + _zoom_punch


func _update_camera_juice(delta: float) -> void:
	_noise_time += delta
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	var pixel_shake: float = 0.0
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var ratio: float = _shake_time / maxf(_shake_duration, 0.001)
		pixel_shake = _shake_strength * ratio * ratio
	else:
		_shake_strength = 0.0
		_shake_duration = 0.0

	var trauma_power: float = _trauma * _trauma
	var amplitude: float = pixel_shake + MAX_SHAKE_OFFSET * trauma_power
	var speed: float = 28.0 + 18.0 * trauma_power
	var shake_offset: Vector2 = Vector2(
		_noise.get_noise_2d(_noise_time * speed, 0.0),
		_noise.get_noise_2d(0.0, _noise_time * speed + 91.0)
	) * amplitude
	_camera_roll = _noise.get_noise_2d(_noise_time * speed * 0.7, 333.0) * MAX_SHAKE_ROLL * trauma_power

	_kick_offset = _kick_offset.lerp(Vector2.ZERO, 1.0 - exp(-KICK_RETURN_SPEED * delta))
	_zoom_punch = lerpf(_zoom_punch, 0.0, 1.0 - exp(-ZOOM_PUNCH_RETURN_SPEED * delta))
	_camera_offset = shake_offset + _kick_offset

	if _camera != null and is_instance_valid(_camera) and not _camera.has_method(&"uses_juice_values"):
		_camera.offset = _camera_base_offset + _camera_offset


# --- Time ---------------------------------------------------------------------

## Freezes gameplay for a few frames to sell impact. Disabled in online matches to keep peers in sync.
func hitstop(duration: float, time_scale: float = 0.04) -> void:
	if not _time_effects_allowed() or not UserSettings.get_bool(UserSettings.HITSTOP):
		return
	var until: int = Time.get_ticks_usec() + int(duration * 1000000.0)
	_hitstop_until_usec = maxi(_hitstop_until_usec, until)
	_hitstop_scale = minf(_hitstop_scale if _hitstop_until_usec > Time.get_ticks_usec() else 1.0, time_scale)


## Slow motion for dramatic moments (round winning kill). Offline only.
func slow_motion(time_scale: float, duration: float, recover_seconds: float = 0.35) -> void:
	if not _time_effects_allowed():
		return
	_slowmo_until_usec = Time.get_ticks_usec() + int(duration * 1000000.0)
	_slowmo_scale = clampf(time_scale, 0.05, 1.0)
	_slowmo_recover = maxf(recover_seconds, 0.01)


func reset_time_scale() -> void:
	_hitstop_until_usec = 0
	_slowmo_until_usec = 0
	_hitstop_scale = 1.0
	_slowmo_scale = 1.0
	_time_scale_current = 1.0
	Engine.time_scale = 1.0


func _time_effects_allowed() -> bool:
	return not NetworkSession.is_steam_match_active()


func _update_time_scale(real_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var target: float = 1.0
	if now < _slowmo_until_usec:
		target = _slowmo_scale
	elif _slowmo_scale < 1.0:
		_slowmo_scale = minf(1.0, _slowmo_scale + real_delta / _slowmo_recover)
		target = _slowmo_scale
	var slowmo_target: float = target
	if now < _hitstop_until_usec:
		target = minf(target, _hitstop_scale)
	else:
		_hitstop_scale = 1.0
	if not is_equal_approx(target, _time_scale_current):
		_time_scale_current = target
		Engine.time_scale = target
	var audio_speed: float = lerpf(0.78, 1.0, clampf((slowmo_target - 0.2) / 0.8, 0.0, 1.0))
	if not is_equal_approx(AudioServer.playback_speed_scale, audio_speed):
		AudioServer.playback_speed_scale = audio_speed


# --- Screen effects ------------------------------------------------------------

func flash(color: Color = Color.WHITE, strength: float = 0.5, duration: float = 0.18) -> void:
	var screen_fx: Node = _screen_fx()
	if screen_fx != null:
		screen_fx.flash(color, strength * UserSettings.get_float(UserSettings.SCREEN_FLASH), duration)


func aberration(strength: float = 1.0, duration: float = 0.25) -> void:
	var screen_fx: Node = _screen_fx()
	if screen_fx != null:
		screen_fx.pulse_aberration(strength, duration)


func shockwave(world_position: Vector2, strength: float = 1.0, duration: float = 0.55) -> void:
	var screen_fx: Node = _screen_fx()
	if screen_fx != null:
		screen_fx.shockwave(world_position, strength, duration)


func _screen_fx() -> Node:
	return get_tree().get_first_node_in_group(SCREEN_FX_GROUP)


# --- VFX -------------------------------------------------------------------------

func spawn_burst(kind: StringName, world_position: Vector2, direction: Vector2 = Vector2.UP, tint: Color = Color.WHITE, scale_factor: float = 1.0) -> void:
	var effect_node: Node2D = BURST_EFFECT_SCENE.instantiate() as Node2D
	if effect_node == null:
		return
	var root_node: Node = _effect_root()
	_place_effect(effect_node, root_node, world_position)
	effect_node.configure(kind, direction, tint, scale_factor)
	root_node.add_child(effect_node)


func spawn_muzzle(world_position: Vector2, direction: Vector2, tint: Color = Color(1.0, 0.82, 0.38, 1.0), power: float = 1.0) -> void:
	var effect_node: Node2D = MUZZLE_EFFECT_SCENE.instantiate() as Node2D
	if effect_node == null:
		return
	var root_node: Node = _effect_root()
	_place_effect(effect_node, root_node, world_position)
	effect_node.configure(direction, tint, power)
	root_node.add_child(effect_node)


func spawn_casing(world_position: Vector2, eject_direction: Vector2) -> void:
	if particles_multiplier <= 0.0:
		return
	var casing: ShellCasing = ShellCasing.new()
	var root_node: Node = _effect_root()
	_place_effect(casing, root_node, world_position)
	casing.launch(eject_direction)
	root_node.add_child(casing)


func spawn_explosion(world_position: Vector2, radius: float = 80.0, tint: Color = Color(1.0, 0.55, 0.18, 1.0)) -> void:
	var power: float = clampf(radius / 80.0, 0.6, 2.2)
	spawn_burst(&"explosion", world_position, Vector2.UP, tint, power)
	ImpactDecals.add_scorch(world_position, radius * 0.75)
	play_sound_2d(&"explosion", world_position)
	add_trauma(0.32 * power)
	kick(Vector2.UP, 6.0 * power)
	zoom_punch(0.02 * power)
	flash(Color(1.0, 0.82, 0.55, 1.0), 0.18 * power, 0.16)
	shockwave(world_position, 0.9 * power)
	aberration(0.8 * power, 0.25)


# --- Audio wrappers ------------------------------------------------------------------

func play_sound(sound_id: StringName, volume_db: float = 0.0, _pitch_variation: float = 0.05) -> void:
	AudioDirector.play(_map_sound_id(sound_id), _legacy_volume_offset(volume_db))


func play_sound_2d(sound_id: StringName, world_position: Vector2, volume_db: float = 0.0, _pitch_variation: float = 0.05) -> void:
	AudioDirector.play_at(_map_sound_id(sound_id), world_position, _legacy_volume_offset(volume_db))


func _map_sound_id(sound_id: StringName) -> StringName:
	return sound_id


## Old call sites passed absolute dB tuned for the original wavs; keep a gentle relative influence.
func _legacy_volume_offset(volume_db: float) -> float:
	return clampf(volume_db * 0.25, -4.0, 3.0)


# --- Damage numbers -----------------------------------------------------------------

func spawn_damage_number(world_position: Vector2, amount: int, color: Color = Color(1.0, 0.28, 0.22, 1.0), target_key: int = 0, is_heal: bool = false) -> void:
	if not UserSettings.get_bool(UserSettings.DAMAGE_NUMBERS) or amount <= 0:
		return
	var now: int = Time.get_ticks_msec()
	if target_key != 0 and _damage_numbers.has(target_key):
		var entry: Dictionary = _damage_numbers[target_key]
		var existing_variant: Variant = entry.get("label")
		var existing: Label = existing_variant as Label if is_instance_valid(existing_variant) else null
		if existing != null and now - int(entry.get("time", 0)) < int(DAMAGE_NUMBER_MERGE_SECONDS * 1000.0) and bool(entry.get("heal", false)) == is_heal:
			var total: int = int(entry.get("total", 0)) + amount
			entry["total"] = total
			entry["time"] = now
			existing.text = ("+%d" if is_heal else "%d") % total
			style_damage_label(existing, total, color, is_heal)
			_animate_damage_label(existing, true)
			return

	var label: Label = Label.new()
	label.text = ("+%d" if is_heal else "%d") % amount
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(96, 40)
	label.pivot_offset = label.size * 0.5
	label.z_index = 60
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_damage_label(label, amount, color, is_heal)

	var root: Node = _effect_root()
	var spawn_pos: Vector2 = world_position
	var root_2d: Node2D = root as Node2D
	if root_2d != null:
		spawn_pos = root_2d.to_local(world_position)
	spawn_pos += Vector2(_rng.randf_range(-10.0, 10.0), -30.0)
	label.position = spawn_pos - label.pivot_offset
	label.rotation = _rng.randf_range(-0.12, 0.12)
	root.add_child(label)
	_animate_damage_label(label, false)
	if target_key != 0:
		_damage_numbers[target_key] = {"label": label, "total": amount, "time": now, "heal": is_heal}


## Shared look of floating damage numbers (also used to pre-warm their glyphs).
func style_damage_label(label: Label, amount: int, color: Color, is_heal: bool) -> void:
	var heavy: float = clampf(float(amount) / 50.0, 0.0, 1.0)
	var font_color: Color = Color(0.55, 1.0, 0.62) if is_heal else Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.82, 0.3), heavy)
	label.add_theme_font_override("font", DAMAGE_FONT)
	label.add_theme_font_size_override("font_size", int(lerpf(22.0, 36.0, heavy)))
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0) if is_heal else color.darkened(0.55))
	label.add_theme_constant_override("outline_size", 9)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)


func _animate_damage_label(label: Label, is_merge: bool) -> void:
	if label.has_meta(&"tween"):
		var previous: Tween = label.get_meta(&"tween") as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	label.modulate.a = 1.0
	var start_position: Vector2 = label.position
	var drift: Vector2 = Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-58.0, -76.0))
	label.scale = Vector2.ONE * (1.65 if is_merge else 0.35)
	var tween: Tween = label.create_tween()
	label.set_meta(&"tween", tween)
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE * 1.18, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE * 0.92, 0.5).set_delay(0.14).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "position", start_position + drift, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


# --- UI feedback ------------------------------------------------------------------------

func attach_button_feedback(root: Node) -> void:
	if root == null:
		return
	var button_nodes: Array[Node] = root.find_children("*", "BaseButton", true, false)
	for node in button_nodes:
		var button: BaseButton = node as BaseButton
		if button == null or button.has_meta("juice_feedback_connected"):
			continue
		button.set_meta("juice_feedback_connected", true)
		button.set_meta("juice_base_scale", button.scale)
		button.set_meta("juice_base_rotation", button.rotation)
		button.mouse_entered.connect(_on_juice_button_hovered.bind(button))
		button.focus_entered.connect(_on_juice_button_hovered.bind(button))
		button.mouse_exited.connect(_on_juice_button_released.bind(button))
		button.focus_exited.connect(_on_juice_button_released.bind(button))
		button.button_down.connect(_on_juice_button_down.bind(button))
		button.button_up.connect(_on_juice_button_released.bind(button))
		if not button.resized.is_connected(_center_button_pivot.bind(button)):
			button.resized.connect(_center_button_pivot.bind(button))
		_center_button_pivot(button)


func _center_button_pivot(button: Control) -> void:
	if button != null and is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _on_juice_button_hovered(button: BaseButton) -> void:
	if button.disabled:
		return
	AudioDirector.play(&"ui_hover")
	_tween_juice_button(button, 1.035, 0.008 * _get_button_rotation_multiplier(button), 0.12)


func _on_juice_button_down(button: BaseButton) -> void:
	if button.disabled:
		AudioDirector.play(&"ui_error")
		return
	AudioDirector.play(&"ui_click")
	_tween_juice_button(button, 0.96, -0.005 * _get_button_rotation_multiplier(button), 0.05)


func _on_juice_button_released(button: BaseButton) -> void:
	var hovered: bool = button.is_hovered() and not button.disabled
	_tween_juice_button(button, 1.035 if hovered else 1.0, 0.0, 0.16)


func _tween_juice_button(button: Control, scale_factor: float, rotation_offset: float, duration: float) -> void:
	if button == null or not is_instance_valid(button) or not button.is_inside_tree():
		return
	var old_tween: Tween = _button_tweens.get(button, null) as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var base_scale: Vector2 = _get_button_base_scale(button)
	var base_rotation: float = _get_button_base_rotation(button)
	var tween: Tween = button.create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", base_scale * scale_factor, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", base_rotation + rotation_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_button_tweens[button] = tween


func _get_button_base_scale(button: Control) -> Vector2:
	var value: Variant = button.get_meta("juice_base_scale", Vector2.ONE)
	return value if value is Vector2 else Vector2.ONE


func _get_button_base_rotation(button: Control) -> float:
	var value: Variant = button.get_meta("juice_base_rotation", 0.0)
	return float(value) if (value is float or value is int) else 0.0


func _get_button_rotation_multiplier(button: Control) -> float:
	var value: Variant = button.get_meta("juice_rotation_multiplier", 1.0)
	return maxf(0.0, float(value)) if (value is float or value is int) else 1.0


# --- Helpers -----------------------------------------------------------------------------

func _effect_root() -> Node:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world != null:
		return world
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return self


func _place_effect(effect: Node2D, root_node: Node, world_position: Vector2) -> void:
	var root_2d: Node2D = root_node as Node2D
	if root_2d != null:
		effect.position = root_2d.to_local(world_position)
	else:
		effect.global_position = world_position
