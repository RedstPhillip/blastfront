extends Control
class_name MainMenu

signal sandbox_requested
signal training_requested
signal online_requested
signal exit_requested

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/menus/settings_menu.tscn")

@onready var _sandbox_button: Button = %SandboxButton
@onready var _training_button: Button = %TrainingButton
@onready var _online_button: Button = %OnlineButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _menu_root: Control = $MenuRoot

var _settings_instance: SettingsMenu = null


func _ready() -> void:
	_sandbox_button.pressed.connect(_on_sandbox_pressed)
	_training_button.pressed.connect(_on_training_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	GameJuice.attach_button_feedback(self)
	_play_intro_animation()

	SteamService.status_changed.connect(_refresh)
	_refresh("")


func _exit_tree() -> void:
	if SteamService.status_changed.is_connected(_refresh):
		SteamService.status_changed.disconnect(_refresh)


func _on_sandbox_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	sandbox_requested.emit()


func _on_training_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	training_requested.emit()


func _on_online_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	online_requested.emit()


func _on_exit_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	exit_requested.emit()


func _on_settings_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -10.0, 0.04)
	_menu_root.hide()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance == null:
		_menu_root.show()
		return
	add_child(_settings_instance)
	_settings_instance.back_pressed.connect(_on_settings_back)


func _on_settings_back() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null
	_menu_root.show()


func _refresh(_message: String) -> void:
	_online_button.disabled = not SteamService.steam_enabled


func _play_intro_animation() -> void:
	_menu_root.pivot_offset = Vector2(300.0, 260.0)
	_menu_root.modulate.a = 0.0
	_menu_root.scale = Vector2(0.96, 0.96)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_menu_root, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_menu_root, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
