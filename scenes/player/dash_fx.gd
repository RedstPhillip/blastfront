extends Node2D
class_name DashFx

## Afterimages behind a dashing player (the body repeated, tinted towards the team colour and fading out)
## and a pale halo while the dash protects. One node draws them all, so a dash spawns no nodes.

const GHOST_LIFE: float = 0.22
const GHOST_INTERVAL: float = 0.022

var _player: Player = null
var _body: Sprite2D = null
## Each ghost: position, flip, scale, age.
var _ghosts: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _trailing: bool = false


func _ready() -> void:
	top_level = true
	z_index = -1
	_player = get_parent() as Player
	_body = _player.get_node_or_null(^"Sprite2D") as Sprite2D
	set_process(false)


## Leaves ghosts behind the player until stop_trail(); the first one appears at once.
func start_trail() -> void:
	_trailing = true
	_spawn_timer = 0.0
	set_process(true)


func stop_trail() -> void:
	_trailing = false


func _process(delta: float) -> void:
	global_position = Vector2.ZERO
	global_rotation = 0.0
	for ghost in _ghosts:
		ghost["age"] = float(ghost["age"]) + delta
	while not _ghosts.is_empty() and float(_ghosts[0]["age"]) >= GHOST_LIFE:
		_ghosts.pop_front()
	if _trailing and _body != null:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = GHOST_INTERVAL
			_ghosts.append({
				"position": _body.global_position,
				"flip": _body.flip_h,
				"scale": _body.global_scale,
				"age": 0.0,
			})
	queue_redraw()
	if not _trailing and _ghosts.is_empty() and not _player.is_dash_protected():
		set_process(false)


func _draw() -> void:
	if _body == null or _body.texture == null:
		return
	var tint: Color = _player.get_visual_tint().lerp(Color.WHITE, 0.35)
	var size: Vector2 = _body.texture.get_size()
	for ghost in _ghosts:
		var fade: float = 1.0 - float(ghost["age"]) / GHOST_LIFE
		var scale: Vector2 = ghost["scale"]
		if bool(ghost["flip"]):
			scale.x = -scale.x
		draw_set_transform(ghost["position"], 0.0, scale)
		draw_texture(_body.texture, -size * 0.5, Color(tint.r, tint.g, tint.b, 0.42 * fade * fade))
	draw_set_transform(Vector2.ZERO)
	if _player.is_dash_protected():
		# A cool shell round the body: soft glow plus a crisp rim, readable on bright sky and dark rock alike.
		var center: Vector2 = _player.global_position
		var extent: float = 74.0
		draw_texture_rect(FxLib.TEX_GLOW, Rect2(center - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false, Color(0.75, 0.93, 1.0, 0.5))
		draw_arc(center, 21.0, 0.0, TAU, 40, Color(0.04, 0.08, 0.12, 0.45), 4.0, true)
		draw_arc(center, 21.0, 0.0, TAU, 40, Color(0.86, 0.97, 1.0, 0.95), 2.0, true)
