extends Control

@onready var _title_label: Label = %TitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _local_ready_label: Label = %LocalReadyLabel
@onready var _remote_ready_label: Label = %RemoteReadyLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _ready_page: Control = $Center
@onready var _extension_page: Control = $ExtensionWorkbench
@onready var _left_page_button: Button = %LeftPageButton
@onready var _right_page_button: Button = %RightPageButton
@onready var _page_label: Label = %PageLabel

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _page_index: int = 0


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_ready_button.pressed.connect(_on_ready_pressed)
	_left_page_button.pressed.connect(_on_previous_page_pressed)
	_right_page_button.pressed.connect(_on_next_page_pressed)
	GameJuice.attach_button_feedback(self)
	OnlineMatch.state_changed.connect(_refresh)
	OnlineMatch.countdown_changed.connect(_on_countdown_changed)
	_show_page(0)
	_refresh()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if OnlineMatch.countdown_changed.is_connected(_on_countdown_changed):
		OnlineMatch.countdown_changed.disconnect(_on_countdown_changed)


func _on_ready_pressed() -> void:
	OnlineMatch.set_local_intermission_ready(true)
	_refresh()


func _on_countdown_changed(_seconds_left: int) -> void:
	_refresh()


func _on_previous_page_pressed() -> void:
	_show_page(1)


func _on_next_page_pressed() -> void:
	_show_page(0)


func _show_page(page_index: int) -> void:
	_page_index = clampi(page_index, 0, 1)
	var showing_extensions: bool = _page_index == 1
	_ready_page.visible = not showing_extensions
	_extension_page.visible = showing_extensions
	_left_page_button.visible = not showing_extensions
	_right_page_button.visible = showing_extensions
	_page_label.text = "EXTENSIONS" if showing_extensions else "READY"


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
