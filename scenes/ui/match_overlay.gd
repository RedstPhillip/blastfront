extends Control

const ROUND_SCORE_DOT_SCENE: PackedScene = preload("res://scenes/ui/RoundScoreDot.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/Game.tscn")

@onready var _left_player_panel: ArcadePlayerPanel = %LeftPlayerPanel
@onready var _right_player_panel: ArcadePlayerPanel = %RightPlayerPanel
@onready var _left_score: Label = %LeftScore
@onready var _right_score: Label = %RightScore
@onready var _left_round_dots: HBoxContainer = %LeftRoundDots
@onready var _right_round_dots: HBoxContainer = %RightRoundDots
@onready var _banner_panel: PanelContainer = %BannerPanel
@onready var _banner_label: Label = %BannerLabel
@onready var _victory_actions: HBoxContainer = %VictoryActions
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _main_menu_button: Button = %MainMenuButton

var _game: Node = null
var _last_banner_text: String = ""
var _round_dot_target: int = 0


func _ready() -> void:
	if not OnlineMatch.state_changed.is_connected(_refresh_score):
		OnlineMatch.state_changed.connect(_refresh_score)
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	GameJuice.attach_button_feedback(self)
	call_deferred("_bind_game")


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh_score):
		OnlineMatch.state_changed.disconnect(_refresh_score)


func _process(_delta: float) -> void:
	if _game == null or not is_instance_valid(_game):
		_bind_game()
	_refresh_score()


func _bind_game() -> void:
	_game = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if _game == null or not _game.has_method("get_player_by_slot"):
		return

	var player_one: Player = _game.call("get_player_by_slot", GameSettings.PLAYER_ONE_SLOT) as Player
	var player_two: Player = _game.call("get_player_by_slot", GameSettings.PLAYER_TWO_SLOT) as Player
	_left_player_panel.bind_player(player_one)
	_right_player_panel.bind_player(player_two)


func _refresh_score() -> void:
	if NetworkSession.is_steam_match_active():
		_refresh_online_score()
	else:
		_refresh_offline_score()


func _refresh_online_score() -> void:
	var left_color: Color = OnlineMatch.get_player_color(GameSettings.PLAYER_ONE_SLOT)
	var right_color: Color = OnlineMatch.get_player_color(GameSettings.PLAYER_TWO_SLOT)
	var left_match_score: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var right_match_score: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	var left_round_score: int = int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0))
	var right_round_score: int = int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0))
	_apply_scoreboard(
		left_match_score,
		right_match_score,
		left_round_score,
		right_round_score,
		GameSettings.ONLINE_SET_KILLS_TO_WIN,
		left_color,
		right_color
	)

	if OnlineMatch.phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_show_winner_banner(OnlineMatch.last_winner_slot)
	elif OnlineMatch.phase == GameSettings.MATCH_PHASE_FINAL:
		_show_victory_screen(
			OnlineMatch.final_winner_slot,
			OnlineMatch.get_player_color(OnlineMatch.final_winner_slot),
			OnlineMatch.get_player_color_name(OnlineMatch.final_winner_slot).to_upper()
		)
	else:
		_banner_panel.hide()


func _refresh_offline_score() -> void:
	_banner_panel.hide()
	var left_score: int = 0
	var right_score: int = 0
	if _game != null and _game.has_method("get_score_for_slot"):
		left_score = int(_game.call("get_score_for_slot", GameSettings.PLAYER_ONE_SLOT))
		right_score = int(_game.call("get_score_for_slot", GameSettings.PLAYER_TWO_SLOT))

	_apply_scoreboard(
		left_score,
		right_score,
		left_score,
		right_score,
		GameSettings.MATCH_WINS_NEEDED,
		GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_LOCAL_COLOR),
		GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_REMOTE_COLOR)
	)

	if _game != null and _game.has_method("is_match_over") and _game.call("is_match_over") == true:
		var winner_slot: int = int(_game.call("get_winner_slot")) if _game.has_method("get_winner_slot") else 0
		var winner_color: Color = GameSettings.player_color_value(
			GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if winner_slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR
		)
		_show_victory_screen(winner_slot, winner_color, "PLAYER %d" % winner_slot)


