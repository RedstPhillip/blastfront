extends Node

## Steam start-up through GodotSteam when it is present; the game runs offline without it. The project
## setting blastfront/steam/disabled (set by the test toolkit's override.cfg) keeps Steam off entirely, so
## automated runs never touch the Steam client of whoever is logged in.
##
## Also the game's achievements, stats and rich presence. The API names below must exist under the same
## names in the Steamworks app configuration (see docs/STEAM_RELEASE.md); until they do, Steam simply
## refuses the calls and nothing else changes.

const DISABLED_SETTING: String = "blastfront/steam/disabled"

const ACH_FIRST_WIN: String = "ACH_FIRST_WIN"
const ACH_BEAT_HARD: String = "ACH_BEAT_HARD"
const ACH_FLAWLESS: String = "ACH_FLAWLESS"
const ACH_ONLINE_WIN: String = "ACH_ONLINE_WIN"
const ACH_ALL_WORLDS: String = "ACH_ALL_WORLDS"
## One per world, unlocked by winning a match there (against the bot or online).
const WORLD_ACHIEVEMENTS: Dictionary = {
	&"verdant": "ACH_WIN_VERDANT",
	&"mars": "ACH_WIN_MARS",
	&"tidewater": "ACH_WIN_TIDEWATER",
	&"rimefall": "ACH_WIN_RIMEFALL",
}
const STAT_MATCHES_PLAYED: String = "STAT_MATCHES_PLAYED"
const STAT_MATCHES_WON: String = "STAT_MATCHES_WON"
const STAT_ONLINE_WINS: String = "STAT_ONLINE_WINS"
const HARD_DIFFICULTY: int = 2

signal initialized
signal initialization_failed(message: String)
signal status_changed(message: String)

var steam_enabled: bool = false
var steam_id: int = 0
var steam_name: String = GameSettings.STEAM_OFFLINE_NAME
var initialization_status: int = -1
var initialization_message: String = GameSettings.STEAM_NOT_INITIALIZED_MESSAGE
## Achievements already set in this session, so a rematch does not ask Steam again.
var _unlocked: Dictionary = {}
var _stats_dirty: bool = false


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


# --- Achievements, stats, presence ---------------------------------------------------------------------------

## A finished match as the local player saw it. `bot_difficulty` is -1 for an online match.
func report_match_result(local_won: bool, bot_difficulty: int, world_id: StringName, flawless: bool) -> void:
	if not steam_enabled:
		return
	var online: bool = bot_difficulty < 0
	_add_stat(STAT_MATCHES_PLAYED)
	if local_won:
		_add_stat(STAT_MATCHES_WON)
		_unlock(ACH_FIRST_WIN)
		if WORLD_ACHIEVEMENTS.has(world_id):
			_unlock(str(WORLD_ACHIEVEMENTS[world_id]))
			_check_all_worlds()
		if flawless:
			_unlock(ACH_FLAWLESS)
		if online:
			_add_stat(STAT_ONLINE_WINS)
			_unlock(ACH_ONLINE_WIN)
		elif bot_difficulty >= HARD_DIFFICULTY:
			_unlock(ACH_BEAT_HARD)
	if _stats_dirty:
		_stats_dirty = false
		Steam.storeStats()


## What friends see next to the player's name ("Duel on Tidewater", "In the menu").
func set_presence(text: String) -> void:
	if steam_enabled:
		Steam.setRichPresence("status", text)


func _unlock(achievement: String) -> void:
	if _unlocked.has(achievement):
		return
	_unlocked[achievement] = true
	if Steam.setAchievement(achievement):
		_stats_dirty = true


func _add_stat(stat: String, amount: int = 1) -> void:
	if Steam.setStatInt(stat, int(Steam.getStatInt(stat)) + amount):
		_stats_dirty = true


func _check_all_worlds() -> void:
	for achievement in WORLD_ACHIEVEMENTS.values():
		if not _unlocked.has(achievement) and not (Steam.getAchievement(str(achievement)) as Dictionary).get("achieved", false):
			return
	_unlock(ACH_ALL_WORLDS)
