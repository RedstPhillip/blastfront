extends Node2D

## The online lobby. Each player stands in their own spotlight inside a wheel of colour discs: shoot a
## colour to wear it, shoot READY when set. Same language as the rest of the game: flat discs with an ink
## rim, amber for "selected / do this now", team colour only for identity, text on soft shadow pools and the
## shared prompt bar along the bottom. While no friend has joined, their half asks for one.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
const BACKDROP_SHADER: Shader = preload("res://scenes/menus/desaturate.gdshader")
const LOCKER_PROJECTILE_COLLISION_MASK: int = 1
const PLAYER_ONE_LOCKER_STATION: Vector2 = Vector2(320.0, 430.0)
const PLAYER_TWO_LOCKER_STATION: Vector2 = Vector2(960.0, 430.0)
const WHEEL_RADIUS: float = 183.0
const WHEEL_CENTER_Y: float = 426.5
const COLOR_RADIUS: float = 22.0
const READY_RADIUS: float = 46.0
## Where the feet are, relative to the player's origin; the ground shadow sits there.
const FEET_OFFSET: float = 34.0
const LEAVE_CONFIRM_MSEC: int = 2600
## Top of the world reveal, relative to the screen centre (just under the countdown number).
const WORLD_REVEAL_TOP: float = 62.0
const HEADER_CAPTION_Y: float = 34.0
const HEADER_NAME_Y: float = 70.0
const HEADER_STATUS_Y: float = 96.0
const NAME_MAX_WIDTH: float = 380.0
const INVITE_BUTTON_SIZE: Vector2 = Vector2(240.0, 52.0)

@onready var _player_one: Player = %PlayerOne
@onready var _player_two: Player = %PlayerTwo
@onready var _player_one_color_targets: Node2D = $LockerWorld/PlayerOneColorTargets
@onready var _player_two_color_targets: Node2D = $LockerWorld/PlayerTwoColorTargets
@onready var _projectiles: Node2D = %Projectiles
@onready var _countdown_label: Label = %CountdownLabel
@onready var _player_one_ready_target: StaticBody2D = %PlayerOneReadyTarget
@onready var _player_two_ready_target: StaticBody2D = %PlayerTwoReadyTarget
@onready var _ui_root: Control = $UILayer/Root

var _local_slot: int = GameSettings.PLAYER_ONE_SLOT
var _remote_slot: int = GameSettings.PLAYER_TWO_SLOT
var _leave_armed_until: int = 0
var _leaving: bool = false
var _local_player: Player = null
var _remote_player: Player = null
var _send_timer: float = 0.0
var _last_locker_countdown_sound_second: int = -1
var _world_reveal: LockerWorldReveal = null
var _overlay: Control = null
var _prompt_bar: UiPromptBar = null
var _invite_button: Button = null
var _stage: Node2D = null
## Target art nodes by their target, and the one the local aim rests on.
var _art: Dictionary = {}
var _hovered: StaticBody2D = null
## Last drawn state per target, so a change of selection can pop the disc.
var _drawn_state: Dictionary = {}


func _ready() -> void:
	_neutralize_backdrop()
	add_to_group(GameSettings.GAME_WORLD_GROUP)
	_local_slot = NetworkSession.local_player_slot
	_remote_slot = NetworkSession.get_remote_slot()
	_configure_players()
	_build_stage()
	_build_target_art()
	_build_overlay()
	_build_invite_button()
	_build_world_reveal()
	_build_prompt_bar()
	UiStyle.style_label(_countdown_label, UiStyle.FONT_DISPLAY, 132, UiStyle.ACCENT, 14)
	var crosshair: HudCrosshair = HudCrosshair.new()
	_ui_root.add_child(crosshair)
	_ui_root.move_child(crosshair, _prompt_bar.get_index())

	OnlineMatch.state_changed.connect(_refresh)
	NetworkSession.status_changed.connect(_refresh)
	NetworkSession.peer_changed.connect(_refresh)
	NetworkSession.packet_received.connect(_on_packet_received)
	InputDevice.device_changed.connect(_on_device_changed)
	_refresh()


