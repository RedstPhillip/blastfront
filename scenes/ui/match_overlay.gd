extends Control

const ROUND_SCORE_DOT_SCENE: PackedScene = preload("res://scenes/ui/round_score_dot.tscn")
const HUD_FONT: Font = preload("res://assets/fonts/blastfront_hud_font.tres")

@onready var _left_player_panel: ArcadePlayerPanel = %LeftPlayerPanel
@onready var _right_player_panel: ArcadePlayerPanel = %RightPlayerPanel
@onready var _left_score: Label = %LeftScore
@onready var _right_score: Label = %RightScore
@onready var _left_round_dots: HBoxContainer = %LeftRoundDots
@onready var _right_round_dots: HBoxContainer = %RightRoundDots
@onready var _banner_panel: PanelContainer = %BannerPanel
@onready var _banner_label: Label = %BannerLabel
@onready var _victory_kicker: Label = %VictoryKicker
@onready var _victory_subtitle: Label = %VictorySubtitle
@onready var _victory_actions: HBoxContainer = %VictoryActions
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _main_menu_button: Button = %MainMenuButton

var _game: Game = null
var _last_banner_text: String = ""
var _round_dot_target: int = 0
var _transition_layer: Control = null
var _transition_flash: ColorRect = null
var _transition_top_bar: ColorRect = null
var _transition_bottom_bar: ColorRect = null
var _transition_center_line: ColorRect = null
var _transition_title: Label = null
var _transition_subtitle: Label = null
var _transition_tween: Tween = null
var _last_transition_key: String = ""


func _ready() -> void:
	if not OnlineMatch.state_changed.is_connected(_refresh_score):
		OnlineMatch.state_changed.connect(_refresh_score)
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_build_round_transition_layer()
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
	_game = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP) as Game
	if _game == null:
		return

	var player_one: Player = _game.get_player_by_slot(GameSettings.PLAYER_ONE_SLOT)
	var player_two: Player = _game.get_player_by_slot(GameSettings.PLAYER_TWO_SLOT)
	_left_player_panel.bind_player(player_one)
	_right_player_panel.bind_player(player_two)
	if not _game.point_awarded.is_connected(_on_offline_point_awarded):
		_game.point_awarded.connect(_on_offline_point_awarded)


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
	if _game != null:
		left_score = _game.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT)
		right_score = _game.get_score_for_slot(GameSettings.PLAYER_TWO_SLOT)

	_apply_scoreboard(
		left_score,
		right_score,
		left_score,
		right_score,
		GameSettings.MATCH_WINS_NEEDED,
		GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_LOCAL_COLOR),
		GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_REMOTE_COLOR)
	)

	if _game != null and _game.is_match_over():
		var winner_slot: int = _game.get_winner_slot()
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
	_victory_kicker.hide()
	_victory_subtitle.hide()
	_banner_label.custom_minimum_size = Vector2(460, 100)
	_banner_label.add_theme_font_size_override("font_size", 64)
	var winner_name: String = OnlineMatch.get_player_color_name(winner_slot).to_upper()
	_banner_label.text = "%s WINS" % winner_name
	_banner_label.add_theme_color_override("font_color", OnlineMatch.get_player_color(winner_slot).lightened(0.12))
	if not _banner_panel.visible or _last_banner_text != _banner_label.text:
		_play_banner_animation()
		_play_round_transition(
			winner_slot,
			OnlineMatch.get_player_color(winner_slot),
			"%s SCORES" % winner_name,
			"NEXT ROUND"
		)
	_last_banner_text = _banner_label.text
	_banner_panel.show()


func _show_victory_screen(winner_slot: int, winner_color: Color, winner_name: String) -> void:
	if winner_slot == 0:
		_banner_panel.hide()
		return

	_banner_panel.custom_minimum_size = Vector2(820, 330)
	_victory_actions.show()
	_victory_kicker.show()
	_victory_subtitle.show()
	_play_again_button.disabled = NetworkSession.is_steam_match_active() and not NetworkSession.is_host()
	_play_again_button.tooltip_text = "Only the host can restart an online match." if _play_again_button.disabled else ""
	_banner_label.custom_minimum_size = Vector2(760, 155)
	_banner_label.add_theme_font_size_override("font_size", 70)
	_victory_kicker.text = "MATCH DECIDED"
	_banner_label.text = "%s\nHOLDS THE FRONT" % winner_name
	_banner_label.add_theme_color_override("font_color", winner_color.lightened(0.2))
	_victory_subtitle.text = "VICTORY CLAIMED  -  THE ARENA IS YOURS"
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

	if NetworkSession.is_training():
		NetworkSession.start_training()
	else:
		NetworkSession.start_offline()
	var main_node: Variant = get_node_or_null("/root/Main")
	if main_node != null:
		main_node.start_game()


func _on_main_menu_pressed() -> void:
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	get_tree().paused = false
	NetworkSession.leave_round()
	var main_node: Variant = get_node_or_null("/root/Main")
	if main_node != null:
		main_node.show_menu()


func _on_offline_point_awarded(winner_slot: int) -> void:
	var winner_color: Color = GameSettings.player_color_value(
		GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if winner_slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR
	)
	_play_round_transition(
		winner_slot,
		winner_color,
		"PLAYER %d SCORES" % winner_slot,
		"NEXT ROUND"
	)


