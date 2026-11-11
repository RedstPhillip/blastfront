extends CharacterBody2D
class_name Projectile

## One round in flight: gravity, wind, drag and the behaviours of its extensions (bounce, drill, hover,
## seek), hits on players and walls, and the impact feedback. Only the authority applies damage. The higher
## marks' hit traits live here too: damage that grows per bounce / wall passed or with range, shoves and
## staggers on a hit, rounds that chip through a raised shield or drill through it.

signal despawn_requested(projectile: Node, reason: StringName, collider)

## Under water (Tidewater) a round loses most of its speed within a fraction of a second, and every
## pixel it travels there uses up this many pixels of its range, so it fizzles out close to the surface.
const WATER_DRAG: float = 6.0
const WATER_RANGE_COST: float = 8.0
## Which part gives a round its look when it carries several (the first one listed wins).
const VISUAL_PRIORITY: Array[String] = [
	"big_bullets_mk1",
	"fire_rounds_mk1",
	"armor_piercing_mk1",
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
	"homing_mk1",
	"laser_scope_mk1",
	"reload_improver_mk1",
]

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
var _tracer: ProjectileTracer = null
var _head_glow: Sprite2D = null
var _whiz_played: bool = false
var _local_view_player: Player = null
var _wind_response: float = 1.0
var _impact_tint: Color = Color(0.98, 0.55, 0.18, 0.9)
## Speed of the clock this round flies on: its shooter's (Time Control slows both).
var _time_scale: float = 1.0
var _in_water: bool = false
## Damage as fired, before the growth traits (see _apply_growth); bounces and walls passed so far.
var _base_damage: int = 0
var _growth_steps_bounce: int = 0
var _growth_steps_wall: int = 0
var _has_bounced: bool = false
## For the kill cam's record: a small id unique within the session and the look (index into VISUAL_PRIORITY,
## + 1; 0 is the plain round).
var replay_id: int = 0
var visual_style_index: int = 0
static var _replay_serial: int = 0


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
	direction = shot_direction.normalized()
	# Shot data can arrive over the network, where typed arrays come back untyped and keys may be
	# missing; read it defensively so a malformed packet never stops the game.
	muzzle_speed = float(projectile_data.get("muzzle_speed", muzzle_speed))
	gravity = float(projectile_data.get("gravity", gravity))
	linear_damping = float(projectile_data.get("linear_damping", linear_damping))
	max_distance = float(projectile_data.get("max_distance", max_distance))
	damage = int(projectile_data.get("damage", damage))
	projectile_scale = float(projectile_data.get("projectile_scale", projectile_scale))
	extension_tags = _string_array(projectile_data.get("extension_tags", []))
	var effects_variant: Variant = projectile_data.get("extension_effects", {})
	extension_effects = effects_variant if effects_variant is Dictionary else {}
	source_extensions = _string_array(projectile_data.get("source_extensions", []))
	var velocity_variant: Variant = projectile_data.get("initial_velocity", Vector2.ZERO)
	initial_velocity = velocity_variant if velocity_variant is Vector2 else Vector2.ZERO
	# A volley shares one data set; every pellet keeps the speed but flies along its own direction.
	if initial_velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED and direction.length_squared() > 0.0001:
		initial_velocity = direction * initial_velocity.length()


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result


func _ready() -> void:
	if direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		direction = Vector2.LEFT
	direction = direction.normalized()

	velocity = initial_velocity if initial_velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else direction * muzzle_speed
	_replay_serial = (_replay_serial + 1) % 1000000
	replay_id = _replay_serial
	visual_style_index = VISUAL_PRIORITY.find(_get_visual_extension_id()) + 1
	var style: Dictionary = _get_projectile_visual_style()
	if _get_visual_extension_id() != "":
		var body: Color = style["body_color"]
		_impact_tint = Color(body.r, body.g, body.b, 0.9)
	_apply_projectile_visual_style(style)
	_apply_projectile_scale()
	_setup_tracer(style)
	_local_view_player = _find_local_view_player()
	_wind_response = WorldConditions.projectile_wind_response(muzzle_speed, projectile_scale, extension_tags, source_extensions)
	max_distance *= WorldConditions.projectile_range_scale
	if extension_tags.has("bouncy"):
		_bounces_left = _get_bouncy_bounces()
	if extension_tags.has("drill"):
		_drill_walls_left = _get_drill_wall_passes()
	_base_damage = damage
	_update_rotation()


