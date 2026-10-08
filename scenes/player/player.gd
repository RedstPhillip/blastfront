extends CharacterBody2D
class_name Player

## One fighter: movement (the State children run it), aim, block, ammo through its Gun, health, armor and
## research effects, and all body feedback. Driven by local input, a BotBrain or network snapshots.

const DEFAULT_BODY_TEXTURE: Texture2D = preload("res://assets/player/body/blue.png")
const BODY_SHADER: Shader = preload("res://scenes/player/player_body.gdshader")
const BODY_TEXTURE_PATH: String = "res://assets/player/body/%s.png"
const LOW_HEALTH_RATIO: float = 0.3
const WALL_SLIDE_FEEDBACK_INTERVAL: float = 0.09

const HEALING_AREA_SEGMENTS: int = 72
const HEALING_AREA_FILL_COLOR: Color = Color(0.0, 0.95, 0.38, 0.24)
const HEALING_AREA_RING_COLOR: Color = Color(0.0, 0.78, 0.22, 0.96)
## Share of the wind speed that turns into drift on the ground and in the air (Mars storms).
const WIND_GROUND_SHARE: float = 0.3
const WIND_AIR_SHARE: float = 0.62
## Seconds a Time Control slow takes to settle in and to wear off, so the change reads instead of snapping.
const TIME_RAMP_SECONDS: float = 0.18

static var _body_texture_cache: Dictionary = {}
static var _body_texture_exists_cache: Dictionary = {}

@export var gravity: float = GameSettings.PLAYER_GRAVITY
@export var wall_slide_speed: float = GameSettings.PLAYER_WALL_SLIDE_SPEED
@export var air_speed: float = GameSettings.PLAYER_AIR_SPEED
@export var speed: float = GameSettings.PLAYER_SPEED
@export var ground_acceleration: float = GameSettings.PLAYER_GROUND_ACCELERATION
@export var ground_friction: float = GameSettings.PLAYER_GROUND_FRICTION
@export var air_acceleration: float = GameSettings.PLAYER_AIR_ACCELERATION
@export var air_friction: float = GameSettings.PLAYER_AIR_FRICTION
@export var fall_gravity_multiplier: float = GameSettings.PLAYER_FALL_GRAVITY_MULTIPLIER
@export var low_jump_gravity_multiplier: float = GameSettings.PLAYER_LOW_JUMP_GRAVITY_MULTIPLIER
@export var jump_velocity: float = GameSettings.PLAYER_JUMP_VELOCITY
@export var coyote_time: float = GameSettings.PLAYER_COYOTE_TIME
@export var jump_buffer_time: float = GameSettings.PLAYER_JUMP_BUFFER_TIME
@export var wall_coyote_time: float = GameSettings.PLAYER_WALL_COYOTE_TIME
@export var max_fall_speed: float = GameSettings.PLAYER_MAX_FALL_SPEED
@export var wall_jump_velocity: Vector2 = GameSettings.PLAYER_WALL_JUMP_VELOCITY
@export var hover_dist: float = GameSettings.PLAYER_HOVER_DISTANCE
@export var hover_snap_speed: float = GameSettings.PLAYER_HOVER_SNAP_SPEED
@export var foot_spread: float = GameSettings.PLAYER_FOOT_SPREAD
@export var hip_y_offset: float = GameSettings.PLAYER_HIP_Y_OFFSET
@export var bounce_amp: float = GameSettings.PLAYER_BOUNCE_AMPLITUDE

@export var look_ahead: float = GameSettings.PLAYER_LOOK_AHEAD
@export var step_trigger: float = GameSettings.PLAYER_STEP_TRIGGER
@export var step_duration: float = GameSettings.PLAYER_STEP_DURATION
@export var step_arc_h: float = GameSettings.PLAYER_STEP_ARC_HEIGHT
@export var stride_min_interval: float = GameSettings.PLAYER_STRIDE_MIN_INTERVAL

@export var air_foot_tuck_x: float = GameSettings.PLAYER_AIR_FOOT_TUCK_X
@export var air_foot_tuck_y: float = GameSettings.PLAYER_AIR_FOOT_TUCK_Y

@export var remote_interpolation_speed: float = GameSettings.PLAYER_REMOTE_INTERPOLATION_SPEED
@export var block_duration: float = GameSettings.PLAYER_BLOCK_DURATION
@export var block_cooldown: float = GameSettings.PLAYER_BLOCK_COOLDOWN
@export var block_cone_degrees: float = GameSettings.PLAYER_BLOCK_CONE_DEGREES

var player_slot: int = 0
var control_mode: StringName = GameSettings.CONTROL_LOCAL
var move_left_action: StringName = GameSettings.INPUT_P1_MOVE_LEFT
var move_right_action: StringName = GameSettings.INPUT_P1_MOVE_RIGHT
var jump_action: StringName = GameSettings.INPUT_P1_JUMP
var shoot_action: StringName = GameSettings.INPUT_P1_SHOOT
var block_action: StringName = GameSettings.INPUT_P1_BLOCK
var reload_action: StringName = GameSettings.INPUT_P1_RELOAD
var time_control_action: StringName = GameSettings.INPUT_P1_TIME_CONTROL
var shooting_enabled: bool = true
var movement_enabled: bool = true
var player_color_id: StringName = &""

var foot_pos_l: Vector2
var foot_pos_r: Vector2
var bounce_t: float = 0.0
var last_dir: float = 1.0
var _last_visual_move_dir: float = 0.0
var _was_visual_grounded: bool = false

var _network_target_position: Vector2 = Vector2.ZERO
var _network_target_velocity: Vector2 = Vector2.ZERO
var _network_aim_world_position: Vector2 = Vector2.ZERO
var _has_network_target: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _block_buffer_timer: float = 0.0
var _wall_coyote_timer: float = 0.0
var _wall_coyote_dir: float = 0.0
var _step_clock: float = 0.0
var _last_stepped: int = 1
var _last_step_time_l: float = GameSettings.PLAYER_INITIAL_STEP_TIME
var _last_step_time_r: float = GameSettings.PLAYER_INITIAL_STEP_TIME
var _step_from_l: Vector2 = Vector2.ZERO
var _step_to_l: Vector2 = Vector2.ZERO
var _step_t_l: float = 1.0
var _step_from_r: Vector2 = Vector2.ZERO
var _step_to_r: Vector2 = Vector2.ZERO
var _step_t_r: float = 1.0
var _can_shoot_when_controls_enabled: bool = true
var _body_base_scale: Vector2 = Vector2.ONE
var _body_motion_scale: Vector2 = Vector2.ONE
var _body_punch_scale: Vector2 = Vector2.ONE
var _hit_flash_timer: float = 0.0
var _hit_feedback_guard_timer: float = 0.0
## How much of the wind reaches the player (terrain upwind gives shelter; Mars storms).
var _wind_exposure: float = 1.0
## Hits landing in the same frame (shotgun pellets, multi-barrel volleys, splash) are gathered here and
## played as one combined hit at the end of the frame: one burst, one sound, one shove sized by the total.
var _pending_hit_damage: int = 0
var _pending_hit_count: int = 0
var _pending_hit_direction: Vector2 = Vector2.ZERO
var _run_dust_timer: float = 0.0
var _step_sound_timer: float = 0.0
var _last_feedback_grounded: bool = false
var _last_feedback_velocity_y: float = 0.0
var _idle_visual_time: float = 0.0
var _is_eliminated: bool = false
var _default_collision_layer: int = 0
var _default_collision_mask: int = 0
var _block_active: bool = false
var _block_timer: float = 0.0
var _block_cooldown_timer: float = 0.0
var _block_direction: Vector2 = Vector2.LEFT
var _remote_block_state_initialized: bool = false
var _stun_timer: float = 0.0
var _status_fx_timer: float = 0.0
var _status_fx_phase: float = 0.0
var _passive_heal_progress: float = 0.0
var _phoenix_used: bool = false
var _armor_attributes: Dictionary = {}
var _base_speed: float = GameSettings.PLAYER_SPEED
var _base_air_speed: float = GameSettings.PLAYER_AIR_SPEED
var _base_jump_velocity: float = GameSettings.PLAYER_JUMP_VELOCITY
var _external_launch: bool = false
var _base_wall_jump_velocity: Vector2 = GameSettings.PLAYER_WALL_JUMP_VELOCITY
var _base_block_duration: float = GameSettings.PLAYER_BLOCK_DURATION
var _base_block_cooldown: float = GameSettings.PLAYER_BLOCK_COOLDOWN
var _base_block_cone_degrees: float = GameSettings.PLAYER_BLOCK_CONE_DEGREES
var _base_max_health: int = GameSettings.DEFAULT_MAX_HEALTH
var _adrenaline_timer: float = 0.0
var _healing_field_progress: float = 0.0
var _healing_field_timer: float = 0.0
var _healing_field_radius: float = 0.0
var _healing_field_rate: float = 0.0
var _healing_field_position: Vector2 = Vector2.ZERO
var _healing_field_has_position: bool = false
var _healing_area_visual_radius: float = 0.0
var _healing_area_visual_phase: float = 0.0
var _frosty_aura_timer: float = 0.0
var _face: PlayerFace = null
var _halo: Sprite2D = null
var _body_material: ShaderMaterial = null
var _wall_slide_timer: float = 0.0
var ai_brain: BotBrain = null
## How fast this player's own clock runs (Time Control): movement, gun, block and bot thinking advance by
## delta * time_scale, and TimeFlow hands the same value to the rounds they fired. 1 is normal time.
var time_scale: float = 1.0
var _time_slow_scale: float = 1.0
var _time_slow_timer: float = 0.0
var _time_slow_duration: float = 0.0
var _time_control_cooldown: float = 0.0
var _time_control_cooldown_total: float = 0.0
## While this player's own cast holds the opponent slowed (drives the HUD dial).
var _time_control_active_timer: float = 0.0
var _time_control_active_total: float = 0.0
## Colour the body sprite currently shows (texture + base modulate are only swapped when it changes) and
## the last values pushed to the body shader, so idle frames do not re-set unchanged uniforms.
var _body_color_id: StringName = &""
var _shader_flash: float = -1.0
var _shader_status: float = -1.0

