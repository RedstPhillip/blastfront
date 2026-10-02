class_name MenuHero
extends Node2D

## Decorative ball character for menus: idle breathing, legs, a held gun and eyes that follow the cursor.

const BODY_PATH: String = "res://assets/player/body/%s.png"
const BODY_SCALE: float = 0.25

@export var color_id: StringName = &"blue"
@export var facing: float = 1.0
@export var phase: float = 0.0

var _body: Sprite2D = null
var _face: PlayerFace = null
var _gun: Node2D = null
var _time: float = 0.0
var _land: float = 0.0
var _limb_color: Color = Color.WHITE
var _recoil: float = 0.0


func _ready() -> void:
	_limb_color = GameSettings.player_color_value(color_id)
	_gun = Node2D.new()
	_gun.scale = Vector2(0.95, 0.95) * Vector2(1.0, 1.0 if facing > 0.0 else -1.0)
	_gun.z_index = -1
	_gun.draw.connect(func() -> void: WeaponArt.draw_weapon(_gun, Transform2D.IDENTITY, {}, {"accent": _limb_color}))
	add_child(_gun)
	_body = Sprite2D.new()
	_body.texture = load(BODY_PATH % str(color_id))
	_body.scale = Vector2.ONE * BODY_SCALE
	_body.flip_h = facing < 0.0
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://scenes/player/player_body.gdshader")
	_body.material = material
	add_child(_body)
	_face = PlayerFace.new()
	_face.body_sprite = _body
	add_child(_face)
	_time = phase


## Plays a little landing squash, e.g. when the hero drops into the menu.
func land() -> void:
	_land = 1.0


func fire() -> void:
	_recoil = 1.0
	var muzzle: Vector2 = _gun.to_global(WeaponArt.muzzle_position({}))
	GameJuice.spawn_muzzle(muzzle, Vector2(facing, -0.12), Color(1.0, 0.82, 0.38, 1.0), 1.6)


func _process(delta: float) -> void:
	_time += delta
	_land = maxf(_land - delta * 3.0, 0.0)
	_recoil = maxf(_recoil - delta * 5.0, 0.0)
	var breathe: float = sin(_time * 2.2) * 0.02
	var squash: float = sin(_land * PI) * 0.22
	_body.scale = Vector2.ONE * BODY_SCALE * Vector2(1.0 + breathe + squash, 1.0 - breathe - squash)
	_body.position = Vector2(0.0, -sin(_time * 2.2) * 2.0 + squash * 30.0)
	var mouse: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse - global_position
	_face.look_target = to_mouse.normalized() * clampf(to_mouse.length() / 300.0, 0.4, 1.0)
	var aim: Vector2 = Vector2(facing, -0.08 + sin(_time * 1.3 + phase) * 0.05).normalized()
	_gun.position = aim * (86.0 - _recoil * 22.0) + Vector2(0.0, 18.0 + _body.position.y * 0.5)
	_gun.rotation = aim.angle() + (-0.25 * _recoil * facing)
	queue_redraw()


func _draw() -> void:
	var body_y: float = _body.position.y
	var outline: Color = _limb_color.darkened(0.62)
	var hip_l: Vector2 = Vector2(-26.0, 52.0 + body_y)
	var hip_r: Vector2 = Vector2(26.0, 52.0 + body_y)
	var foot_l: Vector2 = Vector2(-44.0, 116.0)
	var foot_r: Vector2 = Vector2(44.0, 116.0)
	var shoulder: Vector2 = Vector2(facing * 34.0, 8.0 + body_y)
	var hand: Vector2 = _gun.position + Vector2(-facing * 4.0, 10.0)
	var elbow: Vector2 = (shoulder + hand) * 0.5 + Vector2(0.0, 26.0)
	var guard_shoulder: Vector2 = Vector2(-facing * 34.0, 8.0 + body_y)
	var guard_hand: Vector2 = Vector2(-facing * 92.0, 34.0 + body_y)
	var guard_elbow: Vector2 = (guard_shoulder + guard_hand) * 0.5 + Vector2(0.0, 24.0)
	for limb in [[hip_l, (hip_l + foot_l) * 0.5 + Vector2(-facing * 12.0, 0.0), foot_l], [hip_r, (hip_r + foot_r) * 0.5 + Vector2(-facing * 12.0, 0.0), foot_r], [shoulder, elbow, hand], [guard_shoulder, guard_elbow, guard_hand]]:
		var points: PackedVector2Array = _bezier(limb[0], limb[1], limb[2])
		draw_polyline(points, outline, 15.0, true)
		draw_circle(limb[2], 13.0, outline, true, -1.0, true)
	for limb in [[hip_l, (hip_l + foot_l) * 0.5 + Vector2(-facing * 12.0, 0.0), foot_l], [hip_r, (hip_r + foot_r) * 0.5 + Vector2(-facing * 12.0, 0.0), foot_r], [shoulder, elbow, hand], [guard_shoulder, guard_elbow, guard_hand]]:
		var points: PackedVector2Array = _bezier(limb[0], limb[1], limb[2])
		draw_polyline(points, _limb_color, 9.0, true)
		draw_circle(limb[2], 9.0, _limb_color.lightened(0.08), true, -1.0, true)


func _bezier(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(13):
		var t: float = float(index) / 12.0
		var mt: float = 1.0 - t
		points.append(mt * mt * a + 2.0 * mt * t * b + t * t * c)
	return points
