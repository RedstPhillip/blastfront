extends Control
class_name MainMenu

## Title screen: animated parallax backdrop, glowing logo, staggered menu, versus-bot setup panel,
## living hero characters and a footer with version and Steam status.

signal sandbox_requested
signal online_requested
signal bot_requested(difficulty: int)
signal exit_requested

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
const LOGO_SHADER: Shader = preload("res://scenes/menus/logo.gdshader")
const FOG_SHADER: Shader = preload("res://scenes/maps/environment/fog.gdshader")
const NOISE_TEXTURE: Texture2D = preload("res://assets/fx/noise_fbm.png")
const PARALLAX_STRENGTH: Vector2 = Vector2(22.0, 12.0)
const DIFFICULTY_INFO: Array[Dictionary] = [
	{"name": "EASY", "text": "Slow reactions and loose aim. Learn the arena and the arc of your shots."},
	{"name": "NORMAL", "text": "Leads its shots, blocks some of yours and lobs over cover."},
	{"name": "HARD", "text": "Fast, precise and patient. Blocks often and punishes every mistake."},
]

@onready var _background: TextureRect = $Background
@onready var _menu_root: Control = $MenuRoot

var _buttons: Array[Button] = []
var _bot_panel: PanelContainer = null
var _difficulty_buttons: Array[Button] = []
var _difficulty_text: Label = null
var _selected_difficulty: int = 1
var _online_button: Button = null
var _bot_start_button: Button = null
var _bot_caption: Label = null
var _shop_buttons: Array[Button] = []
var _world_buttons: Array[Button] = []
var _shop_text: Label = null
var _steam_label: Label = null
var _steam_dot: ColorRect = null
var _heroes: Array[MenuHero] = []
var _settings_instance: SettingsMenu = null
var _time: float = 0.0
var _hero_fire_timer: float = 5.0
var _logo: Label = null
var _busy: bool = false


func _ready() -> void:
	_selected_difficulty = UserSettings.get_int(UserSettings.BOT_DIFFICULTY)
	_build_atmosphere()
	_build_heroes()
	_build_menu()
	_build_bot_panel()
	_build_footer()
	GameJuice.attach_button_feedback(self)
	SteamService.status_changed.connect(_refresh_steam)
	_refresh_steam("")
	_play_intro()


func _exit_tree() -> void:
	if SteamService.status_changed.is_connected(_refresh_steam):
		SteamService.status_changed.disconnect(_refresh_steam)


func _process(delta: float) -> void:
	_time += delta
	var viewport_size: Vector2 = get_viewport_rect().size
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var offset: Vector2 = ((mouse / viewport_size) - Vector2(0.5, 0.5)) * -PARALLAX_STRENGTH
	var drift: Vector2 = Vector2(sin(_time * 0.11) * 10.0, cos(_time * 0.09) * 5.0)
	_background.position = _background.position.lerp(offset + drift - Vector2(40.0, 24.0), 1.0 - exp(-3.0 * delta))
	_hero_fire_timer -= delta
	if _hero_fire_timer <= 0.0 and not _heroes.is_empty():
		_hero_fire_timer = randf_range(5.0, 9.0)
		_heroes[randi() % _heroes.size()].fire()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _bot_panel.visible:
		get_viewport().set_input_as_handled()
		_close_bot_panel()


## With START MATCH focused, left/right step the difficulty so keyboard and gamepad players never
## have to leave the button they are about to press.
func _input(event: InputEvent) -> void:
	if not _bot_panel.visible or _bot_start_button == null or not _bot_start_button.has_focus():
		return
	var step: int = 0
	if event.is_action_pressed(&"ui_left"):
		step = -1
	elif event.is_action_pressed(&"ui_right"):
		step = 1
	if step == 0:
		return
	get_viewport().set_input_as_handled()
	var next: int = clampi(_selected_difficulty + step, 0, _difficulty_buttons.size() - 1)
	if next != _selected_difficulty:
		_difficulty_buttons[next].button_pressed = true
		AudioDirector.play(&"ui_toggle")


# --- Build -----------------------------------------------------------------------------

