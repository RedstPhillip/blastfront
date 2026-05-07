extends Node
class_name GameSync

const PLAYER_SYNC_SCRIPT := preload("res://scenes/network/player_sync.gd")
const PROJECTILE_SYNC_SCRIPT := preload("res://scenes/network/projectile_sync.gd")
const COMBAT_SYNC_SCRIPT := preload("res://scenes/network/combat_sync.gd")
const BLOCK_SYNC_SCRIPT := preload("res://scenes/network/block_sync.gd")
const ROUND_SYNC_SCRIPT := preload("res://scenes/network/round_sync.gd")

const CHANNEL_STATE := 1
const CHANNEL_EVENTS := 2
const WORLD_SNAPSHOT_RATE := 10.0

var game: Node = null
var tick := 0

var _sequence := 0
var _modules: Array = []
var _modules_by_name := {}
var _packet_handlers := {}
var _world_snapshot_timer := 0.0


func setup(game_world: Node) -> void:
	game = game_world
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)

	register_module(PLAYER_SYNC_SCRIPT.new())
	register_module(PROJECTILE_SYNC_SCRIPT.new())
	register_module(COMBAT_SYNC_SCRIPT.new())
	register_module(BLOCK_SYNC_SCRIPT.new())
	register_module(ROUND_SYNC_SCRIPT.new())


func _exit_tree() -> void:
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)


func _physics_process(delta: float) -> void:
	if not is_network_active():
		return

	tick += 1
	for module in _modules:
		if module.has_method("physics_sync_tick"):
			module.call("physics_sync_tick", delta)

	if is_host():
		_world_snapshot_timer -= delta
		if _world_snapshot_timer <= 0.0:
			_world_snapshot_timer = 1.0 / WORLD_SNAPSHOT_RATE
			_send_world_snapshot()


func register_module(module) -> void:
	add_child(module)
	_modules.append(module)

	if module.has_method("setup"):
		module.call("setup", self, game)

	var module_name: String = str(module.call("get_module_name")) if module.has_method("get_module_name") else module.name
	_modules_by_name[module_name] = module

	if module.has_method("get_packet_types"):
		var packet_types: Variant = module.call("get_packet_types")
		if not (packet_types is Array):
			return
		for packet_type in packet_types:
			_packet_handlers[str(packet_type)] = module


func get_module(module_name: StringName):
	return _modules_by_name.get(str(module_name), null)


func is_network_active() -> bool:
	return NetworkSession.is_steam_match_active()


func is_host() -> bool:
	return NetworkSession.is_host()


func is_client() -> bool:
	return NetworkSession.is_client()


func get_local_slot() -> int:
	return NetworkSession.local_player_slot


func get_remote_slot() -> int:
	return 2 if get_local_slot() == 1 else 1


func send_reliable(packet_type: StringName, payload: Dictionary, channel := CHANNEL_EVENTS) -> void:
	NetworkSession.send_reliable(_make_packet(packet_type, payload), channel)


func send_unreliable(packet_type: StringName, payload: Dictionary, channel := CHANNEL_STATE) -> void:
	NetworkSession.send_unreliable(_make_packet(packet_type, payload), channel)


func request_shot(owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var projectile_sync = get_module(&"projectile")
	if projectile_sync != null and projectile_sync.has_method("request_shot"):
		projectile_sync.call("request_shot", owner_slot, spawn_position, direction, projectile_data)


func _make_packet(packet_type: StringName, payload: Dictionary) -> Dictionary:
	_sequence += 1
	return {
		"protocol_version": NetworkSession.PROTOCOL_VERSION,
		"type": str(packet_type),
		"seq": _sequence,
		"tick": tick,
		"from_slot": get_local_slot(),
		"payload": payload,
	}


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	if not is_network_active():
		return

	var packet_type := str(packet.get("type", ""))
	if packet_type == "world_snapshot":
		_apply_world_snapshot(_get_payload(packet))
		return

	var module = _packet_handlers.get(packet_type, null)
	if module != null and module.has_method("handle_packet"):
		module.call("handle_packet", packet)


func _send_world_snapshot() -> void:
	var modules_snapshot := {}
	for module in _modules:
		if not module.has_method("build_snapshot"):
			continue

		var module_snapshot_variant: Variant = module.call("build_snapshot")
		if not (module_snapshot_variant is Dictionary):
			continue

		var module_snapshot: Dictionary = module_snapshot_variant
		if module_snapshot.is_empty():
			continue

		var module_name: String = str(module.call("get_module_name")) if module.has_method("get_module_name") else module.name
		modules_snapshot[module_name] = module_snapshot

	if modules_snapshot.is_empty():
		return

	send_unreliable(&"world_snapshot", {"modules": modules_snapshot}, NetworkSession.CHANNEL_STATE)


func _apply_world_snapshot(payload: Dictionary) -> void:
	if is_host():
		return

	var modules_data: Variant = payload.get("modules", {})
	if not (modules_data is Dictionary):
		return

	for module_name in modules_data.keys():
		var module = _modules_by_name.get(str(module_name), null)
		var module_data: Variant = modules_data[module_name]
		if module != null and module.has_method("apply_snapshot") and (module_data is Dictionary):
			module.call("apply_snapshot", module_data)


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}
