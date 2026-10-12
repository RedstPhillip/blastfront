extends Node

## Tracks whether the player is currently on mouse & keyboard or a gamepad, provides right-stick aiming,
## and is the single owner of the mouse cursor state:
##   - aiming in play with the mouse: cursor hidden and confined to the window (a reticle is drawn instead)
##   - gamepad active: cursor hidden
##   - everything else (menus, pause, shop, unfocused window): normal visible, free cursor
## Gameplay reticles report themselves through `set_reticle_active`; nothing else touches mouse_mode.

signal device_changed(using_gamepad: bool)
signal bindings_changed

const STICK_DEADZONE: float = 0.28
const TRIGGER_DEADZONE: float = 0.35
const AIM_SMOOTHING: float = 22.0

## --- Rebinding -------------------------------------------------------------------------------------------------
## InputDevice owns the InputMap: it snapshots the project's defaults before touching them, keeps the
## player's overrides under UserSettings.INPUT_BINDINGS, and formats the short labels the HUD prompts
## and the CONTROLS tab read. A row with no `actions` is not an InputMap action (the mouse aim and the
## stick aim have nothing to rebind) and shows fixed text instead.

const KEYBOARD: StringName = &"keyboard"
const GAMEPAD: StringName = &"gamepad"

const CONTROL_ROWS: Array[Dictionary] = [
	{"label": "Move", "actions": [&"p1_move_left", &"p1_move_right"]},
	{"label": "Jump  ·  Wall jump", "actions": [&"p1_jump"]},
	{"label": "Aim", "actions": [], "keyboard": "MOUSE", "gamepad": "R STICK"},
	{"label": "Shoot", "actions": [&"p1_shoot"]},
	{"label": "Block", "actions": [&"p1_block"]},
	{"label": "Reload", "actions": [&"p1_reload"]},
	{"label": "Time Control", "actions": [&"p1_time_control"]},
	{"label": "Dash", "actions": [&"p1_dash"]},
	{"label": "Slide", "actions": [&"p1_move_down"]},
	{"label": "Orders", "actions": [&"orders_toggle"]},
	{"label": "Pause", "actions": [&"pause"]},
]

var using_gamepad: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

var _raw_aim: Vector2 = Vector2.ZERO
var _reticle_owners: Dictionary = {}
var _window_focused: bool = true
var _default_events: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_defaults()
	_adopt(UserSettings.get_value(UserSettings.INPUT_BINDINGS))
	UserSettings.setting_changed.connect(_on_setting_changed)
	_apply_all()


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
## Reads the live InputMap, so a rebound key shows up in the HUD without anything else changing.
func prompt(action: StringName) -> String:
	var kind: StringName = GAMEPAD if using_gamepad else KEYBOARD
	var event: InputEvent = binding_for(action, kind)
	if event == null:
		# Nothing on the active device (ui_cancel has no stick binding on some setups): take the other
		# kind rather than printing an empty chip.
		event = binding_for(action, KEYBOARD if kind == GAMEPAD else GAMEPAD)
	return describe_event(event)


## `prompt` for a chosen device, so a caller (and the tests) can read a column without switching the
## active device first.
func prompt_for(action: StringName, kind: StringName) -> String:
	return describe_event(binding_for(action, kind))


## The event an action is bound to for one device kind, or null. An override replaces every event of
## that kind, so there is one slot per action per device.
func binding_for(action: StringName, kind: StringName) -> InputEvent:
	for event in events_for(action):
		if event_kind(event) == kind:
			return event
	return null


## Every event currently on an action, overrides applied.
func events_for(action: StringName) -> Array:
	if _overrides.has(action):
		var decoded: Array = []
		for encoded in (_overrides[action] as Array):
			var event: InputEvent = decode_event(encoded as Dictionary)
			if event != null:
				decoded.append(event)
		return decoded
	var stored: Array = _default_events.get(action, [])
	return stored.duplicate()


## Binds `event` to `action`, replacing that action's bindings of the event's own device kind. The
## opposite kind is left alone, so rebinding the keyboard never costs you the pad button.
func rebind(action: StringName, event: InputEvent) -> void:
	if event == null or not _default_events.has(action):
		return
	var kind: StringName = event_kind(event)
	var kept: Array = []
	for existing in events_for(action):
		if event_kind(existing) != kind:
			kept.append(encode_event(existing))
	kept.append(encode_event(event))
	_overrides[action] = kept
	_persist()


func is_modified(action: StringName) -> bool:
	return _overrides.has(action)


func reset_action(action: StringName) -> void:
	if not _overrides.has(action):
		return
	_overrides.erase(action)
	_persist()


