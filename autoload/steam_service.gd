extends Node

signal initialized
signal initialization_failed(message: String)
signal status_changed(message: String)

const GAME_APP_ID := 4714540
const DEBUG_FALLBACK_APP_ID := 480
const STEAM_INIT_OK := 0

var steam_enabled := false
var steam_id: int = 0
var steam_name := "Offline"
var initialization_status := -1
var initialization_message := "Steam not initialized"
var active_app_id := GAME_APP_ID
var using_debug_fallback := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize_steam()


func _process(_delta: float) -> void:
	if _has_steam():
		Steam.run_callbacks()


func initialize_steam() -> void:
	if not _has_steam():
		steam_enabled = false
		initialization_status = -1
		initialization_message = "GodotSteam is not available."
		status_changed.emit(initialization_message)
		initialization_failed.emit(initialization_message)
		return

	_try_initialize_app(GAME_APP_ID)
	if initialization_status != STEAM_INIT_OK and _should_try_debug_fallback():
		var primary_failure := initialization_message
		_try_initialize_app(DEBUG_FALLBACK_APP_ID)
		if initialization_status == STEAM_INIT_OK:
			using_debug_fallback = true
			initialization_message = "Using dev fallback %s. App %s failed: %s" % [DEBUG_FALLBACK_APP_ID, GAME_APP_ID, primary_failure]
		else:
			initialization_message = "App %s failed: %s | Dev fallback %s failed: %s" % [GAME_APP_ID, primary_failure, DEBUG_FALLBACK_APP_ID, initialization_message]

	steam_enabled = initialization_status == STEAM_INIT_OK

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
		if using_debug_fallback:
			return "Steam ready: %s (dev app %s)" % [steam_name, active_app_id]
		return "Steam ready: %s (app %s)" % [steam_name, active_app_id]
	return "Steam unavailable: %s" % initialization_message


func _has_steam() -> bool:
	return Engine.has_singleton("Steam")


func _try_initialize_app(app_id: int) -> Dictionary:
	active_app_id = app_id
	using_debug_fallback = false
	var response: Dictionary = Steam.steamInitEx(app_id, false)
	initialization_status = int(response.get("status", 1))
	initialization_message = str(response.get("verbal", "Unknown Steam init response."))
	return response


func _should_try_debug_fallback() -> bool:
	return OS.is_debug_build()
