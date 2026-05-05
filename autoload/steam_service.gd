extends Node

signal initialized
signal initialization_failed(message: String)
signal status_changed(message: String)

const DEV_APP_ID := 480

var steam_enabled := false
var steam_id: int = 0
var steam_name := "Offline"
var initialization_status := -1
var initialization_message := "Steam not initialized"


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

	var response: Dictionary = Steam.steamInitEx(DEV_APP_ID, false)
	initialization_status = int(response.get("status", 1))
	initialization_message = str(response.get("verbal", "Unknown Steam init response."))
	steam_enabled = initialization_status == 0

	if not steam_enabled:
		status_changed.emit("Steam failed: %s" % initialization_message)
		initialization_failed.emit(initialization_message)
		return

	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	status_changed.emit("Steam ready: %s" % steam_name)
	initialized.emit()


func get_status_text() -> String:
	if steam_enabled:
		return "Steam ready: %s" % steam_name
	return "Steam unavailable: %s" % initialization_message


func _has_steam() -> bool:
	return Engine.has_singleton("Steam")
