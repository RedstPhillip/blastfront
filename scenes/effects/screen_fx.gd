class_name ScreenFx
extends CanvasLayer

## Drives the full-screen post-process shader: flashes, aberration pulses, shockwaves,
## low-health danger tint and dramatic desaturation. Intensity follows the player's setting.

const MAX_WAVES: int = 4
const DANGER_HEALTH_RATIO: float = 0.3

@onready var _rect: ColorRect = $PostProcess

var _material: ShaderMaterial = null
var _flash_amount: float = 0.0
var _flash_decay: float = 4.0
var _aberration: float = 0.0
var _aberration_decay: float = 4.0
var _desaturate: float = 0.0
var _desaturate_target: float = 0.0
var _danger: float = 0.0
var _waves: Array[Dictionary] = []
var _heartbeat_timer: float = 0.0


func _ready() -> void:
	add_to_group(GameJuice.SCREEN_FX_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = _rect.material as ShaderMaterial
	_apply_intensity()
	UserSettings.setting_changed.connect(_on_setting_changed)


func flash(color: Color, strength: float, duration: float) -> void:
	if strength <= 0.0:
		return
	_material.set_shader_parameter(&"flash_color", color)
	_flash_amount = maxf(_flash_amount, clampf(strength, 0.0, 1.0))
	_flash_decay = _flash_amount / maxf(duration, 0.01)


func pulse_aberration(strength: float, duration: float) -> void:
	_aberration = maxf(_aberration, strength * 2.2)
	_aberration_decay = _aberration / maxf(duration, 0.01)


func shockwave(world_position: Vector2, strength: float, duration: float) -> void:
	if UserSettings.get_float(UserSettings.POST_PROCESSING) <= 0.0:
		return
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	_waves.append({"world": world_position, "age": 0.0, "duration": maxf(duration, 0.05), "strength": strength})


## Drains colour from the scene, e.g. during the round-winning kill.
func set_desaturate(amount: float) -> void:
	_desaturate_target = clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
	var danger_target: float = _compute_danger()
	_update_heartbeat(real_delta, danger_target)
	if not _rect.visible:
		return
	_flash_amount = maxf(_flash_amount - _flash_decay * real_delta, 0.0)
	_aberration = maxf(_aberration - _aberration_decay * real_delta, 0.0)
	_desaturate = move_toward(_desaturate, _desaturate_target, real_delta * 2.5)
	_danger = lerpf(_danger, danger_target, clampf(real_delta * 4.0, 0.0, 1.0))

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_material.set_shader_parameter(&"aspect", viewport_size.x / maxf(viewport_size.y, 1.0))
	_material.set_shader_parameter(&"flash_amount", _flash_amount)
	_material.set_shader_parameter(&"aberration", _aberration)
	_material.set_shader_parameter(&"desaturate", _desaturate)
	_material.set_shader_parameter(&"danger", _danger)
	_update_waves(real_delta, viewport_size)


func _update_waves(delta: float, viewport_size: Vector2) -> void:
	var packed: Array[Vector4] = []
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var index: int = _waves.size() - 1
	while index >= 0:
		var wave: Dictionary = _waves[index]
		wave["age"] = float(wave["age"]) + delta
		if float(wave["age"]) >= float(wave["duration"]):
			_waves.remove_at(index)
		index -= 1
	for wave in _waves:
		var t: float = float(wave["age"]) / float(wave["duration"])
		var screen_position: Vector2 = canvas * (wave["world"] as Vector2)
		var uv: Vector2 = screen_position / viewport_size
		var radius: float = lerpf(0.02, 0.42, 1.0 - pow(1.0 - t, 2.4))
		var strength: float = float(wave["strength"]) * (1.0 - t) * (1.0 - t)
		packed.append(Vector4(uv.x, uv.y, radius, strength))
	while packed.size() < MAX_WAVES:
		packed.append(Vector4.ZERO)
	_material.set_shader_parameter(&"waves", packed)


## Low-health heartbeat: starts below the danger threshold and quickens as health runs out.
func _update_heartbeat(real_delta: float, danger_target: float) -> void:
	if danger_target <= 0.0 or get_tree().paused:
		_heartbeat_timer = 0.0
		return
	_heartbeat_timer -= real_delta
	if _heartbeat_timer > 0.0:
		return
	_heartbeat_timer = lerpf(1.05, 0.62, clampf((danger_target - 0.15) / 0.55, 0.0, 1.0))
	AudioDirector.play(&"heartbeat", lerpf(-6.0, 0.0, clampf(danger_target, 0.0, 1.0)))


func _compute_danger() -> float:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_local_player"):
		return 0.0
	var player: Player = world.get_local_player()
	if player == null or not is_instance_valid(player) or player.is_eliminated() or player.health_component == null:
		return 0.0
	var ratio: float = float(player.health_component.health) / maxf(float(player.health_component.max_health), 1.0)
	if ratio >= DANGER_HEALTH_RATIO:
		return 0.0
	return clampf(1.0 - ratio / DANGER_HEALTH_RATIO, 0.0, 1.0) * 0.55 + 0.15


func _apply_intensity() -> void:
	var intensity: float = UserSettings.get_float(UserSettings.POST_PROCESSING)
	_rect.visible = intensity > 0.0
	_material.set_shader_parameter(&"intensity", intensity)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == UserSettings.POST_PROCESSING:
		_apply_intensity()