## True when `event` is already bound to another action, so the settings tab can flag the clash instead
## of silently shadowing it.
func conflicts_with(action: StringName, event: InputEvent) -> bool:
	if event == null:
		return false
	var encoded: Dictionary = encode_event(event)
	for other in _default_events:
		if other == action:
			continue
		for existing in events_for(other):
			if encode_event(existing) == encoded:
				return true
	return false


static func event_kind(event: InputEvent) -> StringName:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return GAMEPAD
	return KEYBOARD


## Short, uppercase label for a binding: "SPACE", "LMB", "RT", "L STICK L".
static func describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return _key_label(code)
	if event is InputEventMouseButton:
		return _mouse_label((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return _pad_button_label((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		return _pad_axis_label(motion.axis, motion.axis_value)
	return "UNBOUND"


## Turns a captured event into something a ConfigFile can store.
static func encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.physical_keycode != 0:
			return {"k": "key", "c": key.physical_keycode, "p": true}
		return {"k": "key", "c": key.keycode, "p": false}
	if event is InputEventMouseButton:
		return {"k": "mouse", "c": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"k": "joy_button", "c": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		return {"k": "joy_axis", "c": motion.axis, "v": 1.0 if motion.axis_value > 0.0 else -1.0}
	return {}


static func decode_event(data: Dictionary) -> InputEvent:
	match str(data.get("k", "")):
		"key":
			var key: InputEventKey = InputEventKey.new()
			if bool(data.get("p", false)):
				key.physical_keycode = int(data.get("c", 0))
			else:
				key.keycode = int(data.get("c", 0))
			return key
		"mouse":
			var mouse: InputEventMouseButton = InputEventMouseButton.new()
			mouse.button_index = int(data.get("c", MOUSE_BUTTON_LEFT)) as MouseButton
			return mouse
		"joy_button":
			var pad: InputEventJoypadButton = InputEventJoypadButton.new()
			pad.button_index = int(data.get("c", 0)) as JoyButton
			return pad
		"joy_axis":
			var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
			axis.axis = int(data.get("c", 0)) as JoyAxis
			axis.axis_value = float(data.get("v", 1.0))
			return axis
	return null


static func _key_label(code: int) -> String:
	var name: String = OS.get_keycode_string(code as Key).to_upper()
	if name.is_empty():
		return "KEY %d" % code
	# The chip column is narrow; the words every layout already uses are the short ones.
	return "ESC" if name == "ESCAPE" else name


static func _mouse_label(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		MOUSE_BUTTON_WHEEL_UP:
			return "WHEEL UP"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "WHEEL DOWN"
	return "MOUSE %d" % button


static func _pad_button_label(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "BACK"
		JOY_BUTTON_START:
			return "START"
		JOY_BUTTON_GUIDE:
			return "GUIDE"
		JOY_BUTTON_DPAD_UP:
			return "UP"
		JOY_BUTTON_DPAD_DOWN:
			return "DOWN"
		JOY_BUTTON_DPAD_LEFT:
			return "LEFT"
		JOY_BUTTON_DPAD_RIGHT:
			return "RIGHT"
	return "PAD %d" % button


static func _pad_axis_label(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "L STICK R" if value > 0.0 else "L STICK L"
		JOY_AXIS_LEFT_Y:
			return "L STICK D" if value > 0.0 else "L STICK U"
		JOY_AXIS_RIGHT_X:
			return "R STICK R" if value > 0.0 else "R STICK L"
		JOY_AXIS_RIGHT_Y:
			return "R STICK D" if value > 0.0 else "R STICK U"
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
	return "AXIS %d" % axis


func _snapshot_defaults() -> void:
	for row in CONTROL_ROWS:
		for action in (row["actions"] as Array):
			_default_events[action] = InputMap.action_get_events(action).duplicate()


func _adopt(value: Variant) -> void:
	_overrides = {}
	if not (value is Dictionary):
		return
	for action in (value as Dictionary):
		var encoded: Array = (value as Dictionary)[action] as Array
		# Anything the project no longer declares is dropped rather than applied blindly.
		if _default_events.has(action) and not encoded.is_empty():
			_overrides[action] = encoded.duplicate()


func _persist() -> void:
	# The settings_changed round trip is what actually rewrites the InputMap and tells the UI.
	UserSettings.set_value(UserSettings.INPUT_BINDINGS, _overrides.duplicate(true))


func _on_setting_changed(key: StringName, value: Variant) -> void:
	# RESET DEFAULTS clears the key; re-read it so the InputMap goes back to the project's own bindings.
	if key == UserSettings.INPUT_BINDINGS:
		_adopt(value)
		_apply_all()
		bindings_changed.emit()


func _apply_all() -> void:
	for action in _default_events:
		var events: Array = events_for(action)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


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
