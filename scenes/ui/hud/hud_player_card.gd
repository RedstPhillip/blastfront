class_name HudPlayerCard
extends Control

## Player status card: portrait with live eyes, shield-charge ring and ability chip, segmented health bar
## with a delayed damage trail, ammo capsules with a reload meter, and status-effect chips.
## Every layer is its own canvas item that only redraws when its state changes; pulses, flashes and
## shakes run on modulate/position, so a card at rest costs nothing per frame.

const CARD_SIZE: Vector2 = Vector2(352.0, 84.0)
const CUT: float = 22.0
const PORTRAIT_CENTER: Vector2 = Vector2(44.0, 42.0)
const PORTRAIT_RADIUS: float = 26.0
const CONTENT_LEFT: float = 84.0
const CONTENT_RIGHT_PAD: float = 20.0
const BAR_Y: float = 36.0
const BAR_HEIGHT: float = 13.0
const AMMO_Y: float = 58.0
const HEALTH_SEGMENT: int = 25
const LOW_HEALTH_RATIO: float = 0.3
const RING_STEPS: float = 72.0
const RELOAD_STEPS: float = 48.0
const DOT_TEXTURE: Texture2D = preload("res://assets/fx/dot.png")
const BODY_TEXTURE_PATH: String = "res://assets/player/body/%s.png"

@export var mirrored: bool = false

var _player: Player = null
var _slot: int = GameSettings.PLAYER_ONE_SLOT
var _color: Color = Color.WHITE
var _time: float = 0.0

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
var _ammo_signature: String = ""
var _status_signature: String = ""
var _portrait: Texture2D = null
var _portrait_color: StringName = &""
var _hp_tween: Tween = null

var _shake_root: Control = null
var _frame: Control = null
var _danger: Control = null
var _hit_flash: Control = null
var _portrait_node: Control = null
var _ring: Control = null
var _ring_glow: Control = null
var _bar: Control = null
var _bar_danger: Control = null
var _ammo: Control = null
var _status: Control = null
var _name_label: Label = null
var _tag_label: Label = null
var _hp_label: Label = null
var _reload_label: Label = null
var _pip_full: StyleBoxFlat = null
var _pip_empty: StyleBoxFlat = null


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_full = UiStyle.panel(UiStyle.ACCENT, UiStyle.ACCENT_HOT, 3, 1)
	_pip_empty = UiStyle.panel(Color(0.08, 0.11, 0.11, 0.9), UiStyle.LINE, 3, 1)
	_build()


func bind_player(player: Player, slot: int) -> void:
	_player = player
	_slot = slot
	_last_health = -1
	visible = player != null
	if player == null:
		return
	_color = player.get_visual_tint()
	_health_target = _ratio()
	_health_ratio = _health_target
	_trail_ratio = _health_target
	_refresh_labels()
	_redraw_all()


# --- Construction ---------------------------------------------------------------------------

func _build() -> void:
	_shake_root = _layer(self)
	_shake_root.size = CARD_SIZE
	_frame = _layer(_shake_root, _draw_frame)
	_danger = _layer(_shake_root, _draw_danger)
	_danger.visible = false
	_portrait_node = _layer(_shake_root, _draw_portrait)
	_ring = _layer(_shake_root, _draw_ring)
	_ring_glow = _layer(_shake_root, _draw_ring_glow)
	_ring_glow.visible = false
	_bar = _layer(_shake_root, _draw_bar)
	_bar_danger = _layer(_shake_root, _draw_bar_danger)
	_bar_danger.visible = false
	_ammo = _layer(_shake_root, _draw_ammo)
	_status = _layer(_shake_root, _draw_status)
	_hit_flash = _layer(_shake_root, _draw_hit_flash)
	_hit_flash.modulate.a = 0.0

	_name_label = _label(UiStyle.FONT_BOLD, 18, UiStyle.TEXT)
	_tag_label = _label(UiStyle.FONT_UI, 11, UiStyle.TEXT_DIM)
	_hp_label = _label(UiStyle.FONT_DISPLAY, 22, UiStyle.TEXT)
	_reload_label = _label(UiStyle.FONT_BOLD, 11, UiStyle.ACCENT)
	_reload_label.visible = false
	_layout_labels()


func _layer(parent: Control, painter: Callable = Callable()) -> Control:
	var layer: Control = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = CARD_SIZE
	if painter.is_valid():
		layer.draw.connect(painter.bind(layer))
	parent.add_child(layer)
	return layer


