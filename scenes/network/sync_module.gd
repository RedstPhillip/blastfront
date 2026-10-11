extends Node
class_name SyncModule

## Base for one part of the online sync (players, projectiles, combat, blocks, world).

var game_sync = null
var game = null


func setup(sync: Node, game_world: Node) -> void:
	game_sync = sync
	game = game_world


func get_module_name() -> StringName:
	return &"module"


func get_packet_types() -> Array[StringName]:
	return []


func handle_packet(_packet: Dictionary) -> void:
	return


func build_snapshot() -> Dictionary:
	return {}


func apply_snapshot(_data: Dictionary) -> void:
	return


func physics_sync_tick(_delta: float) -> void:
	return


## The game's player in this slot, or null (also before setup and while the world is going away).
func _get_player(slot: int) -> Player:
	if game == null:
		return null
	return game.get_player_by_slot(slot)
