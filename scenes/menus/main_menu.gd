extends Control

signal sandbox_requested
signal online_requested
signal exit_requested

@onready var _sandbox_button: Button = %SandboxButton
@onready var _online_button: Button = %OnlineButton
@onready var _exit_button: Button = %ExitButton
@onready var _menu_root: Control = $MenuRoot

var _button_base_scale: Dictionary = {}
var _button_base_rotation: Dictionary = {}
var _button_tweens: Dictionary = {}


func _ready() -> void:
	_sandbox_button.pressed.connect(_on_sandbox_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_wire_button_feedback()
	_play_intro_animation()

	SteamService.status_changed.connect(_refresh)
	_refresh("")


func _exit_tree() -> void:
	if SteamService.status_changed.is_connected(_refresh):
		SteamService.status_changed.disconnect(_refresh)


func _on_sandbox_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	sandbox_requested.emit()


func _on_online_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	online_requested.emit()


func _on_exit_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	exit_requested.emit()


func _refresh(_message: String) -> void:
	_online_button.disabled = not SteamService.steam_enabled


func _wire_button_feedback() -> void:
	var button_nodes: Array[Node] = find_children("*", "Button", true, false)
	for node in button_nodes:
		var button: Button = node as Button
		if button == null:
			continue
		_button_base_scale[button] = button.scale
		_button_base_rotation[button] = button.rotation
		button.mouse_entered.connect(_on_button_hovered.bind(button))
		button.focus_entered.connect(_on_button_hovered.bind(button))
		button.mouse_exited.connect(_on_button_released.bind(button))
		button.focus_exited.connect(_on_button_released.bind(button))
		button.button_down.connect(_on_button_down.bind(button))
		button.button_up.connect(_on_button_released.bind(button))


func _play_intro_animation() -> void:
	_menu_root.pivot_offset = Vector2(300.0, 260.0)
	_menu_root.modulate.a = 0.0
	_menu_root.scale = Vector2(0.96, 0.96)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_menu_root, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_menu_root, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_hovered(button: Button) -> void:
	if button.disabled:
		return
	GameJuice.play_sound(&"ui_hover", -18.0, 0.035)
	_tween_button(button, 1.045, 0.012, 0.10)


func _on_button_down(button: Button) -> void:
	if button.disabled:
		return
	_tween_button(button, 0.965, -0.008, 0.055)


func _on_button_released(button: Button) -> void:
	_tween_button(button, 1.0, 0.0, 0.12)


func _tween_button(button: Button, scale_factor: float, rotation_offset: float, duration: float) -> void:
	var old_tween: Tween = _button_tweens.get(button, null) as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

	var base_scale: Vector2 = _button_base_scale.get(button, Vector2.ONE)
	var base_rotation: float = float(_button_base_rotation.get(button, 0.0))
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", base_scale * scale_factor, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", base_rotation + rotation_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_button_tweens[button] = tween