## ESC / B / Start leaves the lobby; with a friend connected the first press only arms the exit, so nobody
## drops out by accident.
func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(GameSettings.INPUT_PAUSE)):
		return
	get_viewport().set_input_as_handled()
	if _leaving:
		return
	if _has_opponent() and Time.get_ticks_msec() > _leave_armed_until:
		_leave_armed_until = Time.get_ticks_msec() + LEAVE_CONFIRM_MSEC
		_prompt_bar.notify("PRESS %s AGAIN TO LEAVE" % InputDevice.prompt(&"ui_cancel"), UiStyle.ACCENT)
		AudioDirector.play(&"ui_toggle")
		return
	AudioDirector.play(&"ui_back")
	if Main.instance != null:
		_leaving = true
		Main.instance.leave_to_menu()


func _on_invite_pressed() -> void:
	if not _can_invite():
		return
	NetworkSession.open_invite_overlay()


func _can_invite() -> bool:
	return NetworkSession.mode == GameSettings.NETWORK_MODE_HOST and SteamService.steam_enabled


func _has_opponent() -> bool:
	return NetworkSession.remote_steam_id != 0


func _process(_delta: float) -> void:
	_update_hover()
	# Clicking the invite button must not also pull the trigger (no flash, no casing, no shot).
	if _local_player != null:
		_local_player.shooting_enabled = not _pointer_on_invite()


func _pointer_on_invite() -> bool:
	if not _invite_button.visible or InputDevice.using_gamepad:
		return false
	return _invite_button.get_global_rect().has_point(_invite_button.get_global_mouse_position())


func _exit_tree() -> void:
	if OnlineMatch.state_changed.is_connected(_refresh):
		OnlineMatch.state_changed.disconnect(_refresh)
	if NetworkSession.status_changed.is_connected(_refresh):
		NetworkSession.status_changed.disconnect(_refresh)
	if NetworkSession.peer_changed.is_connected(_refresh):
		NetworkSession.peer_changed.disconnect(_refresh)
	if NetworkSession.packet_received.is_connected(_on_packet_received):
		NetworkSession.packet_received.disconnect(_on_packet_received)
	if InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.disconnect(_on_device_changed)


func _physics_process(delta: float) -> void:
	if not NetworkSession.is_steam_match_active() or not _has_opponent():
		return

	_send_timer -= delta
	if _send_timer > 0.0:
		return

	_send_timer = 1.0 / GameSettings.NETWORK_PLAYER_STATE_RATE
	_send_locker_snapshot()


# --- Players -------------------------------------------------------------------------------------------

func _configure_players() -> void:
	_player_one.player_slot = GameSettings.PLAYER_ONE_SLOT
	_player_two.player_slot = GameSettings.PLAYER_TWO_SLOT

	if _local_slot == GameSettings.PLAYER_ONE_SLOT:
		_local_player = _player_one
		_remote_player = _player_two
	else:
		_local_player = _player_two
		_remote_player = _player_one

	_local_player.configure_local_control(
		_local_slot,
		GameSettings.INPUT_P1_MOVE_LEFT,
		GameSettings.INPUT_P1_MOVE_RIGHT,
		GameSettings.INPUT_P1_JUMP,
		GameSettings.INPUT_P1_SHOOT,
		GameSettings.INPUT_P1_BLOCK,
		true
	)

	_remote_player.configure_remote_control(_remote_slot)
	_configure_locker_station(_player_one, PLAYER_ONE_LOCKER_STATION, _player_one == _local_player)
	_configure_locker_station(_player_two, PLAYER_TWO_LOCKER_STATION, _player_two == _local_player)


func _configure_locker_station(player: Player, station_position: Vector2, allow_shoot: bool) -> void:
	player.global_position = station_position
	player.velocity = Vector2.ZERO
	player.gravity = 0.0
	player.movement_enabled = false
	player.shooting_enabled = allow_shoot
	player.collision_mask = 0

	var state_machine: Node = player.get_node_or_null("State")
	if state_machine != null:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED

	var left_ray: RayCast2D = player.get_node_or_null("RayL") as RayCast2D
	var right_ray: RayCast2D = player.get_node_or_null("RayR") as RayCast2D
	if left_ray != null:
		left_ray.enabled = false
	if right_ray != null:
		right_ray.enabled = false


