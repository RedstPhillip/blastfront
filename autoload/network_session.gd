extends Node

signal status_changed(message: String)
signal match_started

const MODE_OFFLINE: StringName = &"offline"
const MODE_HOST: StringName = &"host"
const MODE_CLIENT: StringName = &"client"

const GAME_KEY := "blastfront"
const GAME_VERSION := "invite-test-1"
const CHANNEL_HANDSHAKE := 0
const CHANNEL_STATE := 1
const PACKET_READ_LIMIT := 32

var mode: StringName = MODE_OFFLINE
var lobby_id: int = 0
var lobby_members: Array[Dictionary] = []
var local_player_slot := 1
var remote_steam_id: int = 0
var status_text := "Offline"

var _match_active := false
var _game: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_steam_signals()
	_set_status("Offline")
	_check_command_line_invite()


func _process(_delta: float) -> void:
	if not _can_use_steam() or lobby_id == 0:
		return

	_read_p2p_packets(CHANNEL_HANDSHAKE)
	_read_p2p_packets(CHANNEL_STATE)


func start_offline() -> void:
	leave_round()
	mode = MODE_OFFLINE
	local_player_slot = 1
	remote_steam_id = 0
	_match_active = false
	_game = null
	_set_status("Offline local mode")


func host_invite_round() -> void:
	if not _can_use_steam():
		_set_status(SteamService.get_status_text())
		return

	leave_round()
	mode = MODE_HOST
	local_player_slot = 1
	_set_status("Creating private Steam invite...")
	Steam.createLobby(Steam.LOBBY_TYPE_PRIVATE, 2)


func open_invite_overlay() -> void:
	if not _can_use_steam():
		_set_status(SteamService.get_status_text())
		return
	if lobby_id == 0:
		host_invite_round()
		return

	Steam.activateGameOverlayInviteDialog(lobby_id)
	_set_status("Steam invite overlay opened")


func join_invited_round(target_lobby_id: int) -> void:
	if not _can_use_steam():
		_set_status(SteamService.get_status_text())
		return

	leave_round()
	mode = MODE_CLIENT
	local_player_slot = 2
	_set_status("Joining invited round...")
	Steam.joinLobby(target_lobby_id)


func leave_round() -> void:
	if _can_use_steam():
		if remote_steam_id != 0:
			Steam.closeP2PSessionWithUser(remote_steam_id)
		if lobby_id != 0:
			Steam.leaveLobby(lobby_id)

	lobby_id = 0
	lobby_members.clear()
	remote_steam_id = 0
	_match_active = false


func register_game(game: Node) -> void:
	_game = game


func unregister_game(game: Node) -> void:
	if _game == game:
		_game = null


func is_steam_match_active() -> bool:
	return _match_active and (mode == MODE_HOST or mode == MODE_CLIENT)


func send_player_state(slot: int, position: Vector2, velocity: Vector2, aim_world_position: Vector2) -> void:
	if not is_steam_match_active() or remote_steam_id == 0:
		return

	var packet := {
		"type": "player_state",
		"slot": slot,
		"position": position,
		"velocity": velocity,
		"aim": aim_world_position,
	}
	_send_packet(remote_steam_id, packet, CHANNEL_STATE)


func _connect_steam_signals() -> void:
	if not _can_use_steam():
		return

	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)


func _check_command_line_invite() -> void:
	if not _can_use_steam():
		return

	var args := OS.get_cmdline_args()
	for index in range(args.size()):
		if args[index] == "+connect_lobby" and index + 1 < args.size():
			var invited_lobby_id := int(args[index + 1])
			if invited_lobby_id != 0:
				join_invited_round(invited_lobby_id)
			return


func _on_join_requested(invite, _friend_id := 0) -> void:
	var invited_lobby_id := 0
	if invite is Dictionary:
		invited_lobby_id = int(invite.get("lobby", 0))
	else:
		invited_lobby_id = int(invite)
	if invited_lobby_id == 0:
		return
	join_invited_round(invited_lobby_id)


func _on_lobby_created(connect: int, created_lobby_id: int) -> void:
	if connect != 1:
		_set_status("Could not create Steam invite. Result: %s" % connect)
		mode = MODE_OFFLINE
		return

	lobby_id = created_lobby_id
	Steam.allowP2PPacketRelay(true)
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "game", GAME_KEY)
	Steam.setLobbyData(lobby_id, "version", GAME_VERSION)
	Steam.setLobbyData(lobby_id, "mode", "friend-invite-test")
	Steam.setLobbyData(lobby_id, "name", "%s's Blastfront Round" % SteamService.steam_name)

	_refresh_lobby_members()
	_start_match("Hosting invite round")
	Steam.activateGameOverlayInviteDialog(lobby_id)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_set_status("Could not join invite. Response: %s" % response)
		mode = MODE_OFFLINE
		return

	lobby_id = joined_lobby_id
	Steam.allowP2PPacketRelay(true)
	_refresh_lobby_members()

	if mode == MODE_CLIENT:
		local_player_slot = 2
		remote_steam_id = Steam.getLobbyOwner(lobby_id)
		_start_match("Joined invited round")
		_send_handshake()
	else:
		_start_match("Hosting invite round")