func _label(font: Font, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.style_label(label, font, font_size, color)
	_shake_root.add_child(label)
	return label


func _layout_labels() -> void:
	var name_width: float = 180.0
	_name_label.size = Vector2(name_width, 24.0)
	_name_label.position = Vector2(_mx(CONTENT_LEFT, name_width), 9.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	_tag_label.size = Vector2(90.0, 16.0)
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var hp_width: float = 70.0
	_hp_label.size = Vector2(hp_width, 28.0)
	_hp_label.position = Vector2(_mx(CARD_SIZE.x - CONTENT_RIGHT_PAD - hp_width, hp_width), 5.0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.pivot_offset = Vector2(0.0 if mirrored else hp_width, 18.0)
	_reload_label.size = Vector2(110.0, 16.0)
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT


func _refresh_labels() -> void:
	_name_label.text = UiStyle.player_name(_slot)
	var tag: String = ""
	if NetworkSession.is_bot_duel() and _slot == GameSettings.PLAYER_TWO_SLOT:
		tag = UiStyle.difficulty_name(UserSettings.get_int(UserSettings.BOT_DIFFICULTY))
	_tag_label.text = tag
	_tag_label.visible = tag != ""
	_tag_label.add_theme_color_override("font_color", Color(_color.r, _color.g, _color.b, 0.95))
	var name_width: float = UiStyle.FONT_BOLD.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_tag_label.position = Vector2(_mx(CONTENT_LEFT + name_width + 8.0, _tag_label.size.x), 13.0)
	_update_hp_label(false)


func _redraw_all() -> void:
	for layer in [_frame, _danger, _portrait_node, _ring, _ring_glow, _bar, _bar_danger, _ammo, _status, _hit_flash]:
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
	_update_ammo()
	_update_status()
	_update_blink(delta)
	_update_feedback(delta)


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
		_bar_danger.queue_redraw()
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
	if not is_equal_approx(previous_health, _health_ratio) or not is_equal_approx(previous_trail, _trail_ratio):
		_bar.queue_redraw()
	var low: bool = _health_target <= LOW_HEALTH_RATIO and _health_target > 0.0
	_danger.visible = low
	_bar_danger.visible = low
	if low:
		var pulse: float = 0.5 + 0.5 * sin(_time * 8.0)
		_danger.modulate.a = pulse
		_bar_danger.modulate.a = 0.35 + 0.45 * pulse


func _update_hp_label(damaged: bool) -> void:
	var health: int = _player.health_component.health if _player != null and _player.health_component != null else 0
	_hp_label.text = str(health)
	var low: bool = _ratio() <= LOW_HEALTH_RATIO
	_hp_label.add_theme_color_override("font_color", UiStyle.DANGER if low else UiStyle.TEXT)
	if not damaged:
		return
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_label.scale = Vector2(1.35, 1.35)
	_hp_label.modulate = Color(1.0, 0.55, 0.5)
	_hp_tween = create_tween().set_parallel(true)
	_hp_tween.tween_property(_hp_label, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	var ready: bool = step >= int(RING_STEPS)
	if ready != _ability_ready:
		_ability_ready = ready
		_ring_glow.visible = ready
		_ring.queue_redraw()
	if ready:
		_ring_glow.modulate.a = minf(0.55 + 0.45 * sin(_time * 3.0) + _ready_pop, 1.0)
	_ready_pop = maxf(_ready_pop - delta * 2.5, 0.0)


func _update_ammo() -> void:
	var gun: Variant = _player.get_gun()
	var signature: String = ""
	var reloading: bool = false
	if gun != null:
		reloading = gun.is_reloading()
		var reload_step: int = int(round(gun.get_reload_ratio() * RELOAD_STEPS)) if reloading else -1
		signature = "%d/%d/%d" % [gun.get_current_ammo(), gun.get_max_ammo(), reload_step]
	if signature != _ammo_signature:
		_ammo_signature = signature
		_ammo.queue_redraw()
		_position_reload_label(gun)
	if _reload_label.visible:
		_reload_label.modulate.a = 0.6 + 0.4 * sin(_time * 10.0) if reloading else 1.0


func _position_reload_label(gun: Variant) -> void:
	if gun == null:
		_reload_label.visible = false
		return
	var reloading: bool = gun.is_reloading()
	var empty: bool = not reloading and gun.get_current_ammo() <= 0
	_reload_label.visible = reloading or empty
	if not _reload_label.visible:
		return
	_reload_label.text = "RELOADING" if reloading else "EMPTY"
	_reload_label.add_theme_color_override("font_color", UiStyle.ACCENT if reloading else UiStyle.DANGER)
	var strip: float = _ammo_strip_width(gun.get_max_ammo())
	_reload_label.position = Vector2(_mx(CONTENT_LEFT + strip + 10.0, _reload_label.size.x), AMMO_Y - 1.0)


func _update_status() -> void:
	var signature: String = ""
	if _player.status_effect_manager != null and _player.status_effect_manager.get_active_count() > 0:
		signature = ",".join(_player.status_effect_manager.get_active_effect_names())
	if signature != _status_signature:
		_status_signature = signature
		_status.queue_redraw()


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
		_shake_root.position.x = sin(_time * 70.0) * _shake * _shake * 7.0
	elif _shake_root.position.x != 0.0:
		_shake_root.position.x = 0.0
	if _flash > 0.0 or _hit_flash.modulate.a > 0.0:
		_flash = maxf(_flash - delta * 3.5, 0.0)
		_hit_flash.modulate.a = _flash


# --- Painters ------------------------------------------------------------------------------------

func _draw_frame(layer: Control) -> void:
	var w: float = CARD_SIZE.x
	var h: float = CARD_SIZE.y
	var shape: PackedVector2Array = _card_shape(w, h)
	layer.draw_colored_polygon(shape, Color(UiStyle.PANEL.r, UiStyle.PANEL.g, UiStyle.PANEL.b, 0.84))
	var sheen_bottom: float = h * 0.42
	var sheen: PackedVector2Array = PackedVector2Array([shape[0], shape[1], shape[2], Vector2(w if mirrored else shape[2].x, sheen_bottom), Vector2(0.0 if mirrored else shape[0].x, sheen_bottom)])
	layer.draw_colored_polygon(sheen, Color(1, 1, 1, 0.035))
	var tint_band: PackedVector2Array = PackedVector2Array([Vector2(0.0, h - 3.0), Vector2(w, h - 3.0), Vector2(w, h), Vector2(0.0, h)])
	layer.draw_colored_polygon(tint_band, Color(_color.r, _color.g, _color.b, 0.35))
	var outline: PackedVector2Array = shape.duplicate()
	outline.append(shape[0])
	layer.draw_polyline(outline, UiStyle.LINE, 1.2, true)
	layer.draw_polyline(PackedVector2Array([shape[0], shape[1], shape[2]]), _color, 3.0, true)
	var side_x: float = w - 4.0 if mirrored else 0.0
	layer.draw_rect(Rect2(side_x, CUT if mirrored else 0.0, 4.0, h - (CUT if mirrored else 0.0)), Color(_color.r, _color.g, _color.b, 0.9))
	var center: Vector2 = _portrait_center()
	layer.draw_circle(center, PORTRAIT_RADIUS + 6.0, Color(0.02, 0.04, 0.04, 0.92), true, -1.0, true)


func _draw_danger(layer: Control) -> void:
	var shape: PackedVector2Array = _card_shape(CARD_SIZE.x, CARD_SIZE.y)
	var outline: PackedVector2Array = shape.duplicate()
	outline.append(shape[0])
	layer.draw_polyline(outline, UiStyle.DANGER, 2.0, true)
	layer.draw_colored_polygon(shape, Color(UiStyle.DANGER.r, UiStyle.DANGER.g, UiStyle.DANGER.b, 0.07))


func _draw_hit_flash(layer: Control) -> void:
	layer.draw_colored_polygon(_card_shape(CARD_SIZE.x, CARD_SIZE.y), Color(1.0, 0.25, 0.25, 0.24))


func _draw_portrait(layer: Control) -> void:
	if _player == null:
		return
	var center: Vector2 = _portrait_center()
	var texture: Texture2D = _get_portrait_texture()
	var size_px: float = PORTRAIT_RADIUS * 2.0 - 4.0
	if texture != null:
		layer.draw_texture_rect(texture, Rect2(center - Vector2.ONE * size_px * 0.5, Vector2.ONE * size_px), false)
	else:
		layer.draw_circle(center, size_px * 0.5, _color, true, -1.0, true)
	var look: float = -1.0 if mirrored else 1.0
	var eye_open: float = maxf(absf(_blink * 2.0 - 1.0), 0.12) if _blink > 0.0 else 1.0
	var eye_half: Vector2 = Vector2(2.8, 5.4 * eye_open)
	for side in [-1.0, 1.0]:
		var eye_center: Vector2 = center + Vector2(look * 4.0 + side * 7.5, -2.0)
		layer.draw_texture_rect(DOT_TEXTURE, Rect2(eye_center - eye_half, eye_half * 2.0), false, Color(0.02, 0.025, 0.03, 1.0))
		if eye_open > 0.5:
			layer.draw_texture_rect(DOT_TEXTURE, Rect2(eye_center + Vector2(-1.5, -3.3), Vector2(1.6, 1.8)), false, Color(1, 1, 1, 0.9))


func _draw_ring(layer: Control) -> void:
	var center: Vector2 = _portrait_center()
	var radius: float = PORTRAIT_RADIUS + 3.0
	var charge: float = float(maxi(_charge_step, 0)) / RING_STEPS
	var ring_color: Color = UiStyle.SHIELD if _ability_ready else Color(UiStyle.SHIELD.r, UiStyle.SHIELD.g, UiStyle.SHIELD.b, 0.5)
	if _blocking:
		ring_color = Color.WHITE
	layer.draw_arc(center, radius, 0.0, TAU, 56, Color(0.13, 0.2, 0.2, 0.95), 3.5, true)
	if charge > 0.0:
		layer.draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * charge, maxi(int(56.0 * charge), 4), ring_color, 3.5, true)
	var badge: Vector2 = center + Vector2(PORTRAIT_RADIUS * (-0.78 if mirrored else 0.78), PORTRAIT_RADIUS * 0.78)
	_draw_shield_badge(layer, badge, charge, ring_color)


func _draw_shield_badge(layer: Control, center: Vector2, charge: float, color: Color) -> void:
	var outline: PackedVector2Array = _shield_shape(center, 9.0)
	layer.draw_colored_polygon(outline, Color(0.02, 0.04, 0.05, 0.96))
	var inner: PackedVector2Array = _shield_shape(center, 6.5)
	if _ability_ready or _blocking:
		layer.draw_colored_polygon(inner, color)
	else:
		layer.draw_colored_polygon(inner, Color(0.16, 0.24, 0.26, 1.0))
		var fill_height: float = 13.0 * charge
		var clip: PackedVector2Array = PackedVector2Array([
			Vector2(center.x - 8.0, center.y + 7.0 - fill_height), Vector2(center.x + 8.0, center.y + 7.0 - fill_height),
			Vector2(center.x + 8.0, center.y + 8.0), Vector2(center.x - 8.0, center.y + 8.0),
		])
		for piece in Geometry2D.intersect_polygons(inner, clip):
			layer.draw_colored_polygon(piece, Color(color.r, color.g, color.b, 0.75))
	var border: PackedVector2Array = outline.duplicate()
	border.append(outline[0])
	layer.draw_polyline(border, Color(color.r, color.g, color.b, 0.9), 1.2, true)


func _shield_shape(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius * 0.85, -radius * 0.62),
		center + Vector2(radius * 0.78, radius * 0.18), center + Vector2(0.0, radius),
		center + Vector2(-radius * 0.78, radius * 0.18), center + Vector2(-radius * 0.85, -radius * 0.62),
	])


func _draw_ring_glow(layer: Control) -> void:
	var center: Vector2 = _portrait_center()
	layer.draw_arc(center, PORTRAIT_RADIUS + 6.5, 0.0, TAU, 56, Color(UiStyle.SHIELD.r, UiStyle.SHIELD.g, UiStyle.SHIELD.b, 0.32), 2.0, true)


func _draw_bar(layer: Control) -> void:
	var bar: Rect2 = _bar_rect()
	layer.draw_rect(bar.grow(2.0), Color(0.01, 0.02, 0.02, 0.95))
	layer.draw_rect(bar, Color(0.1, 0.14, 0.14, 1.0))
	layer.draw_rect(_bar_part(bar, _trail_ratio), Color(1.0, 0.92, 0.75, 0.85))
	var fill_rect: Rect2 = _bar_part(bar, _health_ratio)
	layer.draw_rect(fill_rect, _color.lerp(Color(0.95, 1.0, 0.95), 0.08))
	layer.draw_rect(Rect2(fill_rect.position, Vector2(fill_rect.size.x, BAR_HEIGHT * 0.38)), Color(1, 1, 1, 0.18))
	var segments: int = int(ceil(float(_max_health) / float(HEALTH_SEGMENT)))
	for index in range(1, segments):
		var x: float = bar.position.x + bar.size.x * float(index * HEALTH_SEGMENT) / float(_max_health)
		layer.draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.01, 0.02, 0.02, 0.85), 2.0)


