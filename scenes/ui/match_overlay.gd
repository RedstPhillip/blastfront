extends Control

@onready var _match_score_label: Label = %MatchScoreLabel
@onready var _set_score_label: Label = %SetScoreLabel
@onready var _banner_panel: PanelContainer = %BannerPanel
@onready var _banner_label: Label = %BannerLabel

var _last_banner_text: String = ""


func _ready() -> void:
	OnlineMatch.state_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)


func _refresh() -> void:
	if not NetworkSession.is_steam_match_active():
		hide()
		return

	show()
	var slot_one_name: String = OnlineMatch.get_player_color_name(GameSettings.PLAYER_ONE_SLOT)
	var slot_two_name: String = OnlineMatch.get_player_color_name(GameSettings.PLAYER_TWO_SLOT)
	_match_score_label.text = "%s %d - %d %s" % [
		slot_one_name,
		int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)),
		int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0)),
		slot_two_name,
	]
	_set_score_label.text = "Set %d - %d" % [
		int(OnlineMatch.set_kills.get(GameSettings.PLAYER_ONE_SLOT, 0)),
		int(OnlineMatch.set_kills.get(GameSettings.PLAYER_TWO_SLOT, 0)),
	]

	if OnlineMatch.phase == GameSettings.MATCH_PHASE_KILL_BANNER:
		_show_winner_banner(OnlineMatch.last_winner_slot)
	elif OnlineMatch.phase == GameSettings.MATCH_PHASE_FINAL:
		_show_winner_banner(OnlineMatch.final_winner_slot)
	else:
		_banner_panel.hide()


func _show_winner_banner(winner_slot: int) -> void:
	if winner_slot == 0:
		_banner_panel.hide()
		return

	var winner_name: String = OnlineMatch.get_player_color_name(winner_slot).to_upper()
	_banner_label.text = "%s WON" % winner_name
	_banner_label.add_theme_color_override("font_color", OnlineMatch.get_player_color(winner_slot))
	if not _banner_panel.visible or _last_banner_text != _banner_label.text:
		_play_banner_animation()
	_last_banner_text = _banner_label.text
	_banner_panel.show()


func _play_banner_animation() -> void:
	_banner_panel.pivot_offset = _banner_panel.size * GameSettings.HALF
	_banner_panel.scale = Vector2(0.82, 0.82)
	_banner_panel.modulate.a = 0.0
	GameJuice.play_sound(&"ui_click", -8.0, 0.03)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_banner_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
