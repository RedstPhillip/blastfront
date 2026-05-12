extends Node2D

@export var upper_len: float = GameSettings.ARM_UPPER_LENGTH
@export var lower_len: float = GameSettings.ARM_LOWER_LENGTH
@export var line_w: float = GameSettings.ARM_LINE_WIDTH
@export var col_arm: Color = GameSettings.DEFAULT_LIMB_COLOR
@export var shoulder_y: float = GameSettings.ARM_SHOULDER_Y
@export var shoulder_spread: float = GameSettings.ARM_SHOULDER_SPREAD
@export var bezier_pts: int = GameSettings.ARM_BEZIER_POINTS
@export var guard_hand_x: float = GameSettings.ARM_GUARD_HAND_X
@export var guard_hand_y: float = GameSettings.ARM_GUARD_HAND_Y
@export var guard_follow_x: float = GameSettings.ARM_GUARD_FOLLOW_X
@export var guard_follow_y: float = GameSettings.ARM_GUARD_FOLLOW_Y
@export var glove_rotation_offset_degrees: float = GameSettings.ARM_GLOVE_ROTATION_OFFSET_DEGREES

var _p: CharacterBody2D
var _gun: Node2D
var _glove: Sprite2D

var _gun_shoulder: Vector2 = Vector2.ZERO
var _gun_hand: Vector2 = Vector2.ZERO
var _gun_elbow: Vector2 = Vector2.ZERO
var _gun_side: float = 1.0

var _guard_shoulder: Vector2 = Vector2.ZERO
var _guard_hand: Vector2 = Vector2.ZERO
var _guard_elbow: Vector2 = Vector2.ZERO
var _guard_side: float = -1.0


func _ready() -> void:
	_p = get_parent() as CharacterBody2D
	if _p != null:
		_gun = _p.get_node_or_null("Gun") as Node2D
	_glove = get_node_or_null("Glove") as Sprite2D

	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

	if _glove != null:
		var glove_mat := CanvasItemMaterial.new()
		glove_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_glove.material = glove_mat


func _process(_delta: float) -> void:
	_update_pose()
	queue_redraw()


func _draw() -> void:
	if _p == null or _gun == null:
		return

	_draw_arm(_gun_shoulder, _gun_elbow, _gun_hand)
	_draw_arm(_guard_shoulder, _guard_elbow, _guard_hand)


func _update_pose() -> void:
	if _p == null or _gun == null:
		if _glove != null:
			_glove.visible = false
		return

	var aim_vector := _gun.global_position - _p.global_position
	var aim_dir := aim_vector.normalized() if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.RIGHT

	_gun_side = 1.0 if _gun.global_position.x >= _p.global_position.x else -1.0
	_guard_side = -_gun_side

	var gun_shoulder_world := _shoulder_world(_gun_side)
	var gun_hand_world := _gun.global_position

	_gun_shoulder = to_local(gun_shoulder_world)
	_gun_hand = to_local(gun_hand_world)
	_gun_hand = _clamp_to_reach(_gun_shoulder, _gun_hand, upper_len + lower_len - GameSettings.LIMB_REACH_MARGIN)
	_gun_elbow = _two_bone_ik(_gun_shoulder, _gun_hand, upper_len, lower_len, _gun_side)

	var guard_shoulder_world := _shoulder_world(_guard_side)
	var guard_hand_world := _guard_hand_world(aim_dir, _guard_side)

	_guard_shoulder = to_local(guard_shoulder_world)
	_guard_hand = to_local(guard_hand_world)
	_guard_hand = _clamp_to_reach(_guard_shoulder, _guard_hand, upper_len + lower_len - GameSettings.LIMB_REACH_MARGIN)
	_guard_elbow = _two_bone_ik(_guard_shoulder, _guard_hand, upper_len, lower_len, _guard_side)

	_update_glove()


func _shoulder_world(side: float) -> Vector2:
	return _p.global_position + Vector2(side * shoulder_spread, shoulder_y).rotated(_p.rotation)


func _guard_hand_world(aim_dir: Vector2, side: float) -> Vector2:
	var local := Vector2(side * guard_hand_x + aim_dir.x * guard_follow_x, guard_hand_y + aim_dir.y * guard_follow_y)
	return _p.global_position + local.rotated(_p.rotation)


func _update_glove() -> void:
	if _glove == null:
		return

	_glove.visible = true
	_glove.position = _guard_hand
	var body_to_guard := _guard_hand - to_local(_p.global_position)
	_glove.rotation = body_to_guard.angle() + deg_to_rad(glove_rotation_offset_degrees)


func _clamp_to_reach(shoulder: Vector2, hand: Vector2, max_dist: float) -> Vector2:
	var v := hand - shoulder
	var d := v.length()
	return shoulder + v / d * max_dist if d > max_dist and d > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else hand


func _draw_arm(shoulder: Vector2, elbow: Vector2, hand: Vector2) -> void:
	_draw_bezier(shoulder, elbow, hand)


func _draw_bezier(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in range(bezier_pts + 1):
		var t := float(i) / bezier_pts
		var mt := 1.0 - t
		pts.append(mt * mt * p0 + 2.0 * mt * t * p1 + t * t * p2)
	draw_polyline(pts, col_arm, line_w, true)


func _two_bone_ik(shoulder: Vector2, hand: Vector2, l1: float, l2: float, side: float) -> Vector2:
	var d := clampf(
		shoulder.distance_to(hand),
		absf(l1 - l2) + GameSettings.IK_MIN_EXTENSION,
		l1 + l2 - GameSettings.IK_MIN_EXTENSION
	)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir := (hand - shoulder).normalized()
	return shoulder + dir * a + Vector2(-dir.y, dir.x) * h * side
