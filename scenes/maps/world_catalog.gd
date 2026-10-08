class_name WorldCatalog
extends RefCounted

## The playable worlds. The sandbox remembers the last one picked in the pause menu and bot duels the one
## picked in the bot setup; online matches play on a world the host rolls when the lobby opens.

const DEFAULT_WORLD: StringName = &"verdant"
const WORLDS: Dictionary = {
	&"verdant": {"name": "Verdant", "scene": "res://scenes/maps/arena.tscn"},
	&"mars": {"name": "Mars", "scene": "res://scenes/maps/mars/mars_arena.tscn"},
	&"tidewater": {"name": "Tidewater", "scene": "res://scenes/maps/tidewater/tidewater_arena.tscn"},
	&"rimefall": {"name": "Rimefall", "scene": "res://scenes/maps/rimefall/rimefall_arena.tscn"},
}


static func ids() -> Array[StringName]:
	return [&"verdant", &"mars", &"tidewater", &"rimefall"]


static func active_world_id() -> StringName:
	if NetworkSession.is_training():
		return sandbox_world_id()
	if NetworkSession.is_bot_duel():
		return bot_world_id()
	if NetworkSession.is_steam_match_active():
		return online_world_id()
	return DEFAULT_WORLD


static func online_world_id() -> StringName:
	return OnlineMatch.world_id if WORLDS.has(OnlineMatch.world_id) else DEFAULT_WORLD


static func random_id() -> StringName:
	var all: Array[StringName] = ids()
	return all[randi() % all.size()]


static func bot_world_id() -> StringName:
	var id: StringName = StringName(str(UserSettings.get_value(UserSettings.BOT_WORLD)))
	return id if WORLDS.has(id) else DEFAULT_WORLD


static func sandbox_world_id() -> StringName:
	var id: StringName = StringName(str(UserSettings.get_value(UserSettings.SANDBOX_WORLD)))
	return id if WORLDS.has(id) else DEFAULT_WORLD


static func display_name(id: StringName) -> String:
	return str((WORLDS.get(id, WORLDS[DEFAULT_WORLD]) as Dictionary)["name"])


## The world's map scene; Main warms the maps in the background while the menu is up.
static func scene_for(id: StringName) -> PackedScene:
	var entry: Dictionary = WORLDS.get(id, WORLDS[DEFAULT_WORLD])
	return Main.get_scene(str(entry["scene"]))
