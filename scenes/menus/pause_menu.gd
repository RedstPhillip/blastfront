extends Control

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/menus/SettingsMenu.tscn")

@onready var _menu_container: Control = %MenuRoot
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _exit_button: Button = %ExitButton

var _is_paused: bool = false
var _settings_instance: Node = null


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resume_button.pressed.connect(resume_game)
	_settings_button.pressed.connect(_on_settings_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)

	GameJuice.attach_button_feedback(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if _settings_instance != null and is_instance_valid(_settings_instance):
			_on_settings_back()
		else:
			if _is_paused:
				resume_game()
			else:
				pause_game()


func pause_game() -> void:
	_is_paused = true
	show()

	# Pause the physics and processes if offline
	if not NetworkSession.is_steam_match_active():
		get_tree().paused = true
	else:
		# Disable local player inputs so they don't move/shoot when menu is open
		_set_local_controls_enabled(false)


func resume_game() -> void:
	_is_paused = false
	hide()

	# Close settings if it was left open
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null
		_menu_container.show()

	# Unpause the physics/process if offline
	if not NetworkSession.is_steam_match_active():
		get_tree().paused = false
	else:
		# Re-enable local player inputs
		_set_local_controls_enabled(true)


func _on_settings_pressed() -> void:
	_menu_container.hide()
	var inst: Node = SETTINGS_MENU_SCENE.instantiate()
	_settings_instance = inst
	add_child(inst)
	inst.connect("back_pressed", Callable(self, "_on_settings_back"))


func _on_settings_back() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null
	_menu_container.show()


func _on_main_menu_pressed() -> void:
	# Make sure the tree is not paused when moving back to main menu
	get_tree().paused = false

	# Clean up network session
	NetworkSession.leave_round()

	# Transition back
	var main_node: Node = get_node_or_null("/root/Main")
	if main_node != null and main_node.has_method("show_menu"):
		main_node.call("show_menu")

	hide()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _set_local_controls_enabled(enabled: bool) -> void:
	var local_players: Array[Node] = get_tree().get_nodes_in_group(GameSettings.LOCAL_PLAYERS_GROUP)
	for node in local_players:
		var player: Player = node as Player
		if player != null:
			player.set_controls_enabled(enabled)
