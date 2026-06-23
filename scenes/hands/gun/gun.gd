extends Node2D
class_name Gun

const MUZZLE_WORLD_COLLISION_MASK: int = 1
const MUZZLE_PLAYER_COLLISION_MASK: int = 2
const MUZZLE_WALL_CLEARANCE: float = 6.0
const LASER_MUZZLE_OCCLUSION_EPSILON: float = 1.0

@export var orbit_radius: float = GameSettings.GUN_ORBIT_RADIUS
@export var aim_angle_offset_degrees: float = GameSettings.GUN_AIM_ANGLE_OFFSET_DEGREES
@export var fire_interval: float = GameSettings.GUN_FIRE_INTERVAL
@export var projectile_speed: float = GameSettings.GUN_PROJECTILE_SPEED
@export var projectile_gravity: float = GameSettings.GUN_PROJECTILE_GRAVITY
@export var projectile_linear_damping: float = GameSettings.GUN_PROJECTILE_LINEAR_DAMPING
@export var projectile_max_distance: float = GameSettings.GUN_PROJECTILE_MAX_DISTANCE
@export var max_ammo: int = 3
@export var reload_time: float = 1.2

var _aim_direction: Vector2 = Vector2.LEFT
var _fire_cooldown: float = 0.0
var _recoil_offset: float = 0.0
var _recoil_rotation: float = 0.0
var _extension_stats: Dictionary = {}
var _extension_player_slot: int = -1
var _has_laser_scope: bool = false
var _current_ammo: int = 3
var _is_reloading: bool = false
var _reload_timer: float = 0.0

@onready var _player: Player = get_parent() as Player
@onready var _visual_root: Node2D = $VisualRoot
@onready var _muzzle: Marker2D = $VisualRoot/Muzzle
@onready var _extension_visuals: WeaponExtensionVisuals = $VisualRoot/ExtensionVisuals
@onready var _laser_sight: Line2D = $LaserSight
@onready var _laser_beam: Line2D = $LaserSight/LaserBeam
@onready var _laser_core: Line2D = $LaserSight/LaserCore


func _ready() -> void:
	_connect_extension_inventory()
	_refresh_extension_loadout()
	_reset_ammo()


func _update_laser_sight() -> void:
	if _laser_sight == null:
		return
	if not _can_show_laser_sight():
		_laser_sight.hide()
		return
	_laser_sight.show()
	var direction: Vector2 = get_shot_direction()
	var laser_origin: Vector2 = get_muzzle_global_position()
	if _is_muzzle_occluded(laser_origin, direction):
		_laser_sight.hide()
		return
	_laser_sight.global_position = laser_origin
	_laser_sight.global_rotation = 0.0
	_laser_sight.global_scale = Vector2.ONE
	var trajectory: PackedVector2Array = _build_laser_trajectory(laser_origin, direction)
	_laser_sight.points = trajectory
	if _laser_beam != null:
		_laser_beam.points = trajectory
	if _laser_core != null:
		_laser_core.points = trajectory


