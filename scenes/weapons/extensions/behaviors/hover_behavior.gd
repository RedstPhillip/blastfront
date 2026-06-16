class_name HoverBehavior
extends ExtensionBehavior

const HOVER_HEIGHT: float = 34.0
const GROUND_DETECTION_DEPTH: float = 96.0
const FLOOR_NORMAL_THRESHOLD: float = -0.5
const HEIGHT_RESPONSE: float = 7.0
const VERTICAL_DAMPING: float = 5.0
const MAX_CORRECTION_SPEED: float = 420.0


func update(projectile: Projectile, delta: float, effect_data: Dictionary = {}) -> void:
	if projectile == null or delta <= 0.0 or not projectile.is_inside_tree():
		return
	projectile.velocity = adjust_velocity_for_ground(
		projectile.global_position,
		projectile.velocity,
		projectile.gravity,
		delta,
		projectile.get_world_2d().direct_space_state,
		[projectile.get_rid()],
		float(effect_data.get("hover_height", HOVER_HEIGHT)),
		float(effect_data.get("detection_depth", GROUND_DETECTION_DEPTH)),
		float(effect_data.get("height_response", HEIGHT_RESPONSE)),
		float(effect_data.get("vertical_damping", VERTICAL_DAMPING)),
		float(effect_data.get("max_correction_speed", MAX_CORRECTION_SPEED))
	)


static func adjust_velocity_for_ground(
	position: Vector2,
	current_velocity: Vector2,
	gravity: float,
	delta: float,
	space_state: PhysicsDirectSpaceState2D,
	exclude: Array[RID] = [],
	hover_height: float = HOVER_HEIGHT,
	detection_depth: float = GROUND_DETECTION_DEPTH,
	height_response: float = HEIGHT_RESPONSE,
	vertical_damping: float = VERTICAL_DAMPING,
	max_correction_speed: float = MAX_CORRECTION_SPEED
) -> Vector2:
	if delta <= 0.0 or space_state == null:
		return current_velocity

	var next_x: float = position.x + current_velocity.x * delta
	var hit: Dictionary = _find_ground_hit(
		position,
		Vector2(next_x, position.y),
		hover_height,
		detection_depth,
		space_state,
		exclude
	)
	if hit.is_empty():
		return current_velocity

	var normal_variant: Variant = hit.get("normal", Vector2.UP)
	var ground_normal: Vector2 = normal_variant as Vector2
	if ground_normal.y > FLOOR_NORMAL_THRESHOLD:
		return current_velocity

	var hit_position_variant: Variant = hit.get("position", position + Vector2.DOWN * detection_depth)
	var ground_position: Vector2 = hit_position_variant as Vector2
	var target_y: float = ground_position.y - hover_height
	var height_error: float = target_y - position.y

	var adjusted_velocity: Vector2 = current_velocity
	var target_vertical_speed: float = clampf(
		height_error * height_response,
		-max_correction_speed,
		max_correction_speed
	)
	adjusted_velocity.y = move_toward(
		current_velocity.y,
		target_vertical_speed - gravity * delta,
		max_correction_speed * delta * vertical_damping
	)
	return adjusted_velocity


static func _find_ground_hit(
	position: Vector2,
	next_position: Vector2,
	hover_height: float,
	detection_depth: float,
	space_state: PhysicsDirectSpaceState2D,
	exclude: Array[RID]
) -> Dictionary:
	var ray_top_offset: float = maxf(hover_height, 18.0)
	var sample_x_positions: Array[float] = [
		position.x,
		lerpf(position.x, next_position.x, 0.5),
		next_position.x,
	]
	var best_hit: Dictionary = {}
	var best_error: float = INF
	for sample_x in sample_x_positions:
		var ray_start: Vector2 = Vector2(sample_x, position.y - ray_top_offset)
		var ray_end: Vector2 = Vector2(sample_x, position.y + detection_depth)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(ray_start, ray_end, 1)
		query.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal_variant: Variant = hit.get("normal", Vector2.UP)
		var ground_normal: Vector2 = normal_variant as Vector2
		if ground_normal.y > FLOOR_NORMAL_THRESHOLD:
			continue
		var hit_position_variant: Variant = hit.get("position", ray_end)
		var ground_position: Vector2 = hit_position_variant as Vector2
		var hover_error: float = absf((ground_position.y - hover_height) - position.y)
		if best_hit.is_empty() or hover_error < best_error:
			best_hit = hit
			best_error = hover_error
	return best_hit
