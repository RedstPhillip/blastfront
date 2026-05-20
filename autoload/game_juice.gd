extends Node

const BURST_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/BurstEffect.tscn")
const MUZZLE_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/MuzzleEffect.tscn")

const SOUND_PATHS: Dictionary = {
	&"shoot": "res://assets/audio/shoot.wav",
	&"hit": "res://assets/audio/hit.wav",
	&"impact": "res://assets/audio/impact.wav",
	&"jump": "res://assets/audio/jump.wav",
	&"land": "res://assets/audio/land.wav",
	&"step": "res://assets/audio/step.wav",
	&"spawn": "res://assets/audio/spawn.wav",
	&"death": "res://assets/audio/death.wav",
	&"ui_hover": "res://assets/audio/ui_hover.wav",
	&"ui_click": "res://assets/audio/ui_click.wav",
}

var _sounds: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _camera: Camera2D = null
var _camera_base_offset: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _button_tweens: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_load_sounds()


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var ratio: float = _shake_time / maxf(_shake_duration, 0.001)
		var strength: float = _shake_strength * ratio * ratio
		var target_offset: Vector2 = Vector2(
			_rng.randf_range(-strength, strength),
			_rng.randf_range(-strength, strength)
		)
		_shake_offset = _shake_offset.lerp(target_offset, clampf(delta * 34.0, 0.0, 1.0))
		_camera.offset = _camera_base_offset + _shake_offset
	else:
		_shake_offset = _shake_offset.lerp(Vector2.ZERO, clampf(delta * 18.0, 0.0, 1.0))
		_camera.offset = _camera_base_offset + _shake_offset


func bind_camera(camera: Camera2D) -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _camera_base_offset
	_camera = camera
	_camera_base_offset = camera.offset if camera != null else Vector2.ZERO
	_shake_time = 0.0
	_shake_duration = 0.0
	_shake_strength = 0.0
	_shake_offset = Vector2.ZERO


func clear_camera(camera: Camera2D) -> void:
	if camera == null or camera != _camera:
		return
	if is_instance_valid(_camera):
		_camera.offset = _camera_base_offset
	_camera = null
	_shake_offset = Vector2.ZERO


func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = maxf(_shake_time, duration)


func spawn_burst(kind: StringName, world_position: Vector2, direction: Vector2 = Vector2.UP, tint: Color = Color.WHITE) -> void:
	var effect: Node2D = BURST_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	var root_node: Node = _effect_root()
	_place_effect(effect, root_node, world_position)
	if effect.has_method("configure"):
		effect.call("configure", kind, direction, tint)
	root_node.add_child(effect)


func spawn_muzzle(world_position: Vector2, direction: Vector2, tint: Color = Color(1.0, 0.82, 0.38, 1.0)) -> void:
	var effect: Node2D = MUZZLE_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	var root_node: Node = _effect_root()
	_place_effect(effect, root_node, world_position)
	if effect.has_method("configure"):
		effect.call("configure", direction, tint)
	root_node.add_child(effect)


func play_sound(sound_id: StringName, volume_db: float = 0.0, pitch_variation: float = 0.05) -> void:
	var stream: AudioStream = _sounds.get(sound_id, null) as AudioStream
	if stream == null:
		return

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _random_pitch(pitch_variation)
	player.finished.connect(player.queue_free)
	_audio_root().add_child(player)
	player.play()


func play_sound_2d(sound_id: StringName, world_position: Vector2, volume_db: float = 0.0, pitch_variation: float = 0.05) -> void:
	var stream: AudioStream = _sounds.get(sound_id, null) as AudioStream
	if stream == null:
		return

	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.global_position = world_position
	player.volume_db = volume_db
	player.pitch_scale = _random_pitch(pitch_variation)
	player.max_distance = 1800.0
	player.attenuation = 0.35
	player.finished.connect(player.queue_free)
	_audio_root().add_child(player)
	player.play()


func attach_button_feedback(root: Node) -> void:
	if root == null:
		return

	var button_nodes: Array[Node] = root.find_children("*", "Button", true, false)
	for node in button_nodes:
		var button: Button = node as Button
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


func _random_pitch(variation: float) -> float:
	if variation <= 0.0:
		return 1.0
	return 1.0 + _rng.randf_range(-variation, variation)


func _load_sounds() -> void:
	_sounds.clear()
	for sound_id in SOUND_PATHS.keys():
		var path: String = str(SOUND_PATHS[sound_id])
		var stream: AudioStream = load(path) as AudioStream
		if stream != null:
			_sounds[sound_id] = stream


func _on_juice_button_hovered(button: Button) -> void:
	if button.disabled:
		return
	play_sound(&"ui_hover", -18.0, 0.035)
	_tween_juice_button(button, 1.04, 0.01, 0.10)


func _on_juice_button_down(button: Button) -> void:
	if button.disabled:
		return
	play_sound(&"ui_click", -12.0, 0.035)
	_tween_juice_button(button, 0.965, -0.006, 0.055)


func _on_juice_button_released(button: Button) -> void:
	_tween_juice_button(button, 1.0, 0.0, 0.12)


func _tween_juice_button(button: Button, scale_factor: float, rotation_offset: float, duration: float) -> void:
	if button == null or not is_instance_valid(button):
		return

	var old_tween: Tween = _button_tweens.get(button, null) as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

	var base_scale: Vector2 = _get_button_base_scale(button)
	var base_rotation: float = _get_button_base_rotation(button)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", base_scale * scale_factor, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", base_rotation + rotation_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_button_tweens[button] = tween


func _get_button_base_scale(button: Button) -> Vector2:
	var value: Variant = button.get_meta("juice_base_scale", Vector2.ONE)
	if value is Vector2:
		return value
	return Vector2.ONE


func _get_button_base_rotation(button: Button) -> float:
	var value: Variant = button.get_meta("juice_base_rotation", 0.0)
	if value is float or value is int:
		return float(value)
	return 0.0


func _effect_root() -> Node:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world != null:
		return world
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return self


func _audio_root() -> Node:
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return self


func _place_effect(effect: Node2D, root_node: Node, world_position: Vector2) -> void:
	var root_2d: Node2D = root_node as Node2D
	if root_2d != null:
		effect.position = root_2d.to_local(world_position)
	else:
		effect.global_position = world_position