func _build_laser_trajectory(world_start: Vector2, direction: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var speed: float = _get_modified_float(&"projectile_speed", projectile_speed, 1.0)
	var gravity_value: float = projectile_gravity + _get_extension_attribute(&"projectile_gravity")
	var extension_tags: Array[String] = _get_extension_tags()
	var linear_damping_value: float = maxf(
		0.0,
		projectile_linear_damping + _get_extension_attribute(&"projectile_linear_damping")
	)
	var max_distance: float = maxf(50.0, projectile_max_distance + _get_extension_attribute(&"projectile_max_distance"))
	var velocity: Vector2 = direction * speed
	var extension_effects: Dictionary = _get_extension_effects()
	var hover_effect_data: Dictionary = _get_effect_data(extension_effects, &"hover")
	var physics_ticks: float = maxf(float(Engine.physics_ticks_per_second), 1.0)
	var step_time: float = 1.0 / physics_ticks
	var local_position: Vector2 = Vector2.ZERO
	var distance_travelled: float = 0.0
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var collision_mask: int = 3
	var drill_wall_passes: int = _get_drill_wall_passes() if extension_tags.has("drill") else 0
	var max_steps: int = ceili(max_distance / maxf(speed * step_time, 1.0)) + 60

	for step_index in range(max_steps):
		if extension_tags.has("hover"):
			velocity = HoverBehavior.adjust_velocity_for_ground(
				world_start + local_position,
				velocity,
				gravity_value,
				step_time,
				space_state,
				[_player.get_rid()],
				float(hover_effect_data.get("hover_height", HoverBehavior.HOVER_HEIGHT)),
				float(hover_effect_data.get("detection_depth", HoverBehavior.GROUND_DETECTION_DEPTH)),
				float(hover_effect_data.get("height_response", HoverBehavior.HEIGHT_RESPONSE)),
				float(hover_effect_data.get("vertical_damping", HoverBehavior.VERTICAL_DAMPING)),
				float(hover_effect_data.get("max_correction_speed", HoverBehavior.MAX_CORRECTION_SPEED))
			)
		velocity.y += gravity_value * step_time
		if linear_damping_value > 0.0:
			velocity = velocity.move_toward(Vector2.ZERO, linear_damping_value * step_time)
		var next_position: Vector2 = local_position + velocity * step_time
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			world_start + local_position,
			world_start + next_position,
			collision_mask
		)
		query.exclude = [_player.get_rid()]
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector2 = hit["position"]
			var collider: Object = hit["collider"]
			if drill_wall_passes > 0 and not (collider is Player):
				drill_wall_passes -= 1
				var hit_local_position: Vector2 = hit_position - world_start
				distance_travelled += (hit_local_position - local_position).length()
				points.append(hit_local_position)
				var skip_distance: float = 96.0
				local_position = hit_local_position + velocity.normalized() * skip_distance
				distance_travelled += skip_distance
				points.append(local_position)
				if distance_travelled >= max_distance:
					break
				continue
			points.append(hit_position - world_start)
			break
		distance_travelled += (next_position - local_position).length()
		points.append(next_position)
		local_position = next_position
		if distance_travelled >= max_distance:
			if points[points.size() - 1] != local_position:
				points.append(local_position)
			break
	return points


func _can_show_laser_sight() -> bool:
	if not _has_laser_scope or _muzzle == null or _player == null:
		return false
	if _player.control_mode != GameSettings.CONTROL_LOCAL:
		return false
	if NetworkSession.is_steam_match_active() and int(_player.player_slot) != NetworkSession.local_player_slot:
		return false
	return true


func _is_muzzle_occluded(muzzle_position: Vector2, direction: Vector2) -> bool:
	var safe_spawn_position: Vector2 = get_projectile_spawn_position(direction)
	return muzzle_position.distance_squared_to(safe_spawn_position) > LASER_MUZZLE_OCCLUSION_EPSILON


func _reset_ammo() -> void:
	_current_ammo = _get_effective_max_ammo()
	_is_reloading = false
	_reload_timer = 0.0


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if _extension_player_slot != int(_player.player_slot):
		_refresh_extension_loadout()

	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_recoil_offset = move_toward(_recoil_offset, 0.0, GameSettings.GUN_RECOIL_RETURN_SPEED * delta)
	_recoil_rotation = lerp_angle(_recoil_rotation, 0.0, clampf(delta * 18.0, 0.0, 1.0))

	var aim_position: Vector2 = _player.get_aim_world_position()
	var aim_vector: Vector2 = aim_position - _player.global_position
	if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		_set_aim_direction(aim_vector)

	_update_visual_transform()
	_update_laser_sight()

	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()

	if _player.is_shoot_pressed() and _fire_cooldown <= 0.0 and _current_ammo > 0 and not _is_reloading:
		_shoot()
		_current_ammo -= 1
		_fire_cooldown = _get_modified_fire_interval()
		if _current_ammo <= 0:
			_start_reload()