@onready var _healing_area: Node2D = $HealingArea
@onready var _healing_area_fill: Polygon2D = $HealingArea/Fill
@onready var _healing_area_ring: Line2D = $HealingArea/Ring
@onready var _body_sprite: Sprite2D = $Sprite2D
@onready var _shield: Sprite2D = $ArmRenderer/Shield
@onready var _armor_visual_root: ArmorVisualRoot = $ArmorVisualRoot
@onready var _leg_renderer: Node = $LegRenderer
@onready var _arm_renderer: Node = $ArmRenderer
@onready var _gun: Gun = $Gun
@onready var _ray_l: RayCast2D = $RayL
@onready var _ray_r: RayCast2D = $RayR
@onready var _state_machine: StateMachine = $State
@onready var health_component: HealthComponent = $HealthComponent
@onready var status_effect_manager: StatusEffectManager = $StatusEffectManager


func _ready() -> void:
	_capture_base_stats()
	if _healing_area != null:
		_healing_area.top_level = true
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_body_base_scale = _body_sprite.scale
	_setup_visual_extras()
	_update_ground_rays()
	_initialize_feet()
	_network_target_position = global_position
	_network_aim_world_position = global_position + Vector2.LEFT * GameSettings.PLAYER_REMOTE_AIM_DISTANCE
	_apply_control_mode()
	_apply_player_palette()
	_last_feedback_grounded = is_grounded()
	_last_feedback_velocity_y = velocity.y
	status_effect_manager.effect_added.connect(_on_status_effect_added)
	health_component.health_changed.connect(_on_health_changed)
	health_component.health_depleted.connect(_on_health_depleted)
	ArmorInventory.player_loadout_changed.connect(_on_armor_loadout_changed)
	_refresh_armor_visuals()
	_refresh_armor_stats()


func _exit_tree() -> void:
	if ArmorInventory.player_loadout_changed.is_connected(_on_armor_loadout_changed):
		ArmorInventory.player_loadout_changed.disconnect(_on_armor_loadout_changed)
	if time_scale < 1.0:
		TimeFlow.set_scale(player_slot, 1.0, global_position)


func _process(delta: float) -> void:
	if _is_eliminated:
		return
	_update_time_control(delta)
	var own_delta: float = delta * time_scale
	_update_block_timers(own_delta)
	_stun_timer = maxf(_stun_timer - own_delta, 0.0)
	_adrenaline_timer = maxf(_adrenaline_timer - own_delta, 0.0)
	_update_status_effect_feedback(own_delta)
	_update_block_armor_effects(own_delta)
	_update_research_healing(own_delta)
	_update_feedback_visuals(own_delta)


func _physics_process(delta: float) -> void:
	if _is_eliminated:
		return
	_update_ground_rays()
	if control_mode == GameSettings.CONTROL_REMOTE:
		_step_clock += delta
		_physics_process_remote(delta)
		return
	var own_delta: float = delta * time_scale
	_step_clock += own_delta
	_update_time_control_input()
	_update_block_input()
	_update_movement_timers(own_delta)
	update_wall_coyote(own_delta)
	_update_wind_exposure(own_delta)
	_push_out_of_players(own_delta)
	_slide_off_unsupported_floor()