func _physics_process(delta: float) -> void:
	var flow: float = TimeFlow.scale_for(owner_slot)
	if flow != _time_scale:
		_set_time_scale(flow)
	delta *= flow
	ExtensionBehaviorRegistry.update_projectile_behaviors(self, delta)

	velocity.y += gravity * WorldConditions.projectile_gravity_scale * delta
	velocity += WorldConditions.projectile_wind_acceleration(_wind_response) * delta
	if linear_damping > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, linear_damping * delta)
	var in_water: bool = global_position.y > WorldConditions.water_level
	if in_water:
		velocity *= exp(-WATER_DRAG * delta)
		if not _in_water:
			GameJuice.spawn_burst(&"ripple", Vector2(global_position.x, WorldConditions.water_level), Vector2(signf(velocity.x), 0.0), Color.WHITE)
			AudioDirector.play_at(&"splash", global_position, -10.0, 1.4)
	_in_water = in_water
	_update_rotation()

	var motion: Vector2 = velocity * delta
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision != null:
		_distance_travelled += collision.get_travel().length()
		_on_collision(collision)
		_update_drill_visual(delta)
		return

	_distance_travelled += motion.length() * (WATER_RANGE_COST if in_water else 1.0)
	_update_drill_wall_mask(motion.length())
	_update_drill_visual(delta)
	_check_bullet_whiz()
	if _distance_travelled >= max_distance:
		_request_despawn(&"max_distance", null)


func get_wind_response() -> float:
	return _wind_response


func apply_network_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_rotation: Variant = snapshot.get("rotation", rotation)

	if snapshot_position is Vector2:
		# A round frozen in time (Time Control Mk III) takes the host's spot outright, so it hangs in the
		# same place on both screens; moving rounds ease towards it.
		var weight: float = 1.0 if _time_scale <= 0.001 else GameSettings.PROJECTILE_SNAPSHOT_INTERPOLATION
		global_position = global_position.lerp(snapshot_position, weight)
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
		# Drill MK III: a raised shield costs a wall pass and the round carries on into the body.
		if _try_drill_through_shield():
			if blocking_player != null:
				blocking_player.show_trait_callout("SHIELD PIERCED", Color(0.72, 0.86, 1.0, 1.0))
		else:
			if net_id == 0 and blocking_player != null:
				_apply_local_guard_chip(blocking_player)
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
		# A protected dash (Dashing Mk IV): the round flies on through the body.
		if hit_player != null and hit_player.is_dash_protected():
			add_collision_exception_with(hit_player)
			hit_player.play_dash_dodge_feedback()
			global_position += collision.get_remainder()
			return

	if _should_hover_over_collision(collision, collider):
		_apply_hover_collision_avoidance(collision)
		return

	if _should_drill_through_collision(collider):
		_apply_drill_wall_pass(collision)
		_growth_steps_wall += 1
		_apply_growth()
		return

	if not is_player and _bounces_left > 0:
		_bounces_left -= 1
		_has_bounced = true
		_growth_steps_bounce += 1
		_apply_growth()
		# Bouncy Bullets MK III: every bounce sends the round on faster.
		var speed_gain: float = float(get_effect("bouncy").get("speed_gain", 0.0))
		if speed_gain > 0.0:
			velocity *= 1.0 + speed_gain
		var normal: Vector2 = collision.get_normal()
		velocity = velocity.bounce(normal)
		global_position += normal * maxf(2.0, projectile_scale * 2.5)
		_play_collision_feedback(collision, collider)
		return

	if is_player:
		if is_network_authority and KillLog.listener != null:
			KillLog.note_damage(collider as Node, &"round", _kill_note())
		_apply_range_bonus()
		if is_network_authority:
			take_mark_bonus(collider as Player)
		var pierced: Player = collider as Player
		if pierced != null and get_armor_pierce() > 0.0 and pierced.get_armor_reduction() > 0.0:
			pierced.show_trait_callout("ARMOR PIERCED", Color(0.8, 0.86, 0.95, 1.0))
	_play_collision_feedback(collision, collider)
	_play_payload_feedback(collision.get_position())
	if net_id == 0:
		_apply_local_collision_damage(collider)
		_apply_local_impact(collider as Player)
		var marked: Player = collider as Player
		if marked != null and marked.status_effect_manager != null and not get_mark_data().is_empty():
			marked.status_effect_manager.apply_effect(&"marked", get_mark_data())
		ExtensionEffectRegistry.apply_projectile_effects(collider as Player, self)
	_request_despawn(&"collision", collider)


