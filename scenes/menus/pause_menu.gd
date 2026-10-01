extends Control

## In-match pause overlay: frosted-glass backdrop, muffled audio and the resume/loadout/settings/quit actions.
## Online matches keep simulating; only local controls are suspended.

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
const LOADOUT_PAGE_SCENE: PackedScene = preload("res://scenes/ui/loadout/loadout_page.tscn")
const BLUR_SHADER: Shader = preload("res://scenes/menus/pause_blur.gdshader")

var _is_paused: bool = false
var _settings_instance: SettingsMenu = null
var _loadout_instance: LoadoutPage = null
var _blur: ColorRect = null
var _blur_material: ShaderMaterial = null
var _menu_container: Control = null
var _panel: VBoxContainer = null
var _buttons: Array[Button] = []
var _loadout_button: Button = null
var _restart_button: Button = null
var _subtitle: Label = null
var _tween: Tween = null


func _ready() -> void:
	hide()
	add_to_group(&"modal_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	GameJuice.attach_button_feedback(self)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur = ColorRect.new()
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = BLUR_SHADER
	_blur.material = _blur_material
	add_child(_blur)

	_menu_container = Control.new()
	_menu_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_container)

	var stripe: ColorRect = ColorRect.new()
	stripe.color = Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9)
	stripe.position = Vector2(96.0, 150.0)
	stripe.size = Vector2(6.0, 74.0)
	_menu_container.add_child(stripe)

	_panel = VBoxContainer.new()
	_panel.position = Vector2(122.0, 140.0)
	_panel.add_theme_constant_override("separation", 12)
	_menu_container.add_child(_panel)
	var title: Label = Label.new()
	UiStyle.style_label(title, UiStyle.FONT_DISPLAY, 64, UiStyle.TEXT, 10)
	title.text = "PAUSED"
	_panel.add_child(title)
	_subtitle = Label.new()
	UiStyle.style_label(_subtitle, UiStyle.FONT_BOLD, 15, UiStyle.TEXT_DIM)
	_panel.add_child(_subtitle)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 26.0)
	_panel.add_child(spacer)
	_add_button("RESUME", true, resume_game)
	_restart_button = _add_button("RESTART", false, _on_restart_pressed)
	_loadout_button = _add_button("LOADOUT", false, _on_loadout_pressed)
	_add_button("SETTINGS", false, _on_settings_pressed)
	_add_button("MAIN MENU", false, _on_main_menu_pressed)
	_add_button("QUIT GAME", false, _on_exit_pressed)


func _add_button(text: String, primary: bool, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(320.0 if primary else 290.0, 56.0 if primary else 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.set_meta("juice_rotation_multiplier", 0.0)
	UiStyle.style_button(button, primary, 22 if primary else 19)
	button.pressed.connect(callback)
	_panel.add_child(button)
	_buttons.append(button)
	return button


func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed: bool = event.is_action_pressed(GameSettings.INPUT_PAUSE) or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE)
	var back_pressed: bool = _is_paused and event.is_action_pressed(&"ui_cancel")
	if pause_pressed or back_pressed:
		if _is_match_over():
			return
		get_viewport().set_input_as_handled()
		if _loadout_instance != null and is_instance_valid(_loadout_instance):
			_close_loadout()
		elif _settings_instance != null and is_instance_valid(_settings_instance):
			_on_settings_back()
		elif _is_paused:
			resume_game()
		else:
			pause_game()


func pause_game() -> void:
	_is_paused = true
	_loadout_button.visible = NetworkSession.is_training()
	_restart_button.visible = not NetworkSession.is_steam_match_active()
	_subtitle.text = _mode_label()
	show()
	_menu_container.show()
	AudioDirector.play(&"ui_open")
	AudioDirector.set_muffled(true)
	if not NetworkSession.is_steam_match_active():
		get_tree().paused = true
	else:
		_set_local_controls_enabled(false)
	_animate_in()
	_buttons[0].grab_focus.call_deferred()


func resume_game() -> void:
	_is_paused = false
	_close_loadout()
	_close_settings()
	AudioDirector.play(&"ui_close")
	AudioDirector.set_muffled(false)
	if not NetworkSession.is_steam_match_active():
		get_tree().paused = false
	else:
		_set_local_controls_enabled(true)
	_animate_out()


func _animate_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_blur_material.set_shader_parameter(&"amount", 0.0)
	_panel.modulate.a = 0.0
	_panel.position.x = 92.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(value: float) -> void: _blur_material.set_shader_parameter(&"amount", value), 0.0, 1.0, 0.22)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tween.tween_property(_panel, "position:x", 122.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_out() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(value: float) -> void: _blur_material.set_shader_parameter(&"amount", value), 1.0, 0.0, 0.15)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.12)
	_tween.chain().tween_callback(hide)


func _mode_label() -> String:
	if NetworkSession.is_steam_match_active():
		return "ONLINE MATCH  ·  THE MATCH CONTINUES WHILE PAUSED"
	if NetworkSession.is_bot_duel():
		return "VERSUS BOT  ·  %s" % UiStyle.difficulty_name(UserSettings.get_int(UserSettings.BOT_DIFFICULTY))
	if NetworkSession.is_training():
		return "SANDBOX  ·  TRY EVERY EXTENSION IN THE LOADOUT"
	return "LOCAL MATCH"


func _is_match_over() -> bool:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	return world != null and world.has_method(&"is_match_over") and world.is_match_over()


func _on_settings_pressed() -> void:
	_menu_container.hide()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance == null:
		_menu_container.show()
		return
	add_child(_settings_instance)
	_settings_instance.back_pressed.connect(_on_settings_back)


func _on_settings_back() -> void:
	_close_settings()
	AudioDirector.play(&"ui_back")
	_menu_container.show()
	_buttons[3].grab_focus()


func _on_loadout_pressed() -> void:
	if _loadout_instance != null and is_instance_valid(_loadout_instance):
		return
	_menu_container.hide()
	_loadout_instance = LOADOUT_PAGE_SCENE.instantiate() as LoadoutPage
	if _loadout_instance == null:
		_menu_container.show()
		return
	_loadout_instance.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_loadout_instance)
	AudioDirector.play(&"ui_open")


func _close_loadout() -> void:
	if _loadout_instance != null and is_instance_valid(_loadout_instance):
		_loadout_instance.queue_free()
		_loadout_instance = null
	_menu_container.show()


func _close_settings() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null


## Offline only: start the same mode again without a trip through the main menu.
func _on_restart_pressed() -> void:
	if Main.instance == null:
		return
	AudioDirector.set_muffled(false)
	Main.instance.transition_to(func() -> void:
		get_tree().paused = false
		if NetworkSession.is_training():
			NetworkSession.start_training()
		elif NetworkSession.is_bot_duel():
			NetworkSession.start_bot_duel()
		else:
			NetworkSession.start_offline()
		Main.instance.start_game()
	)


func _on_main_menu_pressed() -> void:
	AudioDirector.set_muffled(false)
	if Main.instance == null:
		return
	Main.instance.transition_to(func() -> void:
		get_tree().paused = false
		NetworkSession.leave_round()
		Main.instance.show_menu()
	)


func _on_exit_pressed() -> void:
	get_tree().paused = false
	if Main.instance != null:
		Main.instance.transition_to(func() -> void: get_tree().quit())
	else:
		get_tree().quit()


func _set_local_controls_enabled(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.LOCAL_PLAYERS_GROUP):
		var player: Player = node as Player
		if player != null:
			player.set_controls_enabled(enabled)