## Two players that end up inside each other (a remote player's position catching up into you) would each
## stand on the other and float off together, glued. Step sideways out of the other body, walls still block.
func _push_out_of_players(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var other: Player = node as Player
		if other == null or other == self or (collision_mask & other.collision_layer) == 0:
			continue
		var offset: Vector2 = global_position - other.global_position
		if offset.length_squared() >= GameSettings.PLAYER_OVERLAP_DISTANCE * GameSettings.PLAYER_OVERLAP_DISTANCE:
			continue
		var side: float = signf(offset.x) if absf(offset.x) > 0.5 else (-1.0 if player_slot < other.player_slot else 1.0)
		add_collision_exception_with(other)
		move_and_collide(Vector2(side * GameSettings.PLAYER_OVERLAP_PUSH_SPEED * delta, 0.0))
		remove_collision_exception_with(other)


## Standing needs ground under a foot ray. When the round body rests on something neither ray sees (a
## platform's corner between them, another player's head), the slope it touches still counts as floor, and
## with no gravity on the ground the player would hang there half off the edge, or get pinned on a shoulder
## while pushing towards its middle. Slide off instead: the way the player is heading while that gets them
## anywhere (carrying over a head), else away from the contact (jumping off still works). The floor normal
## tilts away from what the body rests on and stays set while floor snapping holds a still body in place,
## when no slide collision is reported.
func _slide_off_unsupported_floor() -> void:
	if not is_on_floor() or _is_floor_ray(_ray_l) or _is_floor_ray(_ray_r):
		return
	var away: float = signf(get_floor_normal().x) if absf(get_floor_normal().x) > 0.05 else 0.0
	if away == 0.0 and get_slide_collision_count() > 0:
		away = signf(global_position.x - get_last_slide_collision().get_position().x)
	if away == 0.0:
		away = last_dir if last_dir != 0.0 else 1.0
	var side: float = signf(get_move_direction())
	if side == 0.0 or get_real_velocity().x * side < 1.0:
		side = away
	if signf(velocity.x) != side or absf(velocity.x) < GameSettings.PLAYER_EDGE_SLIDE_SPEED:
		velocity.x = side * GameSettings.PLAYER_EDGE_SLIDE_SPEED


func configure_local_control(slot: int, move_left: StringName, move_right: StringName, jump: StringName, shoot: StringName, block: StringName, allow_shoot: bool) -> void:
	player_slot = slot
	control_mode = GameSettings.CONTROL_LOCAL
	move_left_action = move_left
	move_right_action = move_right
	jump_action = jump
	shoot_action = shoot
	block_action = block
	_can_shoot_when_controls_enabled = allow_shoot
	shooting_enabled = movement_enabled and _can_shoot_when_controls_enabled
	_apply_control_mode()
	_apply_player_palette()
	_refresh_armor_visuals()
	_refresh_armor_stats()


func configure_remote_control(slot: int) -> void:
	player_slot = slot
	control_mode = GameSettings.CONTROL_REMOTE
	_can_shoot_when_controls_enabled = false
	shooting_enabled = false
	_block_active = false
	_block_timer = 0.0
	_block_cooldown_timer = 0.0
	_remote_block_state_initialized = false
	_network_target_position = global_position
	_network_target_velocity = Vector2.ZERO
	_network_aim_world_position = global_position + Vector2.LEFT * GameSettings.PLAYER_REMOTE_AIM_DISTANCE
	_has_network_target = false
	_apply_control_mode()
	_apply_player_palette()
	_refresh_armor_visuals()
	_refresh_armor_stats()


func configure_ai_control(slot: int, bot_difficulty: int) -> void:
	player_slot = slot
	control_mode = GameSettings.CONTROL_AI
	_can_shoot_when_controls_enabled = bot_difficulty != BotBrain.Difficulty.DUMMY
	shooting_enabled = movement_enabled and _can_shoot_when_controls_enabled
	if ai_brain == null:
		ai_brain = BotBrain.new()
		ai_brain.name = "BotBrain"
		add_child(ai_brain)
	ai_brain.setup(self, bot_difficulty)
	_has_network_target = false
	_apply_control_mode()
	_apply_player_palette()
	_refresh_armor_visuals()
	_refresh_armor_stats()


func set_controls_enabled(enabled: bool) -> void:
	movement_enabled = enabled and not _is_eliminated
	shooting_enabled = movement_enabled and _can_shoot_when_controls_enabled
	if not movement_enabled:
		_block_active = false
		_block_timer = 0.0


func reset_research_round_state() -> void:
	_phoenix_used = false
	_passive_heal_progress = 0.0
	_clear_time_slow()


func reset_network_state_to_current_transform() -> void:
	var aim_dir: float = signf(last_dir)
	if aim_dir == 0.0:
		aim_dir = 1.0
	_network_target_position = global_position
	_network_target_velocity = Vector2.ZERO
	_network_aim_world_position = global_position + Vector2(aim_dir, 0.0) * GameSettings.PLAYER_REMOTE_AIM_DISTANCE
	if control_mode == GameSettings.CONTROL_REMOTE:
		_has_network_target = true


func set_player_color(color_id: StringName) -> void:
	if not GameSettings.is_valid_player_color(color_id):
		return
	player_color_id = color_id
	_apply_player_palette()


func _on_armor_loadout_changed(changed_player_slot: int = 0) -> void:
	var effective_slot: int = _get_effective_armor_player_slot()
	if changed_player_slot == 0 or changed_player_slot == effective_slot:
		_refresh_armor_visuals()
		_refresh_armor_stats()


func _refresh_armor_visuals() -> void:
	if _armor_visual_root == null:
		return
	var effective_slot: int = _get_effective_armor_player_slot()
	_armor_visual_root.apply_loadout(ArmorInventory.get_loadout_for_player(effective_slot))


func _capture_base_stats() -> void:
	_base_speed = speed
	_base_air_speed = air_speed
	_base_jump_velocity = jump_velocity
	_base_wall_jump_velocity = wall_jump_velocity
	_base_block_duration = block_duration
	_base_block_cooldown = block_cooldown
	_base_block_cone_degrees = block_cone_degrees
	if health_component != null:
		_base_max_health = health_component.max_health


func _refresh_armor_stats() -> void:
	var effective_slot: int = _get_effective_armor_player_slot()
	var loadout: ArmorLoadout = ArmorInventory.get_loadout_for_player(effective_slot)

	_armor_attributes = {}
	if loadout != null:
		_armor_attributes = loadout.get_scaled_attributes()

	speed = maxf(60.0, _base_speed + _get_armor_attribute(&"move_speed"))
	air_speed = maxf(40.0, _base_air_speed + _get_armor_attribute(&"air_speed"))
	jump_velocity = maxf(120.0, _base_jump_velocity + _get_armor_attribute(&"jump_velocity"))
	var wall_jump_y_bonus: float = _get_armor_attribute(&"jump_velocity")
	wall_jump_velocity = Vector2(
		_base_wall_jump_velocity.x,
		_base_wall_jump_velocity.y - wall_jump_y_bonus * 0.45
	)

	var block_strength: float = _get_armor_attribute(&"block_strength")
	block_duration = maxf(0.12, _base_block_duration + block_strength * 0.004)
	block_cooldown = maxf(0.35, _base_block_cooldown - block_strength * 0.003)
	block_cone_degrees = clampf(_base_block_cone_degrees + block_strength * 0.55, 72.0, 178.0)

	if health_component != null:
		var old_max_health: int = health_component.max_health
		var was_full_health: bool = health_component.health >= old_max_health
		health_component.max_health = maxi(
			GameSettings.MIN_MAX_HEALTH,
			int(roundf(float(_base_max_health) + _get_armor_attribute(&"max_health")))
		)
		if was_full_health:
			health_component.health = health_component.max_health


func _get_effective_armor_player_slot() -> int:
	if player_slot != 0:
		return player_slot
	return ArmorInventory.get_local_player_slot()


func get_visual_tint() -> Color:
	return GameSettings.player_color_value(_get_effective_color_id())


func note_damage_dealt() -> void:
	if ai_brain != null:
		ai_brain.on_damage_dealt()
	var duration: float = _get_armor_attribute(&"adrenaline_duration")
	if duration > 0.0:
		_adrenaline_timer = maxf(_adrenaline_timer, duration)


func apply_incoming_damage(
	amount: int,
	source_slot: int = 0,
	source_position: Vector2 = Vector2.ZERO,
	allow_delay: bool = true
) -> int:
	if amount <= 0 or health_component == null:
		return 0

	var modified_damage: int = get_modified_incoming_damage(amount)
	var delay_duration: float = _get_armor_attribute(&"delayed_damage_duration")
	if allow_delay and delay_duration > 0.0 and modified_damage > 1:
		_run_delayed_damage(modified_damage, delay_duration, source_slot, source_position)
		return 0

	var applied: int = apply_resolved_damage(modified_damage, source_position)
	_record_world_stat(source_slot, "hits", 1.0)
	_record_world_stat(source_slot, "damage", float(applied))
	return applied


func _record_world_stat(slot: int, key: String, amount: float) -> void:
	if slot <= 0 or amount <= 0.0 or not is_inside_tree():
		return
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world != null and world.has_method(&"record_stat"):
		world.record_stat(slot, key, amount)


func apply_resolved_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> int:
	if amount <= 0 or health_component == null:
		return 0
	var old_health: int = health_component.health
	apply_hit_feedback(source_position, amount)
	health_component.damage(amount)
	return mini(amount, old_health)


func get_modified_incoming_damage(amount: int) -> int:
	var reduction: float = _get_armor_attribute(&"damage_reduction")
	if _is_stationary_for_armor():
		reduction += _get_armor_attribute(&"stationary_damage_reduction")
	var reduced_damage: int = int(roundf(float(amount) - reduction))
	if amount > 0:
		return maxi(1, reduced_damage)
	return 0


func get_delayed_damage_duration() -> float:
	return _get_armor_attribute(&"delayed_damage_duration")


func adjust_status_effect_data(effect_name: StringName, params: Dictionary) -> Dictionary:
	if effect_name != &"freeze":
		return params
	var resistance: float = clampf(_get_armor_attribute(&"freeze_resistance"), 0.0, 0.9)
	if resistance <= 0.0:
		return params

	var adjusted: Dictionary = params.duplicate(true)
	adjusted["duration"] = maxf(0.05, float(adjusted.get("duration", 0.0)) * (1.0 - resistance))
	if adjusted.has("speed_multiplier"):
		var speed_multiplier: float = float(adjusted.get("speed_multiplier", 1.0))
		adjusted["speed_multiplier"] = clampf(lerpf(speed_multiplier, 1.0, resistance), 0.05, 1.0)
	return adjusted


func try_reflect_projectile(projectile: Projectile) -> bool:
	if projectile == null or projectile.owner_slot == player_slot:
		return false
	var chance: float = clampf(_get_armor_attribute(&"reflect_chance"), 0.0, 0.95)
	if chance <= 0.0 or randf() > chance:
		return false

	var reflect_direction: Vector2 = -projectile.velocity.normalized()
	if reflect_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		reflect_direction = (projectile.global_position - global_position).normalized()
	if reflect_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		reflect_direction = Vector2(signf(last_dir), 0.0)

	projectile.owner_slot = player_slot
	projectile.direction = reflect_direction.normalized()
	projectile.velocity = reflect_direction.normalized() * maxf(projectile.velocity.length(), projectile.muzzle_speed)
	projectile.initial_velocity = projectile.velocity
	projectile.global_position += reflect_direction.normalized() * maxf(8.0, projectile.projectile_scale * 8.0)
	GameJuice.spawn_burst(&"reflect", projectile.global_position, reflect_direction, Color(0.96, 0.96, 1.0, 0.9))
	AudioDirector.play_at(&"reflect", projectile.global_position)
	return true


func is_eliminated() -> bool:
	return _is_eliminated


func get_gun() -> Gun:
	return _gun


func set_eliminated(eliminated: bool) -> void:
	if _is_eliminated == eliminated:
		visible = not eliminated
		collision_layer = 0 if eliminated else _default_collision_layer
		collision_mask = 0 if eliminated else _default_collision_mask
		return

	_is_eliminated = eliminated
	visible = not eliminated
	collision_layer = 0 if eliminated else _default_collision_layer
	collision_mask = 0 if eliminated else _default_collision_mask
	velocity = Vector2.ZERO
	_hit_flash_timer = 0.0
	_hit_feedback_guard_timer = 0.0
	_healing_field_timer = 0.0
	_healing_field_progress = 0.0
	_healing_field_has_position = false
	_update_healing_area_visual(0.0, 0.0)

	if eliminated:
		_clear_time_slow()
		movement_enabled = false
		shooting_enabled = false
		_has_network_target = false
		_block_active = false
		_block_timer = 0.0
		_block_cooldown_timer = 0.0
		if _state_machine != null:
			_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_phoenix_used = false
		_passive_heal_progress = 0.0
		_apply_control_mode()
		shooting_enabled = movement_enabled and _can_shoot_when_controls_enabled
		_block_active = false
		_block_timer = 0.0
		_block_cooldown_timer = 0.0
		if status_effect_manager != null:
			status_effect_manager.clear_all()
		_initialize_feet()
		_last_feedback_grounded = is_grounded()
		_last_feedback_velocity_y = velocity.y


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	var snapshot_position: Variant = snapshot.get("position", global_position)
	var snapshot_velocity: Variant = snapshot.get("velocity", velocity)
	var snapshot_aim: Variant = snapshot.get("aim", _network_aim_world_position)
	var snapshot_facing: Variant = snapshot.get("facing", last_dir)
	var snapshot_ammo: int = int(snapshot.get("ammo", 0))
	var snapshot_reloading: bool = snapshot.get("reloading", false) == true
	var snapshot_reload_ratio: float = float(snapshot.get("reload_ratio", 1.0))
	var had_network_target: bool = _has_network_target
	var aim_origin: Vector2 = _network_target_position

	if snapshot_position is Vector2:
		_network_target_position = snapshot_position
		aim_origin = snapshot_position
	if snapshot_velocity is Vector2:
		_network_target_velocity = snapshot_velocity
		_network_target_position += _network_target_velocity * GameSettings.PLAYER_REMOTE_EXTRAPOLATION_SECONDS
	if snapshot_aim is Vector2:
		_network_aim_world_position = snapshot_aim
		var aim_vector: Vector2 = snapshot_aim - aim_origin
		if aim_vector.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
			_gun.set_aim_direction(aim_vector.normalized())
	if (snapshot_facing is float or snapshot_facing is int) and absf(float(snapshot_facing)) > 0.0:
		last_dir = signf(float(snapshot_facing))
	if snapshot.has("ammo"):
		_gun.apply_remote_ammo_state(snapshot_ammo, snapshot_reloading, snapshot_reload_ratio)

	_has_network_target = true
	if not had_network_target:
		global_position = _network_target_position
		velocity = _network_target_velocity


func get_border_check_position() -> Vector2:
	if control_mode == GameSettings.CONTROL_REMOTE and _has_network_target:
		return _network_target_position
	return global_position


func get_move_direction() -> float:
	if control_mode == GameSettings.CONTROL_AI:
		if ai_brain == null or not movement_enabled or _stun_timer > 0.0:
			return 0.0
		return clampf(ai_brain.move_direction, -1.0, 1.0)
	if not _can_read_input(movement_enabled):
		return 0.0
	return clampf(Input.get_action_strength(move_right_action) - Input.get_action_strength(move_left_action), -1.0, 1.0)


func is_jump_pressed() -> bool:
	return _is_action_available(jump_action, movement_enabled, true)


func is_jump_held() -> bool:
	return _is_action_available(jump_action, movement_enabled, false)


func is_shoot_pressed() -> bool:
	return _is_action_available(shoot_action, shooting_enabled, true)


func is_block_pressed() -> bool:
	return _is_action_available(block_action, movement_enabled, true)


## Held trigger keeps firing for local players; bots and remote players fire on discrete presses.
func is_shoot_held() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL:
		return false
	return _is_action_available(shoot_action, shooting_enabled, false)


func is_reload_pressed() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL or not InputMap.has_action(reload_action):
		return false
	return _is_action_available(reload_action, shooting_enabled, true)


func _is_action_available(action: StringName, enabled: bool, just_pressed: bool) -> bool:
	if control_mode == GameSettings.CONTROL_AI:
		return _is_ai_action_active(action, enabled, just_pressed)
	if not _can_read_input(enabled):
		return false
	return Input.is_action_just_pressed(action) if just_pressed else Input.is_action_pressed(action)


func _is_ai_action_active(action: StringName, enabled: bool, just_pressed: bool) -> bool:
	if ai_brain == null or not enabled or _stun_timer > 0.0:
		return false
	if action == jump_action:
		return ai_brain.jump_pressed if just_pressed else ai_brain.jump_held
	if action == shoot_action:
		return ai_brain.shoot_pressed
	if action == block_action:
		return ai_brain.block_pressed
	if action == time_control_action:
		return ai_brain.time_control_pressed
	return false


func _can_read_input(enabled: bool) -> bool:
	return control_mode == GameSettings.CONTROL_LOCAL and enabled and _stun_timer <= 0.0


func is_blocking() -> bool:
	return _block_active


func get_block_cooldown_ratio() -> float:
	if _block_cooldown_timer <= 0.0 or block_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - (_block_cooldown_timer / block_cooldown), 0.0, 1.0)


func get_block_direction() -> Vector2:
	if _block_direction.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		var fallback_dir: float = signf(last_dir)
		if fallback_dir == 0.0:
			fallback_dir = 1.0
		return Vector2(fallback_dir, 0.0)
	return _block_direction.normalized()


