extends Control

## In-match HUD: scoreboard, player cards, crosshair, off-screen indicators, round announcer and results.
## Works for online matches, versus-bot duels and the sandbox.

const RESULTS_DELAY_SECONDS: float = 1.6
const CARD_MARGIN: float = 18.0

var _game: Game = null
var _quest_tracker: HudQuestTracker = null
var _toasts: HudToasts = null
var _controls_hint: HudControlsHint = null
var _scoreboard: HudScoreboard = null
var _left_card: HudPlayerCard = null
var _right_card: HudPlayerCard = null
var _crosshair: HudCrosshair = null
var _indicators: HudOffscreenIndicators = null
var _banner: HudRoundBanner = null
var _victory: HudVictoryScreen = null
var _sandbox_hint: PanelContainer = null
var _sandbox_hint_text: Label = null
var _last_online_banner_key: String = ""
var _results_pending: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud()
	if not OnlineMatch.state_changed.is_connected(_refresh_online_state):
		OnlineMatch.state_changed.connect(_refresh_online_state)
	_bind_game.call_deferred()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh_online_state):
		OnlineMatch.state_changed.disconnect(_refresh_online_state)


func _build_hud() -> void:
	_indicators = HudOffscreenIndicators.new()
	add_child(_indicators)

	_scoreboard = HudScoreboard.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_scoreboard.position = Vector2(-HudScoreboard.BOARD_SIZE.x * 0.5, 6.0)
	add_child(_scoreboard)

	_left_card = HudPlayerCard.new()
	_left_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_left_card.position = Vector2(CARD_MARGIN, -HudPlayerCard.CARD_SIZE.y - CARD_MARGIN)
	add_child(_left_card)

	_right_card = HudPlayerCard.new()
	_right_card.mirrored = true
	_right_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_right_card.position = Vector2(-HudPlayerCard.CARD_SIZE.x - CARD_MARGIN, -HudPlayerCard.CARD_SIZE.y - CARD_MARGIN)
	add_child(_right_card)

	_sandbox_hint = PanelContainer.new()
	_sandbox_hint.add_theme_stylebox_override("panel", UiStyle.with_margins(UiStyle.panel(UiStyle.PANEL, UiStyle.LINE, 4, 1, 0.15), 22, 8))
	_sandbox_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sandbox_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sandbox_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_row: HBoxContainer = HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 14)
	_sandbox_hint.add_child(hint_row)
	var hint_title: Label = Label.new()
	UiStyle.style_label(hint_title, UiStyle.FONT_DISPLAY, 18, UiStyle.ACCENT)
	hint_title.text = "SANDBOX"
	hint_row.add_child(hint_title)
	_sandbox_hint_text = Label.new()
	UiStyle.style_label(_sandbox_hint_text, UiStyle.FONT_UI, 14, UiStyle.TEXT_DIM)
	_update_sandbox_hint()
	hint_row.add_child(_sandbox_hint_text)
	InputDevice.device_changed.connect(_on_device_changed)
	_sandbox_hint.visible = false
	add_child(_sandbox_hint)

	_quest_tracker = HudQuestTracker.new()
	_quest_tracker.position = Vector2(CARD_MARGIN, CARD_MARGIN)
	_quest_tracker.visible = false
	add_child(_quest_tracker)

	_controls_hint = HudControlsHint.new()
	add_child(_controls_hint)

	_toasts = HudToasts.new()
	add_child(_toasts)

	_crosshair = HudCrosshair.new()
	_crosshair.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_crosshair)

	_banner = HudRoundBanner.new()
	add_child(_banner)

	_victory = HudVictoryScreen.new()
	_victory.rematch_pressed.connect(_on_rematch_pressed)
	_victory.menu_pressed.connect(_on_main_menu_pressed)
	add_child(_victory)


func _bind_game() -> void:
	_game = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP) as Game
	if _game == null:
		return
	_left_card.bind_player(_game.get_player_by_slot(GameSettings.PLAYER_ONE_SLOT), GameSettings.PLAYER_ONE_SLOT)
	_right_card.bind_player(_game.get_player_by_slot(GameSettings.PLAYER_TWO_SLOT), GameSettings.PLAYER_TWO_SLOT)
	if not _game.point_awarded.is_connected(_on_offline_point_awarded):
		_game.point_awarded.connect(_on_offline_point_awarded)
	if not _game.round_intro_started.is_connected(_on_round_intro_started):
		_game.round_intro_started.connect(_on_round_intro_started)
	if not _game.match_finished.is_connected(_on_match_finished):
		_game.match_finished.connect(_on_match_finished)
	var online: bool = NetworkSession.uses_set_flow()
	var training: bool = NetworkSession.is_training()
	_quest_tracker.visible = online
	_scoreboard.visible = not training
	_sandbox_hint.visible = training
	if (training or online) and HudControlsHint.should_show():
		_controls_hint.play(1.2)
	if training:
		var hint_width: float = _sandbox_hint.get_combined_minimum_size().x
		_sandbox_hint.offset_left = -hint_width * 0.5
		_sandbox_hint.offset_right = hint_width * 0.5
		_sandbox_hint.offset_top = 10.0
	_refresh_online_state()


