extends CharacterBody2D
class_name Projectile

signal despawn_requested(projectile: Node, reason: StringName, collider)

@export var muzzle_speed: float = GameSettings.PROJECTILE_MUZZLE_SPEED
@export var gravity: float = GameSettings.PROJECTILE_GRAVITY
@export var max_distance: float = GameSettings.PROJECTILE_MAX_DISTANCE
@export var linear_damping: float = GameSettings.PROJECTILE_LINEAR_DAMPING
@export var rotate_to_velocity: bool = GameSettings.PROJECTILE_ROTATE_TO_VELOCITY
@export var damage: int = GameSettings.PROJECTILE_DAMAGE
@export var projectile_scale: float = 1.0
@export var extension_tags: Array[String] = []
@export var extension_effects: Dictionary = {}
@export var source_extensions: Array[String] = []

var net_id: int = 0
var owner_slot: int = 0
var is_network_authority: bool = true
var direction: Vector2 = Vector2.LEFT
var initial_velocity: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _despawn_requested: bool = false
var _bounces_left: int = 0
var _drill_walls_left: int = 0
var _drill_ignore_distance_remaining: float = 0.0
var _drill_visual_timer: float = 0.0
var _drill_clear_distance_remaining: float = 0.0


func configure_from_data(
	network_id: int,
	shot_owner_slot: int,
	shot_direction: Vector2,
	projectile_data: Dictionary,
	authority: bool = true
) -> void:
	net_id = network_id
	owner_slot = shot_owner_slot
	is_network_authority = authority
	direction = _normalized_or_fallback(shot_direction, Vector2.LEFT)
	muzzle_speed = float(projectile_data.get("muzzle_speed", muzzle_speed))
	gravity = float(projectile_data.get("gravity", gravity))
	linear_damping = float(projectile_data.get("linear_damping", linear_damping))
	max_distance = float(projectile_data.get("max_distance", max_distance))
	damage = int(projectile_data.get("damage", damage))
	projectile_scale = float(projectile_data.get("projectile_scale", projectile_scale))
	extension_tags = _string_array_from(projectile_data.get("extension_tags", extension_tags))
	extension_effects = _dictionary_from(projectile_data.get("extension_effects", extension_effects))
	source_extensions = _string_array_from(projectile_data.get("source_extensions", source_extensions))
	initial_velocity = _vector2_from(projectile_data.get("initial_velocity", direction * muzzle_speed), direction * muzzle_speed)


static func extract_shot_directions(projectile_data: Dictionary, fallback_direction: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var directions_variant: Variant = projectile_data.get("volley_directions", [])
	if directions_variant is Array:
		var raw_directions: Array = directions_variant
		for raw_direction in raw_directions:
			if raw_direction is Vector2:
				var shot_direction: Vector2 = raw_direction
				if shot_direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
					result.append(shot_direction.normalized())
	if result.is_empty():
		result.append(_normalized_or_fallback(fallback_direction, Vector2.LEFT))
	return result


func _ready() -> void:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		direction = Vector2.LEFT
	direction = direction.normalized()

	velocity = initial_velocity if initial_velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else direction * muzzle_speed
	_apply_projectile_visual_style()
	_apply_projectile_scale()
	if extension_tags.has("bouncy"):
		_bounces_left = _get_bouncy_bounces()
	if extension_tags.has("drill"):
		_drill_walls_left = _get_drill_wall_passes()
	_update_rotation()


func _physics_process(delta: float) -> void:
	ExtensionBehaviorRegistry.update_projectile_behaviors(self, delta)

	velocity.y += gravity * delta
	if linear_damping > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, linear_damping * delta)
	_update_rotation()

	var motion: Vector2 = velocity * delta
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision != null:
		_distance_travelled += collision.get_travel().length()
		_on_collision(collision)
		_update_drill_visual(delta)
		return

	_distance_travelled += motion.length()
	_update_drill_wall_mask(motion.length())
	_update_drill_visual(delta)
	if _distance_travelled >= max_distance:
		_request_despawn(&"max_distance", null)