func is_blocking_projectile(projectile_position: Vector2, projectile_velocity: Vector2 = Vector2.ZERO) -> bool:
	if not _block_active:
		return false

	var to_projectile: Vector2 = projectile_position - global_position
	if to_projectile.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		to_projectile = -projectile_velocity
	if to_projectile.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		return true

	var block_direction: Vector2 = get_block_direction()
	var half_angle_radians: float = deg_to_rad(block_cone_degrees * 0.5)
	return block_direction.dot(to_projectile.normalized()) >= cos(half_angle_radians)


func apply_block_feedback(projectile_position: Vector2) -> void:
	var block_direction: Vector2 = get_block_direction()
	GameJuice.spawn_burst(&"block", projectile_position, block_direction, Color(0.72, 0.96, 1.0, 0.92))
	AudioDirector.play_at(&"block", projectile_position)
	GameJuice.shake(GameSettings.PLAYER_BLOCK_FEEDBACK_SHAKE_STRENGTH * 2.0, GameSettings.PLAYER_BLOCK_FEEDBACK_SHAKE_TIME)
	GameJuice.kick(-block_direction, 3.0)
	_record_world_stat(player_slot, "blocks", 1.0)
	_body_punch_scale = Vector2(0.9, 1.08)


func apply_remote_block_state(active: bool, direction_variant: Variant = Vector2.ZERO, cooldown_ratio_variant: Variant = GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO) -> void:
	var was_active: bool = _block_active
	if direction_variant is Vector2:
		var remote_block_direction: Vector2 = direction_variant
		if remote_block_direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
			_block_direction = remote_block_direction.normalized()

	_block_active = active
	if _block_active:
		if not was_active:
			_block_timer = block_duration
			_healing_field_has_position = false
		_block_cooldown_timer = 0.0
	else:
		_block_timer = 0.0

	if cooldown_ratio_variant is float or cooldown_ratio_variant is int:
		var cooldown_ratio: float = clampf(float(cooldown_ratio_variant), 0.0, 1.0)
		var current_ratio: float = get_block_cooldown_ratio()
		var accepts_initial_state: bool = not _remote_block_state_initialized
		var accepts_transition: bool = was_active and not active
		var accepts_progress: bool = not active and cooldown_ratio >= current_ratio
		if accepts_initial_state or accepts_transition or accepts_progress:
			_block_cooldown_timer = (1.0 - cooldown_ratio) * block_cooldown
	_remote_block_state_initialized = true


func get_aim_world_position() -> Vector2:
	if control_mode == GameSettings.CONTROL_REMOTE:
		return _network_aim_world_position
	if control_mode == GameSettings.CONTROL_AI and ai_brain != null:
		return ai_brain.aim_position
	if InputDevice.using_gamepad and player_slot == GameSettings.PLAYER_ONE_SLOT:
		return global_position + InputDevice.aim_direction * GameSettings.GAMEPAD_AIM_DISTANCE
	var camera: GameCamera = get_viewport().get_camera_2d() as GameCamera
	if camera != null:
		return camera.stable_mouse_world_position()
	return get_global_mouse_position()


func _apply_control_mode() -> void:
	if _state_machine == null:
		return

	if control_mode == GameSettings.CONTROL_REMOTE:
		_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_state_machine.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process_remote(delta: float) -> void:
	if _is_eliminated:
		return
	if not _has_network_target:
		return

	var interpolation_weight: float = clampf(delta * remote_interpolation_speed, 0.0, 1.0)
	var distance_to_target_squared: float = global_position.distance_squared_to(_network_target_position)
	var snap_distance: float = GameSettings.PLAYER_REMOTE_SNAP_DISTANCE
	if distance_to_target_squared > snap_distance * snap_distance:
		global_position = _network_target_position
	else:
		global_position = global_position.lerp(_network_target_position, interpolation_weight)
	velocity = _network_target_velocity
	if absf(velocity.x) > GameSettings.PLAYER_REMOTE_FACING_SPEED_THRESHOLD:
		last_dir = signf(velocity.x)
	update_visual_movement(delta)


func is_grounded() -> bool:
	if is_on_floor():
		return true
	if velocity.y < 0.0:
		return false
	return _is_floor_ray(_ray_l) or _is_floor_ray(_ray_r)


func can_jump() -> bool:
	return _coyote_timer > 0.0


func has_buffered_jump() -> bool:
	return _jump_buffer_timer > 0.0


func consume_jump_buffer() -> void:
	_jump_buffer_timer = 0.0


func update_wall_coyote(delta: float) -> void:
	if is_on_wall():
		_wall_coyote_timer = wall_coyote_time
		var wall_x: float = get_wall_normal().x
		_wall_coyote_dir = signf(wall_x) if absf(wall_x) > 0.0 else -last_dir
	else:
		_wall_coyote_timer = maxf(_wall_coyote_timer - delta, 0.0)


func can_wall_jump() -> bool:
	return _wall_coyote_timer > 0.0 and has_buffered_jump()


func wall_jump() -> void:
	var dir: float = _wall_coyote_dir
	if dir == 0.0:
		dir = -last_dir
	var input_dir: float = get_move_direction()
	if input_dir != 0.0:
		dir = -signf(input_dir)
	velocity.x = -dir * wall_jump_velocity.x
	velocity.y = wall_jump_velocity.y
	_wall_coyote_timer = 0.0
	consume_jump_buffer()
	_coyote_timer = 0.0
	_emit_jump_feedback(Vector2(dir, 0.35))


func jump() -> void:
	velocity.y = -jump_velocity
	_coyote_timer = 0.0
	consume_jump_buffer()
	_emit_jump_feedback(Vector2.DOWN)


func apply_horizontal_movement(delta: float, max_speed: float, acceleration: float, friction: float) -> float:
	var direction: float = get_move_direction()
	var slow: float = get_status_speed_multiplier()
	var armor_speed_bonus: float = _get_dynamic_armor_speed_bonus(direction)
	max_speed += armor_speed_bonus
	max_speed *= slow
	acceleration *= slow
	friction *= slow
	var drift: float = get_wind_drift_speed()
	if direction != 0.0:
		last_dir = signf(direction)
		velocity.x = move_toward(velocity.x, direction * max_speed + drift, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, drift, friction * delta)
	return direction


## Sideways speed the wind adds right now: running with a storm is faster, against it slower, and standing
## still lets it shove you. Airborne players catch far more of it than grounded ones.
func get_wind_drift_speed() -> float:
	if not WorldConditions.has_wind():
		return 0.0
	var grounded: bool = is_grounded()
	var share: float = WIND_GROUND_SHARE if grounded else WIND_AIR_SHARE
	var drift: float = WorldConditions.wind.x * _wind_exposure * share
	# Someone standing still digs in at a ledge: the storm alone never shoves a player off a cliff.
	if grounded and get_move_direction() == 0.0 and not _has_ground_ahead(signf(drift)):
		return 0.0
	return drift


func _has_ground_ahead(side: float) -> bool:
	if side == 0.0:
		return true
	var from: Vector2 = global_position + Vector2(side * 22.0, 0.0)
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, hover_dist + 40.0), 1)
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func get_wind_exposure() -> float:
	return _wind_exposure if WorldConditions.has_wind() else 0.0


## Players brace into a storm (lean upwind) and get buffeted by its gusts; sheltered players stand still.
func _wind_lean() -> float:
	if not WorldConditions.has_wind():
		return 0.0
	var strength: float = clampf(absf(WorldConditions.wind.x) / 250.0, 0.0, 1.0) * _wind_exposure
	var buffet: float = sin(_step_clock * 23.0) * sin(_step_clock * 7.3) * 0.05 * WorldConditions.storm
	return (-signf(WorldConditions.wind.x) * 0.14 + buffet) * strength


func _update_wind_exposure(delta: float) -> void:
	if not WorldConditions.has_wind():
		_wind_exposure = 1.0
		return
	var exclude: Array[RID] = [get_rid()]
	var target: float = WorldConditions.wind_exposure_at(get_world_2d().direct_space_state, global_position, exclude)
	_wind_exposure = move_toward(_wind_exposure, target, delta * 3.5)


func _get_dynamic_armor_speed_bonus(direction: float) -> float:
	var bonus: float = 0.0
	if health_component != null:
		var health_ratio: float = float(health_component.health) / float(health_component.max_health)
		var missing_ratio: float = clampf(1.0 - health_ratio, 0.0, 1.0)
		bonus += _get_armor_attribute(&"escape_speed_bonus") * missing_ratio

	if direction != 0.0 and _is_moving_towards_opponent(direction):
		bonus += _get_armor_attribute(&"chase_speed_bonus")

	if _adrenaline_timer > 0.0:
		bonus += _get_armor_attribute(&"adrenaline_speed_bonus")

	return bonus


func _is_moving_towards_opponent(direction: float) -> bool:
	var opponent: Player = _get_nearest_opponent()
	if opponent == null:
		return false
	var to_opponent: float = opponent.global_position.x - global_position.x
	return absf(to_opponent) > 2.0 and signf(to_opponent) == signf(direction)


func _get_nearest_opponent() -> Player:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var other: Player = node as Player
		if other == null or other == self or other.is_eliminated():
			continue
		if other.player_slot == player_slot:
			continue
		return other
	return null


func get_status_speed_multiplier() -> float:
	if status_effect_manager == null:
		return 1.0
	return status_effect_manager.get_slow_multiplier()


## move_and_slide on this player's own clock. Velocity stays in units per second of their time, so a slowed
## player keeps the same arcs (jumps reach the same height) and just plays them out slower.
func move_and_slide_scaled() -> void:
	if time_scale >= 0.999:
		move_and_slide()
		return
	if time_scale <= 0.001:
		return
	velocity *= time_scale
	move_and_slide()
	velocity /= time_scale


func apply_gravity(delta: float, multiplier: float = 1.0) -> void:
	velocity.y = minf(velocity.y + gravity * multiplier * WorldConditions.gravity_scale * delta, max_fall_speed)


## Throws the player (geysers and other launchers): the short-hop gravity cut is skipped until the apex,
## so the throw reaches its full height whether or not jump is held.
func launch(launch_velocity: Vector2) -> void:
	velocity = launch_velocity
	_external_launch = true


