extends Node2D

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
const LOCKER_PROJECTILE_COLLISION_MASK: int = 1
const PLAYER_ONE_LOCKER_STATION: Vector2 = Vector2(320.0, 430.0)
const PLAYER_TWO_LOCKER_STATION: Vector2 = Vector2(960.0, 430.0)

@onready var _player_one: Player = %PlayerOne
@onready var _player_two: Player = %PlayerTwo
@onready var _player_one_color_targets: Node2D = $LockerWorld/PlayerOneColorTargets
@onready var _player_two_color_targets: Node2D = $LockerWorld/PlayerTwoColorTargets
@onready var _projectiles: Node2D = %Projectiles
@onready var _steam_label: Label = %SteamLabel
@onready var _player_one_name_label: Label = %PlayerOneNameLabel
@onready var _player_two_name_label: Label = %PlayerTwoNameLabel
@onready var _player_one_ready_label: Label = %PlayerOneReadyLabel
@onready var _player_two_ready_label: Label = %PlayerTwoReadyLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _invite_button: Button = %InviteButton
@onready var _player_one_ready_target: StaticBody2D = %PlayerOneReadyTarget
@onready var _player_two_ready_target: StaticBody2D = %PlayerTwoReadyTarget

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _local_player: Player = null
var _remote_player: Player = null
var _send_timer: float = 0.0


func _ready() -> void:
	add_to_group(GameSettings.GAME_WORLD_GROUP)
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_configure_players()

	_invite_button.pressed.connect(_on_invite_pressed)
	OnlineMatch.state_changed.connect(_refresh)
	NetworkSession.status_changed.connect(_refresh)
	NetworkSession.peer_changed.connect(_refresh)
	NetworkSession.packet_received.connect(_on_packet_received)
	_refresh("")


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if NetworkSession.status_changed.is_connected(_refresh):
		NetworkSession.status_changed.disconnect(_refresh)
	if NetworkSession.peer_changed.is_connected(_refresh):
		NetworkSession.peer_changed.disconnect(_refresh)
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)


func _physics_process(delta: float) -> void:
	if not NetworkSession.is_steam_match_active() or NetworkSession.remote_steam_id == 0:
		return

	_send_timer -= delta
	if _send_timer > 0.0:
		return

	_send_timer = 1.0 / GameSettings.NETWORK_PLAYER_STATE_RATE
	_send_locker_snapshot()


func _configure_players() -> void:
	_player_one.player_slot = GameSettings.PLAYER_ONE_SLOT
	_player_two.player_slot = GameSettings.PLAYER_TWO_SLOT

	if _local_slot == GameSettings.PLAYER_ONE_SLOT:
		_local_player = _player_one
		_remote_player = _player_two
	else:
		_local_player = _player_two
		_remote_player = _player_one

	_local_player.configure_local_control(
		_local_slot,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		true
	)

	_remote_player.configure_remote_control(_remote_slot)
	_configure_locker_station(_player_one, PLAYER_ONE_LOCKER_STATION, _player_one == _local_player)
	_configure_locker_station(_player_two, PLAYER_TWO_LOCKER_STATION, _player_two == _local_player)


func _configure_locker_station(player: Player, station_position: Vector2, allow_shoot: bool) -> void:
	player.global_position = station_position
	player.velocity = Vector2.ZERO
	player.gravity = 0.0
	player.movement_enabled = false
	player.shooting_enabled = allow_shoot
	player.collision_mask = 0

	var state_machine: Node = player.get_node_or_null("State")
	if state_machine != null:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED

	var left_ray: RayCast2D = player.get_node_or_null("RayL") as RayCast2D
	var right_ray: RayCast2D = player.get_node_or_null("RayR") as RayCast2D
	if left_ray != null:
		left_ray.enabled = false
	if right_ray != null:
		right_ray.enabled = false


func _refresh(_message: String = "") -> void:
	var player_one_color_id: StringName = OnlineMatch.get_player_color_id(GameSettings.PLAYER_ONE_SLOT)
	var player_two_color_id: StringName = OnlineMatch.get_player_color_id(GameSettings.PLAYER_TWO_SLOT)
	_player_one.set_player_color(player_one_color_id)
	_player_two.set_player_color(player_two_color_id)

	_steam_label.text = "%s | %s" % [SteamService.get_status_text(), NetworkSession.status_text]
	_player_one_name_label.text = _build_slot_label(GameSettings.PLAYER_ONE_SLOT, player_one_color_id)
	_player_two_name_label.text = _build_slot_label(GameSettings.PLAYER_TWO_SLOT, player_two_color_id)

	var player_one_ready: bool = OnlineMatch.locker_ready.get(GameSettings.PLAYER_ONE_SLOT, false) == true
	var player_two_ready: bool = OnlineMatch.locker_ready.get(GameSettings.PLAYER_TWO_SLOT, false) == true
	_player_one_ready_label.text = _build_ready_label(GameSettings.PLAYER_ONE_SLOT, player_one_ready)
	_player_two_ready_label.text = _build_ready_label(GameSettings.PLAYER_TWO_SLOT, player_two_ready)
	_invite_button.visible = NetworkSession.mode == GameSettings.NETWORK_MODE_HOST
	_invite_button.disabled = not SteamService.steam_enabled
	_update_ready_target_visual(_player_one_ready_target, player_one_ready)
	_update_ready_target_visual(_player_two_ready_target, player_two_ready)
	_update_color_target_visuals(_player_one_color_targets, GameSettings.PLAYER_ONE_SLOT)
	_update_color_target_visuals(_player_two_color_targets, GameSettings.PLAYER_TWO_SLOT)
	_update_countdown_label()