func has_bounced() -> bool:
	return _has_bounced


## What the kill cam needs to name a kill by this round (see KillCam.describe_kill).
func _kill_note() -> Dictionary:
	return {
		"slot": owner_slot,
		"bounced": _has_bounced,
		"walls": _growth_steps_wall,
		"distance": _distance_travelled,
		"extensions": source_extensions.duplicate(),
		"look": _get_visual_extension_id(),
		"round": replay_id,
	}


## Data of one of this round's effects, or {} (keys may arrive as String or StringName over the network).
func get_effect(effect_name: String) -> Dictionary:
	var effect_variant: Variant = extension_effects.get(effect_name, extension_effects.get(StringName(effect_name)))
	return effect_variant if effect_variant is Dictionary else {}


## Bouncy / Drill MK II, Kinetic Amplifier MK III: every bounce or wall passed adds a share of the damage
## as fired (additive, so three bounces at 25% hit for 175%).
func _apply_growth() -> void:
	var growth: Dictionary = get_effect("growth")
	if growth.is_empty():
		return
	var bonus: float = float(growth.get("bounce", 0.0)) * float(_growth_steps_bounce) \
		+ float(growth.get("wall", 0.0)) * float(_growth_steps_wall)
	damage = maxi(1, int(roundf(float(_base_damage) * (1.0 + bonus))))


## Extended Barrel MK III: a hit grows stronger the farther the round flew, up to max_bonus at
## full_distance. Runs on the authority right before the hit is judged.
func _apply_range_bonus() -> void:
	var range_bonus: Dictionary = get_effect("range_bonus")
	if range_bonus.is_empty():
		return
	var full: float = maxf(float(range_bonus.get("full_distance", 900.0)), 1.0)
	var bonus: float = float(range_bonus.get("max_bonus", 0.0)) * clampf(_distance_travelled / full, 0.0, 1.0)
	damage = maxi(1, int(roundf(float(damage) * (1.0 + bonus))))


## The shove a hit with the impact trait gives (Big Bullets, Heavy Barrel, Shotgun, Kinetic): along the
## round's flight, a little upwards. Zero without the trait.
func get_impact_knockback() -> Vector2:
	var impact: Dictionary = get_effect("impact")
	var strength: float = float(impact.get("knockback", 0.0))
	if strength <= 0.0:
		return Vector2.ZERO
	var side: float = signf(velocity.x) if absf(velocity.x) > 1.0 else signf(direction.x)
	if side == 0.0:
		side = 1.0
	return Vector2(side * strength, -strength * 0.45)


## How long a hit with the impact trait stuns (Big Bullets MK III, Sniper Barrel MK II).
func get_impact_stagger() -> float:
	return float(get_effect("impact").get("stagger", 0.0))


## Armor Piercing: the share of the target's armor this round ignores (0 without the part).
func get_armor_pierce() -> float:
	return clampf(float(get_effect("pierce").get("armor", 0.0)), 0.0, 1.0)


## Armor Piercing MK III: the hit is not spread out by delayed armor.
func ignores_delayed_armor() -> bool:
	return float(get_effect("pierce").get("no_delay", 0.0)) > 0.0


## Sniper Barrel MK III: a hit on a target this round's owner marked spends the mark for +bonus damage.
## Runs on the authority right before the hit is judged; the hit then marks the target anew.
func take_mark_bonus(target: Player) -> void:
	var mark: Dictionary = get_effect("mark")
	if mark.is_empty() or target == null or target.player_slot == owner_slot or target.status_effect_manager == null:
		return
	if target.status_effect_manager.take_mark(owner_slot):
		damage = maxi(1, int(roundf(float(damage) * (1.0 + float(mark.get("bonus", 0.0))))))