func _refresh(_message: String = "") -> void:
	_player_one.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_ONE_SLOT))
	_player_two.set_player_color(OnlineMatch.get_player_color_id(GameSettings.PLAYER_TWO_SLOT))
	# Nobody has joined yet: their half of the room stays empty and asks for a friend instead.
	var present: bool = _has_opponent()
	_remote_player.visible = present
	_color_root(_remote_slot).visible = present
	_ready_target(_remote_slot).visible = present
	for target in _art.keys():
		var art: Node2D = _art[target]
		var state: String = _target_state(target)
		if _drawn_state.get(target, "") != state:
			if _drawn_state.has(target) and (state.begins_with("selected") or state == "ready"):
				_pop(art)
			_drawn_state[target] = state
			art.queue_redraw()
	_stage.queue_redraw()
	_overlay.queue_redraw()
	_prompt_bar.set_prompts(_prompts())
	_update_invite_button()
	_update_countdown_label()


func _on_device_changed(_gamepad: bool) -> void:
	_prompt_bar.set_prompts(_prompts())
	_update_invite_button()


func _prompts() -> Array:
	return [[InputDevice.prompt(&"ui_cancel"), "LEAVE LOBBY"]]


## The invite sits where the friend will stand and only while that spot is empty. With a gamepad it holds
## focus, so A sends the invite.
func _update_invite_button() -> void:
	var show: bool = not _has_opponent() and _can_invite()
	_invite_button.visible = show
	if show and InputDevice.using_gamepad and not _invite_button.has_focus():
		_invite_button.grab_focus.call_deferred()


# --- Build ---------------------------------------------------------------------------------------------

## The painted room is lit teal; pull it towards the game's neutral charcoal and settle it into the dark
## like the title screen, so the discs and type carry the light. The benches give way to ground shadows.
func _neutralize_backdrop() -> void:
	var root: Control = get_node_or_null(^"BackgroundLayer/BackgroundRoot") as Control
	if root == null:
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	for child in root.get_children():
		if child is TextureRect:
			(child as TextureRect).material = material
			(child as TextureRect).self_modulate = Color(0.92, 0.92, 0.92)
	var vignette: TextureRect = TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.16), Color(0.0, 0.004, 0.004, 0.66)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.48)
	texture.fill_to = Vector2(1.08, 1.08)
	vignette.texture = texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(vignette)


## Behind targets and players: each wheel as a hairline track and a ground shadow under each player.
func _build_stage() -> void:
	for line_path in [^"LockerWorld/PlayerOneTargetRing", ^"LockerWorld/PlayerTwoTargetRing"]:
		var line: CanvasItem = get_node_or_null(line_path) as CanvasItem
		if line != null:
			line.hide()
	_stage = Node2D.new()
	_stage.name = "Stage"
	_stage.z_index = -1
	_stage.draw.connect(_draw_stage)
	var world: Node = get_node(^"LockerWorld")
	world.add_child(_stage)
	world.move_child(_stage, 0)


## Every target draws itself flat; the scene's old polygons stay only as collision owners.
func _build_target_art() -> void:
	var targets: Array[StaticBody2D] = [_player_one_ready_target, _player_two_ready_target]
	for root in [_player_one_color_targets, _player_two_color_targets]:
		for child in root.get_children():
			if child is StaticBody2D:
				targets.append(child as StaticBody2D)
	for target in targets:
		for child in target.get_children():
			if child is CanvasItem:
				(child as CanvasItem).hide()
		var art: Node2D = Node2D.new()
		art.name = "Art"
		art.draw.connect(_draw_target.bind(target, art))
		target.add_child(art)
		_art[target] = art


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_ui_root.add_child(_overlay)
	_ui_root.move_child(_overlay, 0)


## A real button under WAITING FOR A FRIEND on the empty half; the trigger is held while the pointer is on it.
func _build_invite_button() -> void:
	_invite_button = Button.new()
	_invite_button.text = "INVITE FRIEND"
	_invite_button.custom_minimum_size = INVITE_BUTTON_SIZE
	_invite_button.size = INVITE_BUTTON_SIZE
	UiStyle.style_button(_invite_button, true, 20)
	var center: Vector2 = Vector2(_station(_remote_slot).x, WHEEL_CENTER_Y)
	_invite_button.position = Vector2(center.x - INVITE_BUTTON_SIZE.x * 0.5, center.y + 22.0)
	_invite_button.pressed.connect(_on_invite_pressed)
	_invite_button.visible = false
	_ui_root.add_child(_invite_button)
	GameJuice.attach_button_feedback(self)