func _apply_scoreboard(
	left_match_score: int,
	right_match_score: int,
	left_round_score: int,
	right_round_score: int,
	round_target: int,
	left_color: Color,
	right_color: Color
) -> void:
	_left_score.text = str(left_match_score)
	_right_score.text = str(right_match_score)
	_left_score.add_theme_color_override("font_color", left_color.lightened(0.12))
	_right_score.add_theme_color_override("font_color", right_color.lightened(0.12))

	if round_target != _round_dot_target:
		_rebuild_round_dots(round_target)
	_update_round_dots(_left_round_dots, left_round_score, left_color)
	_update_round_dots(_right_round_dots, right_round_score, right_color)


func _rebuild_round_dots(round_target: int) -> void:
	var dot_containers: Array[HBoxContainer] = [_left_round_dots, _right_round_dots]
	for container in dot_containers:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
		for dot_index in range(maxi(round_target, 0)):
			var dot: RoundScoreDot = ROUND_SCORE_DOT_SCENE.instantiate() as RoundScoreDot
			if dot != null:
				container.add_child(dot)
	_round_dot_target = round_target


func _update_round_dots(container: HBoxContainer, score: int, player_color: Color) -> void:
	for dot_index in range(container.get_child_count()):
		var dot: RoundScoreDot = container.get_child(dot_index) as RoundScoreDot
		if dot != null:
			dot.set_state(dot_index < score, player_color)


func _show_winner_banner(winner_slot: int) -> void:
	if winner_slot == 0:
		_banner_panel.hide()
		return

	_banner_panel.custom_minimum_size = Vector2(520, 140)
	_victory_actions.hide()
	_banner_label.custom_minimum_size = Vector2(460, 100)
	_banner_label.add_theme_font_size_override("font_size", 64)
	var winner_name: String = OnlineMatch.get_player_color_name(winner_slot).to_upper()
	_banner_label.text = "%s WINS" % winner_name
	_banner_label.add_theme_color_override("font_color", OnlineMatch.get_player_color(winner_slot).lightened(0.12))
	if not _banner_panel.visible or _last_banner_text != _banner_label.text:
		_play_banner_animation()
	_last_banner_text = _banner_label.text
	_banner_panel.show()


func _show_victory_screen(winner_slot: int, winner_color: Color, winner_name: String) -> void:
	if winner_slot == 0:
		_banner_panel.hide()
		return

	_banner_panel.custom_minimum_size = Vector2(720, 260)
	_victory_actions.show()
	_play_again_button.disabled = NetworkSession.is_steam_match_active() and not NetworkSession.is_host()
	_play_again_button.tooltip_text = "Only the host can restart an online match." if _play_again_button.disabled else ""
	_banner_label.custom_minimum_size = Vector2(680, 150)
	_banner_label.add_theme_font_size_override("font_size", 76)
	_banner_label.text = "VICTORY\n%s WINS" % winner_name
	_banner_label.add_theme_color_override("font_color", winner_color.lightened(0.12))
	if not _banner_panel.visible or _last_banner_text != _banner_label.text:
		_play_banner_animation()
		GameJuice.play_sound(&"spawn", -2.0, 0.02)
	_last_banner_text = _banner_label.text
	_banner_panel.show()


func _on_play_again_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	get_tree().paused = false
	if NetworkSession.is_steam_match_active():
		if NetworkSession.is_host():
			OnlineMatch.enter_locker(true)
		return

	if NetworkSession.is_debug():
		NetworkSession.start_debug()
	else:
		NetworkSession.start_offline()
	var main_node: Node = get_node_or_null("/root/Main")
	if main_node != null and main_node.has_method("change_scene"):
		main_node.call("change_scene", GAME_SCENE)


func _on_main_menu_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	get_tree().paused = false
	NetworkSession.leave_round()
	var main_node: Node = get_node_or_null("/root/Main")
	if main_node != null and main_node.has_method("show_menu"):
		main_node.call("show_menu")


func _play_banner_animation() -> void:
	_banner_panel.pivot_offset = _banner_panel.size * GameSettings.HALF
	_banner_panel.scale = Vector2(0.82, 0.82)
	_banner_panel.modulate.a = 0.0
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_banner_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