func _build_slot_label(slot: int, color_id: StringName) -> String:
	return "Player %d: %s (%s)" % [
		slot,
		_get_slot_name(slot),
		GameSettings.player_color_display_name(color_id),
	]


func _build_ready_label(slot: int, is_ready: bool) -> String:
	return "Player %d: READY" % slot if is_ready else "Player %d: shoot ready" % slot


func _on_invite_pressed() -> void:
	NetworkSession.open_invite_overlay()


func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func request_shot(owner: Node, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var projectile: Node2D = PROJECTILE_SCENE.instantiate() as Node2D
	var owner_slot: int = 0
	if owner != null:
		owner_slot = int(owner.get("player_slot"))

	var muzzle_speed: float = float(projectile_data.get("muzzle_speed", projectile.get("muzzle_speed")))
	projectile.set("owner_slot", owner_slot)
	projectile.set("collision_mask", LOCKER_PROJECTILE_COLLISION_MASK)
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", muzzle_speed)
	projectile.set("gravity", float(projectile_data.get("gravity", projectile.get("gravity"))))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile.get("linear_damping"))))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile.get("max_distance"))))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * muzzle_speed))
	if projectile.has_signal("despawn_requested"):
		projectile.connect("despawn_requested", Callable(self, "_on_locker_projectile_despawn_requested"))
	spawn_projectile(projectile, spawn_position)


func _on_locker_projectile_despawn_requested(_projectile: Node, reason: StringName, collider) -> void:
	if reason != &"collision":
		return

	var target: Node = collider as Node
	if target == null:
		return

	var target_slot: int = int(target.get_meta("slot", 0))
	if target_slot != _local_slot:
		return

	var target_type: String = str(target.get_meta("locker_target_type", ""))
	if target_type == "color":
		var color_id: StringName = StringName(str(target.get_meta("color_id", "")))
		if OnlineMatch.is_color_taken_by_other(_local_slot, color_id):
			return
		OnlineMatch.set_local_color(color_id)
	elif target_type == "ready":
		var is_ready: bool = OnlineMatch.locker_ready.get(_local_slot, false) == true
		OnlineMatch.set_local_locker_ready(not is_ready)


func _send_locker_snapshot() -> void:
	if _local_player == null:
		return

	var payload: Dictionary = {
		"slot": _local_slot,
		"position": _local_player.global_position,
		"velocity": _local_player.velocity,
		"aim": _local_player.get_aim_world_position(),
		"facing": _local_player.last_dir,
	}
	NetworkSession.send_unreliable(
		_make_packet(GameSettings.PACKET_ONLINE_LOCKER_PLAYER_STATE, payload),
		GameSettings.NETWORK_CHANNEL_STATE
	)


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type != GameSettings.PACKET_ONLINE_LOCKER_PLAYER_STATE:
		return

	var slot: int = int(packet.get("from_slot", 0))
	if slot == 0 or slot == _local_slot:
		return

	var remote_player: Player = _get_player_by_slot(slot)
	if remote_player == null:
		return

	remote_player.apply_remote_snapshot(_get_payload(packet))


func _make_packet(packet_type: StringName, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": GameSettings.NETWORK_PROTOCOL_VERSION,
		"type": str(packet_type),
		"seq": 0,
		"tick": 0,
		"from_slot": _local_slot,
		"payload": payload,
	}


func _get_payload(packet: Dictionary) -> Dictionary:
	var payload: Variant = packet.get("payload", {})
	if payload is Dictionary:
		return payload
	return {}


func _get_player_by_slot(slot: int) -> Player:
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return _player_one
	if slot == GameSettings.PLAYER_TWO_SLOT:
		return _player_two
	return null


func _update_ready_target_visual(target: StaticBody2D, is_ready: bool) -> void:
	var fill: CanvasItem = target.get_node_or_null("Fill") as CanvasItem
	var check: CanvasItem = target.get_node_or_null("Check") as CanvasItem
	if fill != null:
		fill.visible = is_ready
	if check != null:
		check.visible = is_ready


func _update_color_target_visuals(targets_root: Node2D, owner_slot: int) -> void:
	for child in targets_root.get_children():
		var target: StaticBody2D = child as StaticBody2D
		if target == null:
			continue

		var color_id: StringName = StringName(str(target.get_meta("color_id", "")))
		var is_unavailable: bool = OnlineMatch.is_color_taken_by_other(owner_slot, color_id)
		_update_color_target_visual(target, is_unavailable)


func _update_color_target_visual(target: StaticBody2D, is_unavailable: bool) -> void:
	var circle: CanvasItem = target.get_node_or_null("Circle") as CanvasItem
	var blocked_ring: CanvasItem = target.get_node_or_null("BlockedRing") as CanvasItem
	if circle != null:
		circle.modulate = Color.WHITE
	if blocked_ring != null:
		blocked_ring.visible = is_unavailable


func _update_countdown_label() -> void:
	if OnlineMatch.locker_countdown_remaining < 0.0:
		_countdown_label.hide()
		return

	_countdown_label.text = "%d" % int(ceil(OnlineMatch.locker_countdown_remaining))
	_countdown_label.show()


func _get_slot_name(slot: int) -> String:
	if slot == _local_slot:
		if SteamService.steam_enabled:
			return SteamService.steam_name
		return "Local player"

	if NetworkSession.remote_steam_id == 0:
		return "Waiting"
	if SteamService.steam_enabled:
		return Steam.getFriendPersonaName(NetworkSession.remote_steam_id)
	return "Remote player"