## The match's world stays a surprise until both are ready; the countdown rolls it in under the number.
func _build_world_reveal() -> void:
	_world_reveal = LockerWorldReveal.new()
	_world_reveal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_world_reveal.offset_left = -280.0
	_world_reveal.offset_right = 280.0
	_world_reveal.offset_top = WORLD_REVEAL_TOP
	_world_reveal.offset_bottom = WORLD_REVEAL_TOP + 130.0
	_ui_root.add_child(_world_reveal)
	_ui_root.move_child(_world_reveal, _countdown_label.get_index())


func _build_prompt_bar() -> void:
	_prompt_bar = UiPromptBar.new()
	_prompt_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_bar.offset_left = 24.0
	_prompt_bar.offset_right = -24.0
	_prompt_bar.offset_top = -40.0
	_prompt_bar.offset_bottom = -18.0
	_ui_root.add_child(_prompt_bar)


# --- Drawing -------------------------------------------------------------------------------------------

func _draw_stage() -> void:
	for slot in GameSettings.player_slots():
		var station: Vector2 = _station(slot)
		var present: bool = slot == _local_slot or _has_opponent()
		var track: Color = Color(1.0, 1.0, 1.0, 0.07 if present else 0.035)
		_stage.draw_arc(Vector2(station.x, WHEEL_CENTER_Y), WHEEL_RADIUS, 0.0, TAU, 160, track, 1.5, true)
		if present:
			var feet: Vector2 = station + Vector2(0.0, FEET_OFFSET)
			LoadoutStyle.draw_glow(_stage, feet, Vector2(58.0, 9.0), Color(0.0, 0.0, 0.0, 0.6))


func _draw_target(target: StaticBody2D, art: Node2D) -> void:
	var slot: int = int(target.get_meta("slot", 0))
	var local: bool = slot == _local_slot
	var hovered: bool = target == _hovered
	if str(target.get_meta("locker_target_type", "")) == "ready":
		_draw_ready_disc(art, slot, local, hovered)
		return
	var color_id: StringName = StringName(str(target.get_meta("color_id", "")))
	var fill: Color = GameSettings.player_color_value(color_id)
	var taken: bool = OnlineMatch.is_color_taken_by_other(slot, color_id)
	var selected: bool = OnlineMatch.get_player_color_id(slot) == color_id
	if taken:
		fill = Color(fill.lerp(UiStyle.INK, 0.55), 0.55)
	art.draw_circle(Vector2.ZERO, COLOR_RADIUS + 3.0, Color(UiStyle.INK, 0.9 if not taken else 0.5), true, -1.0, true)
	art.draw_circle(Vector2.ZERO, COLOR_RADIUS, fill, true, -1.0, true)
	if selected:
		art.draw_arc(Vector2.ZERO, COLOR_RADIUS + 8.0, 0.0, TAU, 48, UiStyle.ACCENT, 3.0, true)
	elif hovered and not taken:
		art.draw_arc(Vector2.ZERO, COLOR_RADIUS + 7.0, 0.0, TAU, 48, Color(UiStyle.TEXT, 0.6), 1.5, true)


