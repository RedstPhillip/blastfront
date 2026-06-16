extends Node
class_name SyncModule

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


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