## The status a hit with the mark trait leaves on its target, or {} without the trait.
func get_mark_data() -> Dictionary:
	var mark: Dictionary = get_effect("mark")
	if mark.is_empty():
		return {}
	return {"duration": float(mark.get("duration", 3.0)), "source_slot": owner_slot, "tint_color": Color(1.0, 0.45, 0.4, 1.0)}


## Damage a raised shield lets through (Heavy Barrel MK II / III), as a share of the round's damage.
func get_guard_chip_damage() -> int:
	var share: float = float(get_effect("guard_chip").get("share", 0.0))
	if share <= 0.0:
		return 0
	return maxi(1, int(roundf(float(damage) * share)))


func _try_drill_through_shield() -> bool:
	if not extension_tags.has("drill") or _drill_walls_left <= 0:
		return false
	if float(get_effect("drill").get("through_shield", 0.0)) <= 0.0:
		return false
	_drill_walls_left -= 1
	_growth_steps_wall += 1
	_apply_growth()
	_drill_visual_timer = 0.16
	return true


func _apply_local_guard_chip(target: Player) -> void:
	var chip: int = get_guard_chip_damage()
	if chip <= 0 or target.player_slot == owner_slot:
		return
	var applied: int = target.apply_incoming_damage(chip, owner_slot, global_position)
	_note_source_damage_dealt(applied)


func _apply_local_impact(target: Player) -> void:
	if target == null or target.player_slot == owner_slot or target.is_eliminated():
		return
	var knockback: Vector2 = get_impact_knockback()
	if knockback != Vector2.ZERO:
		target.receive_hit_knockback(knockback)
	var stagger: float = get_impact_stagger()
	if stagger > 0.0:
		target.apply_stun(stagger)


func _apply_projectile_scale() -> void:
	var safe_scale: float = maxf(projectile_scale, 0.1)
	if is_equal_approx(safe_scale, 1.0):
		return
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


func _apply_projectile_visual_style(style: Dictionary) -> void:
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
		var trail_amount: int = int(style.get("trail_amount", trail.amount))
		if trail.amount != trail_amount:
			trail.amount = trail_amount
		trail.lifetime = float(style.get("trail_lifetime", trail.lifetime))
		trail.spread = float(style.get("trail_spread", trail.spread))
		trail.scale_amount_min = float(style.get("trail_scale_min", trail.scale_amount_min))
		trail.scale_amount_max = float(style.get("trail_scale_max", trail.scale_amount_max))


func _get_projectile_visual_style() -> Dictionary:
	return visual_style_for(_get_visual_extension_id())