func apply_better_jump_gravity(delta: float) -> void:
	var multiplier: float = 1.0
	if velocity.y >= 0.0:
		_external_launch = false
	if velocity.y > 0.0:
		multiplier = fall_gravity_multiplier
	elif velocity.y < 0.0 and not is_jump_held() and not _external_launch:
		multiplier = low_jump_gravity_multiplier
	apply_gravity(delta, multiplier)


func maintain_hover_height(delta: float) -> void:
	if not is_grounded():
		return

	var floor_y: float = global_position.y + hover_dist
	if _is_floor_ray(_ray_l):
		floor_y = minf(floor_y, _ray_l.get_collision_point().y)
	if _is_floor_ray(_ray_r):
		floor_y = minf(floor_y, _ray_r.get_collision_point().y)

	var target_y: float = floor_y - hover_dist
	global_position.y = lerpf(global_position.y, target_y, clampf(delta * hover_snap_speed, 0.0, 1.0))
	if velocity.y > 0.0:
		velocity.y = 0.0


func update_visual_movement(delta: float) -> void:
	var speed_ratio: float = clampf(absf(velocity.x) / maxf(speed, 1.0), 0.0, 1.0)
	var grounded: bool = is_grounded()
	_update_surface_feedback(delta, grounded, speed_ratio)
	if grounded:
		var look: float = velocity.x * look_ahead
		var floor_y: float = global_position.y + hover_dist
		if _is_floor_ray(_ray_l):
			floor_y = minf(floor_y, _ray_l.get_collision_point().y)
		if _is_floor_ray(_ray_r):
			floor_y = minf(floor_y, _ray_r.get_collision_point().y)

		var ideal_l: Vector2 = Vector2(global_position.x - foot_spread + look, floor_y)
		var ideal_r: Vector2 = Vector2(global_position.x + foot_spread + look, floor_y)
		var floor_l: bool = _is_floor_ray(_ray_l)
		var floor_r: bool = _is_floor_ray(_ray_r)
		if floor_l != floor_r:
			var edge_gap: float = foot_spread * GameSettings.PLAYER_EDGE_GAP_MULTIPLIER
			if floor_l:
				ideal_l.x = minf(ideal_l.x, _ray_l.get_collision_point().x)
				ideal_r.x = minf(ideal_r.x, ideal_l.x + edge_gap)
			else:
				ideal_r.x = maxf(ideal_r.x, _ray_r.get_collision_point().x)
				ideal_l.x = maxf(ideal_l.x, ideal_r.x - edge_gap)
		var move_dir: float = _get_visual_move_direction()
		var changed_direction: bool = (
			move_dir != 0.0
			and _last_visual_move_dir != 0.0
			and move_dir != _last_visual_move_dir
		)

		if not _was_visual_grounded:
			_set_feet(ideal_l, ideal_r)

		if _step_t_l < 1.0:
			_step_t_l = minf(_step_t_l + delta / step_duration, 1.0)
			foot_pos_l = _arc(_step_from_l, _step_to_l, _step_t_l, step_arc_h)
		if _step_t_r < 1.0:
			_step_t_r = minf(_step_t_r + delta / step_duration, 1.0)
			foot_pos_r = _arc(_step_from_r, _step_to_r, _step_t_r, step_arc_h)

		if changed_direction:
			_set_feet(ideal_l, ideal_r)
		elif _step_t_l >= 1.0 and _step_t_r >= 1.0:
			var dl: float = foot_pos_l.distance_to(ideal_l)
			var dr: float = foot_pos_r.distance_to(ideal_r)
			var l_ready: bool = (_step_clock - _last_step_time_l) >= stride_min_interval
			var r_ready: bool = (_step_clock - _last_step_time_r) >= stride_min_interval

			var prefer_left: bool = _last_stepped == 1
			if prefer_left:
				if dl > step_trigger and l_ready:
					_begin_step(true, ideal_l)
				elif dr > step_trigger and r_ready:
					_begin_step(false, ideal_r)
			else:
				if dr > step_trigger and r_ready:
					_begin_step(false, ideal_r)
				elif dl > step_trigger and l_ready:
					_begin_step(true, ideal_l)

		bounce_t += delta * GameSettings.PLAYER_BOUNCE_SPEED * speed_ratio
		_was_visual_grounded = true
		if move_dir != 0.0:
			_last_visual_move_dir = move_dir
	else:
		_was_visual_grounded = false
		_last_visual_move_dir = 0.0
		_step_t_l = 1.0
		_step_t_r = 1.0
		var hip: Vector2 = global_position + Vector2(0.0, hip_y_offset).rotated(rotation)
		var tuck_y: float = hover_dist * GameSettings.PLAYER_AIR_FOOT_HOVER_MULTIPLIER - air_foot_tuck_y
		foot_pos_l = foot_pos_l.lerp(
			hip + Vector2(-air_foot_tuck_x, tuck_y),
			delta * GameSettings.PLAYER_AIR_FOOT_LERP_SPEED
		)
		foot_pos_r = foot_pos_r.lerp(
			hip + Vector2(air_foot_tuck_x, tuck_y),
			delta * GameSettings.PLAYER_AIR_FOOT_LERP_SPEED
		)
		bounce_t = lerp(bounce_t, 0.0, delta * GameSettings.PLAYER_BOUNCE_SPEED)

	var visual_direction: float = get_move_direction()
	if control_mode == GameSettings.CONTROL_REMOTE:
		visual_direction = clampf(velocity.x / maxf(speed, 1.0), -1.0, 1.0)
	rotation = lerp_angle(
		rotation,
		visual_direction * GameSettings.PLAYER_VISUAL_ROTATION_SCALE + _wind_lean(),
		delta * GameSettings.PLAYER_VISUAL_ROTATION_LERP_SPEED
	)
	_update_body_sprite_direction()
	_update_wall_slide_feedback(delta, grounded)


func _update_wall_slide_feedback(delta: float, grounded: bool) -> void:
	if grounded or not is_on_wall() or velocity.y < 30.0:
		_wall_slide_timer = 0.0
		return
	_wall_slide_timer -= delta
	if _wall_slide_timer > 0.0:
		return
	_wall_slide_timer = WALL_SLIDE_FEEDBACK_INTERVAL
	var wall_normal: Vector2 = get_wall_normal()
	var contact: Vector2 = global_position - wall_normal * 14.0 + Vector2(0.0, 6.0)
	GameJuice.spawn_burst(&"wall_dust", contact, wall_normal, Color.WHITE)
	AudioDirector.play_at(&"wall_slide", contact)


func _update_face() -> void:
	if _face == null:
		return
	var look: Vector2 = Vector2(signf(last_dir) if last_dir != 0.0 else 1.0, 0.0) * 0.6
	var aim: Vector2 = get_aim_world_position() - global_position
	if aim.length_squared() > 16.0:
		look = aim / maxf(aim.length(), 1.0) * clampf(aim.length() / 140.0, 0.45, 1.0)
	if _block_active:
		look = get_block_direction()
	_face.look_target = look
	var health_ratio: float = 1.0
	if health_component != null:
		health_ratio = float(health_component.health) / maxf(float(health_component.max_health), 1.0)
	_face.set_sweating(health_ratio <= LOW_HEALTH_RATIO)


func _is_local_view_player() -> bool:
	if control_mode != GameSettings.CONTROL_LOCAL:
		return false
	if NetworkSession.is_steam_match_active():
		return player_slot == NetworkSession.local_player_slot
	return is_in_group(GameSettings.LOCAL_PLAYERS_GROUP)


func apply_hit_feedback(source_position: Vector2, damage: int = GameSettings.PROJECTILE_DAMAGE) -> void:
	var away_from_source: Vector2 = global_position - source_position
	if away_from_source.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		away_from_source = Vector2(-last_dir, -0.25)
	_hit_flash_timer = GameSettings.PLAYER_HIT_FLASH_TIME
	_hit_feedback_guard_timer = 0.09
	if _pending_hit_count == 0:
		_flush_hit_feedback.call_deferred()
	_pending_hit_count += 1
	_pending_hit_damage += maxi(damage, 0)
	_pending_hit_direction += away_from_source.normalized() * float(maxi(damage, 1))


func _flush_hit_feedback() -> void:
	var damage: int = _pending_hit_damage
	var hits: int = _pending_hit_count
	var hit_direction: Vector2 = _pending_hit_direction.normalized() if _pending_hit_direction.length_squared() > 0.0001 else Vector2(-last_dir, -0.25).normalized()
	_pending_hit_damage = 0
	_pending_hit_count = 0
	_pending_hit_direction = Vector2.ZERO
	if hits <= 0 or not is_inside_tree():
		return
	var tint: Color = GameSettings.player_color_value(_get_effective_color_id())
	# Several pellets at once may shove harder than a single bullet, but stay controllable.
	var max_ratio: float = 1.8 if hits == 1 else 2.4
	var damage_ratio: float = clampf(float(damage) / maxf(float(GameSettings.PROJECTILE_DAMAGE), 1.0), 0.75, max_ratio)

	var heavy: bool = damage >= 40
	_body_punch_scale = Vector2(1.24, 0.78) if heavy else Vector2(1.18, 0.84)
	if _face != null:
		_face.set_expression(PlayerFace.Mood.HURT, 0.38)

	if control_mode != GameSettings.CONTROL_REMOTE and movement_enabled:
		velocity.x += hit_direction.x * GameSettings.PLAYER_HIT_KNOCKBACK_X * damage_ratio
		velocity.y -= GameSettings.PLAYER_HIT_KNOCKBACK_Y * damage_ratio

	GameJuice.spawn_burst(&"hit_heavy" if heavy else &"hit", global_position, hit_direction, tint, 1.0 + 0.12 * float(hits - 1))
	AudioDirector.play_at(&"hit_heavy" if heavy else &"hit", global_position)
	GameJuice.shake(GameSettings.PLAYER_HIT_SHAKE_STRENGTH * damage_ratio, GameSettings.PLAYER_HIT_SHAKE_TIME)
	GameJuice.kick(hit_direction, 4.0 * damage_ratio)
	GameJuice.spawn_damage_number(global_position, damage, tint, get_instance_id())
	ImpactDecals.splatter_around(global_position, tint, 1 if not heavy else 2, 70.0)
	if heavy:
		GameJuice.hitstop(0.035, 0.08)
	if _is_local_view_player():
		GameJuice.flash(Color(0.9, 0.05, 0.08, 1.0), 0.16 * damage_ratio, 0.22)
		GameJuice.aberration(0.6 * damage_ratio, 0.22)


