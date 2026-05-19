extends Control

signal sandbox_requested
signal online_requested
signal exit_requested

@onready var _sandbox_button: Button = %SandboxButton
@onready var _online_button: Button = %OnlineButton
@onready var _exit_button: Button = %ExitButton


func _ready() -> void:
	_sandbox_button.pressed.connect(_on_sandbox_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)

	SteamService.status_changed.connect(_refresh)
	_refresh("")


func _exit_tree() -> void:
	if SteamService.status_changed.is_connected(_refresh):
		SteamService.status_changed.disconnect(_refresh)


func _on_sandbox_pressed() -> void:
	sandbox_requested.emit()


func _on_online_pressed() -> void:
	online_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()


func _refresh(_message: String) -> void:
	_online_button.disabled = not SteamService.steam_enabled