## READY: an ink disc with a hairline while choosing; once a friend is there your own ring turns amber (the
## next thing to do). Ready fills it amber with an ink check.
func _draw_ready_disc(art: Node2D, slot: int, local: bool, hovered: bool) -> void:
	var is_ready: bool = OnlineMatch.locker_ready.get(slot, false) == true
	if is_ready:
		art.draw_circle(Vector2.ZERO, READY_RADIUS + 3.0, Color(UiStyle.INK, 0.9), true, -1.0, true)
		art.draw_circle(Vector2.ZERO, READY_RADIUS, UiStyle.ACCENT, true, -1.0, true)
		art.draw_polyline(PackedVector2Array([Vector2(-15.0, 1.0), Vector2(-4.0, 12.0), Vector2(17.0, -12.0)]), UiStyle.INK, 6.0, true)
		return
	var call_to_action: bool = local and _has_opponent()
	var ring: Color = UiStyle.ACCENT if call_to_action else Color(UiStyle.TEXT, 0.32 if local else 0.18)
	if hovered:
		ring = UiStyle.ACCENT_HOT if call_to_action else Color(UiStyle.TEXT, 0.7)
	art.draw_circle(Vector2.ZERO, READY_RADIUS, Color(UiStyle.INK, 0.86), true, -1.0, true)
	if hovered:
		art.draw_circle(Vector2.ZERO, READY_RADIUS, UiStyle.FILL_HOVER, true, -1.0, true)
	art.draw_arc(Vector2.ZERO, READY_RADIUS, 0.0, TAU, 72, ring, 3.0, true)
	var label: Color = UiStyle.TEXT if local else UiStyle.TEXT_MUTED
	if call_to_action:
		label = UiStyle.ACCENT_HOT if hovered else UiStyle.ACCENT
	art.draw_string(UiStyle.FONT_DISPLAY, Vector2(-READY_RADIUS, 6.0), "READY", HORIZONTAL_ALIGNMENT_CENTER, READY_RADIUS * 2.0, 16, label)


func _draw_overlay() -> void:
	var size: Vector2 = _overlay.size
	# A hairline down the middle that fades out at both ends, in place of the grey bar.
	var mid: float = size.x * 0.5
	var clear: Color = Color(1.0, 1.0, 1.0, 0.0)
	var line: Color = Color(1.0, 1.0, 1.0, 0.1)
	LoadoutStyle.draw_gradient_rect(_overlay, Rect2(mid - 0.5, 0.0, 1.0, size.y * 0.5), clear, line)
	LoadoutStyle.draw_gradient_rect(_overlay, Rect2(mid - 0.5, size.y * 0.5, 1.0, size.y * 0.5), line, clear)
	for slot in GameSettings.player_slots():
		if slot == _local_slot or _has_opponent():
			_draw_header(slot)
		else:
			_draw_empty_side(slot)


## Caption, name with a team-colour dot, and a status line that also says what to do next.
func _draw_header(slot: int) -> void:
	var center_x: float = _station(slot).x
	var local: bool = slot == _local_slot
	LoadoutStyle.draw_glow(_overlay, Vector2(center_x, 66.0), Vector2(260.0, 70.0), Color(0.0, 0.0, 0.0, 0.5))
	_draw_text(UiStyle.FONT_BOLD, "YOU" if local else "OPPONENT", center_x, HEADER_CAPTION_Y, 12, UiStyle.TEXT_MUTED, 0)

	var name: String = _get_slot_name(slot).to_upper()
	var font_size: int = 30
	while font_size > 18 and UiStyle.FONT_DISPLAY.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > NAME_MAX_WIDTH:
		font_size -= 2
	var name_width: float = minf(UiStyle.FONT_DISPLAY.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, NAME_MAX_WIDTH)
	var dot_gap: float = 16.0
	var left: float = center_x - (name_width + dot_gap) * 0.5
	_overlay.draw_circle(Vector2(left + 5.0, HEADER_NAME_Y - font_size * 0.36), 5.0, OnlineMatch.get_player_color(slot), true, -1.0, true)
	_overlay.draw_string_outline(UiStyle.FONT_DISPLAY, Vector2(left + dot_gap, HEADER_NAME_Y), name, HORIZONTAL_ALIGNMENT_LEFT, NAME_MAX_WIDTH, font_size, 6, Color(UiStyle.INK, 0.8))
	_overlay.draw_string(UiStyle.FONT_DISPLAY, Vector2(left + dot_gap, HEADER_NAME_Y), name, HORIZONTAL_ALIGNMENT_LEFT, NAME_MAX_WIDTH, font_size, UiStyle.TEXT)

	var status: Array = _status_for(slot)
	_draw_text(UiStyle.FONT_BOLD, str(status[0]), center_x, HEADER_STATUS_Y, 13, status[1], 4)


