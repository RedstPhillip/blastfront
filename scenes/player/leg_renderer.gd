extends Node2D

@export var upper_len: float = GameSettings.LEG_UPPER_LENGTH
@export var lower_len: float = GameSettings.LEG_LOWER_LENGTH
@export var line_w: float = GameSettings.LEG_LINE_WIDTH
@export var col_leg: Color = GameSettings.DEFAULT_LIMB_COLOR
@export var bezier_pts: int = GameSettings.LEG_BEZIER_POINTS
@export var knee_smooth: float = GameSettings.LEG_KNEE_SMOOTH
@export var wall_hip_x: float = GameSettings.LEG_WALL_HIP_X
@export var wall_foot_x: float = GameSettings.LEG_WALL_FOOT_X
@export var wall_foot_gap: float = GameSettings.LEG_WALL_FOOT_GAP
@export var wall_min_y_velocity: float = GameSettings.LEG_WALL_MIN_Y_VELOCITY

var _p: Player
var _knee_dir_smoothed: float = 1.0
var _last_knee_source_dir: float = 0.0

func _ready() -> void:
	_p = get_parent() as Player
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _p == null:
		return

	var hip_y: float = _p.hip_y_offset - GameSettings.LEG_HIP_OFFSET
	var spread: float = _p.foot_spread
	var bt: float = _p.bounce_t
	var b_amp: float = _p.bounce_amp
	var bounce: float = sin(bt) * b_amp
	var wall_dir: float = _get_wall_dir()
	var wall_active: bool = wall_dir != 0.0

	var knee_source_dir: float = signf(_p.last_dir)
	if knee_source_dir == 0.0:
		knee_source_dir = 1.0
	var target_knee: float = -knee_source_dir
	if wall_active:
		target_knee = wall_dir
		_knee_dir_smoothed = lerpf(
			_knee_dir_smoothed,
			target_knee,
			get_process_delta_time() * knee_smooth * GameSettings.LEG_WALL_KNEE_SMOOTH_MULTIPLIER
		)
	elif _last_knee_source_dir != 0.0 and knee_source_dir != _last_knee_source_dir:
		_knee_dir_smoothed = target_knee
	else:
		_knee_dir_smoothed = lerpf(_knee_dir_smoothed, target_knee, get_process_delta_time() * knee_smooth)
	_last_knee_source_dir = knee_source_dir

	var hip_w: Vector2 = _p.global_position + Vector2(0.0, hip_y).rotated(_p.rotation)
	var hip_l: Vector2 = to_local(hip_w + Vector2(-spread * GameSettings.LEG_HIP_SPREAD_MULTIPLIER, bounce))
	var hip_r: Vector2 = to_local(hip_w + Vector2(spread * GameSettings.LEG_HIP_SPREAD_MULTIPLIER, bounce))

	var foot_l: Vector2 = to_local(_p.foot_pos_l)
	var foot_r: Vector2 = to_local(_p.foot_pos_r)
	if wall_active:
		var foot_y: float = (foot_l.y + foot_r.y) * GameSettings.HALF
		hip_l = Vector2(wall_dir * wall_hip_x, hip_y + wall_foot_gap * 0.25)
		hip_r = Vector2(wall_dir * wall_hip_x, hip_y - wall_foot_gap * 0.25)
		foot_l = Vector2(wall_dir * wall_foot_x, foot_y + wall_foot_gap)
		foot_r = Vector2(wall_dir * wall_foot_x, foot_y - wall_foot_gap)

	var max_reach: float = upper_len + lower_len - GameSettings.LIMB_REACH_MARGIN
	foot_l = _clamp_to_reach(hip_l, foot_l, max_reach)
	foot_r = _clamp_to_reach(hip_r, foot_r, max_reach)

	_draw_leg(hip_l, foot_l, _knee_dir_smoothed)
	_draw_leg(hip_r, foot_r, _knee_dir_smoothed)

func _clamp_to_reach(hip: Vector2, foot: Vector2, max_dist: float) -> Vector2:
	var v := foot - hip
	var d := v.length()
	return hip + v / d * max_dist if d > max_dist and d > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else foot

func _get_wall_dir() -> float:
	if not _p.is_on_wall() or _p.update_grounded() or _p.velocity.y < wall_min_y_velocity:
		return 0.0
	var wall_normal_x: float = _p.get_wall_normal().x
	return -signf(wall_normal_x) if absf(wall_normal_x) > 0.0 else 0.0

func _draw_leg(hip: Vector2, foot: Vector2, side: float) -> void:
	_draw_bezier(hip, _two_bone_ik(hip, foot, upper_len, lower_len, side), foot)

func _draw_bezier(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in range(bezier_pts + 1):
		var t := float(i) / bezier_pts
		var mt := 1.0 - t
		pts.append(mt * mt * p0 + 2.0 * mt * t * p1 + t * t * p2)
	draw_polyline(pts, col_leg, line_w, true)

func _two_bone_ik(hip: Vector2, foot: Vector2, l1: float, l2: float, side: float) -> Vector2:
	var d := clampf(
		hip.distance_to(foot),
		absf(l1 - l2) + GameSettings.IK_MIN_EXTENSION,
		l1 + l2 - GameSettings.IK_MIN_EXTENSION
	)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir := (foot - hip).normalized()
	return hip + dir * a + Vector2(-dir.y, dir.x) * h * side