func _draw_bar_danger(layer: Control) -> void:
	layer.draw_rect(_bar_part(_bar_rect(), _health_target), UiStyle.DANGER)


func _draw_ammo(layer: Control) -> void:
	if _player == null:
		return
	var gun: Variant = _player.get_gun()
	if gun == null:
		return
	var max_ammo: int = gun.get_max_ammo()
	var current: int = gun.get_current_ammo()
	var reloading: bool = gun.is_reloading()
	var reload_ratio: float = gun.get_reload_ratio()
	var spacing: float = _ammo_spacing(max_ammo)
	var pip_size: Vector2 = Vector2(minf(9.0, spacing - 2.0), 15.0)
	for index in range(max_ammo):
		var x: float = _mx(CONTENT_LEFT + float(index) * spacing, pip_size.x)
		var loaded: bool = index < current and not reloading
		if reloading:
			loaded = float(index) / float(max_ammo) < reload_ratio
		layer.draw_style_box(_pip_full if loaded else _pip_empty, Rect2(x, AMMO_Y, pip_size.x, pip_size.y))
		if reloading and loaded:
			layer.draw_rect(Rect2(x, AMMO_Y, pip_size.x, pip_size.y), Color(0.0, 0.05, 0.05, 0.4))
	if reloading:
		var strip: float = _ammo_strip_width(max_ammo)
		var meter: Rect2 = Rect2(_mx(CONTENT_LEFT, strip), AMMO_Y + pip_size.y + 3.0, strip, 3.0)
		layer.draw_rect(meter, Color(0.0, 0.03, 0.03, 0.9))
		layer.draw_rect(_bar_part(meter, reload_ratio), UiStyle.ACCENT)