func _status_for(slot: int) -> Array:
	var is_ready: bool = OnlineMatch.locker_ready.get(slot, false) == true
	if is_ready:
		return ["READY", UiStyle.ACCENT]
	if slot != _local_slot:
		return ["CHOOSING", UiStyle.TEXT_MUTED]
	if not _has_opponent():
		return ["SHOOT A COLOUR", UiStyle.TEXT_DIM]
	return ["SHOOT A COLOUR, THEN READY", UiStyle.TEXT_DIM]


## Nobody there yet: a quiet wheel and, under the line, the invite button where the opponent will stand.
func _draw_empty_side(slot: int) -> void:
	var center: Vector2 = Vector2(_station(slot).x, WHEEL_CENTER_Y)
	LoadoutStyle.draw_glow(_overlay, center + Vector2(0.0, -8.0), Vector2(240.0, 90.0), Color(0.0, 0.0, 0.0, 0.45))
	_draw_text(UiStyle.FONT_DISPLAY, "WAITING FOR A FRIEND", center.x, center.y - 10.0, 24, Color(UiStyle.TEXT, 0.72), 6)
	if not _can_invite():
		var reason: String = "STEAM OFFLINE" if not SteamService.steam_enabled else "CONNECTING"
		_draw_text(UiStyle.FONT_BOLD, reason, center.x, center.y + 28.0, 13, UiStyle.TEXT_MUTED, 4)


func _draw_text(font: Font, text: String, center_x: float, baseline: float, font_size: int, color: Color, outline: int) -> void:
	var origin: Vector2 = Vector2(center_x - 300.0, baseline)
	if outline > 0:
		_overlay.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0, font_size, outline, Color(UiStyle.INK, 0.8 * color.a))
	_overlay.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0, font_size, color)


# --- State ---------------------------------------------------------------------------------------------

## What a target shows right now, as a short key (so a change can be noticed and animated).
func _target_state(target: StaticBody2D) -> String:
	var slot: int = int(target.get_meta("slot", 0))
	if str(target.get_meta("locker_target_type", "")) == "ready":
		var is_ready: bool = OnlineMatch.locker_ready.get(slot, false) == true
		return "ready" if is_ready else ("call" if slot == _local_slot and _has_opponent() else "idle")
	var color_id: StringName = StringName(str(target.get_meta("color_id", "")))
	if OnlineMatch.get_player_color_id(slot) == color_id:
		return "selected:%s" % OnlineMatch.get_player_color_id(slot)
	return "taken" if OnlineMatch.is_color_taken_by_other(slot, color_id) else "free"


