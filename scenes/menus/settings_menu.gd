extends Control

signal back_pressed

@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _ui_slider: HSlider = %UiSlider
@onready var _shake_slider: HSlider = %ShakeSlider
@onready var _particles_button: OptionButton = %ParticlesButton
@onready var _window_mode_button: OptionButton = %WindowModeButton
@onready var _resolution_button: OptionButton = %ResolutionButton
@onready var _vsync_checkbox: CheckBox = %VsyncCheckbox
@onready var _fps_button: OptionButton = %FpsButton
@onready var _back_button: Button = %BackButton

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144]

const PARTICLE_MODIFIERS: Array[float] = [0.0, 0.33, 0.66, 1.0]


func _ready() -> void:
	# 1. Volumes Setup
	_init_volume_slider("Master", _volume_slider)
	_init_volume_slider("SFX", _sfx_slider)
	_init_volume_slider("UI", _ui_slider)

	# 2. Screen Shake Multiplier
	_shake_slider.value = GameJuice.shake_multiplier

	# 3. Particle Details Button Setup
	_particles_button.clear()
	_particles_button.add_item("Aus", 0)
	_particles_button.add_item("Niedrig", 1)
	_particles_button.add_item("Mittel", 2)
	_particles_button.add_item("Hoch", 3)

	var current_particles: float = GameJuice.particles_multiplier
	var part_idx: int = PARTICLE_MODIFIERS.find(current_particles)
	if part_idx != -1:
		_particles_button.select(part_idx)
	else:
		_particles_button.select(3)

	# 4. Window Mode OptionButton Setup
	_window_mode_button.clear()
	_window_mode_button.add_item("Fenster", 0)
	_window_mode_button.add_item("Vollbild", 1)
	_window_mode_button.add_item("Randloses Vollbild", 2)

	var current_mode: int = DisplayServer.window_get_mode()
	match current_mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			_window_mode_button.select(0)
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			_window_mode_button.select(1)
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			_window_mode_button.select(2)
		_:
			_window_mode_button.select(0)

	# 5. Resolution OptionButton Setup
	_resolution_button.clear()
	var current_size: Vector2i = DisplayServer.window_get_size()
	var found_resolution_idx: int = -1
	for idx in range(RESOLUTIONS.size()):
		var res: Vector2i = RESOLUTIONS[idx]
		_resolution_button.add_item("%dx%d" % [res.x, res.y], idx)
		if res.x == current_size.x and res.y == current_size.y:
			found_resolution_idx = idx

	if found_resolution_idx != -1:
		_resolution_button.select(found_resolution_idx)
	else:
		_resolution_button.add_item("%dx%d (Custom)" % [current_size.x, current_size.y], RESOLUTIONS.size())
		_resolution_button.select(RESOLUTIONS.size())

	# 6. VSync
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()
	_vsync_checkbox.button_pressed = (vsync_mode != DisplayServer.VSYNC_DISABLED)

	# 7. FPS Limit
	_fps_button.clear()
	_fps_button.add_item("Unbegrenzt", 0)
	_fps_button.add_item("30 FPS", 1)
	_fps_button.add_item("60 FPS", 2)
	_fps_button.add_item("120 FPS", 3)
	_fps_button.add_item("144 FPS", 4)

	var current_fps_limit: int = Engine.max_fps
	var fps_idx: int = FPS_LIMITS.find(current_fps_limit)
	if fps_idx != -1:
		_fps_button.select(fps_idx)
	else:
		_fps_button.select(0)

	# Connect signals
	_volume_slider.value_changed.connect(_on_volume_changed.bind("Master"))
	_sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX"))
	_ui_slider.value_changed.connect(_on_volume_changed.bind("UI"))
	_shake_slider.value_changed.connect(_on_shake_changed)
	_particles_button.item_selected.connect(_on_particles_selected)
	_window_mode_button.item_selected.connect(_on_window_mode_selected)
	_resolution_button.item_selected.connect(_on_resolution_selected)
	_vsync_checkbox.toggled.connect(_on_vsync_toggled)
	_fps_button.item_selected.connect(_on_fps_selected)
	_back_button.pressed.connect(_on_back_pressed)

	GameJuice.attach_button_feedback(self)


func _init_volume_slider(bus_name: StringName, slider: HSlider) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	else:
		slider.value = 0.75


func _on_volume_changed(value: float, bus_name: StringName) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
		AudioServer.set_bus_mute(bus_index, value <= 0.0)


func _on_shake_changed(value: float) -> void:
	GameJuice.shake_multiplier = value


func _on_particles_selected(index: int) -> void:
	if index >= 0 and index < PARTICLE_MODIFIERS.size():
		GameJuice.particles_multiplier = PARTICLE_MODIFIERS[index]


func _on_window_mode_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < RESOLUTIONS.size():
		var res: Vector2i = RESOLUTIONS[index]
		DisplayServer.window_set_size(res)
		
		var screen: int = DisplayServer.window_get_current_screen()
		var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
		var window_size: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2)


func _on_vsync_toggled(button_pressed: bool) -> void:
	var mode: int = DisplayServer.VSYNC_ENABLED if button_pressed else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


func _on_fps_selected(index: int) -> void:
	if index >= 0 and index < FPS_LIMITS.size():
		Engine.max_fps = FPS_LIMITS[index]


func _on_back_pressed() -> void:
	back_pressed.emit()