func apply_network_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_rotation: Variant = snapshot.get("rotation", rotation)

	if snapshot_position is Vector2:
		global_position = global_position.lerp(snapshot_position, GameSettings.PROJECTILE_SNAPSHOT_INTERPOLATION)
	if snapshot_velocity is Vector2:
		velocity = snapshot_velocity
	if snapshot_rotation is float or snapshot_rotation is int:
		rotation = float(snapshot_rotation)


func _update_rotation() -> void:
	if rotate_to_velocity and velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		rotation = velocity.angle()


func _on_collision(collision: KinematicCollision2D) -> void:
	var collider: Object = collision.get_collider()
	if _is_blocked_by_player(collider):
		var blocking_player: Player = collider as Player
		if blocking_player != null:
			blocking_player.apply_block_feedback(collision.get_position())
		_request_despawn(&"blocked", collider)
		return

	var is_player: bool = collider is Player
	if is_player:
		var hit_player: Player = collider as Player
		if hit_player != null and hit_player.player_slot == owner_slot:
			_request_despawn(&"owner_hit", collider)
			return
		if hit_player != null and hit_player.try_reflect_projectile(self):
			return

	if _should_hover_over_collision(collision, collider):
		_apply_hover_collision_avoidance(collision)
		return

	if _should_drill_through_collision(collider):
		_apply_drill_wall_pass(collision)
		return

	if not is_player and _bounces_left > 0:
		_bounces_left -= 1
		var normal: Vector2 = collision.get_normal()
		velocity = velocity.bounce(normal)
		global_position += normal * maxf(2.0, projectile_scale * 2.5)
		_play_collision_feedback(collision, collider)
		return

	_play_collision_feedback(collision, collider)
	if net_id == 0:
		_apply_local_collision_damage(collider)
		ExtensionEffectRegistry.apply_projectile_effects(collider as Player, self)
	_request_despawn(&"collision", collider)


func _apply_projectile_scale() -> void:
	var safe_scale: float = maxf(projectile_scale, 0.1)
	var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		var scaled_shape: Shape2D = collision_shape.shape.duplicate(true) as Shape2D
		if scaled_shape is CircleShape2D:
			(scaled_shape as CircleShape2D).radius *= safe_scale
		elif scaled_shape is RectangleShape2D:
			(scaled_shape as RectangleShape2D).size *= safe_scale
		collision_shape.shape = scaled_shape

	for child_name in ["Trail", "Outline", "Polygon2D"]:
		var visual: Node2D = get_node_or_null(child_name) as Node2D
		if visual != null:
			visual.scale *= safe_scale


func _apply_projectile_visual_style() -> void:
	var style: Dictionary = _get_projectile_visual_style()
	var body: Polygon2D = get_node_or_null("Polygon2D") as Polygon2D
	var outline: Polygon2D = get_node_or_null("Outline") as Polygon2D
	var trail: CPUParticles2D = get_node_or_null("Trail") as CPUParticles2D

	var body_points: Variant = style.get("body_points", null)
	if body != null:
		body.color = style.get("body_color", body.color)
		if body_points is PackedVector2Array:
			body.polygon = body_points

	var outline_points: Variant = style.get("outline_points", null)
	if outline != null:
		outline.color = style.get("outline_color", outline.color)
		if outline_points is PackedVector2Array:
			outline.polygon = outline_points

	if trail != null:
		trail.color = style.get("trail_color", trail.color)
		trail.amount = int(style.get("trail_amount", trail.amount))
		trail.lifetime = float(style.get("trail_lifetime", trail.lifetime))
		trail.spread = float(style.get("trail_spread", trail.spread))
		trail.scale_amount_min = float(style.get("trail_scale_min", trail.scale_amount_min))
		trail.scale_amount_max = float(style.get("trail_scale_max", trail.scale_amount_max))


