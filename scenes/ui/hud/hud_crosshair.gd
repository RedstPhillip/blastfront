class_name HudCrosshair
extends Control

## Dynamic reticle at the mouse: recoil bloom, ammo arc, reload ring and hit markers.
## The reticle is a child that is moved to the cursor every frame and only redrawn when its look
## changes. Hides the OS cursor while it is active.

const OUTLINE: Color = Color(0.0, 0.03, 0.03, 0.85)
const RELOAD_STEPS: float = 60.0

var _player: Player = null
var _bloom: float = 0.0
var _hit_marker: float = 0.0
var _hit_heavy: bool = false
var _last_ammo: int = -1
var _enemy_health: Dictionary = {}
var _active: bool = false
var _signature: String = ""
var _reticle: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	add_child(_reticle)


func _exit_tree() -> void:
	_set_cursor_hidden(false)


func _process(delta: float) -> void:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	_player = world.get_local_player() if world != null and world.has_method(&"get_local_player") else null
	var should_show: bool = _player != null and is_instance_valid(_player) and not _player.is_eliminated() and _player.control_mode == GameSettings.CONTROL_LOCAL and not get_tree().paused and is_visible_in_tree()
	if should_show and world.has_method(&"is_match_over") and world.is_match_over():
		should_show = false
	if should_show:
		for modal in get_tree().get_nodes_in_group(&"modal_ui"):
			if modal is CanvasItem and (modal as CanvasItem).is_visible_in_tree():
				should_show = false
				break
	_set_cursor_hidden(should_show or InputDevice.using_gamepad)
	_active = should_show
	_reticle.visible = should_show
	if not should_show:
		return
	if InputDevice.using_gamepad:
		_reticle.position = get_viewport().get_canvas_transform() * _player.get_aim_world_position()
	else:
		_reticle.position = get_local_mouse_position()
	var gun: Variant = _player.get_gun()
	if gun != null:
		var ammo: int = gun.get_current_ammo()
		if _last_ammo >= 0 and ammo < _last_ammo:
			_bloom = 1.0
		_last_ammo = ammo
	_detect_hits()
	_bloom = maxf(_bloom - delta * 5.0, 0.0)
	_hit_marker = maxf(_hit_marker - delta * 4.0, 0.0)
	var signature: String = "%.2f|%.2f|%s" % [_bloom, _hit_marker, _gun_signature(gun)]
	if signature != _signature:
		_signature = signature
		_reticle.queue_redraw()


func _gun_signature(gun: Variant) -> String:
	if gun == null:
		return ""
	var reload_step: int = int(round(gun.get_reload_ratio() * RELOAD_STEPS)) if gun.is_reloading() else -1
	return "%d/%d/%d" % [gun.get_current_ammo(), gun.get_max_ammo(), reload_step]


func _detect_hits() -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var other: Player = node as Player
		if other == null or other == _player or other.health_component == null:
			continue
		var id: int = other.get_instance_id()
		var health: int = other.health_component.health
		if _enemy_health.has(id) and health < int(_enemy_health[id]):
			var damage: int = int(_enemy_health[id]) - health
			_hit_marker = 1.0
			_hit_heavy = health <= 0 or damage >= 40
			AudioDirector.play(&"ui_slider", -2.0, 1.6 if not _hit_heavy else 1.1)
		_enemy_health[id] = health


func _set_cursor_hidden(hidden: bool) -> void:
	var mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN if hidden else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = mode


func _draw_reticle() -> void:
	if not _active or _player == null or not is_instance_valid(_player):
		return
	var gun: Variant = _player.get_gun()
	var gap: float = 7.0 + _bloom * 9.0
	var length: float = 7.0
	var color: Color = Color(1, 1, 1, 0.95)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var from: Vector2 = direction * gap
		var to: Vector2 = direction * (gap + length)
		_reticle.draw_line(from, to, OUTLINE, 4.5, true)
		_reticle.draw_line(from, to, color, 2.0, true)
	_reticle.draw_circle(Vector2.ZERO, 2.4, OUTLINE, true, -1.0, true)
	_reticle.draw_circle(Vector2.ZERO, 1.3, color, true, -1.0, true)

	if gun != null:
		var max_ammo: int = gun.get_max_ammo()
		var current: int = gun.get_current_ammo()
		var radius: float = 22.0
		if gun.is_reloading():
			var ratio: float = gun.get_reload_ratio()
			_reticle.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
			_reticle.draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, 40, UiStyle.ACCENT, 3.0, true)
		else:
			var arc_span: float = deg_to_rad(clampf(float(max_ammo) * 14.0, 28.0, 150.0))
			var start: float = PI * 0.5 + arc_span * 0.5
			for index in range(max_ammo):
				var t: float = 0.5 if max_ammo <= 1 else float(index) / float(max_ammo - 1)
				var angle: float = start - arc_span * t
				var pip: Vector2 = Vector2(cos(angle), sin(angle)) * radius
				_reticle.draw_circle(pip, 3.2, OUTLINE, true, -1.0, true)
				_reticle.draw_circle(pip, 2.1, UiStyle.ACCENT if index < current else Color(0.3, 0.32, 0.3, 0.8), true, -1.0, true)

	if _hit_marker > 0.0:
		var marker_color: Color = Color(1.0, 0.35, 0.3, _hit_marker) if _hit_heavy else Color(1, 1, 1, _hit_marker)
		var inner: float = 9.0 + (1.0 - _hit_marker) * 4.0
		var outer: float = inner + 7.0
		for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var unit: Vector2 = diagonal.normalized()
			_reticle.draw_line(unit * inner, unit * outer, Color(0, 0, 0, 0.7 * _hit_marker), 4.5, true)
			_reticle.draw_line(unit * inner, unit * outer, marker_color, 2.2, true)