func _draw_status(layer: Control) -> void:
	if _player == null or _status_signature == "":
		return
	var x_offset: float = 0.0
	for effect_name in _player.status_effect_manager.get_active_effect_names():
		var chip_color: Color = UiStyle.TEXT_DIM
		match effect_name:
			&"freeze":
				chip_color = Color(0.55, 0.88, 1.0)
			&"shock":
				chip_color = Color(1.0, 0.92, 0.35)
			&"poison":
				chip_color = Color(0.5, 1.0, 0.45)
		var x: float = _mx(CARD_SIZE.x - CONTENT_RIGHT_PAD - 18.0 - x_offset, 18.0)
		var center: Vector2 = Vector2(x + 9.0, AMMO_Y + 8.0)
		layer.draw_circle(center, 8.0, Color(chip_color.r, chip_color.g, chip_color.b, 0.25), true, -1.0, true)
		layer.draw_arc(center, 8.0, 0.0, TAU, 20, chip_color, 1.5, true)
		layer.draw_string(UiStyle.FONT_BOLD, Vector2(x, AMMO_Y + 12.5), str(effect_name).substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 18.0, 11, chip_color)
		x_offset += 22.0


# --- Helpers ---------------------------------------------------------------------------------------

func _ratio() -> float:
	if _player == null or _player.health_component == null:
		return 0.0
	return clampf(float(_player.health_component.health) / maxf(float(_player.health_component.max_health), 1.0), 0.0, 1.0)