func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)
	_spawn_status_feedback(&"shock", global_position, Vector2.UP)


func _on_status_effect_added(effect_name: StringName) -> void:
	_spawn_status_feedback(effect_name, global_position, Vector2.UP)


func _update_status_effect_feedback(delta: float) -> void:
	if status_effect_manager == null or status_effect_manager.get_active_count() <= 0:
		_status_fx_timer = 0.0
		return

	_status_fx_phase += delta * 11.0
	_status_fx_timer -= delta
	if _status_fx_timer > 0.0:
		return

	_status_fx_timer = 0.16
	var active_names: Array[StringName] = status_effect_manager.get_active_effect_names()
	for effect_name in active_names:
		var offset: Vector2 = Vector2(cos(_status_fx_phase), sin(_status_fx_phase * 1.37)) * 18.0
		_spawn_status_feedback(effect_name, global_position + offset, offset.normalized())


func _spawn_status_feedback(effect_name: StringName, world_position: Vector2, direction: Vector2) -> void:
	match effect_name:
		&"freeze":
			GameJuice.spawn_burst(&"freeze", world_position, direction, Color(0.35, 0.78, 1.0, 0.86))
			AudioDirector.play_at(&"freeze", world_position)
		&"shock":
			GameJuice.spawn_burst(&"shock", world_position, direction, Color(1.0, 0.9, 0.22, 0.9))
			AudioDirector.play_at(&"shock", world_position)
		&"poison":
			GameJuice.spawn_burst(&"poison", world_position, direction, Color(0.42, 1.0, 0.42, 0.72))
			AudioDirector.play_at(&"poison", world_position)


func _update_movement_timers(delta: float) -> void:
	if is_jump_pressed():
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if is_grounded():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _update_block_input() -> void:
	if _block_active:
		_refresh_block_direction()
		return

	if is_block_pressed():
		_block_buffer_timer = GameSettings.PLAYER_BLOCK_BUFFER_TIME
	if _block_buffer_timer > 0.0 and _block_cooldown_timer <= 0.0:
		_block_buffer_timer = 0.0
		_begin_block()


func _update_block_timers(delta: float) -> void:
	if _block_active:
		if control_mode == GameSettings.CONTROL_REMOTE:
			return
		_refresh_block_direction()
		_block_timer = maxf(_block_timer - delta, 0.0)
		if _block_timer <= 0.0:
			_end_block()
	else:
		_block_cooldown_timer = maxf(_block_cooldown_timer - delta, 0.0)
	_block_buffer_timer = maxf(_block_buffer_timer - delta, 0.0)


func _begin_block() -> void:
	_refresh_block_direction()
	_block_active = true
	_block_timer = block_duration
	_block_cooldown_timer = 0.0
	_healing_field_has_position = false
	if control_mode == GameSettings.CONTROL_LOCAL:
		ResearchQuestManager.record_local_action(ResearchQuestManager.EVENT_BLOCK_ATTEMPT)
	AudioDirector.play_at(&"block_raise", global_position)
	if _face != null:
		_face.set_expression(PlayerFace.Mood.FOCUS, block_duration)
	_apply_block_start_armor_effects()
	_notify_block_state(true)


func _end_block() -> void:
	if not _block_active:
		return
	_block_active = false
	_block_timer = 0.0
	_block_cooldown_timer = block_cooldown
	if control_mode == GameSettings.CONTROL_LOCAL:
		_notify_block_state(false)


func _refresh_block_direction() -> void:
	var aim_vector: Vector2 = get_aim_world_position() - global_position
	if aim_vector.length_squared() <= GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED:
		var fallback_dir: float = signf(last_dir)
		if fallback_dir == 0.0:
			fallback_dir = 1.0
		aim_vector = Vector2(fallback_dir, 0.0)
	_block_direction = aim_vector.normalized()


func _apply_block_start_armor_effects() -> void:
	if _get_armor_attribute(&"instant_reload_on_block") <= 0.0:
		return
	_gun.instant_reload()


func _update_block_armor_effects(delta: float) -> void:
	var healing_radius: float = _get_armor_attribute(&"healing_radius")
	var healing_rate: float = _get_armor_attribute(&"healing_rate")

	if _block_active and healing_radius > 0.0 and healing_rate > 0.0:
		if not _healing_field_has_position:
			_healing_field_position = global_position
			_healing_field_has_position = true
		_healing_field_timer = GameSettings.PLAYER_HEALING_FIELD_DURATION
		_healing_field_radius = healing_radius
		_healing_field_rate = healing_rate
	elif _healing_field_timer > 0.0:
		_healing_field_timer = maxf(_healing_field_timer - delta, 0.0)
	else:
		_healing_field_progress = 0.0
		_healing_field_has_position = false

	var field_active: bool = _healing_field_timer > 0.0
	_update_healing_area_visual(_healing_field_radius if field_active else 0.0, delta)
	if field_active:
		_update_healing_shield(delta, _healing_field_radius, _healing_field_rate)

	if not _block_active:
		_frosty_aura_timer = 0.0
		return

	_update_frosty_shield(delta)
	_update_pull_shield(delta)


func _update_frosty_shield(delta: float) -> void:
	var radius: float = _get_armor_attribute(&"frosty_radius")
	if radius <= 0.0:
		return
	_frosty_aura_timer -= delta
	if _frosty_aura_timer > 0.0:
		return
	_frosty_aura_timer = 0.18

	var slow_multiplier: float = clampf(_get_armor_attribute(&"frosty_speed_multiplier"), 0.05, 1.0)
	var duration: float = maxf(_get_armor_attribute(&"frosty_duration"), 0.05)
	for target in _get_players_in_radius(radius, false):
		if target.status_effect_manager == null:
			continue
		target.status_effect_manager.apply_effect(&"freeze", {
			"duration": duration,
			"speed_multiplier": slow_multiplier,
			"tint_color": Color(0.36, 0.82, 1.0, 0.55),
		})


func _update_healing_shield(delta: float, radius: float, heal_rate: float) -> void:
	if radius <= 0.0 or heal_rate <= 0.0:
		_healing_field_progress = 0.0
		return

	_healing_field_progress += heal_rate * delta
	var heal_amount: int = int(floor(_healing_field_progress))
	if heal_amount <= 0:
		return
	_healing_field_progress -= float(heal_amount)

	for target in _get_players_in_radius_from(_healing_field_position, radius, true):
		if target.health_component != null:
			target.health_component.heal(heal_amount)


func _update_healing_area_visual(radius: float, delta: float) -> void:
	if _healing_area == null or _healing_area_fill == null or _healing_area_ring == null:
		return

	if radius <= 0.0:
		_healing_area.hide()
		_healing_area_visual_radius = 0.0
		return

	_healing_area.show()
	_healing_area.global_position = _healing_field_position if _healing_field_has_position else global_position
	_healing_area.global_rotation = 0.0
	_healing_area.global_scale = Vector2.ONE
	_healing_area_visual_phase += delta * 1.4

	if not is_equal_approx(_healing_area_visual_radius, radius):
		_healing_area_visual_radius = radius
		_healing_area_fill.polygon = _build_circle_points(radius)
		var ring_points: PackedVector2Array = _build_circle_points(radius)
		ring_points.append(ring_points[0])
		_healing_area_ring.points = ring_points

	var pulse: float = 0.5 + sin(_healing_area_visual_phase) * 0.5
	_healing_area_fill.color = Color(
		HEALING_AREA_FILL_COLOR.r,
		HEALING_AREA_FILL_COLOR.g,
		HEALING_AREA_FILL_COLOR.b,
		lerpf(0.18, 0.26, pulse)
	)
	_healing_area_ring.default_color = Color(
		HEALING_AREA_RING_COLOR.r,
		HEALING_AREA_RING_COLOR.g,
		HEALING_AREA_RING_COLOR.b,
		lerpf(0.78, 1.0, pulse)
	)
	_healing_area_ring.width = lerpf(3.6, 4.8, pulse)


func _build_circle_points(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point_index in range(HEALING_AREA_SEGMENTS):
		var angle: float = TAU * float(point_index) / float(HEALING_AREA_SEGMENTS)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _update_pull_shield(delta: float) -> void:
	var radius: float = _get_armor_attribute(&"pull_radius")
	var strength: float = _get_armor_attribute(&"pull_strength")
	if radius <= 0.0 or strength <= 0.0:
		return

	for target in _get_players_in_radius(radius, false):
		var to_center: Vector2 = global_position - target.global_position
		var distance: float = to_center.length()
		if distance <= 1.0:
			continue
		var falloff: float = 1.0 - clampf(distance / radius, 0.0, 1.0)
		target.velocity += to_center.normalized() * strength * falloff * delta


func _get_players_in_radius(radius: float, include_self: bool) -> Array[Player]:
	return _get_players_in_radius_from(global_position, radius, include_self)


func _get_players_in_radius_from(center: Vector2, radius: float, include_self: bool) -> Array[Player]:
	var result: Array[Player] = []
	var radius_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player_node: Player = node as Player
		if player_node == null or player_node.is_eliminated():
			continue
		if player_node == self and not include_self:
			continue
		if center.distance_squared_to(player_node.global_position) <= radius_sq:
			result.append(player_node)
	return result


func _notify_block_state(active: bool) -> void:
	var world: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null:
		return
	world.request_block_state(self, active, get_block_direction(), get_block_cooldown_ratio())


# --- Time Control ---------------------------------------------------------------------------------------

func is_time_control_pressed() -> bool:
	if control_mode == GameSettings.CONTROL_LOCAL and not InputMap.has_action(time_control_action):
		return false
	return _is_action_available(time_control_action, movement_enabled, true)


func has_time_control() -> bool:
	return not ResearchManager.get_time_control_profile(player_slot).is_empty()


## Nobody casts from inside slowed time: the slowed player has to wait it out.
func can_cast_time_control() -> bool:
	return (
		movement_enabled
		and not _is_eliminated
		and _time_control_cooldown <= 0.0
		and _time_slow_timer <= 0.0
		and has_time_control()
	)


func is_time_slowed() -> bool:
	return _time_slow_timer > 0.0


func get_time_slow_left() -> float:
	return _time_slow_timer


## 1 when Time Control is ready, rising from 0 while it recharges.
func get_time_control_charge() -> float:
	if _time_control_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _time_control_cooldown / _time_control_cooldown_total, 0.0, 1.0)