func _on_lobby_chat_update(changed_lobby_id: int, changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if changed_lobby_id != lobby_id:
		return

	_refresh_lobby_members()

	if changed_id == SteamService.steam_id:
		return

	if _is_lobby_member(changed_id):
		remote_steam_id = changed_id
		_send_handshake()
		_set_status("Friend connected: %s" % Steam.getFriendPersonaName(changed_id))
	elif changed_id == remote_steam_id:
		remote_steam_id = 0
		_set_status("Friend left the round")


func _on_p2p_session_request(remote_id) -> void:
	var requester_id := _extract_steam_id(remote_id)
	if requester_id == 0:
		return

	if _is_lobby_member(requester_id):
		Steam.acceptP2PSessionWithUser(requester_id)
		remote_steam_id = requester_id
		_send_handshake()


func _on_p2p_session_connect_fail(remote_id, session_error := -1) -> void:
	var failed_id := _extract_steam_id(remote_id)
	_set_status("Steam P2P failed with %s: %s" % [failed_id, _describe_p2p_error(int(session_error))])


func _refresh_lobby_members() -> void:
	lobby_members.clear()
	if lobby_id == 0:
		return

	var member_count := Steam.getNumLobbyMembers(lobby_id)
	for index in range(member_count):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, index)
		lobby_members.append({
			"steam_id": member_id,
			"steam_name": Steam.getFriendPersonaName(member_id),
		})
		if member_id != SteamService.steam_id:
			remote_steam_id = member_id


func _send_handshake() -> void:
	if remote_steam_id == 0:
		return

	var packet := {
		"type": "hello",
		"slot": local_player_slot,
		"steam_id": SteamService.steam_id,
		"name": SteamService.steam_name,
	}
	_send_packet(remote_steam_id, packet, CHANNEL_HANDSHAKE)


func _read_p2p_packets(channel: int) -> void:
	var packets_read := 0
	while packets_read < PACKET_READ_LIMIT:
		var packet_size: int = Steam.getAvailableP2PPacketSize(channel)
		if packet_size <= 0:
			return

		var raw_packet: Dictionary = Steam.readP2PPacket(packet_size, channel)
		packets_read += 1

		if raw_packet.is_empty():
			continue

		var payload: PackedByteArray = raw_packet.get("data", PackedByteArray())
		var packet: Variant = bytes_to_var(payload)
		if not (packet is Dictionary):
			continue

		var packet_dictionary: Dictionary = packet
		var sender_id := _extract_steam_id(raw_packet)
		_handle_packet(sender_id, packet_dictionary)


func _handle_packet(sender_id: int, packet: Dictionary) -> void:
	match str(packet.get("type", "")):
		"hello":
			var hello_sender := _resolve_packet_sender(sender_id, packet)
			if _is_lobby_member(hello_sender):
				remote_steam_id = hello_sender
				_set_status("Steam peer ready: %s" % packet.get("name", hello_sender))
				_send_packet(hello_sender, {"type": "hello_ack", "slot": local_player_slot, "steam_id": SteamService.steam_id}, CHANNEL_HANDSHAKE)
		"hello_ack":
			var ack_sender := _resolve_packet_sender(sender_id, packet)
			if _is_lobby_member(ack_sender):
				remote_steam_id = ack_sender
				_set_status("Steam peer ready")
		"player_state":
			if _game != null and _game.has_method("apply_remote_player_snapshot"):
				_game.apply_remote_player_snapshot(int(packet.get("slot", 0)), packet)


func _send_packet(target_steam_id: int, packet: Dictionary, channel: int) -> void:
	if not _can_use_steam() or target_steam_id == 0:
		return

	var data := var_to_bytes(packet)
	var send_type := _get_p2p_send_type(packet)
	Steam.sendP2PPacket(target_steam_id, data, send_type, channel)


func _start_match(message: String) -> void:
	if _match_active:
		_set_status(message)
		return

	_match_active = true
	_set_status(message)
	match_started.emit()


func _is_lobby_member(steam_id: int) -> bool:
	for member in lobby_members:
		if int(member.get("steam_id", 0)) == steam_id:
			return true
	return steam_id == SteamService.steam_id


func _extract_steam_id(value) -> int:
	if value is Dictionary:
		if value.has("remote_steam_id"):
			return int(value["remote_steam_id"])
		if value.has("steam_id_remote"):
			return int(value["steam_id_remote"])
		if value.has("steam_id"):
			return int(value["steam_id"])
		if value.has("identity"):
			return int(value["identity"])
	return int(value)


func _resolve_packet_sender(sender_id: int, packet: Dictionary) -> int:
	if sender_id != 0:
		return sender_id
	return int(packet.get("steam_id", 0))


func _get_p2p_send_type(packet: Dictionary) -> int:
	if str(packet.get("type", "")).begins_with("hello"):
		return Steam.P2P_SEND_RELIABLE
	return Steam.P2P_SEND_UNRELIABLE_NO_DELAY


func _describe_p2p_error(session_error: int) -> String:
	match session_error:
		0:
			return "none"
		1:
			return "target user not running same game"
		2:
			return "local user does not own app"
		3:
			return "target user is not connected to Steam"
		4:
			return "connection timed out"
		_:
			return "unknown error %s" % session_error


func _can_use_steam() -> bool:
	return SteamService != null and SteamService.steam_enabled


func _set_status(message: String) -> void:
	status_text = message
	status_changed.emit(status_text)
