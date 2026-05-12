extends Node
class_name GameSync

const PLAYER_SYNC_SCRIPT := preload("res://scenes/network/player_sync.gd")
const PROJECTILE_SYNC_SCRIPT := preload("res://scenes/network/projectile_sync.gd")
const COMBAT_SYNC_SCRIPT := preload("res://scenes/network/combat_sync.gd")
const BLOCK_SYNC_SCRIPT := preload("res://scenes/network/block_sync.gd")
const ROUND_SYNC_SCRIPT := preload("res://scenes/network/round_sync.gd")

var game: Node = null
var tick: int = 0

var _sequence: int = 0
var _modules: Array[SyncModule] = []
var _modules_by_name: Dictionary = {}
var _packet_handlers: Dictionary = {}
var _world_snapshot_timer: float = 0.0
var _snapshot_rate: float = GameSettings.DEFAULT_WORLD_SNAPSHOT_RATE


func setup(game_world: Node) -> void:
	game = game_world
	process_mode = Node.PROCESS_MODE_ALWAYS

	if game != null and game.has_method("get_config"):
		var config: Variant = game.call("get_config")
		if config is Dictionary:
			_snapshot_rate = config.get("snapshot_rate", GameSettings.DEFAULT_WORLD_SNAPSHOT_RATE)

	if not NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.connect(_on_packet_received)

	register_module(PLAYER_SYNC_SCRIPT.new() as SyncModule)
	register_module(PROJECTILE_SYNC_SCRIPT.new() as SyncModule)
	register_module(COMBAT_SYNC_SCRIPT.new() as SyncModule)
	register_module(BLOCK_SYNC_SCRIPT.new() as SyncModule)
	register_module(ROUND_SYNC_SCRIPT.new() as SyncModule)


func _exit_tree() -> void:
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)


func _physics_process(delta: float) -> void:
	if not is_network_active():
		return

	tick += 1
	for module in _modules:
		module.physics_sync_tick(delta)

	if is_host():
		_world_snapshot_timer -= delta
		if _world_snapshot_timer <= 0.0:
			_world_snapshot_timer = 1.0 / _snapshot_rate
			_send_world_snapshot()


func register_module(module: SyncModule) -> void:
	add_child(module)
	_modules.append(module)

	module.setup(self, game)

	var module_name: String = _get_module_name(module)
	_modules_by_name[module_name] = module

	for packet_type in module.get_packet_types():
		_packet_handlers[str(packet_type)] = module


func get_module(module_name: StringName) -> SyncModule:
	return _modules_by_name.get(str(module_name), null) as SyncModule


func is_network_active() -> bool:
	return NetworkSession.is_steam_match_active()


func is_host() -> bool:
	return NetworkSession.is_host()


func is_client() -> bool:
	return NetworkSession.is_client()


func get_local_slot() -> int:
	return NetworkSession.local_player_slot


func get_remote_slot() -> int:
	return GameSettings.PLAYER_TWO_SLOT if get_local_slot() == GameSettings.PLAYER_ONE_SLOT else GameSettings.PLAYER_ONE_SLOT


func send_reliable(packet_type: StringName, payload: Dictionary, channel: int = GameSettings.NETWORK_DEFAULT_CHANNEL) -> void:
	if channel == GameSettings.NETWORK_DEFAULT_CHANNEL:
		channel = GameSettings.NETWORK_CHANNEL_EVENTS
	NetworkSession.send_reliable(_make_packet(packet_type, payload), channel)


func send_unreliable(packet_type: StringName, payload: Dictionary, channel: int = GameSettings.NETWORK_DEFAULT_CHANNEL) -> void:
	if channel == GameSettings.NETWORK_DEFAULT_CHANNEL:
		channel = GameSettings.NETWORK_CHANNEL_STATE
	NetworkSession.send_unreliable(_make_packet(packet_type, payload), channel)


func request_shot(owner_slot: int, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var projectile_sync: Variant = get_module(&"projectile")
	if projectile_sync != null and projectile_sync.has_method("request_shot"):
		projectile_sync.call("request_shot", owner_slot, spawn_position, direction, projectile_data)


func _make_packet(packet_type: StringName, payload: Dictionary) -> Dictionary:
	_sequence += 1
	return {
		"protocol_version": GameSettings.NETWORK_PROTOCOL_VERSION,
		"type": str(packet_type),
		"seq": _sequence,
		"tick": tick,
		"from_slot": get_local_slot(),
		"payload": payload,
	}


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	if not is_network_active():
		return

	var packet_type: String = str(packet.get("type", ""))
	if packet_type == str(GameSettings.PACKET_WORLD_SNAPSHOT):
		_apply_world_snapshot(_get_payload(packet))
		return

	var module: SyncModule = _packet_handlers.get(packet_type, null) as SyncModule
	if module != null:
		module.handle_packet(packet)


func _send_world_snapshot() -> void:
	var modules_snapshot: Dictionary = {}
	for module in _modules:
		var module_snapshot: Dictionary = module.build_snapshot()
		if module_snapshot.is_empty():
			continue

		var module_name: String = _get_module_name(module)
		modules_snapshot[module_name] = module_snapshot

	if modules_snapshot.is_empty():
		return

	send_unreliable(GameSettings.PACKET_WORLD_SNAPSHOT, {"modules": modules_snapshot})


func _apply_world_snapshot(payload: Dictionary) -> void:
	if is_host():
		return

	var modules_data: Variant = payload.get("modules", {})
	if not (modules_data is Dictionary):
		return

	for module_name in modules_data.keys():
		var module: SyncModule = _modules_by_name.get(str(module_name), null) as SyncModule
		var module_data: Variant = modules_data[module_name]
		if module != null and (module_data is Dictionary):
			module.apply_snapshot(module_data)


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}


func _get_module_name(module: SyncModule) -> String:
	return str(module.get_module_name())
