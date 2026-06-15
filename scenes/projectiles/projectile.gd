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
	_apply_projectile_scale()
	if extension_tags.has("bouncy"):
		_bounces_left = 1
	if extension_tags.has("drill"):
		_drill_walls_left = _get_drill_wall_passes()
	_update_rotation()


# Behaviors modify velocity first; gravity, damping and collision run afterward.
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


# Resolve blocking first, then bounces, then damage and impact effects.
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


# Duplicate collision shapes before scaling so scene instances never share mutations.
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


func _get_drill_wall_passes() -> int:
	var drill_variant: Variant = extension_effects.get("drill", {})
	if drill_variant is Dictionary:
		var drill_effect: Dictionary = drill_variant
		return maxi(0, int(roundf(float(drill_effect.get("wall_passes", 1.0)))))
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


# Only authority announces despawns; every peer still frees its local node.
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
