class_name WorldCatalog
extends RefCounted

## The playable worlds. The sandbox remembers the last one picked in the pause menu; every other mode
## plays on the default world.

const DEFAULT_WORLD: StringName = &"verdant"
const WORLDS: Dictionary = {
	&"verdant": {"name": "Verdant", "scene": "res://scenes/maps/arena.tscn"},
	&"mars": {"name": "Mars", "scene": "res://scenes/maps/mars/mars_arena.tscn"},
}


static func ids() -> Array[StringName]:
	return [&"verdant", &"mars"]


static func active_world_id() -> StringName:
	if not NetworkSession.is_training():
		return DEFAULT_WORLD
	return sandbox_world_id()


static func sandbox_world_id() -> StringName:
	var id: StringName = StringName(str(UserSettings.get_value(UserSettings.SANDBOX_WORLD)))
	return id if WORLDS.has(id) else DEFAULT_WORLD


static func display_name(id: StringName) -> String:
	return str((WORLDS.get(id, WORLDS[DEFAULT_WORLD]) as Dictionary)["name"])


static func scene_for(id: StringName) -> PackedScene:
	var entry: Dictionary = WORLDS.get(id, WORLDS[DEFAULT_WORLD])
	return load(str(entry["scene"])) as PackedScene
