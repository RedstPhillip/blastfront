extends Node

## Tracks whether the player is currently on mouse & keyboard or a gamepad, provides right-stick aiming,
## and is the single owner of the mouse cursor state:
##   - aiming in play with the mouse: cursor hidden and confined to the window (a reticle is drawn instead)
##   - gamepad active: cursor hidden
##   - everything else (menus, pause, shop, unfocused window): normal visible, free cursor
## Gameplay reticles report themselves through `set_reticle_active`; nothing else touches mouse_mode.

signal device_changed(using_gamepad: bool)

const STICK_DEADZONE: float = 0.28
const TRIGGER_DEADZONE: float = 0.35
const AIM_SMOOTHING: float = 22.0

var using_gamepad: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

var _raw_aim: Vector2 = Vector2.ZERO
var _reticle_owners: Dictionary = {}
var _window_focused: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		_apply_cursor()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		_apply_cursor()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_gamepad(true)
	elif event is InputEventJoypadMotion:
		var deadzone: float = TRIGGER_DEADZONE if event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT else STICK_DEADZONE
		if absf(event.axis_value) > deadzone:
			_set_gamepad(true)
	elif event is InputEventMouseMotion:
		if event.relative.length_squared() > 4.0:
			_set_gamepad(false)
	elif event is InputEventMouseButton and event.pressed:
		_set_gamepad(false)
	elif event is InputEventKey and event.pressed:
		_set_gamepad(false)


func _process(delta: float) -> void:
	_prune_reticles()
	_apply_cursor()
	if not using_gamepad:
		return
	var stick: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < STICK_DEADZONE:
		return
	_raw_aim = stick.normalized()
	var weight: float = 1.0 - exp(-AIM_SMOOTHING * delta / maxf(Engine.time_scale, 0.05))
	aim_direction = aim_direction.slerp(_raw_aim, weight).normalized()


## Called every frame by gameplay reticles: while any owner reports active, the OS cursor stays hidden.
func set_reticle_active(owner: Node, active: bool) -> void:
	if active:
		_reticle_owners[owner.get_instance_id()] = owner
	else:
		_reticle_owners.erase(owner.get_instance_id())
	_apply_cursor()


func is_reticle_active() -> bool:
	return not _reticle_owners.is_empty()


## Short label for an action's binding on the active device, used in on-screen prompts.
func prompt(action: StringName) -> String:
	var gamepad: Dictionary = {
		&"p1_shoot": "RT", &"p1_block": "LT", &"p1_jump": "A", &"p1_reload": "X", &"p1_time_control": "Y", &"ui_cancel": "B", &"pause": "START",
	}
	var keyboard: Dictionary = {
		&"p1_shoot": "LMB", &"p1_block": "RMB", &"p1_jump": "SPACE", &"p1_reload": "R", &"p1_time_control": "Q", &"ui_cancel": "ESC", &"pause": "ESC",
	}
	var table: Dictionary = gamepad if using_gamepad else keyboard
	return str(table.get(action, ""))


func _set_gamepad(value: bool) -> void:
	if using_gamepad == value:
		return
	using_gamepad = value
	_apply_cursor()
	device_changed.emit(value)


func _prune_reticles() -> void:
	for id in _reticle_owners.keys():
		var owner: Variant = _reticle_owners[id]
		if not is_instance_valid(owner) or not (owner as Node).is_inside_tree():
			_reticle_owners.erase(id)


func _apply_cursor() -> void:
	var mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
	if _window_focused and is_reticle_active() and not using_gamepad:
		mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	elif _window_focused and using_gamepad:
		mode = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