func _pop(art: Node2D) -> void:
	art.scale = Vector2.ONE * 1.18
	art.create_tween().tween_property(art, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The disc your aim rests on gets a hairline, so you know what a shot will pick.
func _update_hover() -> void:
	if _local_player == null:
		return
	var aim: Vector2 = _local_player.get_aim_world_position()
	var best: StaticBody2D = null
	for target in _art.keys():
		var body: StaticBody2D = target
		if int(body.get_meta("slot", 0)) != _local_slot:
			continue
		var radius: float = READY_RADIUS if str(body.get_meta("locker_target_type", "")) == "ready" else COLOR_RADIUS + 6.0
		if body.global_position.distance_to(aim) <= radius:
			best = body
			break
	if best == _hovered:
		return
	var previous: StaticBody2D = _hovered
	_hovered = best
	for body in [previous, best]:
		if body != null and _art.has(body):
			(_art[body] as Node2D).queue_redraw()


func _station(slot: int) -> Vector2:
	return PLAYER_ONE_LOCKER_STATION if slot == GameSettings.PLAYER_ONE_SLOT else PLAYER_TWO_LOCKER_STATION


func _color_root(slot: int) -> Node2D:
	return _player_one_color_targets if slot == GameSettings.PLAYER_ONE_SLOT else _player_two_color_targets


func _ready_target(slot: int) -> StaticBody2D:
	return _player_one_ready_target if slot == GameSettings.PLAYER_ONE_SLOT else _player_two_ready_target


# --- Shooting ------------------------------------------------------------------------------------------

func spawn_projectile(projectile: Node2D, spawn_position: Vector2) -> void:
	_projectiles.add_child(projectile)
	projectile.global_position = spawn_position


func get_player_by_slot(slot: int) -> Player:
	return _get_player_by_slot(slot)


func get_local_player() -> Player:
	return _local_player


func get_score_for_slot(_slot: int) -> int:
	return 0


func is_match_over() -> bool:
	return false


func get_winner_slot() -> int:
	return 0


func request_block_state(_owner: Node, _active: bool, _direction: Vector2, _cooldown_ratio: float) -> void:
	return


func request_shot(owner: Player, spawn_position: Vector2, direction: Vector2, projectile_data: Dictionary) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	projectile.configure_from_data(0, owner.player_slot, direction, projectile_data)
	projectile.collision_mask = LOCKER_PROJECTILE_COLLISION_MASK
	projectile.despawn_requested.connect(_on_locker_projectile_despawn_requested)
	spawn_projectile(projectile, spawn_position)


func _on_locker_projectile_despawn_requested(_projectile: Node, reason: StringName, collider) -> void:
	if reason != &"collision":
		return

	var target: Node = collider as Node
	if target == null:
		return

	var target_slot: int = int(target.get_meta("slot", 0))
	if target_slot != _local_slot:
		return

	var target_type: String = str(target.get_meta("locker_target_type", ""))
	if target_type == "color":
		var color_id: StringName = StringName(str(target.get_meta("color_id", "")))
		if OnlineMatch.is_color_taken_by_other(_local_slot, color_id):
			AudioDirector.play(&"ui_error")
			return
		OnlineMatch.set_local_color(color_id)
	elif target_type == "ready":
		var is_ready: bool = OnlineMatch.locker_ready.get(_local_slot, false) == true
		OnlineMatch.set_local_locker_ready(not is_ready)


# --- Network -------------------------------------------------------------------------------------------

func _send_locker_snapshot() -> void:
	if _local_player == null:
		return

	var payload: Dictionary = {
		"slot": _local_slot,
		"position": _local_player.global_position,
		"velocity": _local_player.velocity,
		"aim": _local_player.get_aim_world_position(),
		"facing": _local_player.last_dir,
	}
	NetworkSession.send_unreliable(
		NetworkSession.make_packet(GameSettings.PACKET_ONLINE_LOCKER_PLAYER_STATE, payload),
		GameSettings.NETWORK_CHANNEL_STATE
	)


func _on_packet_received(packet: Dictionary, _sender_id: int) -> void:
	var packet_type: StringName = StringName(str(packet.get("type", "")))
	if packet_type != GameSettings.PACKET_ONLINE_LOCKER_PLAYER_STATE:
		return

	var slot: int = int(packet.get("from_slot", 0))
	if slot == 0 or slot == _local_slot:
		return

	var remote_player: Player = _get_player_by_slot(slot)
	if remote_player == null:
		return

	remote_player.apply_remote_snapshot(NetworkSession.get_payload(packet))


func _get_player_by_slot(slot: int) -> Player:
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return _player_one
	if slot == GameSettings.PLAYER_TWO_SLOT:
		return _player_two
	return null


# --- Countdown -----------------------------------------------------------------------------------------

func _update_countdown_label() -> void:
	if OnlineMatch.locker_countdown_remaining < 0.0:
		_countdown_label.hide()
		_world_reveal.stop()
		_last_locker_countdown_sound_second = -1
		return

	var seconds_left: int = int(ceil(OnlineMatch.locker_countdown_remaining))
	_countdown_label.text = "%d" % seconds_left
	_countdown_label.show()
	if not _world_reveal.is_playing():
		_world_reveal.play(OnlineMatch.world_id)
	if seconds_left > 0 and seconds_left != _last_locker_countdown_sound_second:
		_last_locker_countdown_sound_second = seconds_left
		AudioDirector.play(&"ui_click", -2.25)
		var tween: Tween = create_tween()
		tween.tween_property(_countdown_label, "scale", Vector2(1.14, 1.14), 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _get_slot_name(slot: int) -> String:
	if slot == _local_slot:
		if SteamService.steam_enabled:
			return SteamService.steam_name
		return "Player %d" % slot

	if not _has_opponent():
		return "Waiting"
	if SteamService.steam_enabled:
		return Steam.getFriendPersonaName(NetworkSession.remote_steam_id)
	return "Player %d" % slot