func _shoot() -> void:
	var base_direction: Vector2 = get_shot_direction()
	var muzzle_position: Vector2 = get_projectile_spawn_position(base_direction)
	ResearchQuestManager.record_local_action(ResearchQuestManager.EVENT_SHOT)
	_play_fire_feedback(base_direction, muzzle_position)

	var projectile_data: Dictionary = _build_projectile_data(base_direction)
	projectile_data["volley_directions"] = _build_shot_directions(base_direction)
	_fire_projectile(base_direction, muzzle_position, projectile_data)


func _build_shot_directions(base_direction: Vector2) -> Array[Vector2]:
	var directions: Array[Vector2] = []
	var shots: int = maxi(1, int(roundf(1.0 + _get_extension_attribute(&"shots_per_fire"))))
	var spread_degrees: float = maxf(0.0, _get_extension_attribute(&"shot_spread_degrees"))
	var random_spread_degrees: float = maxf(0.0, _get_extension_attribute(&"shot_random_spread_degrees"))
	for shot_index in range(shots):
		var shot_direction: Vector2 = base_direction
		if shots > 1 and spread_degrees > 0.0:
			var ratio: float = (float(shot_index) / float(shots - 1)) - 0.5
			shot_direction = base_direction.rotated(deg_to_rad(spread_degrees * ratio))
		if random_spread_degrees > 0.0:
			shot_direction = shot_direction.rotated(deg_to_rad(randf_range(-random_spread_degrees, random_spread_degrees)))
		directions.append(shot_direction.normalized())
	return directions


func _fire_projectile(direction: Vector2, muzzle_position: Vector2, projectile_data: Dictionary) -> void:
	var world: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null and _player != null:
		world = _player.get_parent()
	if world == null:
		return

	world.request_shot(_player, muzzle_position, direction, projectile_data)


func build_shot_data() -> Dictionary:
	var direction: Vector2 = get_shot_direction()
	return {
		"spawn_position": get_projectile_spawn_position(direction),
		"direction": direction,
		"directions": _build_shot_directions(direction),
		"fire_interval": _get_modified_fire_interval(),
		"projectile": _build_projectile_data(direction),
	}


func get_muzzle_global_position() -> Vector2:
	if _muzzle == null:
		return global_position
	return _muzzle.global_position


func get_projectile_spawn_position(direction: Vector2 = Vector2.ZERO) -> Vector2:
	var muzzle_position: Vector2 = get_muzzle_global_position()
	if _player == null or not is_inside_tree():
		return muzzle_position

	var shot_direction: Vector2 = direction
	if shot_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		shot_direction = get_shot_direction()
	shot_direction = shot_direction.normalized()

	var player_position: Vector2 = _player.global_position
	if player_position.distance_squared_to(muzzle_position) <= 1.0:
		return muzzle_position

	var player_hit_position: Vector2 = _get_player_blocked_spawn_position(player_position, muzzle_position, shot_direction)
	if player_hit_position != Vector2.INF:
		return player_hit_position

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		player_position,
		muzzle_position,
		MUZZLE_WORLD_COLLISION_MASK
	)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return muzzle_position

	var hit_position: Vector2 = hit["position"]
	var player_side: Vector2 = player_position - hit_position
	if player_side.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return hit_position + player_side.normalized() * MUZZLE_WALL_CLEARANCE
	return hit_position - shot_direction * MUZZLE_WALL_CLEARANCE


func _get_player_blocked_spawn_position(player_position: Vector2, muzzle_position: Vector2, shot_direction: Vector2) -> Vector2:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		player_position,
		muzzle_position,
		MUZZLE_PLAYER_COLLISION_MASK
	)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2.INF

	var hit_player: Player = hit["collider"] as Player
	if hit_player == null or hit_player == _player:
		return Vector2.INF

	var hit_position: Vector2 = hit["position"]
	return hit_position - shot_direction * MUZZLE_WALL_CLEARANCE


