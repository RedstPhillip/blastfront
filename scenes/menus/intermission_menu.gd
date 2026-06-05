extends Control

@onready var _title_label: Label = %TitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _local_ready_label: Label = %LocalReadyLabel
@onready var _remote_ready_label: Label = %RemoteReadyLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _status_page: Control = %StatusPage
@onready var _loadout_page: Control = %LoadoutPage
@onready var _left_page_button: Button = %LeftPageButton
@onready var _right_page_button: Button = %RightPageButton
@onready var _page_label: Label = %PageLabel

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _showing_loadout: bool = false


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_ready_button.pressed.connect(_on_ready_pressed)
	_left_page_button.pressed.connect(_on_previous_page_pressed)
	_right_page_button.pressed.connect(_on_next_page_pressed)
	GameJuice.attach_button_feedback(self)
	OnlineMatch.state_changed.connect(_refresh)
	OnlineMatch.countdown_changed.connect(_on_countdown_changed)
	_set_loadout_visible(false)
	_refresh()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if OnlineMatch.countdown_changed.is_connected(_on_countdown_changed):
		OnlineMatch.countdown_changed.disconnect(_on_countdown_changed)


func _on_ready_pressed() -> void:
	OnlineMatch.set_local_intermission_ready(true)
	_refresh()


func _input(event: InputEvent) -> void:
	if _is_page_left_event(event):
		_set_loadout_visible(true)
		get_viewport().set_input_as_handled()
	elif _is_page_right_event(event):
		if _showing_loadout:
			_set_loadout_visible(false)
			get_viewport().set_input_as_handled()


func _on_countdown_changed(_seconds_left: int) -> void:
	_refresh()


func _on_previous_page_pressed() -> void:
	_set_loadout_visible(true)


func _on_next_page_pressed() -> void:
	_set_loadout_visible(false)


func _refresh() -> void:
	var local_name: String = OnlineMatch.get_player_color_name(_local_slot)
	var remote_name: String = OnlineMatch.get_player_color_name(_remote_slot)
	_title_label.text = "Next set"
	_score_label.text = "%s %d - %d %s" % [
		local_name,
		int(OnlineMatch.match_points.get(_local_slot, 0)),
		int(OnlineMatch.match_points.get(_remote_slot, 0)),
		remote_name,
	]
	_countdown_label.text = "%ds" % int(ceil(OnlineMatch.intermission_remaining))

	var local_ready: bool = OnlineMatch.intermission_ready.get(_local_slot, false) == true
	var remote_ready: bool = OnlineMatch.intermission_ready.get(_remote_slot, false) == true
	_local_ready_label.text = "You: READY" if local_ready else "You: not ready"
	_remote_ready_label.text = "Friend: READY" if remote_ready else "Friend: not ready"
	_ready_button.disabled = local_ready
	_ready_button.text = "Ready" if not local_ready else "Ready locked"


func _set_loadout_visible(visible: bool) -> void:
	_showing_loadout = visible
	_status_page.visible = not visible
	_loadout_page.visible = visible
	_left_page_button.visible = not visible
	_right_page_button.visible = visible
	_page_label.text = "LOADOUT" if visible else "READY"


func _is_page_left_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_left"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_LEFT


func _is_page_right_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false
	return key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_ESCAPE
