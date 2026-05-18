extends Node2D

@onready var _local_player: Player = %LocalPlayer
@onready var _remote_preview: Player = %RemotePreview
@onready var _ready_area: Area2D = %ReadyArea
@onready var _steam_label: Label = %SteamLabel
@onready var _local_name_label: Label = %LocalNameLabel
@onready var _remote_name_label: Label = %RemoteNameLabel
@onready var _local_ready_label: Label = %LocalReadyLabel
@onready var _remote_ready_label: Label = %RemoteReadyLabel
@onready var _color_picker: OptionButton = %ColorPicker
@onready var _invite_button: Button = %InviteButton

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _is_updating_picker: bool = false


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_configure_players()
	_build_color_picker()

	_ready_area.body_entered.connect(_on_ready_body_entered)
	_ready_area.body_exited.connect(_on_ready_body_exited)
	_color_picker.item_selected.connect(_on_color_selected)
	_invite_button.pressed.connect(_on_invite_pressed)
	OnlineMatch.state_changed.connect(_refresh)
	NetworkSession.status_changed.connect(_refresh)
	NetworkSession.peer_changed.connect(_refresh)
	_refresh("")


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if NetworkSession.status_changed.is_connected(_refresh):
		NetworkSession.status_changed.disconnect(_refresh)
	if NetworkSession.peer_changed.is_connected(_refresh):
		NetworkSession.peer_changed.disconnect(_refresh)


func _configure_players() -> void:
	_local_player.configure_local_control(
		_local_slot,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		false
	)
	_local_player.set_controls_enabled(true)

	_remote_preview.configure_remote_control(_remote_slot)
	_remote_preview.set_controls_enabled(false)
	_remote_preview.collision_layer = 0
	_remote_preview.collision_mask = 0


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
	var local_color_id: StringName = OnlineMatch.get_player_color_id(_local_slot)
	var remote_color_id: StringName = OnlineMatch.get_player_color_id(_remote_slot)
	_local_player.set_player_color(local_color_id)
	_remote_preview.set_player_color(remote_color_id)

	_steam_label.text = "%s | %s" % [SteamService.get_status_text(), NetworkSession.status_text]
	_local_name_label.text = "%s (%s)" % [_get_local_name(), GameSettings.player_color_display_name(local_color_id)]
	_remote_name_label.text = "%s (%s)" % [_get_remote_name(), GameSettings.player_color_display_name(remote_color_id)]

	var local_ready: bool = OnlineMatch.locker_ready.get(_local_slot, false) == true
	var remote_ready: bool = OnlineMatch.locker_ready.get(_remote_slot, false) == true
	_local_ready_label.text = "You: READY" if local_ready else "You: walk into the ready area"
	_remote_ready_label.text = "Friend: READY" if remote_ready else "Friend: waiting"
	_invite_button.disabled = NetworkSession.mode != GameSettings.NETWORK_MODE_HOST or not SteamService.steam_enabled
	_select_color(local_color_id)


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


func _on_ready_body_entered(body: Node) -> void:
	if body == _local_player:
		OnlineMatch.set_local_locker_ready(true)


func _on_ready_body_exited(body: Node) -> void:
	if body == _local_player:
		OnlineMatch.set_local_locker_ready(false)


func _get_local_name() -> String:
	if SteamService.steam_enabled:
		return SteamService.steam_name
	return "You"


func _get_remote_name() -> String:
	if NetworkSession.remote_steam_id == 0:
		return "Waiting for friend"
	if SteamService.steam_enabled:
		return Steam.getFriendPersonaName(NetworkSession.remote_steam_id)
	return "Friend"