func _get_projectile_visual_style() -> Dictionary:
	match _get_visual_extension_id():
		"big_bullets_mk1":
			return _make_projectile_style(
				Color(1.0, 0.52, 0.12, 1.0),
				Color(0.16, 0.055, 0.018, 1.0),
				Color(1.0, 0.32, 0.08, 0.42),
				PackedVector2Array([Vector2(9.0, 0.0), Vector2(1.0, -4.6), Vector2(-6.0, -4.0), Vector2(-8.0, 0.0), Vector2(-6.0, 4.0), Vector2(1.0, 4.6)]),
				PackedVector2Array([Vector2(12.0, 0.0), Vector2(1.5, -6.0), Vector2(-8.6, -5.2), Vector2(-11.0, 0.0), Vector2(-8.6, 5.2), Vector2(1.5, 6.0)]),
				18,
				0.14,
				24.0
			)
		"bouncy_bullets_mk1":
			return _make_projectile_style(
				Color(0.54, 1.0, 0.28, 1.0),
				Color(0.04, 0.12, 0.035, 1.0),
				Color(0.52, 1.0, 0.22, 0.38),
				PackedVector2Array([Vector2(6.2, 0.0), Vector2(3.6, -3.8), Vector2(-1.0, -4.5), Vector2(-5.8, -1.8), Vector2(-5.8, 1.8), Vector2(-1.0, 4.5), Vector2(3.6, 3.8)]),
				PackedVector2Array([Vector2(8.8, 0.0), Vector2(5.1, -5.2), Vector2(-1.4, -6.2), Vector2(-8.2, -2.5), Vector2(-8.2, 2.5), Vector2(-1.4, 6.2), Vector2(5.1, 5.2)]),
				16,
				0.13,
				34.0
			)
		"drill_bullets_mk1":
			return _make_projectile_style(
				Color(0.62, 0.74, 0.86, 1.0),
				Color(0.08, 0.09, 0.12, 1.0),
				Color(0.42, 0.7, 1.0, 0.36),
				PackedVector2Array([Vector2(10.8, 0.0), Vector2(2.0, -2.4), Vector2(-2.2, -3.2), Vector2(-6.0, -1.2), Vector2(-6.0, 1.2), Vector2(-2.2, 3.2), Vector2(2.0, 2.4)]),
				PackedVector2Array([Vector2(13.6, 0.0), Vector2(2.5, -4.1), Vector2(-3.0, -4.9), Vector2(-8.8, -2.2), Vector2(-8.8, 2.2), Vector2(-3.0, 4.9), Vector2(2.5, 4.1)]),
				12,
				0.10,
				8.0
			)
		"explosive_bullet_mk1":
			return _make_projectile_style(
				Color(1.0, 0.2, 0.08, 1.0),
				Color(0.18, 0.025, 0.018, 1.0),
				Color(1.0, 0.2, 0.05, 0.55),
				PackedVector2Array([Vector2(8.2, 0.0), Vector2(1.2, -4.1), Vector2(-4.9, -3.0), Vector2(-6.8, 0.0), Vector2(-4.9, 3.0), Vector2(1.2, 4.1)]),
				PackedVector2Array([Vector2(11.2, 0.0), Vector2(1.7, -5.8), Vector2(-7.0, -4.2), Vector2(-9.8, 0.0), Vector2(-7.0, 4.2), Vector2(1.7, 5.8)]),
				22,
				0.16,
				38.0
			)
		"freeze_rounds_mk1":
			return _make_projectile_style(
				Color(0.46, 0.88, 1.0, 1.0),
				Color(0.035, 0.09, 0.14, 1.0),
				Color(0.36, 0.78, 1.0, 0.44),
				PackedVector2Array([Vector2(8.6, 0.0), Vector2(0.4, -3.4), Vector2(-5.2, 0.0), Vector2(0.4, 3.4)]),
				PackedVector2Array([Vector2(11.5, 0.0), Vector2(0.7, -5.0), Vector2(-8.2, 0.0), Vector2(0.7, 5.0)]),
				16,
				0.15,
				18.0
			)
		"grenades_mk1":
			return _make_projectile_style(
				Color(0.43, 0.72, 0.24, 1.0),
				Color(0.045, 0.085, 0.035, 1.0),
				Color(0.55, 0.9, 0.18, 0.3),
				PackedVector2Array([Vector2(5.5, -2.8), Vector2(5.5, 2.8), Vector2(-4.4, 4.0), Vector2(-7.0, 0.0), Vector2(-4.4, -4.0)]),
				PackedVector2Array([Vector2(8.4, -4.2), Vector2(8.4, 4.2), Vector2(-6.4, 5.6), Vector2(-10.0, 0.0), Vector2(-6.4, -5.6)]),
				10,
				0.11,
				10.0
			)
		"ground_hover_mk1":
			return _make_projectile_style(
				Color(0.28, 0.95, 0.78, 1.0),
				Color(0.025, 0.12, 0.1, 1.0),
				Color(0.25, 0.95, 0.8, 0.34),
				PackedVector2Array([Vector2(7.8, -1.4), Vector2(7.8, 1.4), Vector2(-5.4, 3.2), Vector2(-7.8, 0.0), Vector2(-5.4, -3.2)]),
				PackedVector2Array([Vector2(10.8, -2.5), Vector2(10.8, 2.5), Vector2(-7.8, 4.6), Vector2(-10.8, 0.0), Vector2(-7.8, -4.6)]),
				14,
				0.12,
				12.0
			)
		"heavy_barrel_mk1":
			return _make_projectile_style(
				Color(0.46, 0.48, 0.52, 1.0),
				Color(0.02, 0.023, 0.027, 1.0),
				Color(0.36, 0.34, 0.3, 0.38),
				PackedVector2Array([Vector2(8.6, 0.0), Vector2(-0.4, -4.0), Vector2(-6.8, -2.5), Vector2(-7.8, 0.0), Vector2(-6.8, 2.5), Vector2(-0.4, 4.0)]),
				PackedVector2Array([Vector2(11.6, 0.0), Vector2(-0.5, -5.5), Vector2(-9.4, -3.6), Vector2(-10.6, 0.0), Vector2(-9.4, 3.6), Vector2(-0.5, 5.5)]),
				13,
				0.12,
				9.0
			)
		"kinetic_amplifier_mk1":
			return _make_projectile_style(
				Color(0.96, 0.34, 1.0, 1.0),
				Color(0.12, 0.03, 0.15, 1.0),
				Color(0.9, 0.26, 1.0, 0.46),
				PackedVector2Array([Vector2(10.6, 0.0), Vector2(-0.8, -2.5), Vector2(-5.8, 0.0), Vector2(-0.8, 2.5)]),
				PackedVector2Array([Vector2(13.8, 0.0), Vector2(-1.2, -4.0), Vector2(-8.9, 0.0), Vector2(-1.2, 4.0)]),
				20,
				0.13,
				8.0
			)
		"laser_scope_mk1":
			return _make_projectile_style(
				Color(1.0, 0.16, 0.12, 1.0),
				Color(0.16, 0.02, 0.02, 1.0),
				Color(1.0, 0.1, 0.08, 0.42),
				PackedVector2Array([Vector2(9.8, 0.0), Vector2(-0.8, -2.1), Vector2(-5.6, 0.0), Vector2(-0.8, 2.1)]),
				PackedVector2Array([Vector2(12.8, 0.0), Vector2(-1.0, -3.5), Vector2(-8.2, 0.0), Vector2(-1.0, 3.5)]),
				18,
				0.11,
				6.0
			)
		"lighter_barrel_mk1":
			return _make_projectile_style(
				Color(1.0, 0.88, 0.38, 1.0),
				Color(0.14, 0.095, 0.02, 1.0),
				Color(1.0, 0.82, 0.25, 0.36),
				PackedVector2Array([Vector2(7.2, 0.0), Vector2(-1.0, -2.4), Vector2(-4.8, 0.0), Vector2(-1.0, 2.4)]),
				PackedVector2Array([Vector2(9.6, 0.0), Vector2(-1.5, -3.8), Vector2(-7.2, 0.0), Vector2(-1.5, 3.8)]),
				12,
				0.10,
				12.0
			)
		"multi_barrel_mk1":
			return _make_projectile_style(
				Color(0.82, 0.82, 0.9, 1.0),
				Color(0.05, 0.05, 0.06, 1.0),
				Color(0.72, 0.72, 0.82, 0.34),
				PackedVector2Array([Vector2(8.0, -1.6), Vector2(8.0, 1.6), Vector2(0.2, 2.8), Vector2(-5.2, 1.2), Vector2(-5.2, -1.2), Vector2(0.2, -2.8)]),
				PackedVector2Array([Vector2(10.8, -2.8), Vector2(10.8, 2.8), Vector2(0.0, 4.4), Vector2(-8.0, 2.4), Vector2(-8.0, -2.4), Vector2(0.0, -4.4)]),
				14,
				0.11,
				20.0
			)
		"poison_rounds_mk1":
			return _make_projectile_style(
				Color(0.18, 0.96, 0.28, 1.0),
				Color(0.02, 0.12, 0.025, 1.0),
				Color(0.16, 1.0, 0.22, 0.42),
				PackedVector2Array([Vector2(8.0, 0.0), Vector2(-0.8, -3.5), Vector2(-5.8, -1.6), Vector2(-5.8, 1.6), Vector2(-0.8, 3.5)]),
				PackedVector2Array([Vector2(10.8, 0.0), Vector2(-1.2, -5.0), Vector2(-8.4, -2.5), Vector2(-8.4, 2.5), Vector2(-1.2, 5.0)]),
				18,
				0.15,
				18.0
			)
		"reload_improver_mk1":
			return _make_projectile_style(
				Color(0.96, 0.72, 0.18, 1.0),
				Color(0.13, 0.08, 0.015, 1.0),
				Color(0.96, 0.64, 0.16, 0.34),
				PackedVector2Array([Vector2(8.0, 0.0), Vector2(-1.2, -2.8), Vector2(-5.4, 0.0), Vector2(-1.2, 2.8)]),
				PackedVector2Array([Vector2(10.8, 0.0), Vector2(-1.8, -4.3), Vector2(-8.0, 0.0), Vector2(-1.8, 4.3)]),
				15,
				0.10,
				15.0
			)
		"shocking_rounds_mk1":
			return _make_projectile_style(
				Color(1.0, 0.94, 0.16, 1.0),
				Color(0.14, 0.12, 0.018, 1.0),
				Color(1.0, 0.92, 0.12, 0.48),
				PackedVector2Array([Vector2(8.8, 0.0), Vector2(1.2, -2.8), Vector2(-0.8, -1.0), Vector2(-5.2, -3.6), Vector2(-2.4, 0.0), Vector2(-5.2, 3.6), Vector2(-0.8, 1.0), Vector2(1.2, 2.8)]),
				PackedVector2Array([Vector2(11.6, 0.0), Vector2(1.8, -4.6), Vector2(-1.3, -2.0), Vector2(-8.4, -5.2), Vector2(-4.2, 0.0), Vector2(-8.4, 5.2), Vector2(-1.3, 2.0), Vector2(1.8, 4.6)]),
				22,
				0.12,
				28.0
			)
		"shotgun_mk1":
			return _make_projectile_style(
				Color(0.9, 0.54, 0.28, 1.0),
				Color(0.12, 0.06, 0.025, 1.0),
				Color(0.9, 0.46, 0.22, 0.28),
				PackedVector2Array([Vector2(6.8, 0.0), Vector2(1.2, -3.3), Vector2(-4.8, -2.4), Vector2(-6.2, 0.0), Vector2(-4.8, 2.4), Vector2(1.2, 3.3)]),
				PackedVector2Array([Vector2(9.4, 0.0), Vector2(1.8, -4.8), Vector2(-7.0, -3.6), Vector2(-8.8, 0.0), Vector2(-7.0, 3.6), Vector2(1.8, 4.8)]),
				10,
				0.09,
				30.0
			)
		"sniper_barrel_mk1":
			return _make_projectile_style(
				Color(0.28, 0.64, 1.0, 1.0),
				Color(0.02, 0.06, 0.14, 1.0),
				Color(0.24, 0.55, 1.0, 0.44),
				PackedVector2Array([Vector2(13.0, 0.0), Vector2(-0.8, -1.7), Vector2(-7.2, 0.0), Vector2(-0.8, 1.7)]),
				PackedVector2Array([Vector2(16.4, 0.0), Vector2(-1.2, -3.0), Vector2(-10.6, 0.0), Vector2(-1.2, 3.0)]),
				16,
				0.11,
				5.0
			)
		"standard_scope_mk1":
			return _make_projectile_style(
				Color(0.76, 0.84, 0.9, 1.0),
				Color(0.05, 0.06, 0.07, 1.0),
				Color(0.58, 0.66, 0.72, 0.32),
				PackedVector2Array([Vector2(8.8, 0.0), Vector2(-1.0, -2.7), Vector2(-5.2, 0.0), Vector2(-1.0, 2.7)]),
				PackedVector2Array([Vector2(11.6, 0.0), Vector2(-1.5, -4.2), Vector2(-7.8, 0.0), Vector2(-1.5, 4.2)]),
				14,
				0.11,
				10.0
			)
		"extended_barrel_mk1":
			return _make_projectile_style(
				Color(0.9, 0.9, 0.82, 1.0),
				Color(0.095, 0.095, 0.075, 1.0),
				Color(0.84, 0.8, 0.58, 0.32),
				PackedVector2Array([Vector2(11.2, 0.0), Vector2(-0.4, -2.8), Vector2(-6.8, 0.0), Vector2(-0.4, 2.8)]),
				PackedVector2Array([Vector2(14.6, 0.0), Vector2(-0.7, -4.3), Vector2(-9.8, 0.0), Vector2(-0.7, 4.3)]),
				16,
				0.11,
				7.0
			)
	return _make_projectile_style(
		Color(0.98, 0.38, 0.055, 1.0),
		Color(0.012, 0.014, 0.012, 0.98),
		Color(0.08, 0.055, 0.025, 0.34),
		PackedVector2Array([Vector2(8.4, 0.0), Vector2(-1.2, -2.7), Vector2(-4.7, 0.0), Vector2(-1.2, 2.7)]),
		PackedVector2Array([Vector2(11.5, 0.0), Vector2(-2.0, -4.4), Vector2(-7.2, 0.0), Vector2(-2.0, 4.4)]),
		14,
		0.12,
		14.0
	)


