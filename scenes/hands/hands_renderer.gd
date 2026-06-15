extends Node2D
class_name HandsRenderer

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
@export var shield_rotation_offset_degrees: float = GameSettings.ARM_SHIELD_ROTATION_OFFSET_DEGREES
@export var block_hand_distance: float = GameSettings.ARM_BLOCK_HAND_DISTANCE
@export var block_hand_lerp_speed: float = GameSettings.ARM_BLOCK_HAND_LERP_SPEED
@export var player_path: NodePath = NodePath("..")
@export var gun_path: NodePath = NodePath("../Gun")
@export var shield_path: NodePath = NodePath("Shield")
@export var shield_visual_root_path: NodePath = NodePath("Shield/ShieldVisualRoot")

var _p: Player
var _gun: Node2D
var _shield: Sprite2D
var _shield_visual_root: Node2D
var _shield_visual_instance: Node = null

var _gun_shoulder: Vector2 = Vector2.ZERO
var _gun_hand: Vector2 = Vector2.ZERO
var _gun_elbow: Vector2 = Vector2.ZERO
var _gun_side: float = 1.0

var _guard_shoulder: Vector2 = Vector2.ZERO
var _guard_hand: Vector2 = Vector2.ZERO
var _guard_elbow: Vector2 = Vector2.ZERO
var _guard_side: float = -1.0
var _guard_hand_world_current: Vector2 = Vector2.ZERO
var _has_guard_hand_pose: bool = false


func _ready() -> void:
	_p = get_node_or_null(player_path) as Player
	_gun = get_node_or_null(gun_path) as Node2D
	_shield = get_node_or_null(shield_path) as Sprite2D
	_shield_visual_root = get_node_or_null(shield_visual_root_path) as Node2D

	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

	if _shield != null:
		var shield_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		shield_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_shield.material = shield_mat


func set_shield_visual_scene(visual_scene: PackedScene) -> void:
	_clear_shield_visual()
	if _shield == null or _shield_visual_root == null:
		return

	_shield.texture = null
	if visual_scene == null:
		return
	_shield_visual_instance = visual_scene.instantiate()
	_shield_visual_root.add_child(_shield_visual_instance)


func clear_shield_visual_scene() -> void:
	_clear_shield_visual()
	if _shield != null:
		_shield.texture = null


func _process(delta: float) -> void:
	_update_pose(delta)
	queue_redraw()


func _draw() -> void:
	if _p == null or _gun == null:
		return

	_draw_arm(_gun_shoulder, _gun_elbow, _gun_hand)
	_draw_arm(_guard_shoulder, _guard_elbow, _guard_hand)


# Both arms use two-bone IK; the guard hand interpolates to avoid block snapping.
func _update_pose(delta: float) -> void:
	if _p == null or _gun == null:
		if _shield != null:
			_shield.visible = false
		return

	var aim_vector: Vector2 = _gun.global_position - _p.global_position
	var aim_dir: Vector2 = aim_vector.normalized() if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.RIGHT

	_gun_side = 1.0 if _gun.global_position.x >= _p.global_position.x else -1.0
	_guard_side = -_gun_side

	var gun_shoulder_world: Vector2 = _shoulder_world(_gun_side)
	var gun_hand_world: Vector2 = _gun.global_position

	_gun_shoulder = to_local(gun_shoulder_world)
	_gun_hand = to_local(gun_hand_world)
	_gun_hand = _clamp_to_reach(_gun_shoulder, _gun_hand, upper_len + lower_len - GameSettings.LIMB_REACH_MARGIN)
	_gun_elbow = _two_bone_ik(_gun_shoulder, _gun_hand, upper_len, lower_len, _gun_side)

	var guard_shoulder_world: Vector2 = _shoulder_world(_guard_side)
	var guard_hand_world: Vector2 = _get_guard_hand_target_world(aim_dir, _guard_side)
	if not _has_guard_hand_pose:
		_guard_hand_world_current = guard_hand_world
		_has_guard_hand_pose = true
	else:
		var hand_weight: float = clampf(delta * block_hand_lerp_speed, 0.0, 1.0)
		_guard_hand_world_current = _guard_hand_world_current.lerp(guard_hand_world, hand_weight)

	_guard_shoulder = to_local(guard_shoulder_world)
	_guard_hand = to_local(_guard_hand_world_current)
	_guard_hand = _clamp_to_reach(_guard_shoulder, _guard_hand, upper_len + lower_len - GameSettings.LIMB_REACH_MARGIN)
	_guard_elbow = _two_bone_ik(_guard_shoulder, _guard_hand, upper_len, lower_len, _guard_side)

	_update_shield()


func _shoulder_world(side: float) -> Vector2:
	return _p.global_position + Vector2(side * shoulder_spread, shoulder_y).rotated(_p.rotation)


func _guard_hand_world(aim_dir: Vector2, side: float) -> Vector2:
	var local_position: Vector2 = Vector2(side * guard_hand_x + aim_dir.x * guard_follow_x, guard_hand_y + aim_dir.y * guard_follow_y)
	return _p.global_position + local_position.rotated(_p.rotation)


func _get_guard_hand_target_world(aim_dir: Vector2, side: float) -> Vector2:
	var player: Player = _p as Player
	if player != null and player.is_blocking():
		return _p.global_position + player.get_block_direction() * block_hand_distance
	return _guard_hand_world(aim_dir, side)


func _update_shield() -> void:
	if _shield == null:
		return

	_shield.visible = true
	_shield.position = _guard_hand
	var body_to_guard: Vector2 = _guard_hand - to_local(_p.global_position)
	_shield.rotation = body_to_guard.angle() + deg_to_rad(shield_rotation_offset_degrees)
	if _shield_visual_root != null:
		_shield_visual_root.scale = Vector2.ONE
		_shield_visual_root.rotation = PI if _guard_hand.x < 0.0 else 0.0


func _clear_shield_visual() -> void:
	if _shield_visual_instance != null and is_instance_valid(_shield_visual_instance):
		_shield_visual_instance.queue_free()
	_shield_visual_instance = null


func _clamp_to_reach(shoulder: Vector2, hand: Vector2, max_dist: float) -> Vector2:
	var v: Vector2 = hand - shoulder
	var d: float = v.length()
	return shoulder + v / d * max_dist if d > max_dist and d > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else hand


func _draw_arm(shoulder: Vector2, elbow: Vector2, hand: Vector2) -> void:
	_draw_bezier(shoulder, elbow, hand)


func _draw_bezier(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(bezier_pts + 1):
		var t: float = float(i) / bezier_pts
		var mt: float = 1.0 - t
		pts.append(mt * mt * p0 + 2.0 * mt * t * p1 + t * t * p2)
	draw_polyline(pts, col_arm, line_w, true)


# Solve the elbow from two segment lengths and an explicit bend direction.
func _two_bone_ik(shoulder: Vector2, hand: Vector2, l1: float, l2: float, side: float) -> Vector2:
	var d: float = clampf(
		shoulder.distance_to(hand),
		absf(l1 - l2) + GameSettings.IK_MIN_EXTENSION,
		l1 + l2 - GameSettings.IK_MIN_EXTENSION
	)
	var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir: Vector2 = (hand - shoulder).normalized()
	return shoulder + dir * a + Vector2(-dir.y, dir.x) * h * side
