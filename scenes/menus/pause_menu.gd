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
var _world_row: HBoxContainer = null
var _settings_button: Button = null
var _world_buttons: Dictionary = {}
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

	_panel = VBoxContainer.new()
	_panel.position = Vector2(96.0, 108.0)
	_panel.add_theme_constant_override("separation", 12)
	_menu_container.add_child(_panel)
	var title: Label = Label.new()
	UiStyle.style_label(title, UiStyle.FONT_DISPLAY, 64, UiStyle.TEXT)
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
	_build_world_row()
	_settings_button = _add_button("SETTINGS", false, _on_settings_pressed)
	_add_button("MAIN MENU", false, _on_main_menu_pressed)
	_add_button("QUIT GAME", false, _on_exit_pressed)


## Same list look as the main menu: plain entries, the accent highlight follows focus (and the mouse).
func _add_button(text: String, _primary: bool, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(300.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.set_meta("juice_rotation_multiplier", 0.0)
	UiStyle.style_button(button, false, 20)
	var lit: StyleBoxFlat = UiStyle.with_margins(UiStyle.panel(UiStyle.ACCENT), 26, 10)
	button.add_theme_stylebox_override("normal", UiStyle.with_margins(UiStyle.panel(Color(0, 0, 0, 0)), 26, 10))
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("focus", lit)
	button.add_theme_stylebox_override("pressed", UiStyle.with_margins(UiStyle.panel(UiStyle.ACCENT_DEEP), 26, 10))
	for color_name in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, UiStyle.INK)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.grab_focus())
	button.pressed.connect(callback)
	_panel.add_child(button)
	_buttons.append(button)
	return button


## Sandbox only: pick the world. The other world loads behind the usual cover transition and the loadout
## carries over.
func _build_world_row() -> void:
	_world_row = HBoxContainer.new()
	_world_row.add_theme_constant_override("separation", 8)
	var caption: Label = Label.new()
	UiStyle.style_label(caption, UiStyle.FONT_BOLD, 14, UiStyle.TEXT_DIM)
	caption.text = "WORLD"
	caption.custom_minimum_size = Vector2(70.0, 0.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_world_row.add_child(caption)
	for world_id in WorldCatalog.ids():
		var button: Button = Button.new()
		button.text = WorldCatalog.display_name(world_id).to_upper()
		button.custom_minimum_size = Vector2(110.0, 44.0)
		button.set_meta("juice_rotation_multiplier", 0.0)
		button.pressed.connect(_on_world_pressed.bind(world_id))
		_world_row.add_child(button)
		_world_buttons[world_id] = button
		_buttons.append(button)
	_panel.add_child(_world_row)


func _refresh_world_row() -> void:
	var current: StringName = WorldCatalog.sandbox_world_id()
	for world_id in _world_buttons.keys():
		var button: Button = _world_buttons[world_id]
		UiStyle.style_button(button, false, 16)
		if world_id == current:
			# The world you are on reads as selected (light fill), not as a second call to action.
			var selected: StyleBoxFlat = UiStyle.with_margins(UiStyle.panel(UiStyle.TEXT), 26, 10)
			for state in ["normal", "hover", "focus", "pressed"]:
				button.add_theme_stylebox_override(state, selected)
			for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
				button.add_theme_color_override(color_name, UiStyle.INK)


func _on_world_pressed(world_id: StringName) -> void:
	if world_id == WorldCatalog.sandbox_world_id() or Main.instance == null:
		return
	UserSettings.set_value(UserSettings.SANDBOX_WORLD, str(world_id))
	_refresh_world_row()
	AudioDirector.set_muffled(false)
	Main.instance.transition_to(func() -> void:
		get_tree().paused = false
		Main.instance.start_game()
	)


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
	_world_row.visible = NetworkSession.is_training()
	_refresh_world_row()
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
		var shop_note: String = "  ·  PHASE SHOP" if NetworkSession.is_bot_shop_duel() else ""
		return "VERSUS BOT  ·  %s%s" % [UiStyle.difficulty_name(UserSettings.get_int(UserSettings.BOT_DIFFICULTY)), shop_note]
	if NetworkSession.is_training():
		return "SANDBOX  ·  %s" % WorldCatalog.display_name(WorldCatalog.sandbox_world_id()).to_upper()
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
	_settings_button.grab_focus()


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
		if NetworkSession.is_bot_duel():
			Main.instance.start_bot_match()
			return
		if NetworkSession.is_training():
			NetworkSession.start_training()
		else:
			NetworkSession.start_offline()
		Main.instance.start_game()
	)


func _on_main_menu_pressed() -> void:
	AudioDirector.set_muffled(false)
	if Main.instance == null:
		return
	Main.instance.leave_to_menu()


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
