extends Control

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
const LOADOUT_PAGE_SCENE: PackedScene = preload("res://scenes/ui/loadout/loadout_page.tscn")

@onready var _menu_container: Control = %MenuRoot
@onready var _resume_button: Button = %ResumeButton
@onready var _loadout_button: Button = %LoadoutButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _exit_button: Button = %ExitButton

var _is_paused: bool = false
var _settings_instance: SettingsMenu = null
var _loadout_instance: LoadoutPage = null


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resume_button.pressed.connect(resume_game)
	_loadout_button.pressed.connect(_on_loadout_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)

	GameJuice.attach_button_feedback(self)
	_refresh_training_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if _loadout_instance != null and is_instance_valid(_loadout_instance):
			_close_loadout()
		elif _settings_instance != null and is_instance_valid(_settings_instance):
			_on_settings_back()
		else:
			if _is_paused:
				resume_game()
			else:
				pause_game()


func pause_game() -> void:
	_is_paused = true
	_refresh_training_ui()
	show()

	if not NetworkSession.is_steam_match_active():
		get_tree().paused = true
	else:
		_set_local_controls_enabled(false)


func resume_game() -> void:
	_is_paused = false
	hide()

	_close_loadout()
	_close_settings()

	if not NetworkSession.is_steam_match_active():
		get_tree().paused = false
	else:
		_set_local_controls_enabled(true)


func _on_settings_pressed() -> void:
	_menu_container.hide()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance == null:
		_menu_container.show()
		return
	add_child(_settings_instance)
	_settings_instance.back_pressed.connect(_on_settings_back)


func _on_settings_back() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null
	_menu_container.show()


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


func _close_loadout() -> void:
	if _loadout_instance != null and is_instance_valid(_loadout_instance):
		_loadout_instance.queue_free()
		_loadout_instance = null
	_menu_container.show()


func _close_settings() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	NetworkSession.leave_round()

	var main_node: Variant = get_node_or_null("/root/Main")
	if main_node != null:
		main_node.show_menu()

	hide()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _refresh_training_ui() -> void:
	var is_training: bool = NetworkSession.is_training()
	_loadout_button.visible = is_training


func _set_local_controls_enabled(enabled: bool) -> void:
	var local_players: Array[Node] = get_tree().get_nodes_in_group(GameSettings.LOCAL_PLAYERS_GROUP)
	for node in local_players:
		var player: Player = node as Player
		if player != null:
			player.set_controls_enabled(enabled)
