extends RigidBody2D

# ── Einstellungen ──────────────────────────────────────
@export var move_force : float = 800.0
@export var max_speed  : float = 280.0
@export var jump_force : float = 480.0

@export var hover_dist : float = 55.0  # Wie hoch er schweben soll
@export var spring_str : float = 200.0 # Federhärte
@export var damp_str   : float = 20.0  # Dämpfung (Fix für den Raketen-Bug)

@export var foot_spread: float = 16.0
@export var hip_y_offset: float = 18.0
@export var bounce_amp : float = 2.0

# ── Vom LegRenderer genutzt ────────────────────────────
var foot_pos_l : Vector2
var foot_pos_r : Vector2
var bounce_t   : float = 0.0

@onready var _ray_l : RayCast2D = $RayL
@onready var _ray_r : RayCast2D = $RayR
@onready var _legs  : Node2D    = $LegRenderer


func _ready() -> void:
	foot_pos_l = global_position + Vector2(-foot_spread, hover_dist)
	foot_pos_r = global_position + Vector2( foot_spread, hover_dist)


func _physics_process(delta: float) -> void:
	var hit_l = _ray_l.is_colliding()
	var hit_r = _ray_r.is_colliding()
	var grounded = hit_l or hit_r

	# ── 1. Hover-Physik (Super Kompakt & Sicher) ───────
	if grounded:
		# Den höchsten Punkt des Bodens finden (kleinerer Y-Wert)
		var floor_y = 99999.0
		if hit_l: floor_y = minf(floor_y, _ray_l.get_collision_point().y)
		if hit_r: floor_y = minf(floor_y, _ray_r.get_collision_point().y)

		var dist = floor_y - global_position.y
		if dist < hover_dist:
			var compression = hover_dist - dist
			# Feder drückt nach OBEN (-Y), Dämpfung bremst die aktuelle Geschwindigkeit
			var force_y = (-spring_str * compression) - (damp_str * linear_velocity.y)
			apply_central_force(Vector2(0.0, force_y))

	# ── 2. Movement ────────────────────────────────────
	var dir = Input.get_axis("left", "right")

	if dir != 0:
		apply_central_force(Vector2(dir * move_force, 0))
		linear_velocity.x = clampf(linear_velocity.x, -max_speed, max_speed)
	elif grounded:
		linear_velocity.x = lerp(linear_velocity.x, 0.0, 15.0 * delta)

	if Input.is_action_just_pressed("jump") and grounded:
		linear_velocity.y = -jump_force

	# ── 3. Bein-Logik ───────────
	var hip = global_position + Vector2(0, hip_y_offset).rotated(rotation)

	if grounded and absf(linear_velocity.x) > 10.0:
		# Laufen: Simple Sinus-Wellen (fügt einen organischen Walk-Cycle hinzu)
		bounce_t += delta * 12.0 * (absf(linear_velocity.x) / max_speed)
		
		var stride = sin(bounce_t) * 25.0
		var lift_l = maxf(0, -cos(bounce_t)) * 18.0
		var lift_r = maxf(0,  cos(bounce_t)) * 18.0
		
		foot_pos_l = hip + Vector2(-foot_spread + stride, hover_dist - lift_l)
		foot_pos_r = hip + Vector2( foot_spread - stride, hover_dist - lift_r)
	elif grounded:
		# Stehen: Beine sanft zurück in die Ausgangsposition
		bounce_t = 0.0
		foot_pos_l = foot_pos_l.lerp(hip + Vector2(-foot_spread, hover_dist), delta * 15.0)
		foot_pos_r = foot_pos_r.lerp(hip + Vector2( foot_spread, hover_dist), delta * 15.0)
	else:
		# In der Luft: Beine leicht einklappen
		bounce_t = 0.0
		foot_pos_l = foot_pos_l.lerp(hip + Vector2(-foot_spread * 1.2, hover_dist * 0.5), delta * 10.0)
		foot_pos_r = foot_pos_r.lerp(hip + Vector2( foot_spread * 1.2, hover_dist * 0.5), delta * 10.0)

	# Leichtes Vorbeugen beim Laufen
	rotation = lerp_angle(rotation, dir * 0.1, delta * 10.0)
	
	_legs.queue_redraw()
