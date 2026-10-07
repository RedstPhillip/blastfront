extends SyncModule
class_name WorldSync

## Keeps the living parts of a world (storms, geysers) on the same beat for both players. The host's copy
## runs them; the client's copy follows. Map nodes join GROUP and implement:
##   net_state() -> Dictionary          with an int "step" that grows on every phase change
##   apply_net_state(state: Dictionary)  called on the client
## Phase changes go out reliably the moment they happen; the regular world snapshot corrects timers.

const GROUP: StringName = &"net_world"

var _sent_steps: Dictionary = {}
var _applied_steps: Dictionary = {}


func get_module_name() -> StringName:
	return GameSettings.MODULE_WORLD


func get_packet_types() -> Array[StringName]:
	return [GameSettings.PACKET_WORLD_EVENT]


func physics_sync_tick(_delta: float) -> void:
	if game_sync == null or not game_sync.is_host():
		return
	for node in _participants():
		var state: Dictionary = node.net_state()
		var key: String = _key_for(node)
		var step: int = int(state.get("step", 0))
		if int(_sent_steps.get(key, -1)) == step:
			continue
		_sent_steps[key] = step
		game_sync.send_reliable(GameSettings.PACKET_WORLD_EVENT, {"key": key, "state": state}, GameSettings.NETWORK_CHANNEL_EVENTS)


func build_snapshot() -> Dictionary:
	if game_sync == null or not game_sync.is_host():
		return {}
	var states: Dictionary = {}
	for node in _participants():
		states[_key_for(node)] = node.net_state()
	return {} if states.is_empty() else {"nodes": states}


func apply_snapshot(data: Dictionary) -> void:
	var states: Variant = data.get("nodes", {})
	if not (states is Dictionary):
		return
	for key in (states as Dictionary).keys():
		_apply(str(key), (states as Dictionary)[key])


func handle_packet(packet: Dictionary) -> void:
	if game_sync == null or game_sync.is_host():
		return
	var payload: Dictionary = NetworkSession.get_payload(packet)
	_apply(str(payload.get("key", "")), payload.get("state", {}))


## A snapshot can arrive after the reliable event that superseded it; anything from an older step is
## dropped so a geyser never erupts twice or a storm rewinds.
func _apply(key: String, state_variant: Variant) -> void:
	if key == "" or not (state_variant is Dictionary) or game == null:
		return
	var state: Dictionary = state_variant
	var step: int = int(state.get("step", 0))
	if step < int(_applied_steps.get(key, -1)):
		return
	var node: Node = game.get_node_or_null(NodePath(key))
	if node == null or not node.is_in_group(GROUP):
		return
	_applied_steps[key] = step
	node.apply_net_state(state)


func _participants() -> Array[Node]:
	if game == null or not game.is_inside_tree():
		return []
	return game.get_tree().get_nodes_in_group(GROUP)


func _key_for(node: Node) -> String:
	return str(game.get_path_to(node))