func _get_visual_extension_id() -> String:
	var priority: Array[String] = [
		"big_bullets_mk1",
		"bouncy_bullets_mk1",
		"drill_bullets_mk1",
		"explosive_bullet_mk1",
		"freeze_rounds_mk1",
		"grenades_mk1",
		"poison_rounds_mk1",
		"shocking_rounds_mk1",
		"shotgun_mk1",
		"sniper_barrel_mk1",
		"kinetic_amplifier_mk1",
		"extended_barrel_mk1",
		"heavy_barrel_mk1",
		"lighter_barrel_mk1",
		"multi_barrel_mk1",
		"ground_hover_mk1",
		"laser_scope_mk1",
		"reload_improver_mk1",
		"standard_scope_mk1",
	]
	for extension_id in priority:
		if source_extensions.has(extension_id):
			return extension_id
	return ""


func _make_projectile_style(
	body_color: Color,
	outline_color: Color,
	trail_color: Color,
	body_points: PackedVector2Array,
	outline_points: PackedVector2Array,
	trail_amount: int,
	trail_lifetime: float,
	trail_spread: float
) -> Dictionary:
	return {
		"body_color": body_color,
		"outline_color": outline_color,
		"trail_color": trail_color,
		"body_points": body_points,
		"outline_points": outline_points,
		"trail_amount": trail_amount,
		"trail_lifetime": trail_lifetime,
		"trail_spread": trail_spread,
		"trail_scale_min": 0.2,
		"trail_scale_max": 0.58,
	}