func get_time_control_cooldown_left() -> float:
	return _time_control_cooldown


## Share of this player's own cast still holding the opponent slowed (1 just cast, 0 over).
func get_time_control_active_ratio() -> float:
	if _time_control_active_timer <= 0.0:
		return 0.0
	return clampf(_time_control_active_timer / _time_control_active_total, 0.0, 1.0)


## The world decides whether a cast goes through (round state, cooldown, targets); a refused press only
## answers with a sound when the player owns the ability.
func _update_time_control_input() -> void:
	if not is_time_control_pressed():
		return
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	var cast: bool = world != null and world.has_method(&"request_time_control") and world.request_time_control(self)
	if not cast and control_mode == GameSettings.CONTROL_LOCAL and has_time_control():
		AudioDirector.play(&"time_denied")


## Starts the wait after this player's own cast; active_seconds is how long the opponent stays slowed.
func begin_time_control_cooldown(cooldown: float, active_seconds: float) -> void:
	_time_control_cooldown = cooldown
	_time_control_cooldown_total = maxf(cooldown, 0.01)
	_time_control_active_timer = active_seconds
	_time_control_active_total = maxf(active_seconds, 0.01)
	_body_punch_scale = Vector2(0.86, 1.14)
	if _face != null:
		_face.set_expression(PlayerFace.Mood.FOCUS, 0.6)
	GameJuice.spawn_burst(&"time_cast", global_position, Vector2.UP, TimeFlow.COLOR)
	AudioDirector.play_at(&"time_cast", global_position)


## Runs this player's clock at `scale` for `duration` seconds (a Time Control cast on them).
func apply_time_slow(scale: float, duration: float) -> void:
	var was_slowed: bool = _time_slow_timer > 0.0
	_time_slow_scale = clampf(scale, 0.0, 1.0)
	_time_slow_timer = maxf(_time_slow_timer, duration)
	_time_slow_duration = maxf(_time_slow_timer, 0.01)
	if was_slowed:
		return
	if _face != null:
		_face.set_expression(PlayerFace.Mood.SHOCKED, 0.5)
	GameJuice.spawn_burst(&"time_slow", global_position, Vector2.UP, TimeFlow.COLOR)
	AudioDirector.play_at(&"time_slow_start", global_position)
	AudioDirector.duck_music(-8.0, duration, 0.6)
	GameJuice.shockwave(global_position, 1.5, 0.9)
	GameJuice.flash(TimeFlow.COLOR, 0.22, 0.4)
	GameJuice.aberration(1.4, 0.55)
	GameJuice.zoom_punch(0.035)


func _update_time_control(delta: float) -> void:
	_time_control_cooldown = maxf(_time_control_cooldown - delta, 0.0)
	_time_control_active_timer = maxf(_time_control_active_timer - delta, 0.0)
	if _time_slow_timer > 0.0:
		_time_slow_timer = maxf(_time_slow_timer - delta, 0.0)
		if _time_slow_timer <= 0.0:
			_play_time_slow_end()
	var previous: float = time_scale
	var target: float = _time_slow_scale if _time_slow_timer > 0.0 else 1.0
	if time_scale != target:
		time_scale = move_toward(time_scale, target, delta / TIME_RAMP_SECONDS)
	if previous < 1.0 or time_scale < 1.0:
		TimeFlow.set_scale(player_slot, time_scale, global_position)


func _play_time_slow_end() -> void:
	GameJuice.spawn_burst(&"time_release", global_position, Vector2.UP, TimeFlow.COLOR)
	AudioDirector.play_at(&"time_slow_end", global_position)
	GameJuice.shockwave(global_position, 0.7, 0.5)
	if _is_local_view_player():
		GameJuice.aberration(0.6, 0.3)


func _clear_time_slow() -> void:
	_time_slow_timer = 0.0
	if time_scale < 1.0:
		time_scale = 1.0
		TimeFlow.set_scale(player_slot, 1.0, global_position)


func _initialize_feet() -> void:
	_set_feet(
		global_position + Vector2(-foot_spread, hover_dist),
		global_position + Vector2(foot_spread, hover_dist)
	)


func _update_ground_rays() -> void:
	var target_len: float = maxf(hover_dist, GameSettings.PLAYER_FLOOR_RAY_MIN_LENGTH)
	_ray_l.target_position.y = target_len
	_ray_r.target_position.y = target_len


func _is_floor_ray(ray: RayCast2D) -> bool:
	if not ray.is_colliding():
		return false
	return ray.get_collision_normal().y <= GameSettings.PLAYER_FLOOR_NORMAL_Y_THRESHOLD


func _get_visual_move_direction() -> float:
	var input_direction: float = get_move_direction()
	if input_direction != 0.0:
		return signf(input_direction)
	if absf(velocity.x) > GameSettings.PLAYER_VISUAL_SPEED_THRESHOLD:
		return signf(velocity.x)
	return 0.0


func _set_feet(left: Vector2, right: Vector2) -> void:
	foot_pos_l = left
	foot_pos_r = right
	_step_from_l = foot_pos_l
	_step_to_l = foot_pos_l
	_step_from_r = foot_pos_r
	_step_to_r = foot_pos_r
	_step_t_l = 1.0
	_step_t_r = 1.0


func _arc(a: Vector2, b: Vector2, t: float, h: float) -> Vector2:
	var p: Vector2 = a.lerp(b, t)
	p.y -= sin(t * PI) * h
	return p


func _apply_player_palette() -> void:
	var effective_color_id: StringName = _get_effective_color_id()
	var limb_color: Color = GameSettings.player_color_value(effective_color_id)
	# The limbs only redraw when their pose moves, so a new colour has to ask for it.
	if _leg_renderer != null:
		_leg_renderer.col_leg = limb_color
		_leg_renderer.queue_redraw()
	if _arm_renderer != null:
		_arm_renderer.col_arm = limb_color
		_arm_renderer.queue_redraw()
	if _shield != null:
		_shield.self_modulate = limb_color
	if _halo != null:
		_halo.modulate = Color(limb_color.r, limb_color.g, limb_color.b, 0.2)
	if _armor_visual_root != null:
		_armor_visual_root.set_team_color(limb_color)
	var gun_visuals: WeaponExtensionVisuals = get_node_or_null(^"Gun/VisualRoot/ExtensionVisuals") as WeaponExtensionVisuals
	if gun_visuals != null:
		gun_visuals.set_accent(limb_color)
	_update_body_sprite_direction()


func _update_body_sprite_direction() -> void:
	if _body_sprite == null:
		return
	var facing_dir: float = signf(last_dir)
	if facing_dir == 0.0:
		facing_dir = 1.0
	_refresh_body_color()
	_body_sprite.flip_h = facing_dir < 0.0


func _refresh_body_color() -> void:
	var color_id: StringName = _get_effective_color_id()
	if color_id == _body_color_id:
		return
	_body_color_id = color_id
	_body_sprite.texture = _get_body_texture(color_id)
	_body_sprite.modulate = _get_body_sprite_base_modulate(color_id)


func _setup_visual_extras() -> void:
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_body_sprite.material = _body_material
	_face = PlayerFace.new()
	_face.name = "Face"
	_face.body_sprite = _body_sprite
	_face.z_index = 3
	add_child(_face)
	var shadow: GroundShadow = GroundShadow.new()
	shadow.name = "GroundShadow"
	add_child(shadow)
	_halo = Sprite2D.new()
	_halo.name = "TeamHalo"
	_halo.texture = FxLib.TEX_GLOW
	_halo.material = FxLib.additive_material()
	_halo.scale = Vector2(0.62, 0.62)
	_halo.z_index = -1
	_halo.show_behind_parent = true
	add_child(_halo)
	var block_fx: BlockShieldFx = BlockShieldFx.new()
	block_fx.name = "BlockShieldFx"
	add_child(block_fx)
	var time_fx: TimeFieldFx = TimeFieldFx.new()
	time_fx.name = "TimeFieldFx"
	add_child(time_fx)


func get_face() -> PlayerFace:
	return _face


func _get_effective_color_id() -> StringName:
	if GameSettings.is_valid_player_color(player_color_id):
		return player_color_id
	if player_slot == GameSettings.PLAYER_TWO_SLOT:
		return GameSettings.ONLINE_DEFAULT_REMOTE_COLOR
	return GameSettings.ONLINE_DEFAULT_LOCAL_COLOR


func _get_body_texture(color_id: StringName) -> Texture2D:
	var texture_path: String = _get_body_texture_path(color_id)
	if _has_body_texture_path(texture_path):
		if not _body_texture_cache.has(texture_path):
			_body_texture_cache[texture_path] = load(texture_path)
		var texture: Texture2D = _body_texture_cache[texture_path] as Texture2D
		if texture != null:
			return texture
	return DEFAULT_BODY_TEXTURE


func _has_body_texture(color_id: StringName) -> bool:
	return _has_body_texture_path(_get_body_texture_path(color_id))


func _has_body_texture_path(texture_path: String) -> bool:
	if not _body_texture_exists_cache.has(texture_path):
		_body_texture_exists_cache[texture_path] = ResourceLoader.exists(texture_path)
	return bool(_body_texture_exists_cache[texture_path])


func _get_body_texture_path(color_id: StringName) -> String:
	return BODY_TEXTURE_PATH % str(color_id)


func _get_body_sprite_base_modulate(color_id: StringName) -> Color:
	return Color.WHITE if _has_body_texture(color_id) else GameSettings.player_color_value(color_id)


func _begin_step(is_left: bool, target: Vector2) -> void:
	if absf(velocity.x) > GameSettings.PLAYER_VISUAL_SPEED_THRESHOLD:
		AudioDirector.play_at(&"step", target)
	if is_left:
		_step_from_l = foot_pos_l
		_step_to_l = target
		_step_t_l = 0.0
		_last_stepped = 0
		_last_step_time_l = _step_clock
	else:
		_step_from_r = foot_pos_r
		_step_to_r = target
		_step_t_r = 0.0
		_last_stepped = 1
		_last_step_time_r = _step_clock


