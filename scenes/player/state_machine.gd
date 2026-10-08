extends Node
class_name StateMachine

## Runs the active movement State of a player and switches between them. States get the delta of the
## player's own clock (Time Control slows it).

@export var initial_state: State
var current_state: State
var states: Dictionary = {}

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	for child in get_children():
		var state: State = child as State
		if state == null:
			continue
		states[state.name] = state
		state.player = get_parent() as Player
		state.state_machine = self

	if initial_state != null:
		change_state(initial_state.name)


func change_state(new_state: String) -> void:
	if current_state:
		current_state.exit()

	current_state = states.get(new_state) as State
	if current_state != null:
		current_state.enter()


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta * _time_scale())


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta * _time_scale())


func _time_scale() -> float:
	return _player.time_scale if _player != null else 1.0


func _input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)
