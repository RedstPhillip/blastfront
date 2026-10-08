class_name HudPlayerCard
extends Control

## A player's status in a bottom corner, kept slim so the arena stays visible: the portrait with live eyes
## inside a thin ring that charges with the block (white while blocking), name and health, a segmented
## health bar with a delayed damage trail, status effects, the Time Control dial for whoever has it, and for
## the opponent a reload tag (your own ammo lives at the crosshair). No panel: a soft shadow keeps it legible, and the whole strip steps back
## whenever a player passes behind it.
## Every layer only redraws when its state changes; pulses and shakes run on modulate/position.

const CARD_SIZE: Vector2 = Vector2(300.0, 54.0)
const PORTRAIT_CENTER: Vector2 = Vector2(22.0, 28.0)
const PORTRAIT_RADIUS: float = 16.0
const RING_RADIUS: float = 21.0
const CONTENT_LEFT: float = 54.0
const BAR_Y: float = 25.0
const BAR_HEIGHT: float = 7.0
const STATUS_Y: float = 42.0
const HEALTH_SEGMENT: int = 25
const LOW_HEALTH_RATIO: float = 0.3
const RING_STEPS: float = 48.0
const TIME_DIAL_STEPS: float = 24.0
const OCCLUDED_ALPHA: float = 0.3
const DOT_TEXTURE: Texture2D = preload("res://assets/fx/dot.png")
const BODY_TEXTURE_PATH: String = "res://assets/player/body/%s.png"

@export var mirrored: bool = false

var _player: Player = null
var _slot: int = GameSettings.PLAYER_ONE_SLOT
var _color: Color = Color.WHITE
var _time: float = 0.0
var _local: bool = true

var _health_ratio: float = 1.0
var _health_target: float = 1.0
var _trail_ratio: float = 1.0
var _trail_hold: float = 0.0
var _last_health: int = -1
var _max_health: int = 100
var _shake: float = 0.0
var _flash: float = 0.0
var _blink: float = 0.0
var _blink_timer: float = 2.0
var _charge_step: int = -1
var _blocking: bool = false
var _ability_ready: bool = false
var _ready_pop: float = 0.0
var _reload_signature: String = ""
var _status_signature: String = ""
var _time_signature: String = ""
var _time_pop: float = 0.0
var _time_chip_width: float = 0.0
var _portrait: Texture2D = null
var _portrait_color: StringName = &""
var _hp_tween: Tween = null
var _alpha: float = 1.0

var _shake_root: Control = null
var _shadow: Control = null
var _portrait_node: Control = null
var _ring: Control = null
var _bar: Control = null
var _bar_flash: Control = null
var _status: Control = null
var _time_chip: Control = null
var _name_label: Label = null
var _tag_label: Label = null
var _hp_label: Label = null


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func bind_player(player: Player, slot: int) -> void:
	_player = player
	_slot = slot
	_last_health = -1
	visible = player != null
	if player == null:
		return
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	_local = world != null and world.has_method(&"get_local_player") and world.get_local_player() == player
	_color = player.get_visual_tint()
	_health_target = _ratio()
	_health_ratio = _health_target
	_trail_ratio = _health_target
	_refresh_labels()
	_redraw_all()


# --- Construction ---------------------------------------------------------------------------

func _build() -> void:
	_shadow = _layer(self, _draw_shadow)
	_shake_root = _layer(self)
	_portrait_node = _layer(_shake_root, _draw_portrait)
	_ring = _layer(_shake_root, _draw_ring)
	_bar = _layer(_shake_root, _draw_bar)
	_bar_flash = _layer(_shake_root, _draw_bar_flash)
	_bar_flash.modulate.a = 0.0
	_status = _layer(_shake_root, _draw_status)
	_time_chip = _layer(_shake_root, _draw_time_chip)
	_name_label = _label(UiStyle.FONT_BOLD, 14, UiStyle.TEXT, 4)
	_tag_label = _label(UiStyle.FONT_BOLD, 10, UiStyle.TEXT_DIM, 3)
	_hp_label = _label(UiStyle.FONT_DISPLAY, 22, UiStyle.TEXT, 5)
	_layout_labels()