func _get_drill_wall_passes() -> int:
	var drill_variant: Variant = extension_effects.get("drill", {})
	if drill_variant is Dictionary:
		var drill_effect: Dictionary = drill_variant
		return maxi(0, int(roundf(float(drill_effect.get("wall_passes", 1.0)))))
	return 1


func _get_bouncy_bounces() -> int:
	var bouncy_variant: Variant = extension_effects.get("bouncy", {})
	if bouncy_variant is Dictionary:
		var bouncy_effect: Dictionary = bouncy_variant
		return maxi(1, int(roundf(float(bouncy_effect.get("bounces", 1.0)))))
	return 1


func _should_drill_through_collision(collider: Object) -> bool:
	return extension_tags.has("drill") and _drill_walls_left > 0 and not (collider is Player)


func _apply_drill_wall_pass(collision: KinematicCollision2D) -> void:
	_drill_walls_left -= 1
	_drill_ignore_distance_remaining = maxf(_drill_ignore_distance_remaining, 220.0)
	_drill_clear_distance_remaining = maxf(_drill_clear_distance_remaining, 18.0)
	_drill_visual_timer = 0.16
	collision_mask &= ~1
	var forward: Vector2 = velocity.normalized() if velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else direction
	global_position += forward * maxf(6.0, projectile_scale * 6.0)
	_play_collision_feedback(collision, collision.get_collider())


