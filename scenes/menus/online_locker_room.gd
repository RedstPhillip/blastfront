extends Node2D

@onready var _player_one: Player = %PlayerOne
@onready var _player_two: Player = %PlayerTwo
@onready var _player_one_ready_area: Area2D = %PlayerOneReadyArea
@onready var _player_two_ready_area: Area2D = %PlayerTwoReadyArea
@onready var _steam_label: Label = %SteamLabel
@onready var _player_one_name_label: Label = %PlayerOneNameLabel
@onready var _player_two_name_label: Label = %PlayerTwoNameLabel
@onready var _player_one_ready_label: Label = %PlayerOneReadyLabel
@onready var _player_two_ready_label: Label = %PlayerTwoReadyLabel
@onready var _color_label: Label = %ColorLabel
@onready var _color_picker: OptionButton = %ColorPicker
@onready var _invite_button: Button = %InviteButton

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _local_player: Player = null
var _remote_player: Player = null
var _is_updating_picker: bool = false
var _send_timer: float = 0.0


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_configure_players()
	_build_color_picker()

	_player_one_ready_area.body_entered.connect(_on_ready_body_entered.bind(GameSettings.PLAYER_ONE_SLOT))
	_player_one_ready_area.body_exited.connect(_on_ready_body_exited.bind(GameSettings.PLAYER_ONE_SLOT))
	_player_two_ready_area.body_entered.connect(_on_ready_body_entered.bind(GameSettings.PLAYER_TWO_SLOT))
	_player_two_ready_area.body_exited.connect(_on_ready_body_exited.bind(GameSettings.PLAYER_TWO_SLOT))
	_color_picker.item_selected.connect(_on_color_selected)
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
		false
	)
	_local_player.set_controls_enabled(true)

	_remote_player.configure_remote_control(_remote_slot)
	_remote_player.set_controls_enabled(false)


func _build_color_picker() -> void:
	_is_updating_picker = true
	_color_picker.clear()
	var colors: Array[StringName] = GameSettings.player_color_ids()
	for index in range(colors.size()):
		var color_id: StringName = colors[index]
		_color_picker.add_item(GameSettings.player_color_display_name(color_id))
		_color_picker.set_item_metadata(index, color_id)
	_is_updating_picker = false


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
	_select_color(OnlineMatch.get_player_color_id(_local_slot))


func _build_slot_label(slot: int, color_id: StringName) -> String:
	return "Player %d: %s (%s)" % [
		slot,
		_get_slot_name(slot),
		GameSettings.player_color_display_name(color_id),
	]


func _build_ready_label(slot: int, is_ready: bool) -> String:
	return "Player %d: READY" % slot if is_ready else "Player %d: ready zone" % slot


func _select_color(color_id: StringName) -> void:
	_is_updating_picker = true
	for index in range(_color_picker.item_count):
		var metadata: Variant = _color_picker.get_item_metadata(index)
		if StringName(str(metadata)) == color_id:
			_color_picker.select(index)
			break
	_is_updating_picker = false


func _on_color_selected(index: int) -> void:
	if _is_updating_picker:
		return
	var metadata: Variant = _color_picker.get_item_metadata(index)
	var color_id: StringName = StringName(str(metadata))
	OnlineMatch.set_local_color(color_id)


func _on_invite_pressed() -> void:
	NetworkSession.open_invite_overlay()


func _on_ready_body_entered(body: Node, slot: int) -> void:
	if slot == _local_slot and body == _local_player:
		OnlineMatch.set_local_locker_ready(true)


func _on_ready_body_exited(body: Node, slot: int) -> void:
	if slot == _local_slot and body == _local_player:
		OnlineMatch.set_local_locker_ready(false)


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