func _card_shape(w: float, h: float) -> PackedVector2Array:
	if mirrored:
		return PackedVector2Array([Vector2(0.0, CUT), Vector2(CUT, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)])
	return PackedVector2Array([Vector2(0.0, 0.0), Vector2(w - CUT, 0.0), Vector2(w, CUT), Vector2(w, h), Vector2(0.0, h)])


func _mx(x: float, width: float = 0.0) -> float:
	return CARD_SIZE.x - x - width if mirrored else x


func _portrait_center() -> Vector2:
	return Vector2(_mx(PORTRAIT_CENTER.x), PORTRAIT_CENTER.y)


func _bar_rect() -> Rect2:
	var bar_width: float = CARD_SIZE.x - CONTENT_LEFT - CONTENT_RIGHT_PAD
	return Rect2(_mx(CONTENT_LEFT, bar_width), BAR_Y, bar_width, BAR_HEIGHT)


func _bar_part(bar: Rect2, ratio: float) -> Rect2:
	var width: float = bar.size.x * clampf(ratio, 0.0, 1.0)
	if mirrored:
		return Rect2(bar.end.x - width, bar.position.y, width, bar.size.y)
	return Rect2(bar.position.x, bar.position.y, width, bar.size.y)


func _ammo_spacing(max_ammo: int) -> float:
	return clampf(150.0 / maxf(float(max_ammo), 1.0), 6.0, 13.0)


func _ammo_strip_width(max_ammo: int) -> float:
	var spacing: float = _ammo_spacing(max_ammo)
	return maxf(float(max_ammo) * spacing - 2.0, 12.0)


func _get_portrait_texture() -> Texture2D:
	var color_id: StringName = _player.player_color_id
	if not GameSettings.is_valid_player_color(color_id):
		color_id = GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if _slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR
	if color_id != _portrait_color:
		_portrait_color = color_id
		var path: String = BODY_TEXTURE_PATH % str(color_id)
		_portrait = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _portrait
