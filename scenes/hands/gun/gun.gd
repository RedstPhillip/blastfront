extends Node2D

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

@export var orbit_radius: float = GameSettings.GUN_ORBIT_RADIUS
@export var aim_angle_offset_degrees: float = GameSettings.GUN_AIM_ANGLE_OFFSET_DEGREES
@export var fire_interval: float = GameSettings.GUN_FIRE_INTERVAL
@export var automatic_fire: bool = GameSettings.GUN_AUTOMATIC_FIRE
@export var projectile_speed: float = GameSettings.GUN_PROJECTILE_SPEED
@export var projectile_gravity: float = GameSettings.GUN_PROJECTILE_GRAVITY
@export var projectile_linear_damping: float = GameSettings.GUN_PROJECTILE_LINEAR_DAMPING
@export var projectile_max_distance: float = GameSettings.GUN_PROJECTILE_MAX_DISTANCE

var _aim_direction: Vector2 = Vector2.LEFT
var _pointing_right: bool = false
var _fire_cooldown: float = 0.0
var _recoil_offset: float = 0.0
var _recoil_rotation: float = 0.0
var _extension_stats: Dictionary = {}
var _extension_player_slot: int = -1
var _laser_sight: Line2D = null
var _has_laser_scope: bool = false

@onready var _player: Player = get_parent() as Player
@onready var _visual_root: Node2D = $VisualRoot
@onready var _muzzle: Marker2D = $VisualRoot/Muzzle
@onready var _extension_visuals: WeaponExtensionVisuals = $VisualRoot/ExtensionVisuals


func _ready() -> void:
	_connect_extension_inventory()
	_refresh_extension_loadout()
	_setup_laser_sight()


func _setup_laser_sight() -> void:
	_laser_sight = Line2D.new()
	_laser_sight.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT * 1400])
	_laser_sight.default_color = Color(0.9, 0.2, 0.15, 0.3)
	_laser_sight.width = 1.5
	_laser_sight.antialiased = true
	_laser_sight.hide()
	if _muzzle != null:
		_muzzle.add_child(_laser_sight)
		_laser_sight.owner = _muzzle


func _update_laser_sight() -> void:
	if _laser_sight == null or not _has_laser_scope:
		return
	_laser_sight.show()
	var aim_dir: Vector2 = get_shot_direction()
	var end_pos: Vector2 = aim_dir * 1400
	_laser_sight.set_point_position(1, end_pos)


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

	var wants_shot: bool = _player.is_shoot_down() if automatic_fire else _player.is_shoot_pressed()
	if wants_shot and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = _get_modified_fire_interval()


func _shoot() -> void:
	var base_direction: Vector2 = get_shot_direction()
	var muzzle_position: Vector2 = get_muzzle_global_position()
	_play_fire_feedback(base_direction, muzzle_position)

	var projectile_data: Dictionary = _build_projectile_data(base_direction)
	var shots: int = maxi(1, int(1.0 + _get_extension_attribute(&"shots_per_fire")))
	var spread_degrees: float = _get_extension_attribute(&"shot_spread_degrees")

	for i in range(shots):
		var dir: Vector2 = base_direction
		if shots > 1 and spread_degrees > 0.0:
			var ratio: float = (float(i) / float(shots - 1)) - 0.5
			dir = base_direction.rotated(deg_to_rad(spread_degrees * ratio))
		_fire_projectile(dir, muzzle_position, projectile_data)


func _fire_projectile(direction: Vector2, muzzle_position: Vector2, projectile_data: Dictionary) -> void:
	var world: Node = get_tree().get_first_node_in_group("game_world")
	if world == null:
		world = _player.get_parent()
	if world != null and world.has_method("request_shot"):
		world.request_shot(_player, muzzle_position, direction, projectile_data)
		return

	if world == null or not world.has_method("spawn_projectile"):
		return

	var muzzle_speed: float = float(projectile_data.get("muzzle_speed", projectile_speed))
	var projectile: Node2D = PROJECTILE_SCENE.instantiate() as Node2D
	projectile.set("direction", direction)
	projectile.set("muzzle_speed", muzzle_speed)
	projectile.set("gravity", float(projectile_data.get("gravity", projectile_gravity)))
	projectile.set("linear_damping", float(projectile_data.get("linear_damping", projectile_linear_damping)))
	projectile.set("max_distance", float(projectile_data.get("max_distance", projectile_max_distance)))
	projectile.set("damage", int(projectile_data.get("damage", GameSettings.PROJECTILE_DAMAGE)))
	projectile.set("projectile_scale", float(projectile_data.get("projectile_scale", 1.0)))
	projectile.set("extension_tags", projectile_data.get("extension_tags", []))
	projectile.set("extension_effects", projectile_data.get("extension_effects", {}))
	projectile.set("source_extensions", projectile_data.get("source_extensions", []))
	projectile.set("initial_velocity", projectile_data.get("initial_velocity", direction * muzzle_speed))
	world.spawn_projectile(projectile, muzzle_position)