## The look of a round led by this extension ("" for the plain round): colours, body and outline shapes, trail.
static func visual_style_for(extension_id: String) -> Dictionary:
	match extension_id:
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
		"armor_piercing_mk1":
			return _make_projectile_style(
				Color(0.78, 0.84, 0.92, 1.0),
				Color(0.06, 0.07, 0.09, 1.0),
				Color(0.6, 0.7, 0.85, 0.36),
				PackedVector2Array([Vector2(11.5, 0.0), Vector2(1.0, -2.0), Vector2(-5.5, -2.0), Vector2(-5.5, 2.0), Vector2(1.0, 2.0)]),
				PackedVector2Array([Vector2(14.5, 0.0), Vector2(1.0, -3.4), Vector2(-8.0, -3.4), Vector2(-8.0, 3.4), Vector2(1.0, 3.4)]),
				14,
				0.10,
				6.0
			)
		"fire_rounds_mk1":
			return _make_projectile_style(
				Color(1.0, 0.5, 0.14, 1.0),
				Color(0.2, 0.04, 0.01, 1.0),
				Color(1.0, 0.35, 0.08, 0.55),
				PackedVector2Array([Vector2(8.4, 0.0), Vector2(1.0, -3.6), Vector2(-5.6, -2.4), Vector2(-7.4, 0.0), Vector2(-5.6, 2.4), Vector2(1.0, 3.6)]),
				PackedVector2Array([Vector2(11.4, 0.0), Vector2(1.4, -5.2), Vector2(-8.2, -3.6), Vector2(-10.6, 0.0), Vector2(-8.2, 3.6), Vector2(1.4, 5.2)]),
				24,
				0.18,
				30.0
			)
		"homing_mk1":
			return _make_projectile_style(
				Color(0.4, 0.92, 1.0, 1.0),
				Color(0.02, 0.1, 0.13, 1.0),
				Color(0.36, 0.85, 1.0, 0.42),
				PackedVector2Array([Vector2(8.6, 0.0), Vector2(-0.6, -3.0), Vector2(-5.4, 0.0), Vector2(-0.6, 3.0)]),
				PackedVector2Array([Vector2(11.6, 0.0), Vector2(-1.0, -4.5), Vector2(-8.0, 0.0), Vector2(-1.0, 4.5)]),
				18,
				0.16,
				14.0
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
	for extension_id in VISUAL_PRIORITY:
		if source_extensions.has(extension_id):
			return extension_id
	return ""


static func _make_projectile_style(
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


func _update_drill_visual(delta: float) -> void:
	if _drill_visual_timer > 0.0:
		_drill_visual_timer = maxf(_drill_visual_timer - delta, 0.0)
	var look: Color = Color.WHITE
	if extension_tags.has("drill") and (_drill_visual_timer > 0.0 or _drill_ignore_distance_remaining > 0.0):
		look = Color(0.72, 0.86, 1.0, 0.76)
	if _time_scale < 1.0:
		look *= Color.WHITE.lerp(TimeFlow.COLOR.lightened(0.3), TimeFlow.strength_of(_time_scale) * 0.75)
	modulate = look


## Slowed rounds trail slowly too, and their glow swells so they read as caught in slowed time. Frozen
## rounds (Mk III) hang where they are with their trail and streak standing still, then fly on.
func _set_time_scale(flow: float) -> void:
	_time_scale = flow
	var trail: CPUParticles2D = get_node_or_null("Trail") as CPUParticles2D
	if trail != null:
		trail.speed_scale = flow
	if _head_glow != null:
		var swell: float = 1.0 + TimeFlow.strength_of(flow) * 0.6 + (0.5 if flow <= 0.001 else 0.0)
		_head_glow.scale = Vector2.ONE * 0.26 * maxf(projectile_scale, 0.7) * swell


func _apply_local_collision_damage(collider: Object) -> void:
	var player: Player = collider as Player
	if player != null:
		var applied_damage: int = player.apply_incoming_damage(damage, owner_slot, global_position, not ignores_delayed_armor(), get_armor_pierce())
		_apply_local_life_steal(applied_damage)
		_note_source_damage_dealt(applied_damage)


func _apply_local_life_steal(applied_damage: int) -> void:
	ResearchManager.apply_local_life_steal(owner_slot, applied_damage)


func _note_source_damage_dealt(applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player.player_slot == owner_slot:
			player.note_damage_dealt()
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
	if reason == &"max_distance":
		GameJuice.spawn_burst(&"run_dust", global_position, -velocity, Color.WHITE)
	_release_tracer()
	queue_free()


func _play_collision_feedback(collision: KinematicCollision2D, collider: Object) -> void:
	var collision_position: Vector2 = collision.get_position()
	var impact_direction: Vector2 = collision.get_normal()
	if impact_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED and velocity.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		impact_direction = -velocity.normalized()

	var hit_player: Player = collider as Player
	if hit_player != null:
		return

	_play_world_impact(collision_position, impact_direction, WorldConditions.is_ice(collider))


## Ice answers a round with shards and a glassy crack instead of soil and sparks.
func _play_world_impact(impact_position: Vector2, normal: Vector2, on_ice: bool = false) -> void:
	if on_ice:
		GameJuice.spawn_burst(&"ice_chip", impact_position, normal, _impact_tint, projectile_scale)
		AudioDirector.play_at(&"step_ice", impact_position, 3.0, 1.35)
	else:
		GameJuice.spawn_burst(&"impact", impact_position, normal, _impact_tint, projectile_scale)
	AudioDirector.play_at(&"impact", impact_position)
	GameJuice.shake(GameSettings.PROJECTILE_IMPACT_SHAKE_STRENGTH, GameSettings.PROJECTILE_IMPACT_SHAKE_TIME)
	ImpactDecals.add_hole(impact_position, normal)


## Explosive and grenade rounds get their blast visuals here on every peer; damage stays authoritative.
func _play_payload_feedback(impact_position: Vector2) -> void:
	var explosive: Variant = extension_effects.get("explosive", extension_effects.get(&"explosive"))
	if explosive is Dictionary:
		var blast_radius: float = float((explosive as Dictionary).get("radius", 80.0))
		GameJuice.spawn_explosion(impact_position, blast_radius)
		# Explosive Bullet MK III: the second blast, shown on every peer.
		if float((explosive as Dictionary).get("aftershock", 0.0)) > 0.0 and is_inside_tree():
			get_tree().create_timer(ExtensionEffectRegistry.AFTERSHOCK_DELAY, false).timeout.connect(
				ExtensionEffectRegistry.show_aftershock.bind(impact_position, owner_slot, blast_radius))
	# Fire Rounds: the ground under the impact catches fire (FirePatch judges the burns where hits are judged).
	var fire: Dictionary = get_effect("fire")
	if not fire.is_empty() and is_inside_tree():
		FirePatch.ignite(get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP), impact_position, owner_slot, fire)
	var grenade: Variant = extension_effects.get("grenade", extension_effects.get(&"grenade"))
	if grenade is Dictionary:
		var fx: GrenadeFx = GrenadeFx.new()
		fx.owner_slot = owner_slot
		fx.fuse = float((grenade as Dictionary).get("delay", 0.5))
		fx.radius = float((grenade as Dictionary).get("radius", 80.0))
		var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
		if world == null:
			return
		world.add_child(fx)
		fx.global_position = impact_position


## Called on clients when the host reports this projectile gone.
func play_remote_despawn_feedback(reason: StringName, despawn_position: Vector2) -> void:
	global_position = despawn_position
	var normal: Vector2 = -velocity.normalized() if velocity.length_squared() > 1.0 else Vector2.UP
	match reason:
		&"collision":
			var hit: bool = false
			for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
				var player: Player = node as Player
				if player != null and not player.is_eliminated() and player.global_position.distance_to(despawn_position) < 30.0:
					hit = true
					break
			if not hit:
				_play_world_impact(despawn_position, normal)
			_play_payload_feedback(despawn_position)
		&"blocked":
			GameJuice.spawn_burst(&"block", despawn_position, normal, Color(0.72, 0.96, 1.0, 0.92))
			AudioDirector.play_at(&"block", despawn_position)
		&"max_distance":
			GameJuice.spawn_burst(&"run_dust", despawn_position, normal, Color.WHITE)
	_release_tracer()


func _setup_tracer(style: Dictionary) -> void:
	var body_color: Color = style["body_color"]
	_tracer = ProjectileTracer.new()
	# Faster rounds draw longer streaks: a sniper shot reads as a line of light, pellets as short sparks.
	var streak: float = clampf(muzzle_speed * 0.085, 60.0, 250.0) + 30.0 * projectile_scale
	_tracer.setup(self, body_color.lightened(0.15), 3.2 * maxf(projectile_scale, 0.6), streak)
	add_child(_tracer)
	_head_glow = Sprite2D.new()
	_head_glow.texture = FxLib.TEX_GLOW
	_head_glow.material = FxLib.additive_material()
	_head_glow.modulate = Color(body_color.r, body_color.g, body_color.b, 0.75)
	_head_glow.scale = Vector2.ONE * 0.26 * maxf(projectile_scale, 0.7)
	_head_glow.z_index = -1
	add_child(_head_glow)


func _release_tracer() -> void:
	if _tracer != null and is_instance_valid(_tracer):
		_tracer.detach()
	_tracer = null


func _find_local_view_player() -> Player:
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null or not world.has_method(&"get_local_player"):
		return null
	return world.get_local_player()


func _check_bullet_whiz() -> void:
	if _whiz_played or _local_view_player == null or not is_instance_valid(_local_view_player):
		return
	if _local_view_player.player_slot == owner_slot or _local_view_player.is_eliminated():
		return
	var distance: float = global_position.distance_to(_local_view_player.global_position)
	if distance < 70.0 and distance > 22.0:
		_whiz_played = true
		AudioDirector.play_at(&"bullet_whiz", global_position)


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
