extends Node2D

@export var upper_len : float = 10.0
@export var lower_len : float = 10.0
@export var line_w    : float = 4.0
@export var col_leg   : Color = Color(0.15, 0.15, 0.15)
@export var col_joint : Color = Color(0.08, 0.08, 0.08)

var _p : RigidBody2D

func _ready() -> void:
	_p = get_parent() as RigidBody2D

func _draw() -> void:
	if not _p: return

	# Werte vom Player holen
	var hip_y = _p.get("hip_y_offset") if "hip_y_offset" in _p else 18.0
	var spread = _p.get("foot_spread") if "foot_spread" in _p else 16.0
	var b_amp = _p.get("bounce_amp") if "bounce_amp" in _p else 0.0
	
	var hip_w : Vector2 = _p.global_position + Vector2(0.0, hip_y).rotated(_p.rotation)
	
	# Zusätzlicher Bounce-Effekt (falls bounce_amp > 0)
	var extra_bounce = sin(_p.bounce_t) * b_amp

	# Beine zeichnen
	_draw_leg(hip_w + Vector2(-spread * 0.45, extra_bounce), _p.foot_pos_l, true)
	_draw_leg(hip_w + Vector2( spread * 0.45, extra_bounce), _p.foot_pos_r, false)

func _draw_leg(hip_w: Vector2, foot_w: Vector2, is_left: bool) -> void:
	var hip  : Vector2 = to_local(hip_w)
	var foot : Vector2 = to_local(foot_w)
	var knee : Vector2 = _two_bone_ik(hip, foot, upper_len, lower_len, is_left)

	draw_line(hip,  knee, col_leg, line_w, true)
	draw_line(knee, foot, col_leg, line_w, true)
	draw_circle(knee, line_w * 0.8, col_joint)
	draw_circle(foot, line_w * 1.4, col_joint)

func _two_bone_ik(hip: Vector2, foot: Vector2, l1: float, l2: float, is_left: bool) -> Vector2:
	var d    : float   = clampf(hip.distance_to(foot), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var a    : float   = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h    : float   = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir  : Vector2 = (foot - hip).normalized()
	var perp : Vector2 = Vector2(-dir.y, dir.x)
	var side : float   = 1.0 if is_left else -1.0
	return hip + dir * a + perp * h * side