func _on_device_changed(_using_gamepad: bool) -> void:
	_update_sandbox_hint()


func _update_sandbox_hint() -> void:
	_sandbox_hint_text.text = "Free practice  ·  %s  Loadout & Menu" % InputDevice.prompt(&"pause")


func _process(_delta: float) -> void:
	if _game == null or not is_instance_valid(_game):
		_bind_game()
		return
	if NetworkSession.uses_set_flow():
		_refresh_online_scoreboard()
	else:
		_refresh_offline_scoreboard()


func _refresh_offline_scoreboard() -> void:
	var left_score: int = _game.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT)
	var right_score: int = _game.get_score_for_slot(GameSettings.PLAYER_TWO_SLOT)
	_scoreboard.left_color = UiStyle.player_color(GameSettings.PLAYER_ONE_SLOT)
	_scoreboard.right_color = UiStyle.player_color(GameSettings.PLAYER_TWO_SLOT)
	_scoreboard.left_name = UiStyle.player_name(GameSettings.PLAYER_ONE_SLOT)
	_scoreboard.right_name = UiStyle.player_name(GameSettings.PLAYER_TWO_SLOT)
	_scoreboard.center_label = "R%d" % maxi(_game.get_round_number(), 1)
	_scoreboard.set_state(left_score, right_score, left_score, right_score, _game.get_wins_needed())


func _refresh_online_scoreboard() -> void:
	_scoreboard.left_color = OnlineMatch.get_player_color(GameSettings.PLAYER_ONE_SLOT)
	_scoreboard.right_color = OnlineMatch.get_player_color(GameSettings.PLAYER_TWO_SLOT)
	_scoreboard.left_name = _set_flow_name(GameSettings.PLAYER_ONE_SLOT)
	_scoreboard.right_name = _set_flow_name(GameSettings.PLAYER_TWO_SLOT)
	var left_points: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var right_points: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	_scoreboard.center_label = "S%d" % (left_points + right_points + 1)
	_scoreboard.set_state(
		left_points,
		right_points,
		int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0)),
		int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0)),
		GameSettings.ONLINE_SET_KILLS_TO_WIN
	)


func _set_flow_name(slot: int) -> String:
	if NetworkSession.is_bot_shop_duel():
		return UiStyle.player_name(slot)
	return OnlineMatch.get_player_color_name(slot).to_upper()


func _refresh_online_state() -> void:
	if not NetworkSession.uses_set_flow():
		return
	if OnlineMatch.phase == GameSettings.MATCH_PHASE_KILL_BANNER and OnlineMatch.last_winner_slot != 0:
		var key: String = "%d:%d:%d:%d" % [
			OnlineMatch.last_winner_slot,
			int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0)),
			int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0)),
			OnlineMatch.match_generation,
		]
		if key != _last_online_banner_key:
			_last_online_banner_key = key
			var winner: int = OnlineMatch.last_winner_slot
			var subtitle: String = "%d  —  %d" % [int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0)), int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0))]
			var title: String = "%s SCORES" % OnlineMatch.get_player_color_name(winner).to_upper()
			var set_over: bool = int(OnlineMatch.set_kills.get(winner, 0)) >= GameSettings.ONLINE_SET_KILLS_TO_WIN
			if NetworkSession.is_bot_shop_duel():
				var local_won: bool = winner == GameSettings.PLAYER_ONE_SLOT
				if set_over:
					title = "SET WON" if local_won else "SET LOST"
					subtitle = "SETS  %d  —  %d" % [int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)), int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))]
				else:
					title = "ROUND WON" if local_won else "ROUND LOST"
				if local_won and not set_over:
					_announce_round_award(_game.get_player_by_slot(winner))
			_banner.play_point(OnlineMatch.get_player_color(winner), title, subtitle, set_over)
	elif OnlineMatch.phase == GameSettings.MATCH_PHASE_PLAYING_SET:
		_last_online_banner_key = ""
	if OnlineMatch.phase == GameSettings.MATCH_PHASE_FINAL and OnlineMatch.final_winner_slot != 0 and not _victory.is_shown():
		_show_online_results()


func _on_round_intro_started(round_number: int, duration: float) -> void:
	if NetworkSession.is_bot_shop_duel():
		var set_number: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)) + int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0)) + 1
		var set_subtitle: String = "FIRST TO %d SETS" % GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN if set_number == 1 and OnlineMatch.small_round_number <= 1 else "ROUND %d" % OnlineMatch.small_round_number
		_banner.play_intro(set_number, duration, set_subtitle, "SET %d" % set_number)
		if set_number == 1 and OnlineMatch.small_round_number <= 1 and HudControlsHint.should_show():
			_controls_hint.play(duration * 0.35)
		return
	var wins_needed: int = _game.get_wins_needed()
	var subtitle: String = ""
	if round_number == 1:
		subtitle = "FIRST TO %d" % wins_needed
	elif _game.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT) == wins_needed - 1 or _game.get_score_for_slot(GameSettings.PLAYER_TWO_SLOT) == wins_needed - 1:
		subtitle = "MATCH POINT"
	_banner.play_intro(round_number, duration, subtitle)
	if round_number == 1 and HudControlsHint.should_show():
		_controls_hint.play(duration * 0.35)


