extends Node2D

@export var upper_len  : float = 13.0   # ↓ war 22
@export var lower_len  : float = 12.0   # ↓ war 20
@export var line_w     : float = 3.0    # ↓ dünner
@export var col_leg : Color = Color8(238, 130, 238, 255)
@export var bezier_pts : int   = 16

var _p : RigidBody2D

func _ready() -> void:
	_p = get_parent() as RigidBody2D

	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not _p:
		return
	if not ("foot_pos_l" in _p) or not ("foot_pos_r" in _p):
		return

	var hip_y  : float = _p.get("hip_y_offset") if "hip_y_offset" in _p else 18.0
	var spread : float = _p.get("foot_spread")  if "foot_spread"  in _p else 16.0
	var b_amp  : float = _p.get("bounce_amp")   if "bounce_amp"   in _p else 0.0
	var bt     : float = _p.get("bounce_t")     if "bounce_t"     in _p else 0.0
	var bounce : float = sin(bt) * b_amp

	var hip_w : Vector2 = _p.global_position + Vector2(0.0, hip_y).rotated(_p.rotation)
	var hip_l : Vector2 = hip_w + Vector2(-spread * 0.4, bounce)
	var hip_r : Vector2 = hip_w + Vector2( spread * 0.4, bounce)

	var vel_x    : float = _p.linear_velocity.x
	var knee_dir : float = -signf(vel_x) if absf(vel_x) > 20.0 else -1.0

	var hip_l_local  = to_local(hip_l)
	var hip_r_local  = to_local(hip_r)
	var foot_l_local = to_local(_p.foot_pos_l)
	var foot_r_local = to_local(_p.foot_pos_r)

	_draw_leg(hip_l_local, foot_l_local, knee_dir)
	_draw_leg(hip_r_local, foot_r_local, knee_dir)

func _draw_leg(hip: Vector2, foot: Vector2, knee_dir: float) -> void:
	var knee : Vector2 = _two_bone_ik(hip, foot, upper_len, lower_len, knee_dir)

	_draw_bezier(hip, knee, foot)

func _draw_bezier(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var points := PackedVector2Array()
	for i in range(bezier_pts + 1):
		var t  : float   = float(i) / float(bezier_pts)
		var mt : float   = 1.0 - t
		var pt : Vector2 = mt * mt * p0 + 2.0 * mt * t * p1 + t * t * p2
		points.append(pt)

	draw_polyline(points, col_leg, line_w, true)

func _two_bone_ik(hip: Vector2, foot: Vector2, l1: float, l2: float, side: float) -> Vector2:
	var d    : float   = clampf(hip.distance_to(foot), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var a    : float   = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h    : float   = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir  : Vector2 = (foot - hip).normalized()
	var perp : Vector2 = Vector2(-dir.y, dir.x)
	return hip + dir * a + perp * h * side