func _layer(parent: Control, painter: Callable = Callable()) -> Control:
	var layer: Control = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = CARD_SIZE
	if painter.is_valid():
		layer.draw.connect(painter.bind(layer))
	parent.add_child(layer)
	return layer


func _label(font: Font, font_size: int, color: Color, outline: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.style_label(label, font, font_size, color, outline)
	_shake_root.add_child(label)
	return label


func _layout_labels() -> void:
	var name_width: float = 150.0
	_name_label.size = Vector2(name_width, 20.0)
	_name_label.position = Vector2(_mx(CONTENT_LEFT, name_width), 2.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	_tag_label.size = Vector2(90.0, 14.0)
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var hp_width: float = 60.0
	_hp_label.size = Vector2(hp_width, 26.0)
	_hp_label.position = Vector2(_mx(CARD_SIZE.x - hp_width, hp_width), -3.0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.pivot_offset = Vector2(0.0 if mirrored else hp_width, 16.0)


func _refresh_labels() -> void:
	_name_label.text = UiStyle.player_name(_slot)
	var tag: String = ""
	if NetworkSession.is_bot_duel() and _slot == GameSettings.PLAYER_TWO_SLOT:
		tag = UiStyle.difficulty_name(UserSettings.get_int(UserSettings.BOT_DIFFICULTY))
	_tag_label.text = tag
	_tag_label.visible = tag != ""
	var name_width: float = UiStyle.FONT_BOLD.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_tag_label.position = Vector2(_mx(CONTENT_LEFT + name_width + 8.0, _tag_label.size.x), 5.0)
	_update_hp_label(false)


func _redraw_all() -> void:
	for layer in [_shadow, _portrait_node, _ring, _bar, _bar_flash, _status, _time_chip]:
		layer.queue_redraw()


# --- Per-frame state (cheap; only invalidates layers that changed) ----------------------------

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		visible = false
		return
	visible = true
	_time += delta
	var tint: Color = _player.get_visual_tint()
	if not tint.is_equal_approx(_color):
		_color = tint
		_refresh_labels()
		_redraw_all()
	_update_health(delta)
	_update_ring(delta)
	_update_reload()
	_update_status()
	_update_time_chip(delta)
	_update_blink(delta)
	_update_feedback(delta)
	_update_occlusion(delta)


func _update_health(delta: float) -> void:
	var health: int = _player.health_component.health if _player.health_component != null else 0
	var max_health: int = maxi(_player.health_component.max_health if _player.health_component != null else 100, 1)
	if max_health != _max_health:
		_max_health = max_health
		_bar.queue_redraw()
	if health != _last_health:
		if _last_health >= 0 and health < _last_health:
			_shake = 1.0
			_flash = 1.0
			_trail_hold = 0.45
			_update_hp_label(true)
		else:
			_update_hp_label(false)
			if _last_health >= 0:
				_trail_ratio = _ratio()
		_last_health = health
		_health_target = _ratio()
		_bar.queue_redraw()
	var previous_health: float = _health_ratio
	var previous_trail: float = _trail_ratio
	_health_ratio = lerpf(_health_ratio, _health_target, 1.0 - exp(-18.0 * delta))
	if absf(_health_ratio - _health_target) < 0.001:
		_health_ratio = _health_target
	if _trail_hold > 0.0:
		_trail_hold -= delta
	else:
		_trail_ratio = move_toward(_trail_ratio, _health_target, delta * 0.9)
	_trail_ratio = maxf(_trail_ratio, _health_ratio)
	var low: bool = _health_target <= LOW_HEALTH_RATIO and _health_target > 0.0
	if not is_equal_approx(previous_health, _health_ratio) or not is_equal_approx(previous_trail, _trail_ratio) or low:
		_bar.queue_redraw()


func _update_hp_label(damaged: bool) -> void:
	var health: int = _player.health_component.health if _player != null and _player.health_component != null else 0
	_hp_label.text = str(health)
	var low: bool = _ratio() <= LOW_HEALTH_RATIO
	_hp_label.add_theme_color_override("font_color", UiStyle.DANGER.lightened(0.15) if low else UiStyle.TEXT)
	if not damaged:
		return
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_label.scale = Vector2(1.3, 1.3)
	_hp_label.modulate = Color(1.0, 0.55, 0.5)
	_hp_tween = create_tween().set_parallel(true)
	_hp_tween.tween_property(_hp_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(_hp_label, "modulate", Color.WHITE, 0.4)


func _update_ring(delta: float) -> void:
	var charge: float = clampf(_player.get_block_cooldown_ratio(), 0.0, 1.0)
	var step: int = int(round(charge * RING_STEPS))
	var blocking: bool = _player.is_blocking()
	if step != _charge_step or blocking != _blocking:
		var became_ready: bool = _charge_step >= 0 and _charge_step < int(RING_STEPS) and step >= int(RING_STEPS)
		_charge_step = step
		_blocking = blocking
		_ring.queue_redraw()
		if became_ready:
			_ready_pop = 1.0
	_ability_ready = step >= int(RING_STEPS)
	if _ready_pop > 0.0:
		_ready_pop = maxf(_ready_pop - delta * 2.5, 0.0)
		_ring.queue_redraw()


## Only the opponent's reload is shown here; your own lives at the crosshair.
func _update_reload() -> void:
	var gun: Variant = _player.get_gun()
	var signature: String = ""
	if gun != null and not _local:
		if gun.is_reloading():
			signature = "reload"
		elif gun.get_current_ammo() <= 0:
			signature = "empty"
	if signature != _reload_signature:
		_reload_signature = signature
		_status.queue_redraw()
	if _reload_signature == "reload":
		_status.modulate.a = 0.65 + 0.35 * sin(_time * 10.0)
	elif _status.modulate.a != 1.0:
		_status.modulate.a = 1.0


func _update_status() -> void:
	var signature: String = ",".join(_status_names())
	if signature != _status_signature:
		_status_signature = signature
		_status.queue_redraw()


func _status_names() -> Array[StringName]:
	var names: Array[StringName] = []
	if _player.is_time_slowed():
		names.append(&"slowed")
	if _player.status_effect_manager != null and _player.status_effect_manager.get_active_count() > 0:
		names.append_array(_player.status_effect_manager.get_active_effect_names())
	return names


## Time Control: the dial charges back after a cast, turns amber when ready and drains while the cast holds
## the opponent slowed. Shown on both cards, so you can see when theirs is up too.
func _update_time_chip(delta: float) -> void:
	var signature: String = ""
	if _player.has_time_control():
		var active: float = _player.get_time_control_active_ratio()
		var charge: float = _player.get_time_control_charge()
		if active > 0.0:
			signature = "active:%d" % int(ceil(active * TIME_DIAL_STEPS))
		elif charge >= 1.0:
			signature = "ready:%s" % InputDevice.prompt(GameSettings.INPUT_P1_TIME_CONTROL)
		else:
			signature = "charge:%d:%d" % [int(charge * TIME_DIAL_STEPS), int(ceil(_player.get_time_control_cooldown_left()))]
	if signature != _time_signature:
		if signature.begins_with("ready") and _time_signature.begins_with("charge"):
			_time_pop = 1.0
		_time_signature = signature
		_time_chip_width = float(_time_chip_layout()["width"])
		_time_chip.queue_redraw()
		_status.queue_redraw()
	if _time_pop > 0.0:
		_time_pop = maxf(_time_pop - delta * 2.5, 0.0)
		_time_chip.queue_redraw()


func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink = 1.0
		_blink_timer = randf_range(2.5, 5.0)
	if _blink > 0.0:
		_blink = maxf(_blink - delta / 0.15, 0.0)
		_portrait_node.queue_redraw()


func _update_feedback(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 4.0, 0.0)
		_shake_root.position.x = sin(_time * 70.0) * _shake * _shake * 5.0
	elif _shake_root.position.x != 0.0:
		_shake_root.position.x = 0.0
	if _flash > 0.0 or _bar_flash.modulate.a > 0.0:
		_flash = maxf(_flash - delta * 3.5, 0.0)
		_bar_flash.modulate.a = _flash


## Steps back to a whisper while any player is behind the strip, so it never hides the fight.
func _update_occlusion(delta: float) -> void:
	var occluded: bool = false
	var area: Rect2 = get_global_rect().grow(18.0)
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Node2D = node as Node2D
		if player != null and player.visible and area.has_point(canvas * player.global_position):
			occluded = true
			break
	var target: float = OCCLUDED_ALPHA if occluded else 1.0
	if not is_equal_approx(_alpha, target):
		_alpha = move_toward(_alpha, target, delta * 4.0)
		modulate.a = _alpha


# --- Painters ------------------------------------------------------------------------------------

## A soft ink pool behind the strip instead of a panel: legible over bright sky, invisible over dark rock.
func _draw_shadow(layer: Control) -> void:
	var center: Vector2 = Vector2(_mx(110.0), 30.0)
	LoadoutStyle.draw_glow(layer, center, Vector2(190.0, 44.0), Color(0.0, 0.012, 0.016, 0.5), 40)


func _draw_portrait(layer: Control) -> void:
	if _player == null:
		return
	var center: Vector2 = _portrait_center()
	var texture: Texture2D = _get_portrait_texture()
	var size_px: float = PORTRAIT_RADIUS * 2.0
	layer.draw_circle(center, RING_RADIUS - 1.0, Color(0.03, 0.03, 0.028, 0.8), true, -1.0, true)
	if texture != null:
		layer.draw_texture_rect(texture, Rect2(center - Vector2.ONE * size_px * 0.5, Vector2.ONE * size_px), false)
	else:
		layer.draw_circle(center, size_px * 0.5, _color, true, -1.0, true)
	var look: float = -1.0 if mirrored else 1.0
	var eye_open: float = maxf(absf(_blink * 2.0 - 1.0), 0.12) if _blink > 0.0 else 1.0
	var eye_half: Vector2 = Vector2(1.9, 3.6 * eye_open)
	for side in [-1.0, 1.0]:
		var eye_center: Vector2 = center + Vector2(look * 2.6 + side * 5.0, -1.5)
		layer.draw_texture_rect(DOT_TEXTURE, Rect2(eye_center - eye_half, eye_half * 2.0), false, Color(0.02, 0.025, 0.03, 1.0))
		if eye_open > 0.5:
			layer.draw_texture_rect(DOT_TEXTURE, Rect2(eye_center + Vector2(-1.0, -2.3), Vector2(1.1, 1.2)), false, Color(1, 1, 1, 0.9))


## The block's charge as a thin ring around the portrait: shield-blue as it fills, full when ready,
## white while blocking.
func _draw_ring(layer: Control) -> void:
	var center: Vector2 = _portrait_center()
	var charge: float = float(maxi(_charge_step, 0)) / RING_STEPS
	var color: Color = UiStyle.SHIELD if _ability_ready else LoadoutStyle.with_alpha(UiStyle.SHIELD, 0.55)
	if _blocking:
		color = Color.WHITE
	layer.draw_arc(center, RING_RADIUS, 0.0, TAU, 48, Color(0.0, 0.0, 0.0, 0.45), 2.5, true)
	if charge > 0.0:
		layer.draw_arc(center, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * charge, maxi(int(48.0 * charge), 4), color, 2.5, true)
	if _ready_pop > 0.0:
		layer.draw_arc(center, RING_RADIUS + 3.0 + (1.0 - _ready_pop) * 6.0, 0.0, TAU, 48, LoadoutStyle.with_alpha(UiStyle.SHIELD, _ready_pop * 0.7), 1.5, true)


func _draw_bar(layer: Control) -> void:
	var bar: Rect2 = _bar_rect()
	layer.draw_rect(bar.grow(1.5), Color(0.0, 0.015, 0.02, 0.8))
	layer.draw_rect(bar, Color(1, 1, 1, 0.08))
	layer.draw_rect(_bar_part(bar, _trail_ratio), Color(1.0, 0.92, 0.78, 0.8))
	var low: bool = _health_target <= LOW_HEALTH_RATIO and _health_target > 0.0
	var fill: Color = _color.lerp(Color(0.95, 1.0, 0.97), 0.1)
	if low:
		fill = UiStyle.DANGER.lerp(Color(1.0, 0.75, 0.7), 0.5 + 0.5 * sin(_time * 8.0))
	var fill_rect: Rect2 = _bar_part(bar, _health_ratio)
	layer.draw_rect(fill_rect, fill)
	layer.draw_rect(Rect2(fill_rect.position, Vector2(fill_rect.size.x, 2.0)), Color(1, 1, 1, 0.22))
	var segments: int = int(ceil(float(_max_health) / float(HEALTH_SEGMENT)))
	for index in range(1, segments):
		var x: float = bar.position.x + bar.size.x * float(index * HEALTH_SEGMENT) / float(_max_health)
		if mirrored:
			x = bar.end.x - (x - bar.position.x)
		layer.draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.0, 0.015, 0.02, 0.9), 2.0)


func _draw_bar_flash(layer: Control) -> void:
	layer.draw_rect(_bar_rect().grow(1.5), Color(1.0, 0.9, 0.85, 0.85))


func _draw_status(layer: Control) -> void:
	if _player == null:
		return
	var x_offset: float = 0.0
	if _status_signature != "":
		for effect_name in _status_names():
			var chip_color: Color = UiStyle.TEXT_DIM
			match effect_name:
				&"slowed":
					chip_color = TimeFlow.COLOR.lightened(0.2)
				&"freeze":
					chip_color = Color(0.55, 0.88, 1.0)
				&"shock":
					chip_color = Color(1.0, 0.92, 0.35)
				&"poison":
					chip_color = Color(0.5, 1.0, 0.45)
			var text: String = str(effect_name).to_upper()
			var width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0
			var x: float = _mx(CONTENT_LEFT + x_offset, width)
			layer.draw_circle(Vector2(x + 4.0, STATUS_Y + 4.0), 2.5, chip_color, true, -1.0, true)
			layer.draw_string_outline(UiStyle.FONT_BOLD, Vector2(x + 10.0, STATUS_Y + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.7))
			layer.draw_string(UiStyle.FONT_BOLD, Vector2(x + 10.0, STATUS_Y + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, chip_color)
			x_offset += width + 8.0
	if _reload_signature != "":
		var label: String = "RELOADING" if _reload_signature == "reload" else "EMPTY"
		var color: Color = UiStyle.ACCENT if _reload_signature == "reload" else UiStyle.DANGER
		var width: float = UiStyle.FONT_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var end_gap: float = _time_chip_width + 12.0 if _time_signature != "" else 0.0
		var x: float = _mx(CARD_SIZE.x - end_gap - width, width)
		layer.draw_string_outline(UiStyle.FONT_BOLD, Vector2(x, STATUS_Y + 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.7))
		layer.draw_string(UiStyle.FONT_BOLD, Vector2(x, STATUS_Y + 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


## Pieces of the Time Control chip for the current signature: dial, label, seconds left or the key to press.
func _time_chip_layout() -> Dictionary:
	if _time_signature == "":
		return {"width": 0.0}
	var parts: PackedStringArray = _time_signature.split(":")
	var state: String = parts[0]
	var font: Font = UiStyle.FONT_BOLD
	var seconds: String = parts[2] if state == "charge" else ""
	var key: String = parts[1] if state == "ready" and _local else ""
	var label_width: float = font.get_string_size("TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var seconds_width: float = font.get_string_size(seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x if seconds != "" else 0.0
	var key_width: float = maxf(font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0, 13.0) if key != "" else 0.0
	var width: float = 17.0 + label_width + (5.0 + seconds_width if seconds != "" else 0.0) + (6.0 + key_width if key != "" else 0.0)
	return {"parts": parts, "state": state, "seconds": seconds, "key": key, "label_width": label_width, "width": width}


func _draw_time_chip(layer: Control) -> void:
	if _player == null or _time_signature == "":
		return
	var chip: Dictionary = _time_chip_layout()
	var parts: PackedStringArray = chip["parts"]
	var state: String = chip["state"]
	var seconds: String = chip["seconds"]
	var key: String = chip["key"]
	var label: String = "TIME"
	var label_width: float = chip["label_width"]
	var font: Font = UiStyle.FONT_BOLD
	var width: float = chip["width"]
	var x: float = _mx(CARD_SIZE.x - width, width)
	var center: Vector2 = Vector2(x + 6.0, STATUS_Y + 4.0)
	var ratio: float = 1.0
	var dial_color: Color = UiStyle.ACCENT
	var label_color: Color = UiStyle.ACCENT
	if state == "active":
		ratio = float(parts[1]) / TIME_DIAL_STEPS
		dial_color = TimeFlow.COLOR
		label_color = TimeFlow.COLOR.lightened(0.2)
	elif state == "charge":
		ratio = float(parts[1]) / TIME_DIAL_STEPS
		dial_color = LoadoutStyle.with_alpha(TimeFlow.COLOR, 0.65)
		label_color = UiStyle.TEXT_DIM
	layer.draw_circle(center, 7.0, Color(0.0, 0.0, 0.0, 0.55), true, -1.0, true)
	if ratio > 0.0:
		layer.draw_arc(center, 4.2, -PI * 0.5, -PI * 0.5 + TAU * ratio, maxi(int(24.0 * ratio), 3), dial_color, 3.4, true)
	layer.draw_line(center, center + Vector2(0.0, -4.6).rotated(TAU * ratio), Color(1.0, 1.0, 1.0, 0.85), 1.2, true)
	if _time_pop > 0.0:
		layer.draw_arc(center, 8.0 + (1.0 - _time_pop) * 7.0, 0.0, TAU, 32, LoadoutStyle.with_alpha(UiStyle.ACCENT, _time_pop * 0.8), 1.5, true)
	var text_x: float = x + 17.0
	var baseline: float = STATUS_Y + 8.0
	layer.draw_string_outline(font, Vector2(text_x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.7))
	layer.draw_string(font, Vector2(text_x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_color)
	text_x += label_width
	if seconds != "":
		text_x += 5.0
		layer.draw_string_outline(font, Vector2(text_x, baseline), seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.7))
		layer.draw_string(font, Vector2(text_x, baseline), seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.TEXT_MUTED)
	if key != "":
		LoadoutStyle.draw_key_chip(layer, Vector2(text_x + 6.0, STATUS_Y - 2.5), key, 13.0, UiStyle.TEXT)


# --- Helpers ---------------------------------------------------------------------------------------

func _ratio() -> float:
	if _player == null or _player.health_component == null:
		return 0.0
	return clampf(float(_player.health_component.health) / maxf(float(_player.health_component.max_health), 1.0), 0.0, 1.0)


func _mx(x: float, width: float = 0.0) -> float:
	return CARD_SIZE.x - x - width if mirrored else x


func _portrait_center() -> Vector2:
	return Vector2(_mx(PORTRAIT_CENTER.x), PORTRAIT_CENTER.y)


func _bar_rect() -> Rect2:
	var bar_width: float = CARD_SIZE.x - CONTENT_LEFT
	return Rect2(_mx(CONTENT_LEFT, bar_width), BAR_Y, bar_width, BAR_HEIGHT)


func _bar_part(bar: Rect2, ratio: float) -> Rect2:
	var width: float = bar.size.x * clampf(ratio, 0.0, 1.0)
	if mirrored:
		return Rect2(bar.end.x - width, bar.position.y, width, bar.size.y)
	return Rect2(bar.position.x, bar.position.y, width, bar.size.y)


func _get_portrait_texture() -> Texture2D:
	var color_id: StringName = _player.player_color_id
	if not GameSettings.is_valid_player_color(color_id):
		color_id = GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if _slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR
	if color_id != _portrait_color:
		_portrait_color = color_id
		var path: String = BODY_TEXTURE_PATH % str(color_id)
		_portrait = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _portrait
