extends Node

## Steam start-up through GodotSteam when it is present; the game runs offline without it. The project
## setting blastfront/steam/disabled (set by the test toolkit's override.cfg) keeps Steam off entirely, so
## automated runs never touch the Steam client of whoever is logged in.

const DISABLED_SETTING: String = "blastfront/steam/disabled"

signal initialized
signal initialization_failed(message: String)
signal status_changed(message: String)

var steam_enabled: bool = false
var steam_id: int = 0
var steam_name: String = GameSettings.STEAM_OFFLINE_NAME
var initialization_status: int = -1
var initialization_message: String = GameSettings.STEAM_NOT_INITIALIZED_MESSAGE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_steam()


func _process(_delta: float) -> void:
	if steam_enabled:
		Steam.run_callbacks()


func initialize_steam() -> void:
	if ProjectSettings.get_setting(DISABLED_SETTING, false) == true:
		steam_enabled = false
		initialization_status = -1
		initialization_message = "Steam disabled by " + DISABLED_SETTING
		status_changed.emit(initialization_message)
		initialization_failed.emit(initialization_message)
		return
	if not _has_steam():
		steam_enabled = false
		initialization_status = -1
		initialization_message = "GodotSteam is not available."
		status_changed.emit(initialization_message)
		initialization_failed.emit(initialization_message)
		return

	_try_initialize_app(GameSettings.STEAM_APP_ID)
	steam_enabled = initialization_status == GameSettings.STEAM_INIT_OK

	if not steam_enabled:
		status_changed.emit("Steam failed: %s" % initialization_message)
		initialization_failed.emit(initialization_message)
		return

	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	status_changed.emit(get_status_text())
	initialized.emit()


func get_status_text() -> String:
	if steam_enabled:
		return "Steam ready: %s" % steam_name
	return "Steam unavailable: %s" % initialization_message


func _has_steam() -> bool:
	return Engine.has_singleton("Steam")


func _try_initialize_app(app_id: int) -> Dictionary:
	var response: Dictionary = Steam.steamInitEx(app_id, false)
	initialization_status = int(response.get("status", 1))
	initialization_message = str(response.get("verbal", "Unknown Steam init response."))
	return response