func _update_drill_wall_mask(travel_distance: float) -> void:
	if _drill_ignore_distance_remaining <= 0.0:
		return

	_drill_ignore_distance_remaining = maxf(_drill_ignore_distance_remaining - travel_distance, 0.0)
	_drill_clear_distance_remaining = maxf(_drill_clear_distance_remaining - travel_distance, 0.0)
	if _drill_clear_distance_remaining > 0.0:
		return
	if _drill_ignore_distance_remaining > 0.0 and _is_overlapping_world_obstacle():
		return

	_enable_world_collision_after_drill()


func _enable_world_collision_after_drill() -> void:
	_drill_ignore_distance_remaining = 0.0
	_drill_clear_distance_remaining = 0.0
	collision_mask |= 1


func _is_overlapping_world_obstacle() -> bool:
	var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return false

	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _exit_tree() -> void:
	if _drill_ignore_distance_remaining > 0.0:
		collision_mask |= 1


func _update_drill_visual(delta: float) -> void:
	if _drill_visual_timer > 0.0:
		_drill_visual_timer = maxf(_drill_visual_timer - delta, 0.0)
	if extension_tags.has("drill") and (_drill_visual_timer > 0.0 or _drill_ignore_distance_remaining > 0.0):
		modulate = Color(0.72, 0.86, 1.0, 0.76)
	else:
		modulate = Color.WHITE


