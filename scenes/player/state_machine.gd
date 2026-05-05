extends Node
class_name StateMachine


@export var initial_state: State
var current_state: State
var states: Dictionary = {}


func _ready():
	for child in get_children():
		states[child.name] = child;
		child.player = self.get_parent();
		child.state_machine = self;
	
	change_state(initial_state.name);
	
func change_state(new_state: String):
	if current_state:
		current_state.exit();
		
	current_state = states.get(new_state);
	current_state.enter();
	
func _physics_process(delta: float):
	if current_state:
		current_state.physics_update(delta);
		
func _process(delta: float):
	if current_state:
		current_state.update(delta);
		
func _input(event: InputEvent):
	if current_state:
		current_state.handle_input(event);
