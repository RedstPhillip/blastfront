extends Control

signal offline_requested

@onready var _steam_label: Label = %SteamLabel
@onready var _status_label: Label = %StatusLabel
@onready var _offline_button: Button = %OfflineButton
@onready var _invite_button: Button = %InviteButton


func _ready() -> void:
	_offline_button.pressed.connect(_on_offline_pressed)
	_invite_button.pressed.connect(_on_invite_pressed)

	SteamService.status_changed.connect(_refresh)
	NetworkSession.status_changed.connect(_refresh)

	_refresh("")


func _on_offline_pressed() -> void:
	NetworkSession.start_offline()
	offline_requested.emit()


func _on_invite_pressed() -> void:
	NetworkSession.host_invite_round()
	_refresh("")


func _refresh(_message: String) -> void:
	_steam_label.text = SteamService.get_status_text()
	_status_label.text = NetworkSession.status_text
	_invite_button.disabled = not SteamService.steam_enabled