func _apply_local_collision_damage(collider: Object) -> void:
	var player: Player = collider as Player
	if player != null:
		var applied_damage: int = player.apply_incoming_damage(damage, owner_slot, global_position)
		_apply_local_life_steal(applied_damage)
		_note_source_damage_dealt(applied_damage)


func _apply_local_life_steal(applied_damage: int) -> void:
	ResearchManager.apply_local_life_steal(owner_slot, applied_damage)


func _note_source_damage_dealt(applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player != null and player.player_slot == owner_slot:
			player.note_damage_dealt(applied_damage)
			return


func _is_blocked_by_player(collider: Object) -> bool:
	var player: Player = collider as Player
	if player == null:
		return false
	return player.is_blocking_projectile(global_position, velocity)


func _request_despawn(reason: StringName, collider: Object) -> void:
	if _despawn_requested:
		return

	_despawn_requested = true
	if is_network_authority:
		despawn_requested.emit(self, reason, collider)
	queue_free()


func _play_collision_feedback(collision: KinematicCollision2D, collider: Object) -> void:
	var collision_position: Vector2 = collision.get_position()
	var impact_direction: Vector2 = collision.get_normal()
	if impact_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED and velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		impact_direction = -velocity.normalized()

	var hit_player: Player = collider as Player
	if hit_player != null:
		return

	GameJuice.spawn_burst(&"impact", collision_position, impact_direction, Color(0.98, 0.55, 0.18, 0.9))
	GameJuice.play_sound_2d(&"impact", collision_position, -7.0, 0.035)
	GameJuice.shake(GameSettings.PROJECTILE_IMPACT_SHAKE_STRENGTH, GameSettings.PROJECTILE_IMPACT_SHAKE_TIME)


func _should_hover_over_collision(collision: KinematicCollision2D, collider: Object) -> bool:
	if not extension_tags.has("hover"):
		return false
	if collider is Player:
		return false
	var normal: Vector2 = collision.get_normal()
	return normal.y <= HoverBehavior.FLOOR_NORMAL_THRESHOLD


func _apply_hover_collision_avoidance(collision: KinematicCollision2D) -> void:
	var normal: Vector2 = collision.get_normal()
	var clearance: float = maxf(8.0, projectile_scale * 5.0)
	global_position += normal * clearance
	velocity = velocity.slide(normal)
	if velocity.y > 0.0:
		velocity.y = 0.0


static func _normalized_or_fallback(value: Vector2, fallback: Vector2) -> Vector2:
	if value.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return value.normalized()
	return fallback.normalized()


static func _vector2_from(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	return fallback


static func _dictionary_from(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _string_array_from(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for raw_value in value:
			result.append(str(raw_value))
	return result