func _build_atmosphere() -> void:
	_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_background.size = get_viewport_rect().size + Vector2(80.0, 48.0)
	var fog: ColorRect = ColorRect.new()
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog_material: ShaderMaterial = ShaderMaterial.new()
	fog_material.shader = FOG_SHADER
	fog_material.set_shader_parameter(&"noise_tex", NOISE_TEXTURE)
	fog_material.set_shader_parameter(&"fog_color", Color(0.62, 0.72, 0.62))
	fog_material.set_shader_parameter(&"density", 0.16)
	fog_material.set_shader_parameter(&"speed", 0.02)
	fog_material.set_shader_parameter(&"top_softness", 0.6)
	fog_material.set_shader_parameter(&"bottom_softness", 0.05)
	fog.material = fog_material
	add_child(fog)
	move_child(fog, 1)

	var shade: TextureRect = TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(0.01, 0.03, 0.03, 0.88), Color(0.01, 0.03, 0.03, 0.45), Color(0.01, 0.03, 0.03, 0.05)])
	var gradient_texture: GradientTexture2D = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256
	gradient_texture.height = 4
	shade.texture = gradient_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)
	move_child(shade, 2)

	var vignette: TextureRect = TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_gradient: Gradient = Gradient.new()
	vignette_gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	vignette_gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.15), Color(0, 0.01, 0.01, 0.65)])
	var vignette_texture: GradientTexture2D = GradientTexture2D.new()
	vignette_texture.gradient = vignette_gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.45)
	vignette_texture.fill_to = Vector2(1.1, 1.1)
	vignette.texture = vignette_texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(vignette)
	move_child(vignette, 3)

	var fireflies: Fireflies = Fireflies.new()
	fireflies.area = Rect2(Vector2(0.0, 220.0), get_viewport_rect().size - Vector2(0.0, 240.0))
	fireflies.count = 26
	fireflies.size_range = Vector2(12.0, 26.0)
	add_child(fireflies)
	move_child(fireflies, 4)


func _build_heroes() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var stage: Node2D = Node2D.new()
	stage.name = "HeroStage"
	stage.z_index = 1
	add_child(stage)
	move_child(stage, 5)
	var spotlight: Sprite2D = Sprite2D.new()
	spotlight.texture = FxLib.TEX_GLOW
	spotlight.material = FxLib.additive_material()
	spotlight.modulate = Color(0.85, 1.0, 0.85, 0.16)
	spotlight.scale = Vector2(5.5, 3.0)
	spotlight.position = Vector2(viewport_size.x * 0.795, viewport_size.y * 0.62)
	stage.add_child(spotlight)
	var ground_shadow: Sprite2D = Sprite2D.new()
	ground_shadow.texture = FxLib.TEX_SOFT
	ground_shadow.modulate = Color(0.0, 0.02, 0.02, 0.55)
	ground_shadow.scale = Vector2(7.5, 0.7)
	ground_shadow.position = Vector2(viewport_size.x * 0.795, viewport_size.y * 0.62 + 72.0)
	stage.add_child(ground_shadow)
	var specs: Array[Dictionary] = [
		{"color": &"blue", "facing": 1.0, "x": 0.71, "phase": 0.0},
		{"color": &"red", "facing": -1.0, "x": 0.88, "phase": 1.7},
	]
	for spec in specs:
		var hero: MenuHero = MenuHero.new()
		hero.color_id = spec["color"]
		hero.facing = spec["facing"]
		hero.phase = spec["phase"]
		hero.position = Vector2(viewport_size.x * float(spec["x"]), viewport_size.y * 0.62)
		hero.scale = Vector2.ONE * 0.62
		stage.add_child(hero)
		_heroes.append(hero)


func _build_menu() -> void:
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.position = Vector2(96.0, 92.0)
	column.add_theme_constant_override("separation", 0)
	_menu_root.add_child(column)

	var logo_holder: Control = Control.new()
	logo_holder.custom_minimum_size = Vector2(620.0, 112.0)
	column.add_child(logo_holder)
	var logo_shadow: Label = Label.new()
	UiStyle.style_label(logo_shadow, UiStyle.FONT_DISPLAY, 96, Color(0.01, 0.03, 0.03, 1.0), 18)
	logo_shadow.text = "BLASTFRONT"
	logo_shadow.position = Vector2(4.0, 6.0)
	logo_holder.add_child(logo_shadow)
	_logo = Label.new()
	UiStyle.style_label(_logo, UiStyle.FONT_DISPLAY, 96, Color.WHITE)
	_logo.text = "BLASTFRONT"
	var logo_material: ShaderMaterial = ShaderMaterial.new()
	logo_material.shader = LOGO_SHADER
	logo_material.set_shader_parameter(&"text_top", 20.0)
	logo_material.set_shader_parameter(&"text_bottom", 100.0)
	_logo.material = logo_material
	logo_holder.add_child(_logo)

	var tagline: Label = Label.new()
	UiStyle.style_label(tagline, UiStyle.FONT_BOLD, 17, UiStyle.TEXT_DIM)
	tagline.text = "ARTILLERY  ·  PARKOUR  ·  DUELS"
	column.add_child(tagline)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 46.0)
	column.add_child(spacer)

	var buttons: VBoxContainer = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_add_menu_button(buttons, "VERSUS BOT", true, _open_bot_panel)
	_online_button = _add_menu_button(buttons, "ONLINE DUEL", false, _on_online_pressed)
	_add_menu_button(buttons, "SANDBOX", false, _on_sandbox_pressed)
	_add_menu_button(buttons, "SETTINGS", false, _on_settings_pressed)
	_add_menu_button(buttons, "QUIT", false, _on_exit_pressed)