func _play_banner_animation() -> void:
	_banner_panel.pivot_offset = _banner_panel.size * GameSettings.HALF
	_banner_panel.scale = Vector2(0.82, 0.82)
	_banner_panel.modulate.a = 0.0
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_banner_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_round_transition_layer() -> void:
	_transition_layer = Control.new()
	_transition_layer.name = "RoundTransition"
	_transition_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_layer.z_index = 90
	_transition_layer.visible = false
	add_child(_transition_layer)

	_transition_flash = ColorRect.new()
	_transition_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_transition_flash)

	_transition_top_bar = _create_transition_bar("TopSlash")
	_transition_bottom_bar = _create_transition_bar("BottomSlash")

	_transition_center_line = ColorRect.new()
	_transition_center_line.name = "CenterLine"
	_transition_center_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.add_child(_transition_center_line)

	_transition_title = _create_transition_label("Title", 58)
	_transition_subtitle = _create_transition_label("Subtitle", 22)


func _create_transition_bar(node_name: String) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.name = node_name
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.pivot_offset = Vector2(620.0, 40.0)
	_transition_layer.add_child(bar)
	return bar


func _create_transition_label(node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", HUD_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	label.add_theme_constant_override("outline_size", 7 if font_size > 30 else 4)
	_transition_layer.add_child(label)
	return label


func _play_round_transition(winner_slot: int, winner_color: Color, title_text: String, subtitle_text: String) -> void:
	if winner_slot == 0 or _transition_layer == null:
		return

	var transition_key: String = "%d:%s:%s" % [winner_slot, title_text, subtitle_text]
	if transition_key == _last_transition_key and _transition_layer.visible:
		return
	_last_transition_key = transition_key

	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var viewport_size: Vector2 = get_viewport_rect().size
	var sweep_width: float = viewport_size.x + 360.0
	var winner_tint: Color = winner_color.lightened(0.18)
	var dark_tint: Color = winner_color.darkened(0.55)

	_transition_layer.visible = true
	_transition_layer.modulate = Color.WHITE
	_transition_flash.color = Color(winner_tint.r, winner_tint.g, winner_tint.b, 0.38)
	_transition_flash.modulate.a = 1.0

	_transition_top_bar.color = Color(dark_tint.r, dark_tint.g, dark_tint.b, 0.88)
	_transition_top_bar.size = Vector2(sweep_width, 86.0)
	_transition_top_bar.position = Vector2(-sweep_width, viewport_size.y * 0.27)
	_transition_top_bar.rotation = -0.08

	_transition_bottom_bar.color = Color(winner_tint.r, winner_tint.g, winner_tint.b, 0.78)
	_transition_bottom_bar.size = Vector2(sweep_width, 72.0)
	_transition_bottom_bar.position = Vector2(viewport_size.x + 120.0, viewport_size.y * 0.59)
	_transition_bottom_bar.rotation = -0.08

	_transition_center_line.color = Color(1.0, 1.0, 1.0, 0.78)
	_transition_center_line.size = Vector2(viewport_size.x, 4.0)
	_transition_center_line.position = Vector2(0.0, viewport_size.y * 0.51)
	_transition_center_line.modulate.a = 0.0

	_transition_title.text = title_text
	_transition_title.add_theme_color_override("font_color", winner_tint)
	_transition_title.size = Vector2(viewport_size.x, 86.0)
	_transition_title.position = Vector2(0.0, viewport_size.y * 0.38 - 52.0)
	_transition_title.scale = Vector2(0.72, 0.72)
	_transition_title.pivot_offset = _transition_title.size * GameSettings.HALF
	_transition_title.modulate.a = 0.0

	_transition_subtitle.text = subtitle_text
	_transition_subtitle.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	_transition_subtitle.size = Vector2(viewport_size.x, 42.0)
	_transition_subtitle.position = Vector2(0.0, viewport_size.y * 0.54)
	_transition_subtitle.scale = Vector2(1.15, 1.15)
	_transition_subtitle.pivot_offset = _transition_subtitle.size * GameSettings.HALF
	_transition_subtitle.modulate.a = 0.0

	GameJuice.shake(5.0, 0.34)
	GameJuice.play_sound(&"spawn", -4.0, 0.03)

	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_flash, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_top_bar, "position:x", -70.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_top_bar, "position:x", viewport_size.x + 110.0, 0.42).set_delay(0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_bottom_bar, "position:x", -130.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_bottom_bar, "position:x", -sweep_width - 120.0, 0.42).set_delay(0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_center_line, "modulate:a", 1.0, 0.08).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_center_line, "modulate:a", 0.0, 0.34).set_delay(0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_title, "modulate:a", 1.0, 0.12).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_title, "scale", Vector2.ONE, 0.2).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_title, "modulate:a", 0.0, 0.28).set_delay(0.66).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_subtitle, "modulate:a", 1.0, 0.12).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_subtitle, "scale", Vector2.ONE, 0.18).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_subtitle, "modulate:a", 0.0, 0.22).set_delay(0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition_tween.finished.connect(_on_round_transition_finished)


func _on_round_transition_finished() -> void:
	if _transition_layer != null:
		_transition_layer.hide()
