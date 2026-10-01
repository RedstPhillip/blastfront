extends Node

## Persistent player preferences stored in user://settings.cfg.
## Owns applying audio, display and gameplay options so menus only edit values.

signal setting_changed(key: StringName, value: Variant)

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"

const MASTER_VOLUME: StringName = &"audio_master"
const MUSIC_VOLUME: StringName = &"audio_music"
const SFX_VOLUME: StringName = &"audio_sfx"
const UI_VOLUME: StringName = &"audio_ui"
const WINDOW_MODE: StringName = &"video_window_mode"
const RESOLUTION: StringName = &"video_resolution"
const VSYNC: StringName = &"video_vsync"
const FPS_LIMIT: StringName = &"video_fps_limit"
const POST_PROCESSING: StringName = &"video_post_processing"
const SCREEN_FLASH: StringName = &"video_screen_flash"
const SCREEN_SHAKE: StringName = &"gameplay_screen_shake"
const PARTICLES: StringName = &"gameplay_particles"
const DAMAGE_NUMBERS: StringName = &"gameplay_damage_numbers"
const HITSTOP: StringName = &"gameplay_hitstop"
const BOT_DIFFICULTY: StringName = &"gameplay_bot_difficulty"
const BOT_PHASE_SHOP: StringName = &"gameplay_bot_phase_shop"
const CONTROLS_HINTS_SEEN: StringName = &"progress_controls_hints_seen"
const MENU_LAST_CHOICE: StringName = &"progress_menu_last_choice"
const LOCKER_HELP_SEEN: StringName = &"progress_locker_help_seen"
const REVISION: StringName = &"settings_revision"
## Revision 2 made exclusive fullscreen the default (direct flip, steadier frame pacing on Windows).
const CURRENT_REVISION: int = 2

const WINDOW_MODE_WINDOWED: int = 0
const WINDOW_MODE_FULLSCREEN: int = 1
const WINDOW_MODE_EXCLUSIVE: int = 2

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 165, 240]

var _values: Dictionary = {}
var _loaded_keys: Dictionary = {}
var _save_queued: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = _defaults()
	_load()
	apply_all.call_deferred()


func get_value(key: StringName) -> Variant:
	return _values.get(key, _defaults().get(key))


func get_float(key: StringName) -> float:
	return float(get_value(key))


func get_bool(key: StringName) -> bool:
	return bool(get_value(key))


func get_int(key: StringName) -> int:
	return int(get_value(key))


func set_value(key: StringName, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_loaded_keys[key] = true
	_apply(key)
	setting_changed.emit(key, value)
	_queue_save()


func reset_to_defaults() -> void:
	var kept: Dictionary = {}
	for key in [CONTROLS_HINTS_SEEN, MENU_LAST_CHOICE, LOCKER_HELP_SEEN]:
		kept[key] = get_value(key)
	_values = _defaults()
	_values.merge(kept, true)
	_loaded_keys.clear()
	apply_all()
	for key in _values.keys():
		setting_changed.emit(key, _values[key])
	_queue_save()


func apply_all() -> void:
	for key in _values.keys():
		_apply(key)


func save() -> void:
	_save_queued = false
	var config: ConfigFile = ConfigFile.new()
	for key in _values.keys():
		config.set_value(SECTION, str(key), _values[key])
	config.save(SETTINGS_PATH)


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	save.call_deferred()


func _load() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var defaults: Dictionary = _defaults()
	for key in defaults.keys():
		if not config.has_section_key(SECTION, str(key)):
			continue
		var stored: Variant = config.get_value(SECTION, str(key))
		if typeof(stored) == typeof(defaults[key]) or (stored is int and defaults[key] is float):
			_values[key] = stored
			_loaded_keys[key] = true
	_migrate(int(config.get_value(SECTION, str(REVISION), 1)))


func _migrate(stored_revision: int) -> void:
	if stored_revision >= CURRENT_REVISION:
		return
	if stored_revision < 2 and get_int(WINDOW_MODE) == WINDOW_MODE_FULLSCREEN:
		_values[WINDOW_MODE] = WINDOW_MODE_EXCLUSIVE
	_values[REVISION] = CURRENT_REVISION
	_queue_save()


func _defaults() -> Dictionary:
	return {
		MASTER_VOLUME: 0.85,
		MUSIC_VOLUME: 0.6,
		SFX_VOLUME: 0.85,
		UI_VOLUME: 0.7,
		WINDOW_MODE: WINDOW_MODE_EXCLUSIVE,
		RESOLUTION: Vector2i(1600, 900),
		VSYNC: true,
		FPS_LIMIT: 0,
		POST_PROCESSING: 1.0,
		SCREEN_FLASH: 1.0,
		SCREEN_SHAKE: 1.0,
		PARTICLES: 1.0,
		DAMAGE_NUMBERS: true,
		HITSTOP: true,
		BOT_DIFFICULTY: 1,
		BOT_PHASE_SHOP: false,
		CONTROLS_HINTS_SEEN: 0,
		MENU_LAST_CHOICE: 0,
		LOCKER_HELP_SEEN: 0,
		REVISION: CURRENT_REVISION,
	}


func _apply(key: StringName) -> void:
	match key:
		MASTER_VOLUME:
			_apply_bus_volume(&"Master", get_float(key))
		MUSIC_VOLUME:
			_apply_bus_volume(&"Music", get_float(key))
		SFX_VOLUME:
			_apply_bus_volume(&"SFX", get_float(key))
			_apply_bus_volume(&"Ambience", get_float(key))
		UI_VOLUME:
			_apply_bus_volume(&"UI", get_float(key))
		WINDOW_MODE, RESOLUTION:
			_apply_window()
		VSYNC:
			if not _is_headless():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_bool(key) else DisplayServer.VSYNC_DISABLED)
		FPS_LIMIT:
			Engine.max_fps = get_int(key)
		SCREEN_SHAKE:
			GameJuice.shake_multiplier = get_float(key)
		PARTICLES:
			GameJuice.particles_multiplier = get_float(key)


func _apply_bus_volume(bus_name: StringName, linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(clamped, 0.0001)))
	AudioServer.set_bus_mute(bus_index, clamped <= 0.001)


func _apply_window() -> void:
	if _is_headless() or _is_embedded_or_overridden():
		return
	# Editor runs keep the project window unless the player explicitly chose a mode.
	if OS.has_feature("editor") and not _loaded_keys.has(WINDOW_MODE):
		return
	match get_int(WINDOW_MODE):
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WINDOW_MODE_EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var target_size: Vector2i = get_value(RESOLUTION)
			var screen: int = DisplayServer.window_get_current_screen()
			var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
			target_size = Vector2i(mini(target_size.x, usable.size.x), mini(target_size.y, usable.size.y))
			DisplayServer.window_set_size(target_size)
			DisplayServer.window_set_position(usable.position + (usable.size - target_size) / 2)


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _is_embedded_or_overridden() -> bool:
	return ProjectSettings.get_setting("display/window/size/no_focus", false)
