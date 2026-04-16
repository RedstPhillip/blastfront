extends Node2D

@export var upper_len := 13.0
@export var lower_len := 12.0
@export var line_w := 3.0
@export var col_leg: Color = Color8(238, 130, 238, 255)
@export var bezier_pts := 16
@export var knee_smooth := 8.0

var _p: RigidBody2D
var _knee_dir_smoothed := 1.0

func _ready() -> void:
	_p = get_parent() as RigidBody2D
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not _p or not ("foot_pos_l" in _p) or not ("foot_pos_r" in _p):
		return

	var hip_y: float = _p.get("hip_y_offset") if "hip_y_offset" in _p else 18.0
	var spread: float = _p.get("foot_spread") if "foot_spread" in _p else 16.0

	var bt: float = _p.get("bounce_t") if "bounce_t" in _p else 0.0
	var b_amp: float = _p.get("bounce_amp") if "bounce_amp" in _p else 0.0
	var bounce: float = sin(bt) * b_amp

	var vel_x := _p.linear_velocity.x
	var target_knee: float = -signf(vel_x) if absf(vel_x) > 20.0 else -_p.last_dir
	_knee_dir_smoothed = lerp(_knee_dir_smoothed, target_knee, get_process_delta_time() * knee_smooth)

	var hip_w := _p.global_position + Vector2(0.0, hip_y).rotated(_p.rotation)
	var hip_l := to_local(hip_w + Vector2(-spread * 0.4, bounce))
	var hip_r := to_local(hip_w + Vector2(spread * 0.4, bounce))
	var foot_l := to_local(_p.foot_pos_l)
	var foot_r := to_local(_p.foot_pos_r)

	var max_reach := upper_len + lower_len - 0.5
	foot_l = _clamp_to_reach(hip_l, foot_l, max_reach)
	foot_r = _clamp_to_reach(hip_r, foot_r, max_reach)

	_draw_leg(hip_l, foot_l, _knee_dir_smoothed)
	_draw_leg(hip_r, foot_r, _knee_dir_smoothed)

func _clamp_to_reach(hip: Vector2, foot: Vector2, max_dist: float) -> Vector2:
	var v := foot - hip
	var d := v.length()
	return hip + v / d * max_dist if d > max_dist and d > 0.0001 else foot

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
	var d := clampf(hip.distance_to(foot), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir := (foot - hip).normalized()
	return hip + dir * a + Vector2(-dir.y, dir.x) * h * side