func get_shot_direction() -> Vector2:
	if _aim_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return Vector2.LEFT
	return _aim_direction.normalized()


func set_aim_direction(direction: Vector2) -> void:
	if _set_aim_direction(direction):
		_update_visual_transform()


func _set_aim_direction(direction: Vector2) -> bool:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return false

	_aim_direction = direction.normalized()
	return true


func _update_visual_transform() -> void:
	if _player == null or _visual_root == null:
		return

	var current_radius: float = maxf(orbit_radius - _recoil_offset, orbit_radius * 0.58)
	global_position = _player.global_position + _aim_direction * current_radius
	global_rotation = _aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees) + _recoil_rotation
	_visual_root.scale.x = 1.0 + _recoil_offset * 0.008
	_visual_root.scale.y = (-1.0 if _aim_direction.x > 0.0 else 1.0) * (1.0 - _recoil_offset * 0.004)


func _build_projectile_data(direction: Vector2) -> Dictionary:
	var muzzle_speed: float = _get_modified_float(&"projectile_speed", projectile_speed, 1.0)
	var gravity: float = projectile_gravity + _get_extension_attribute(&"projectile_gravity")
	var linear_damping: float = maxf(0.0, projectile_linear_damping + _get_extension_attribute(&"projectile_linear_damping"))
	var max_distance: float = maxf(50.0, projectile_max_distance + _get_extension_attribute(&"projectile_max_distance"))
	return {
		"muzzle_speed": muzzle_speed,
		"gravity": gravity,
		"linear_damping": linear_damping,
		"max_distance": max_distance,
		"damage": _get_modified_damage(),
		"projectile_scale": _get_modified_float(&"projectile_scale", 1.0, 0.1),
		"extension_tags": _get_extension_tags(),
		"extension_effects": _get_extension_effects(),
		"source_extensions": _get_source_extensions(),
		"initial_velocity": direction * muzzle_speed,
	}


func _play_fire_feedback(direction: Vector2, muzzle_position: Vector2) -> void:
	_recoil_offset = GameSettings.GUN_RECOIL_DISTANCE
	var recoil_side: float = -1.0 if _aim_direction.x > 0.0 else 1.0
	var recoil_degrees: float = GameSettings.GUN_RECOIL_ROTATION_DEGREES + _get_extension_attribute(&"recoil_rotation_degrees")
	_recoil_rotation = deg_to_rad(maxf(0.0, recoil_degrees)) * recoil_side
	GameJuice.spawn_muzzle(muzzle_position, direction)
	GameJuice.play_sound_2d(&"shoot", muzzle_position, -12.0, 0.06)
	GameJuice.shake(GameSettings.GUN_FIRE_SHAKE_STRENGTH, GameSettings.GUN_FIRE_SHAKE_TIME)


func _start_reload() -> void:
	_is_reloading = true
	_reload_timer = _get_effective_reload_time()


func _finish_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0
	_current_ammo = _get_effective_max_ammo()


func _get_effective_max_ammo() -> int:
	return maxi(1, max_ammo + int(roundf(_get_extension_attribute(&"ammo_max"))))


func _get_effective_reload_time() -> float:
	return maxf(0.1, reload_time + _get_extension_attribute(&"reload_time"))


func get_current_ammo() -> int:
	return _current_ammo


func get_max_ammo() -> int:
	return _get_effective_max_ammo()


func is_reloading() -> bool:
	return _is_reloading


func instant_reload() -> void:
	_finish_reload()


func get_reload_ratio() -> float:
	if not _is_reloading:
		return 1.0
	var reload_duration: float = _get_effective_reload_time()
	return clampf(1.0 - (_reload_timer / reload_duration), 0.0, 1.0)


func apply_remote_ammo_state(current_ammo: int, reloading: bool, reload_ratio: float) -> void:
	_current_ammo = clampi(current_ammo, 0, _get_effective_max_ammo())
	_is_reloading = reloading
	if _is_reloading:
		_reload_timer = (1.0 - clampf(reload_ratio, 0.0, 1.0)) * _get_effective_reload_time()
	else:
		_reload_timer = 0.0


