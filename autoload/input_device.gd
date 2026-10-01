extends Node

## Tracks whether the player is currently on mouse & keyboard or a gamepad, and provides right-stick
## aiming. Switching is automatic: any meaningful input from a device makes it the active one.

signal device_changed(using_gamepad: bool)

const STICK_DEADZONE: float = 0.28
const TRIGGER_DEADZONE: float = 0.35
const AIM_SMOOTHING: float = 22.0

var using_gamepad: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

var _raw_aim: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	if not using_gamepad:
		return
	var stick: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < STICK_DEADZONE:
		return
	_raw_aim = stick.normalized()
	var weight: float = 1.0 - exp(-AIM_SMOOTHING * delta / maxf(Engine.time_scale, 0.05))
	aim_direction = aim_direction.slerp(_raw_aim, weight).normalized()


## Short label for an action's binding on the active device, used in on-screen prompts.
func prompt(action: StringName) -> String:
	var gamepad: Dictionary = {
		&"p1_shoot": "RT", &"p1_block": "LT", &"p1_jump": "A", &"p1_reload": "X", &"ui_cancel": "START",
	}
	var keyboard: Dictionary = {
		&"p1_shoot": "LMB", &"p1_block": "RMB", &"p1_jump": "SPACE", &"p1_reload": "R", &"ui_cancel": "ESC",
	}
	var table: Dictionary = gamepad if using_gamepad else keyboard
	return str(table.get(action, ""))


func _set_gamepad(value: bool) -> void:
	if using_gamepad == value:
		return
	using_gamepad = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	device_changed.emit(value)