func _add_menu_button(parent: Container, text: String, primary: bool, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(340.0 if primary else 300.0, 58.0 if primary else 50.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiStyle.style_button(button, primary, 24 if primary else 20)
	button.set_meta("juice_rotation_multiplier", 0.0)
	button.pressed.connect(callback)
	button.mouse_entered.connect(_slide_button.bind(button, true))
	button.focus_entered.connect(_slide_button.bind(button, true))
	button.mouse_exited.connect(_slide_button.bind(button, false))
	button.focus_exited.connect(_slide_button.bind(button, false))
	parent.add_child(button)
	_buttons.append(button)
	return button


## Phase shop on/off for bot duels, styled like the difficulty picker and remembered between sessions.
## Which world the duel is fought on: the green ridge, or Mars with its low gravity and dust storms.
func _build_world_choice(box: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_BOLD, 16, UiStyle.TEXT)
	label.text = "WORLD"
	label.custom_minimum_size = Vector2(130.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var group: ButtonGroup = ButtonGroup.new()
	var current: StringName = WorldCatalog.bot_world_id()
	for world_id in WorldCatalog.ids():
		var option: Button = Button.new()
		option.text = WorldCatalog.display_name(world_id).to_upper()
		option.toggle_mode = true
		option.button_group = group
		option.custom_minimum_size = Vector2(110.0, 42.0)
		UiStyle.style_button(option, false, 17)
		option.add_theme_stylebox_override("pressed", UiStyle.with_margins(UiStyle.panel(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.22), UiStyle.ACCENT, 3, 2, 0.18), 26, 10))
		option.add_theme_color_override("font_pressed_color", UiStyle.ACCENT_HOT)
		option.toggled.connect(_on_world_toggled.bind(world_id))
		option.set_pressed_no_signal(world_id == current)
		row.add_child(option)
		_world_buttons.append(option)


func _on_world_toggled(pressed: bool, world_id: StringName) -> void:
	if pressed:
		UserSettings.set_value(UserSettings.BOT_WORLD, str(world_id))


func _build_shop_toggle(box: VBoxContainer) -> void:
	var divider: ColorRect = ColorRect.new()
	divider.color = UiStyle.LINE
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	box.add_child(divider)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label: Label = Label.new()
	UiStyle.style_label(label, UiStyle.FONT_BOLD, 16, UiStyle.TEXT)
	label.text = "PHASE SHOP"
	label.custom_minimum_size = Vector2(130.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var group: ButtonGroup = ButtonGroup.new()
	for index in range(2):
		var option: Button = Button.new()
		option.text = "OFF" if index == 0 else "ON"
		option.toggle_mode = true
		option.button_group = group
		option.custom_minimum_size = Vector2(110.0, 42.0)
		UiStyle.style_button(option, false, 17)
		option.add_theme_stylebox_override("pressed", UiStyle.with_margins(UiStyle.panel(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.22), UiStyle.ACCENT, 3, 2, 0.18), 26, 10))
		option.add_theme_color_override("font_pressed_color", UiStyle.ACCENT_HOT)
		option.toggled.connect(_on_shop_toggled.bind(index == 1))
		row.add_child(option)
		_shop_buttons.append(option)
	_shop_text = Label.new()
	UiStyle.style_label(_shop_text, UiStyle.FONT_BODY, 14, UiStyle.TEXT_DIM)
	_shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_text.custom_minimum_size = Vector2(370.0, 40.0)
	box.add_child(_shop_text)
	var enabled: bool = UserSettings.get_bool(UserSettings.BOT_PHASE_SHOP)
	_shop_buttons[1 if enabled else 0].set_pressed_no_signal(true)
	_update_shop_text(enabled)


func _on_shop_toggled(pressed: bool, enabled: bool) -> void:
	if not pressed:
		return
	UserSettings.set_value(UserSettings.BOT_PHASE_SHOP, enabled)
	_update_shop_text(enabled)


func _update_shop_text(enabled: bool) -> void:
	if enabled:
		_bot_caption.text = "SETS OF %d KILLS  ·  FIRST TO %d SETS" % [GameSettings.ONLINE_SET_KILLS_TO_WIN, GameSettings.ONLINE_MATCH_SET_WINS_TO_WIN]
		_shop_text.text = "Earn coins each set and shop, equip and research between sets. The bot shops too."
	else:
		_bot_caption.text = "FIRST TO %d ROUNDS  ·  PURE SKILL" % GameSettings.BOT_MATCH_WINS_NEEDED
		_shop_text.text = "No shop: both fighters keep the standard weapon for the whole match."


func _slide_button(button: Button, hovered: bool) -> void:
	var target: float = 26.0 + (16.0 if hovered and not button.disabled else 0.0)
	var tween: Tween = button.create_tween().set_parallel(true)
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style: StyleBox = button.get_theme_stylebox(state)
		if style is StyleBoxFlat:
			tween.tween_property(style, "content_margin_left", target, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_bot_panel() -> void:
	_bot_panel = PanelContainer.new()
	_bot_panel.add_theme_stylebox_override("panel", UiStyle.with_shadow(UiStyle.with_margins(UiStyle.panel(UiStyle.PANEL_SOLID, UiStyle.LINE_STRONG, 8, 1), 28, 22), 24, Vector2(0, 10)))
	_bot_panel.position = Vector2(470.0, 290.0)
	_bot_panel.custom_minimum_size = Vector2(430.0, 0.0)
	_bot_panel.visible = false
	_bot_panel.z_index = 2
	_menu_root.add_child(_bot_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_bot_panel.add_child(box)
	var title: Label = Label.new()
	UiStyle.style_label(title, UiStyle.FONT_DISPLAY, 28, UiStyle.TEXT)
	title.text = "VERSUS BOT"
	box.add_child(title)
	_bot_caption = Label.new()
	UiStyle.style_label(_bot_caption, UiStyle.FONT_BOLD, 13, UiStyle.ACCENT)
	box.add_child(_bot_caption)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var group: ButtonGroup = ButtonGroup.new()
	for index in range(DIFFICULTY_INFO.size()):
		var option: Button = Button.new()
		option.text = str(DIFFICULTY_INFO[index]["name"])
		option.toggle_mode = true
		option.button_group = group
		option.custom_minimum_size = Vector2(118.0, 46.0)
		UiStyle.style_button(option, false, 18)
		option.add_theme_stylebox_override("pressed", UiStyle.with_margins(UiStyle.panel(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.22), UiStyle.ACCENT, 3, 2, 0.18), 26, 10))
		option.add_theme_color_override("font_pressed_color", UiStyle.ACCENT_HOT)
		option.toggled.connect(_on_difficulty_toggled.bind(index))
		row.add_child(option)
		_difficulty_buttons.append(option)
	_difficulty_text = Label.new()
	UiStyle.style_label(_difficulty_text, UiStyle.FONT_BODY, 16, UiStyle.TEXT_DIM)
	_difficulty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_difficulty_text.custom_minimum_size = Vector2(370.0, 48.0)
	box.add_child(_difficulty_text)
	_build_world_choice(box)
	_build_shop_toggle(box)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var start: Button = Button.new()
	start.text = "START MATCH"
	start.custom_minimum_size = Vector2(230.0, 52.0)
	UiStyle.style_button(start, true, 20)
	start.pressed.connect(_on_bot_start_pressed)
	_bot_start_button = start
	actions.add_child(start)
	var back: Button = Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(130.0, 52.0)
	UiStyle.style_button(back, false, 18)
	back.pressed.connect(_close_bot_panel)
	actions.add_child(back)
	_difficulty_buttons[clampi(_selected_difficulty, 0, 2)].button_pressed = true
	_update_difficulty_text()


func _build_footer() -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 96.0
	footer.offset_right = -40.0
	footer.offset_top = -46.0
	footer.offset_bottom = -18.0
	footer.add_theme_constant_override("separation", 10)
	add_child(footer)
	var version: Label = Label.new()
	UiStyle.style_label(version, UiStyle.FONT_UI, 14, UiStyle.TEXT_MUTED)
	version.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	footer.add_child(version)
	var filler: Control = Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(filler)
	_steam_dot = ColorRect.new()
	_steam_dot.custom_minimum_size = Vector2(9.0, 9.0)
	_steam_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_steam_dot)
	_steam_label = Label.new()
	UiStyle.style_label(_steam_label, UiStyle.FONT_BOLD, 14, UiStyle.TEXT_DIM)
	footer.add_child(_steam_label)


# --- Behaviour ---------------------------------------------------------------------------

func _play_intro() -> void:
	_logo.get_parent().modulate.a = 0.0
	var holder: Control = _logo.get_parent() as Control
	holder.pivot_offset = Vector2(0.0, 56.0)
	holder.scale = Vector2(1.25, 1.25)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(holder, "modulate:a", 1.0, 0.35).set_delay(0.1)
	tween.tween_property(holder, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.1)
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		button.modulate.a = 0.0
		var delay: float = 0.35 + index * 0.06
		tween.tween_property(button, "modulate:a", 1.0, 0.25).set_delay(delay)
	for index in range(_heroes.size()):
		var hero: MenuHero = _heroes[index]
		var target_y: float = hero.position.y
		hero.position.y -= 520.0
		tween.tween_property(hero, "position:y", target_y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.45 + index * 0.18)
		tween.tween_callback(_on_hero_landed.bind(hero)).set_delay(0.95 + index * 0.18)
	if not _buttons.is_empty():
		_preferred_button().grab_focus.call_deferred()


## The mode the player picked last time gets focus, so "Enter" repeats the usual choice.
func _preferred_button() -> Button:
	var index: int = clampi(UserSettings.get_int(UserSettings.MENU_LAST_CHOICE), 0, _buttons.size() - 1)
	var button: Button = _buttons[index]
	return _buttons[0] if button.disabled else button


func _remember_choice(index: int) -> void:
	UserSettings.set_value(UserSettings.MENU_LAST_CHOICE, index)


func _on_hero_landed(hero: MenuHero) -> void:
	hero.land()
	GameJuice.spawn_burst(&"land", hero.global_position + Vector2(0.0, 72.0), Vector2.UP, Color.WHITE, 1.6)
	AudioDirector.play(&"land_heavy" if randf() > 0.5 else &"land", -4.0)


func _refresh_steam(_message: String) -> void:
	var enabled: bool = SteamService.steam_enabled
	_online_button.disabled = not enabled
	_online_button.tooltip_text = "" if enabled else "Steam must be running to play online."
	_steam_dot.color = UiStyle.SUCCESS if enabled else UiStyle.TEXT_MUTED
	_steam_label.text = ("STEAM ONLINE  ·  %s" % SteamService.steam_name.to_upper()) if enabled else "STEAM OFFLINE"


func _open_bot_panel() -> void:
	_bot_panel.visible = true
	_bot_panel.modulate.a = 0.0
	_bot_panel.position.x = 440.0
	AudioDirector.play(&"ui_open")
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_bot_panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(_bot_panel, "position:x", 470.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _bot_start_button != null:
		_bot_start_button.grab_focus()


func _close_bot_panel() -> void:
	if not _bot_panel.visible:
		return
	AudioDirector.play(&"ui_close")
	var tween: Tween = create_tween()
	tween.tween_property(_bot_panel, "modulate:a", 0.0, 0.12)
	tween.tween_callback(_bot_panel.hide)
	_buttons[0].grab_focus()


func _on_difficulty_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		return
	_selected_difficulty = index
	_update_difficulty_text()


func _update_difficulty_text() -> void:
	_difficulty_text.text = str(DIFFICULTY_INFO[clampi(_selected_difficulty, 0, 2)]["text"])


func _on_bot_start_pressed() -> void:
	if _busy:
		return
	_busy = true
	_remember_choice(0)
	AudioDirector.play(&"ui_confirm")
	bot_requested.emit(_selected_difficulty)


func _on_sandbox_pressed() -> void:
	if _busy:
		return
	_busy = true
	_remember_choice(2)
	AudioDirector.play(&"ui_confirm")
	sandbox_requested.emit()


func _on_online_pressed() -> void:
	if _busy:
		return
	_busy = true
	_remember_choice(1)
	AudioDirector.play(&"ui_confirm")
	online_requested.emit()


func _on_exit_pressed() -> void:
	if _busy:
		return
	_busy = true
	exit_requested.emit()


func _on_settings_pressed() -> void:
	_close_bot_panel()
	AudioDirector.play(&"ui_open")
	_menu_root.hide()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance == null:
		_menu_root.show()
		return
	_settings_instance.z_index = 3
	add_child(_settings_instance)
	_settings_instance.back_pressed.connect(_on_settings_back)


func _on_settings_back() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
		_settings_instance = null
	AudioDirector.play(&"ui_back")
	_menu_root.show()
	_buttons[3].grab_focus()