func _connect_extension_inventory() -> void:
	if not ExtensionInventory.loadout_changed.is_connected(_on_extension_loadout_changed):
		ExtensionInventory.loadout_changed.connect(_on_extension_loadout_changed)


func _on_extension_loadout_changed(player_slot: int) -> void:
	if _player == null:
		return
	if player_slot == int(_player.player_slot):
		_refresh_extension_loadout()


func _refresh_extension_loadout() -> void:
	if _player == null:
		return

	_extension_player_slot = int(_player.player_slot)
	_extension_stats = {}

	_extension_stats = ExtensionInventory.build_effective_stats_for_player(_extension_player_slot)

	if _extension_visuals != null:
		_extension_visuals.set_extensions_by_slot(ExtensionInventory.get_equipped_for_player(_extension_player_slot))

	_has_laser_scope = _get_source_extensions().has("laser_scope_mk1")
	if _laser_sight != null:
		_laser_sight.visible = _can_show_laser_sight()

	_reset_ammo()


func _get_modified_fire_interval() -> float:
	return maxf(0.03, fire_interval + _get_extension_attribute(&"fire_interval"))


func _get_modified_float(attribute_name: StringName, base_value: float, minimum_value: float) -> float:
	return maxf(minimum_value, base_value + _get_extension_attribute(attribute_name))


func _get_modified_damage() -> int:
	var damage_value: float = float(GameSettings.PROJECTILE_DAMAGE) + _get_extension_attribute(&"damage")
	if _player != null and _player.health_component != null:
		var health_ratio: float = float(_player.health_component.health) / maxf(float(_player.health_component.max_health), 1.0)
		if health_ratio <= 0.2:
			damage_value *= ResearchManager.get_rage_damage_multiplier(_player.player_slot)
	return maxi(1, int(roundf(damage_value)))


func _get_extension_attribute(attribute_name: StringName) -> float:
	return float(_extension_stats.attributes.get(attribute_name, 0.0))


func _get_extension_tags() -> Array[String]:
	var result: Array[String] = []
	for tag in _extension_stats.projectile_tags:
		var tag_str: String = str(tag)
		if not result.has(tag_str):
			result.append(tag_str)
	return result


func _get_extension_effects() -> Dictionary:
	return _get_balanced_extension_effects(_extension_stats.projectile_effects)


func _get_effect_data(effects: Dictionary, effect_name: StringName) -> Dictionary:
	var effect: Variant = effects.get(effect_name, effects.get(str(effect_name)))
	if effect is Dictionary:
		return effect
	return {}


func _get_balanced_extension_effects(effects: Dictionary) -> Dictionary:
	var balanced_effects: Dictionary = effects.duplicate(true)
	if not _get_source_extensions().has("shotgun_mk1"):
		return balanced_effects

	var poison_variant: Variant = balanced_effects.get("poison", {})
	if not (poison_variant is Dictionary):
		return balanced_effects
	var poison_data: Dictionary = poison_variant
	var base_damage_per_tick: int = int(poison_data.get("damage_per_tick", 0))
	var base_tick_count: int = int(poison_data.get("tick_count", 1))
	poison_data["damage_per_tick"] = clampi(base_damage_per_tick, 0, 8)
	poison_data["tick_count"] = mini(base_tick_count, 3)
	poison_data["duration"] = minf(float(poison_data.get("duration", 3.0)), 3.0)
	balanced_effects["poison"] = poison_data
	return balanced_effects


func _get_drill_wall_passes() -> int:
	var drill: Dictionary = _get_extension_effects().get("drill", {})
	return maxi(0, int(roundf(float(drill.get("wall_passes", 1.0)))))


func _get_source_extensions() -> Array[String]:
	var result: Array[String] = []
	for ext in _extension_stats.source_extensions:
		result.append(str(ext))
	return result
