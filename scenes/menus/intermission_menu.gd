extends Control

@onready var _title_label: Label = %TitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _local_ready_label: Label = %LocalReadyLabel
@onready var _remote_ready_label: Label = %RemoteReadyLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _status_page: Control = %StatusPage
@onready var _loadout_page: Control = %LoadoutPage
@onready var _research_page: Control = %ResearchPage
@onready var _left_page_button: Button = %LeftPageButton
@onready var _right_page_button: Button = %RightPageButton
@onready var _page_label: Label = %PageLabel
@onready var _damage_earnings_label: Label = %DamageEarningsLabel
@onready var _damage_coins_label: Label = %DamageCoinsLabel
@onready var _survival_earnings_label: Label = %SurvivalEarningsLabel
@onready var _survival_coins_label: Label = %SurvivalCoinsLabel
@onready var _blocking_earnings_label: Label = %BlockingEarningsLabel
@onready var _blocking_coins_label: Label = %BlockingCoinsLabel
@onready var _first_hit_earnings_label: Label = %FirstHitEarningsLabel
@onready var _first_hit_coins_label: Label = %FirstHitCoinsLabel
@onready var _earned_total_label: Label = %EarnedTotalLabel
@onready var _coin_balance_label: Label = %CoinBalanceLabel
@onready var _reward_cap_label: Label = %RewardCapLabel

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _page_index: int = 0


func _ready() -> void:
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	var completed_sets: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	completed_sets += int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	RoundRewardInventory.prepare_for_round(completed_sets)
	_ready_button.pressed.connect(_on_ready_pressed)
	_left_page_button.pressed.connect(_on_previous_page_pressed)
	_right_page_button.pressed.connect(_on_next_page_pressed)
	GameJuice.attach_button_feedback(self)
	OnlineMatch.state_changed.connect(_refresh)
	OnlineMatch.countdown_changed.connect(_on_countdown_changed)
	_set_page(0)
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
		if _page_index > -1:
			_set_page(_page_index - 1)
			get_viewport().set_input_as_handled()
	elif _is_page_right_event(event):
		if _page_index < 1:
			_set_page(_page_index + 1)
			get_viewport().set_input_as_handled()
	elif _is_page_cancel_event(event) and _page_index != 0:
		_set_page(0)
		get_viewport().set_input_as_handled()


func _on_countdown_changed(_seconds_left: int) -> void:
	_refresh()


func _on_previous_page_pressed() -> void:
	_set_page(_page_index - 1)


func _on_next_page_pressed() -> void:
	_set_page(_page_index + 1)


func _refresh() -> void:
	var local_name: String = OnlineMatch.get_player_color_name(_local_slot)
	var remote_name: String = OnlineMatch.get_player_color_name(_remote_slot)
	_title_label.text = "NEXT SET"
	_score_label.text = "%s %d - %d %s" % [
		local_name.to_upper(),
		int(OnlineMatch.match_points.get(_local_slot, 0)),
		int(OnlineMatch.match_points.get(_remote_slot, 0)),
		remote_name.to_upper(),
	]
	_countdown_label.text = "%dS" % int(ceil(OnlineMatch.intermission_remaining))

	var local_ready: bool = OnlineMatch.intermission_ready.get(_local_slot, false) == true
	var remote_ready: bool = OnlineMatch.intermission_ready.get(_remote_slot, false) == true
	_local_ready_label.text = "YOU // READY" if local_ready else "YOU // NOT READY"
	_remote_ready_label.text = "OPPONENT // READY" if remote_ready else "OPPONENT // NOT READY"
	_ready_button.disabled = local_ready
	_ready_button.text = "LOCK IN" if not local_ready else "READY LOCKED"
	_refresh_earnings()


func _refresh_earnings() -> void:
	var earnings: Dictionary = OnlineMatch.get_last_set_earnings(_local_slot)
	var damage: int = int(earnings.get("damage", 0))
	var survival_seconds: int = int(earnings.get("survival_seconds", 0))
	var blocked_damage: int = int(earnings.get("blocked_damage", 0))
	var first_hit: bool = earnings.get("first_hit", false) == true
	_damage_earnings_label.text = "%d DAMAGE" % damage
	_damage_coins_label.text = "+%d" % int(earnings.get("damage_coins", 0))
	_survival_earnings_label.text = "%dS ALIVE" % survival_seconds
	_survival_coins_label.text = "+%d" % int(earnings.get("survival_coins", 0))
	_blocking_earnings_label.text = "%d BLOCKED" % blocked_damage
	_blocking_coins_label.text = "+%d" % int(earnings.get("block_coins", 0))
	_first_hit_earnings_label.text = "FIRST HIT" if first_hit else "NO FIRST HIT"
	_first_hit_coins_label.text = "+%d" % int(earnings.get("first_hit_coins", 0))
	_earned_total_label.text = "EARNED  +%d" % int(earnings.get("earned", 0))
	_coin_balance_label.text = "BALANCE  %d COINS" % OnlineMatch.get_local_coin_balance()
	_reward_cap_label.visible = earnings.get("capped", false) == true


func _set_page(next_page: int) -> void:
	_page_index = clampi(next_page, -1, 1)
	_loadout_page.visible = _page_index == -1
	_status_page.visible = _page_index == 0
	_research_page.visible = _page_index == 1
	_left_page_button.visible = _page_index > -1
	_right_page_button.visible = _page_index < 1
	match _page_index:
		-1:
			_page_label.text = "LOADOUT // EQUIPMENT BAY"
		1:
			_page_label.text = "RESEARCH // FIELD LAB"
		_:
			_page_label.text = "< LOADOUT      COMBAT DEBRIEF      RESEARCH >"


func _is_page_left_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_left"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_LEFT


func _is_page_right_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_right"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false
	return key_event.keycode == KEY_RIGHT


func _is_page_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