func _on_offline_point_awarded(winner_slot: int) -> void:
	if NetworkSession.is_training():
		return
	var color: Color = UiStyle.player_color(winner_slot)
	var local_won: bool = winner_slot == GameSettings.PLAYER_ONE_SLOT
	var left: int = _game.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT)
	var right: int = _game.get_score_for_slot(GameSettings.PLAYER_TWO_SLOT)
	var final_point: bool = maxi(left, right) >= _game.get_wins_needed()
	var title: String = "KNOCKOUT" if final_point else ("ROUND WON" if local_won else "ROUND LOST")
	_banner.play_point(color, title, "%d  —  %d" % [left, right], final_point)
	if local_won and not final_point:
		_announce_round_award(_game.get_player_by_slot(winner_slot))


## Small extra recognition for standout rounds; shown after the point banner has landed.
func _announce_round_award(winner: Player) -> void:
	if winner == null or not is_instance_valid(winner) or winner.health_component == null:
		return
	var ratio: float = float(winner.health_component.health) / maxf(float(winner.health_component.max_health), 1.0)
	var title: String = ""
	var detail: String = ""
	if ratio >= 0.999:
		title = "PERFECT ROUND"
		detail = "Won without taking a single hit"
	elif ratio <= 0.25:
		title = "CLUTCH"
		detail = "Survived on the last sliver of health"
	if title == "":
		return
	await get_tree().create_timer(0.7, true, false, true).timeout
	if is_inside_tree():
		HudToasts.notify(title, detail, UiStyle.ACCENT_HOT, &"reward")


func _on_match_finished(winner_slot: int) -> void:
	if _results_pending:
		return
	_results_pending = true
	await get_tree().create_timer(RESULTS_DELAY_SECONDS, true, false, true).timeout
	_results_pending = false
	if not is_inside_tree():
		return
	var local_won: bool = winner_slot == GameSettings.PLAYER_ONE_SLOT
	var left: int = _game.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT)
	var right: int = _game.get_score_for_slot(GameSettings.PLAYER_TWO_SLOT)
	var winner_name: String = UiStyle.player_name(winner_slot)
	_victory.show_result(
		local_won,
		UiStyle.player_color(winner_slot).lightened(0.2),
		"%s WIN%s   %d — %d" % [winner_name, "" if winner_name == "YOU" else "S", left, right],
		_build_stats(GameSettings.PLAYER_ONE_SLOT),
		true,
		"REMATCH"
	)


func _show_online_results() -> void:
	var winner: int = OnlineMatch.final_winner_slot
	var local_won: bool = winner == NetworkSession.local_player_slot
	var left: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var right: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	if NetworkSession.is_bot_shop_duel():
		var winner_name: String = UiStyle.player_name(winner)
		_victory.show_result(
			local_won,
			UiStyle.player_color(winner).lightened(0.2),
			"%s WIN%s   SETS %d — %d" % [winner_name, "" if winner_name == "YOU" else "S", left, right],
			_build_stats(GameSettings.PLAYER_ONE_SLOT),
			true,
			"REMATCH"
		)
		return
	var can_rematch: bool = NetworkSession.is_host()
	var no_stats: Array[Dictionary] = []
	_victory.show_result(
		local_won,
		OnlineMatch.get_player_color(winner).lightened(0.2),
		"%s HOLDS THE FRONT   %d — %d" % [OnlineMatch.get_player_color_name(winner).to_upper(), left, right],
		no_stats,
		can_rematch,
		"PLAY AGAIN" if can_rematch else "HOST DECIDES"
	)

func _build_stats(slot: int) -> Array[Dictionary]:
	var stats: Dictionary = _game.get_match_stats(slot)
	var shots: int = int(stats.get("shots", 0))
	var hits: int = int(stats.get("hits", 0))
	var accuracy: float = (float(hits) / float(shots) * 100.0) if shots > 0 else 0.0
	var result: Array[Dictionary] = [
		{"label": "ACCURACY", "value": accuracy, "format": "%d%%"},
		{"label": "DAMAGE", "value": float(stats.get("damage", 0)), "format": "%d"},
		{"label": "BLOCKS", "value": float(stats.get("blocks", 0)), "format": "%d"},
		{"label": "ROUNDS", "value": float(_game.get_score_for_slot(slot)), "format": "%d"},
	]
	return result


func _on_rematch_pressed() -> void:
	get_tree().paused = false
	if NetworkSession.is_steam_match_active():
		if NetworkSession.is_host():
			OnlineMatch.enter_locker(true)
		return
	if Main.instance == null:
		return
	if NetworkSession.is_bot_duel():
		Main.instance.transition_to(Main.instance.start_bot_match)
		return
	Main.instance.transition_to(func() -> void:
		if NetworkSession.is_training():
			NetworkSession.start_training()
		else:
			NetworkSession.start_offline()
		Main.instance.start_game()
	)


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	if Main.instance == null:
		return
	Main.instance.leave_to_menu()