func _emit_jump_feedback(direction: Vector2) -> void:
	var dust_position: Vector2 = global_position + Vector2(0.0, hover_dist - 4.0)
	_body_punch_scale = Vector2(0.78, 1.22)
	if control_mode == GameSettings.CONTROL_LOCAL:
		ResearchQuestManager.record_local_action(ResearchQuestManager.EVENT_JUMP)
	GameJuice.spawn_burst(&"jump", dust_position, direction, Color(0.86, 0.78, 0.56, 0.65))
	AudioDirector.play_at(&"jump", global_position)


func _update_surface_feedback(delta: float, grounded: bool, speed_ratio: float) -> void:
	if grounded and not _last_feedback_grounded:
		var land_speed: float = maxf(_last_feedback_velocity_y, 0.0)
		if land_speed >= GameSettings.PLAYER_LAND_EFFECT_MIN_SPEED:
			var land_ratio: float = clampf(
				land_speed / GameSettings.PLAYER_HEAVY_LAND_EFFECT_SPEED,
				0.35,
				1.35
			)
			_body_punch_scale = Vector2(1.16 + land_ratio * 0.1, 0.86 - land_ratio * 0.08)
			GameJuice.spawn_burst(&"land", global_position + Vector2(0.0, hover_dist - 3.0), Vector2.UP, Color(0.78, 0.70, 0.54, 0.7), land_ratio)
			AudioDirector.play_at(&"land_heavy" if land_ratio > 1.0 else &"land", global_position)
			if _is_local_view_player():
				GameJuice.shake(1.1 * land_ratio, 0.07)

	if grounded and speed_ratio > 0.34 and absf(velocity.x) > GameSettings.PLAYER_VISUAL_SPEED_THRESHOLD:
		_run_dust_timer -= delta
		_step_sound_timer -= delta
		if _run_dust_timer <= 0.0:
			var move_direction: Vector2 = Vector2(signf(velocity.x), 0.0)
			GameJuice.spawn_burst(&"run_dust", global_position + Vector2(0.0, hover_dist - 2.0), move_direction, Color(0.76, 0.68, 0.50, 0.5))
			_run_dust_timer = GameSettings.PLAYER_RUN_DUST_INTERVAL
	else:
		_run_dust_timer = minf(_run_dust_timer, GameSettings.PLAYER_RUN_DUST_INTERVAL)
		_step_sound_timer = minf(_step_sound_timer, GameSettings.PLAYER_STEP_SOUND_INTERVAL)

	_last_feedback_grounded = grounded
	_last_feedback_velocity_y = velocity.y


func _update_feedback_visuals(delta: float) -> void:
	if _body_sprite == null:
		return

	_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
	_hit_feedback_guard_timer = maxf(_hit_feedback_guard_timer - delta, 0.0)

	var horizontal_ratio: float = clampf(absf(velocity.x) / maxf(speed, 1.0), 0.0, 1.0)
	var target_scale: Vector2 = Vector2(1.0 + horizontal_ratio * 0.035, 1.0 - horizontal_ratio * 0.02)
	if _last_feedback_grounded and horizontal_ratio < 0.08:
		_idle_visual_time += delta
		var idle_pulse: float = sin(_idle_visual_time * 2.4) * 0.012
		target_scale = Vector2(1.0 + idle_pulse, 1.0 - idle_pulse)
	elif not _last_feedback_grounded:
		var vertical_ratio: float = clampf(absf(velocity.y) / maxf(max_fall_speed, 1.0), 0.0, 1.0)
		target_scale = Vector2(1.0 - vertical_ratio * 0.045, 1.0 + vertical_ratio * 0.075)
	else:
		_idle_visual_time = 0.0

	_body_motion_scale = _body_motion_scale.lerp(target_scale, clampf(delta * GameSettings.PLAYER_BODY_SCALE_LERP_SPEED, 0.0, 1.0))
	_body_punch_scale = _body_punch_scale.lerp(Vector2.ONE, clampf(delta * GameSettings.PLAYER_BODY_PUNCH_RETURN_SPEED, 0.0, 1.0))

	var combined_scale: Vector2 = Vector2(
		_body_motion_scale.x * _body_punch_scale.x,
		_body_motion_scale.y * _body_punch_scale.y
	)
	_body_sprite.scale = Vector2(
		_body_base_scale.x * combined_scale.x,
		_body_base_scale.y * combined_scale.y
	)

	_refresh_body_color()
	if _body_material != null:
		var hit_ratio: float = clampf(_hit_flash_timer / GameSettings.PLAYER_HIT_FLASH_TIME, 0.0, 1.0)
		if hit_ratio * hit_ratio != _shader_flash:
			_shader_flash = hit_ratio * hit_ratio
			_body_material.set_shader_parameter(&"flash", _shader_flash)
		var status_amount: float = 0.0
		var chrono: float = TimeFlow.strength_of(time_scale)
		if chrono > 0.0:
			# Slowed time wins over other status tints: it is the one the fight now turns on.
			status_amount = chrono * (0.5 + sin(Time.get_ticks_msec() * 0.003) * 0.08)
			_body_material.set_shader_parameter(&"status_tint", TimeFlow.COLOR)
		elif status_effect_manager != null and status_effect_manager.get_active_count() > 0:
			var tint: Color = status_effect_manager.get_tint_color()
			if tint != Color.WHITE:
				status_amount = 0.38 + sin(Time.get_ticks_msec() * 0.008) * 0.12
				_body_material.set_shader_parameter(&"status_tint", tint)
		if status_amount != _shader_status:
			_shader_status = status_amount
			_body_material.set_shader_parameter(&"status_amount", status_amount)
	_update_face()


func _on_health_changed(old_health: int, new_health: int) -> void:
	if new_health >= old_health or _hit_feedback_guard_timer > 0.0:
		return
	var fallback_source: Vector2 = global_position - Vector2(last_dir * 64.0, 0.0)
	apply_hit_feedback(fallback_source, old_health - new_health)


func _on_health_depleted() -> void:
	if _is_eliminated:
		return
	if ResearchManager.has_phoenix(player_slot) and not _phoenix_used:
		_phoenix_used = true
		health_component.health = maxi(1, int(roundf(float(health_component.max_health) * 0.4)))
		_hit_flash_timer = GameSettings.PLAYER_HIT_FLASH_TIME
		_body_punch_scale = Vector2(1.22, 0.78)
		GameJuice.spawn_burst(&"spawn", global_position, Vector2.UP, Color(1.0, 0.55, 0.12, 0.95))
		GameJuice.spawn_burst(&"explosion", global_position, Vector2.UP, Color(1.0, 0.55, 0.12, 0.95), 0.7)
		AudioDirector.play_at(&"phoenix", global_position)
		GameJuice.shake(3.4, 0.14)
		GameJuice.flash(Color(1.0, 0.6, 0.2, 1.0), 0.25, 0.3)
		if _face != null:
			_face.set_expression(PlayerFace.Mood.SHOCKED, 0.6)
		return
	var tint: Color = GameSettings.player_color_value(_get_effective_color_id())
	_hit_flash_timer = GameSettings.PLAYER_HIT_FLASH_TIME
	_body_punch_scale = Vector2(1.28, 0.72)
	GameJuice.spawn_burst(&"death", global_position, Vector2.UP, tint)
	AudioDirector.play_at(&"death", global_position)
	GameJuice.shake(GameSettings.PLAYER_DEATH_SHAKE_STRENGTH, GameSettings.PLAYER_DEATH_SHAKE_TIME)
	GameJuice.add_trauma(0.55)
	GameJuice.zoom_punch(0.06)
	GameJuice.flash(Color(1.0, 0.97, 0.9, 1.0), 0.32, 0.25)
	GameJuice.shockwave(global_position, 1.4, 0.7)
	GameJuice.aberration(1.4, 0.45)
	GameJuice.hitstop(0.07, 0.05)
	AudioDirector.duck_music(-10.0, 0.5, 1.4)
	ImpactDecals.splatter_around(global_position, tint, 7, 150.0)
	set_eliminated(true)


func _update_research_healing(delta: float) -> void:
	if NetworkSession.is_steam_match_active() and NetworkSession.mode != GameSettings.NETWORK_MODE_HOST:
		return
	var healing_cap_ratio: float = ResearchManager.get_passive_healing_cap(player_slot)
	var healing_rate: float = ResearchManager.get_passive_healing_rate(player_slot)
	if healing_cap_ratio <= 0.0 or healing_rate <= 0.0:
		_passive_heal_progress = 0.0
		return
	var target_health: int = int(floor(float(health_component.max_health) * healing_cap_ratio))
	var is_standing: bool = is_grounded() and absf(velocity.x) < 8.0 and absf(velocity.y) < 8.0
	if not is_standing or health_component.health >= target_health:
		_passive_heal_progress = 0.0
		return
	_passive_heal_progress += healing_rate * delta
	var heal_amount: int = int(floor(_passive_heal_progress))
	if heal_amount <= 0:
		return
	_passive_heal_progress -= float(heal_amount)
	health_component.health = mini(health_component.health + heal_amount, target_health)


func _run_delayed_damage(amount: int, duration: float, source_slot: int, source_position: Vector2) -> void:
	var tick_count: int = maxi(1, int(ceil(duration)))
	var tick_interval: float = duration / float(tick_count)
	var remaining_damage: int = amount
	for tick_index in range(tick_count):
		if not is_inside_tree() or _is_eliminated:
			return
		var ticks_left: int = tick_count - tick_index
		var tick_damage: int = maxi(1, int(roundf(float(remaining_damage) / float(ticks_left))))
		remaining_damage -= tick_damage
		var applied_damage: int = apply_resolved_damage(tick_damage, source_position)
		if tick_index == 0:
			_record_world_stat(source_slot, "hits", 1.0)
		_record_world_stat(source_slot, "damage", float(applied_damage))
		if source_slot > 0 and applied_damage > 0:
			ResearchManager.apply_local_life_steal(source_slot, applied_damage)
			_notify_player_damage_dealt(source_slot)
		if tick_index < tick_count - 1:
			await get_tree().create_timer(tick_interval, false).timeout


func _get_armor_attribute(attribute_name: StringName) -> float:
	return float(_armor_attributes.get(attribute_name, 0.0))


func _is_stationary_for_armor() -> bool:
	return is_grounded() and absf(velocity.x) < 8.0 and absf(velocity.y) < 8.0


func _notify_player_damage_dealt(source_slot: int) -> void:
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player_node: Player = node as Player
		if player_node.player_slot == source_slot:
			player_node.note_damage_dealt()
			return