func build_shot_data() -> Dictionary:
	var direction: Vector2 = get_shot_direction()
	return {
		"spawn_position": get_muzzle_global_position(),
		"direction": direction,
		"fire_interval": _get_modified_fire_interval(),
		"projectile": _build_projectile_data(direction),
	}


func get_muzzle_global_position() -> Vector2:
	if _muzzle == null:
		return global_position
	return _muzzle.global_position


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
	_pointing_right = _aim_direction.x > 0.0
	return true


func _update_visual_transform() -> void:
	if _player == null or _visual_root == null:
		return

	var current_radius: float = maxf(orbit_radius - _recoil_offset, orbit_radius * 0.58)
	global_position = _player.global_position + _aim_direction * current_radius
	global_rotation = _aim_direction.angle() + deg_to_rad(aim_angle_offset_degrees) + _recoil_rotation
	_visual_root.scale.x = 1.0 + _recoil_offset * 0.008
	_visual_root.scale.y = (-1.0 if _pointing_right else 1.0) * (1.0 - _recoil_offset * 0.004)


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
	var recoil_side: float = -1.0 if _pointing_right else 1.0
	var recoil_degrees: float = GameSettings.GUN_RECOIL_ROTATION_DEGREES + _get_extension_attribute(&"recoil_rotation_degrees")
	_recoil_rotation = deg_to_rad(maxf(0.0, recoil_degrees)) * recoil_side
	GameJuice.spawn_muzzle(muzzle_position, direction)
	GameJuice.play_sound_2d(&"shoot", muzzle_position, -12.0, 0.06)
	GameJuice.shake(GameSettings.GUN_FIRE_SHAKE_STRENGTH, GameSettings.GUN_FIRE_SHAKE_TIME)


func _connect_extension_inventory() -> void:
	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null or not inventory_node.has_signal("loadout_changed"):
		return

	var callback: Callable = Callable(self, "_on_extension_loadout_changed")
	if not inventory_node.is_connected("loadout_changed", callback):
		inventory_node.connect("loadout_changed", callback)


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

	var inventory_node: Node = get_node_or_null("/root/ExtensionInventory")
	if inventory_node == null:
		_has_laser_scope = false
		if _laser_sight != null:
			_laser_sight.visible = false
		if _extension_visuals != null:
			_extension_visuals.clear_all()
		return

	if inventory_node.has_method("build_effective_stats_for_player"):
		var stats_variant: Variant = inventory_node.call("build_effective_stats_for_player", _extension_player_slot)
		if stats_variant is Dictionary:
			_extension_stats = stats_variant

	if _extension_visuals != null and inventory_node.has_method("get_equipped_for_player"):
		var equipped_variant: Variant = inventory_node.call("get_equipped_for_player", _extension_player_slot)
		if equipped_variant is Dictionary:
			var equipped: Dictionary = equipped_variant
			_extension_visuals.set_extensions_by_slot(equipped)

	_has_laser_scope = _get_source_extensions().has("laser_scope_mk1")
	if _laser_sight != null:
		_laser_sight.visible = _has_laser_scope


func _get_modified_fire_interval() -> float:
	return maxf(0.03, fire_interval + _get_extension_attribute(&"fire_interval"))


func _get_modified_float(attribute_name: StringName, base_value: float, minimum_value: float) -> float:
	return maxf(minimum_value, base_value + _get_extension_attribute(attribute_name))


func _get_modified_damage() -> int:
	var damage_value: float = float(GameSettings.PROJECTILE_DAMAGE) + _get_extension_attribute(&"damage")
	return maxi(1, int(roundf(damage_value)))


func _get_extension_attribute(attribute_name: StringName) -> float:
	var attributes_variant: Variant = _extension_stats.get("attributes", {})
	if not (attributes_variant is Dictionary):
		return 0.0

	var attributes: Dictionary = attributes_variant
	return float(attributes.get(attribute_name, 0.0))


func _get_extension_tags() -> Array[String]:
	var result: Array[String] = []
	var tags_variant: Variant = _extension_stats.get("projectile_tags", [])
	if not (tags_variant is Array):
		return result

	var tags: Array = tags_variant
	for raw_tag in tags:
		var tag: String = str(raw_tag)
		if not result.has(tag):
			result.append(tag)
	return result


func _get_extension_effects() -> Dictionary:
	var effects_variant: Variant = _extension_stats.get("projectile_effects", {})
	if effects_variant is Dictionary:
		var effects: Dictionary = effects_variant
		return effects.duplicate(true)
	return {}


func _get_source_extensions() -> Array[String]:
	var result: Array[String] = []
	var source_variant: Variant = _extension_stats.get("source_extensions", [])
	if not (source_variant is Array):
		return result

	var source_extensions: Array = source_variant
	for raw_extension_id in source_extensions:
		result.append(str(raw_extension_id))
	return result
