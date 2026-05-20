class_name GameSettings
extends RefCounted

const PLAYER_ONE_SLOT: int = 1
const PLAYER_TWO_SLOT: int = 2
const HALF: float = 0.5
const MILLISECONDS_PER_SECOND: float = 1000.0

const GAME_WORLD_GROUP: StringName = &"game_world"
const PLAYERS_GROUP: StringName = &"players"
const LOCAL_PLAYERS_GROUP: StringName = &"local_players"
const MAP_BOUNDS_GROUP: StringName = &"map_bounds"
const PLAYER_ONE_SPAWN_MARKER: StringName = &"Spawn1"
const PLAYER_TWO_SPAWN_MARKER: StringName = &"Spawn2"

const PLAYER_ONE_SPAWN: Vector2 = Vector2(200.0, 116.0)
const PLAYER_TWO_SPAWN: Vector2 = Vector2(1100.0, 116.0)
const PLAYER_ONE_START_FACING: float = 1.0
const PLAYER_TWO_START_FACING: float = -1.0
const MATCH_WINS_NEEDED: int = 2
const ONLINE_SET_KILLS_TO_WIN: int = 2
const ONLINE_MATCH_SET_WINS_TO_WIN: int = 7
const ONLINE_KILL_BANNER_SECONDS: float = 2.0
const ONLINE_INTERMISSION_SECONDS: float = 60.0
const ONLINE_LOCKER_COUNTDOWN_SECONDS: float = 3.0
const ONLINE_DEFAULT_LOCAL_COLOR: StringName = &"blue"
const ONLINE_DEFAULT_REMOTE_COLOR: StringName = &"red"
const MATCH_PHASE_LOCKER: StringName = &"locker"
const MATCH_PHASE_PLAYING_SET: StringName = &"playing_set"
const MATCH_PHASE_KILL_BANNER: StringName = &"kill_banner"
const MATCH_PHASE_INTERMISSION: StringName = &"intermission"
const MATCH_PHASE_FINAL: StringName = &"final"
const CAMERA_FOLLOW_SPEED: float = 5.0
const CAMERA_ZOOM_SPEED: float = 4.5
const CAMERA_MIN_ZOOM: float = 0.64
const CAMERA_MAX_ZOOM: float = 1.0
const CAMERA_ONLINE_ZOOM: float = 0.86
const CAMERA_DUEL_PADDING_X: float = 420.0
const CAMERA_Y: float = 360.0
const DEFAULT_MAP_BOUNDS: Rect2 = Rect2(0.0, 0.0, 2262.0, 720.0)
const DEFAULT_WORLD_SNAPSHOT_RATE: float = 10.0

const STEAM_APP_ID: int = 4714540
const STEAM_INIT_OK: int = 0
const STEAM_LOBBY_CREATE_OK: int = 1
const STEAM_OFFLINE_NAME: String = "Offline"
const STEAM_NOT_INITIALIZED_MESSAGE: String = "Steam not initialized"
const STEAM_CONNECT_LOBBY_ARG: String = "+connect_lobby"

const NETWORK_MODE_OFFLINE: StringName = &"offline"
const NETWORK_MODE_HOST: StringName = &"host"
const NETWORK_MODE_CLIENT: StringName = &"client"
const NETWORK_PROTOCOL_VERSION: int = 1
const NETWORK_GAME_KEY: String = "blastfront"
const NETWORK_GAME_VERSION: String = "invite-test-1"
const NETWORK_LOBBY_MODE: String = "friend-invite-test"
const NETWORK_LOBBY_MAX_MEMBERS: int = 2
const NETWORK_CHANNEL_CONTROL: int = 0
const NETWORK_CHANNEL_STATE: int = 1
const NETWORK_CHANNEL_EVENTS: int = 2
const NETWORK_DEFAULT_CHANNEL: int = -1
const NETWORK_PACKET_READ_LIMIT: int = 32
const NETWORK_PLAYER_STATE_RATE: float = 30.0
const NETWORK_FIRST_PROJECTILE_ID: int = 1
const NETWORK_LAST_SHOT_INITIAL_TIME: float = -1000000.0

const MODULE_BLOCK: StringName = &"block"
const MODULE_COMBAT: StringName = &"combat"
const MODULE_PLAYER: StringName = &"player"
const MODULE_PROJECTILE: StringName = &"projectile"

const PACKET_BLOCK_STARTED: StringName = &"block_started"
const PACKET_BLOCK_ENDED: StringName = &"block_ended"
const PACKET_BLOCK_STATE: StringName = &"block_state"
const PACKET_HEALTH_CHANGED: StringName = &"health_changed"
const PACKET_PLAYER_HIT: StringName = &"player_hit"
const PACKET_PLAYER_KILLED: StringName = &"player_killed"
const PACKET_PLAYER_SNAPSHOT: StringName = &"player_snapshot"
const PACKET_PROJECTILE_DESPAWNED: StringName = &"projectile_despawned"
const PACKET_PROJECTILE_SNAPSHOT: StringName = &"projectile_snapshot"
const PACKET_PROJECTILE_SPAWNED: StringName = &"projectile_spawned"
const PACKET_SHOT_REQUEST: StringName = &"shot_request"
const PACKET_WORLD_SNAPSHOT: StringName = &"world_snapshot"
const PACKET_ONLINE_MATCH_STATE: StringName = &"online_match_state"
const PACKET_ONLINE_PLAYER_COLOR: StringName = &"online_player_color"
const PACKET_ONLINE_LOCKER_READY: StringName = &"online_locker_ready"
const PACKET_ONLINE_INTERMISSION_READY: StringName = &"online_intermission_ready"
const PACKET_ONLINE_LOCKER_PLAYER_STATE: StringName = &"online_locker_player_state"

const CONTROL_LOCAL: StringName = &"local"
const CONTROL_REMOTE: StringName = &"remote"

const INPUT_P1_MOVE_LEFT: StringName = &"p1_move_left"
const INPUT_P1_MOVE_RIGHT: StringName = &"p1_move_right"
const INPUT_P1_JUMP: StringName = &"p1_jump"
const INPUT_P1_SHOOT: StringName = &"p1_shoot"
const INPUT_P2_MOVE_LEFT: StringName = &"p2_move_left"
const INPUT_P2_MOVE_RIGHT: StringName = &"p2_move_right"
const INPUT_P2_JUMP: StringName = &"p2_jump"
const INPUT_P2_SHOOT: StringName = &"p2_shoot"

const DEFAULT_MAX_HEALTH: int = 100
const MIN_MAX_HEALTH: int = 1
const PROJECTILE_DAMAGE: int = 10

const PLAYER_GRAVITY: float = 1350.0
const PLAYER_WALL_SLIDE_SPEED: float = 80.0
const PLAYER_AIR_SPEED: float = 120.0
const PLAYER_SPEED: float = 250.0
const PLAYER_GROUND_ACCELERATION: float = 6000.0
const PLAYER_GROUND_FRICTION: float = 5500.0
const PLAYER_AIR_ACCELERATION: float = 3000.0
const PLAYER_AIR_FRICTION: float = 1000.0
const PLAYER_FALL_GRAVITY_MULTIPLIER: float = 1.5
const PLAYER_LOW_JUMP_GRAVITY_MULTIPLIER: float = 2.5
const PLAYER_WALL_GRAVITY_MULTIPLIER: float = 0.55
const PLAYER_JUMP_VELOCITY: float = 500.0
const PLAYER_COYOTE_TIME: float = 0.12
const PLAYER_JUMP_BUFFER_TIME: float = 0.12
const PLAYER_WALL_COYOTE_TIME: float = 0.15
const PLAYER_MAX_FALL_SPEED: float = 720.0
const PLAYER_WALL_JUMP_VELOCITY: Vector2 = Vector2(320.0, -500.0)
const PLAYER_HOVER_DISTANCE: float = 24.0
const PLAYER_HOVER_SNAP_SPEED: float = 30.0
const PLAYER_FOOT_SPREAD: float = 12.0
const PLAYER_HIP_Y_OFFSET: float = 13.5
const PLAYER_BOUNCE_AMPLITUDE: float = 1.5
const PLAYER_LOOK_AHEAD: float = 0.155
const PLAYER_STEP_TRIGGER: float = 7.5
const PLAYER_STEP_DURATION: float = 0.10
const PLAYER_STEP_ARC_HEIGHT: float = 5.0
const PLAYER_STRIDE_MIN_INTERVAL: float = 0.08
const PLAYER_AIR_FOOT_TUCK_X: float = 10.5
const PLAYER_AIR_FOOT_TUCK_Y: float = 7.5
const PLAYER_REMOTE_INTERPOLATION_SPEED: float = 25.0
const PLAYER_FLOOR_NORMAL_Y_THRESHOLD: float = -0.5
const PLAYER_MIN_VECTOR_LENGTH_SQUARED: float = 0.0001
const PLAYER_REMOTE_AIM_DISTANCE: float = 80.0
const PLAYER_REMOTE_FACING_SPEED_THRESHOLD: float = 1.0
const PLAYER_VISUAL_SPEED_THRESHOLD: float = 20.0
const PLAYER_FLOOR_RAY_MIN_LENGTH: float = 8.0
const PLAYER_EDGE_GAP_MULTIPLIER: float = 1.25
const PLAYER_BOUNCE_SPEED: float = 8.0
const PLAYER_AIR_FOOT_HOVER_MULTIPLIER: float = 0.7
const PLAYER_AIR_FOOT_LERP_SPEED: float = 10.0
const PLAYER_VISUAL_ROTATION_SCALE: float = 0.08
const PLAYER_VISUAL_ROTATION_LERP_SPEED: float = 10.0
const PLAYER_INITIAL_STEP_TIME: float = -1000.0
const PLAYER_BODY_SCALE_LERP_SPEED: float = 14.0
const PLAYER_BODY_PUNCH_RETURN_SPEED: float = 12.0
const PLAYER_HIT_FLASH_TIME: float = 0.16
const PLAYER_HIT_KNOCKBACK_X: float = 115.0
const PLAYER_HIT_KNOCKBACK_Y: float = 72.0
const PLAYER_HIT_SHAKE_STRENGTH: float = 5.0
const PLAYER_HIT_SHAKE_TIME: float = 0.10
const PLAYER_DEATH_SHAKE_STRENGTH: float = 8.0
const PLAYER_DEATH_SHAKE_TIME: float = 0.18
const PLAYER_SPAWN_SHAKE_STRENGTH: float = 2.2
const PLAYER_SPAWN_SHAKE_TIME: float = 0.08
const PLAYER_RUN_DUST_INTERVAL: float = 0.105
const PLAYER_STEP_SOUND_INTERVAL: float = 0.42
const PLAYER_LAND_EFFECT_MIN_SPEED: float = 190.0
const PLAYER_HEAVY_LAND_EFFECT_SPEED: float = 430.0

const PLAYER_BLUE_LIMB_COLOR: Color = Color8(80, 170, 255, 255)
const PLAYER_RED_LIMB_COLOR: Color = Color8(235, 80, 80, 255)
const DEFAULT_LIMB_COLOR: Color = Color8(238, 130, 238, 255)

const LEG_UPPER_LENGTH: float = 9.75
const LEG_LOWER_LENGTH: float = 9.0
const LEG_LINE_WIDTH: float = 2.25
const LEG_BEZIER_POINTS: int = 16
const LEG_KNEE_SMOOTH: float = 8.0
const LEG_WALL_HIP_X: float = 8.5
const LEG_WALL_FOOT_X: float = 15.5
const LEG_WALL_FOOT_GAP: float = 9.0
const LEG_WALL_MIN_Y_VELOCITY: float = -20.0
const LEG_HIP_OFFSET: float = 4.0
const LEG_HIP_SPREAD_MULTIPLIER: float = 0.4
const LEG_WALL_KNEE_SMOOTH_MULTIPLIER: float = 1.5
const LIMB_REACH_MARGIN: float = 0.5
const IK_MIN_EXTENSION: float = 0.01

const ARM_UPPER_LENGTH: float = 12.5
const ARM_LOWER_LENGTH: float = 12.0
const ARM_LINE_WIDTH: float = 2.25
const ARM_SHOULDER_Y: float = -2.0
const ARM_SHOULDER_SPREAD: float = 6.75
const ARM_BEZIER_POINTS: int = 16
const ARM_GUARD_HAND_X: float = 30.0
const ARM_GUARD_HAND_Y: float = 6.5
const ARM_GUARD_FOLLOW_X: float = 4.0
const ARM_GUARD_FOLLOW_Y: float = 5.0
const ARM_GLOVE_ROTATION_OFFSET_DEGREES: float = 0.0

const GUN_ORBIT_RADIUS: float = 30.0
const GUN_AIM_ANGLE_OFFSET_DEGREES: float = 180.0
const GUN_FIRE_INTERVAL: float = 0.12
const GUN_AUTOMATIC_FIRE: bool = false
const GUN_PROJECTILE_SPEED: float = 1200.0
const GUN_PROJECTILE_GRAVITY: float = 2500.0
const GUN_PROJECTILE_LINEAR_DAMPING: float = 0.0
const GUN_PROJECTILE_MAX_DISTANCE: float = 1400.0
const GUN_RECOIL_DISTANCE: float = 10.0
const GUN_RECOIL_RETURN_SPEED: float = 70.0
const GUN_RECOIL_ROTATION_DEGREES: float = 5.0
const GUN_FIRE_SHAKE_STRENGTH: float = 2.6
const GUN_FIRE_SHAKE_TIME: float = 0.055

const PROJECTILE_MUZZLE_SPEED: float = 1200.0
const PROJECTILE_GRAVITY: float = 980.0
const PROJECTILE_MAX_DISTANCE: float = 1400.0
const PROJECTILE_LINEAR_DAMPING: float = 0.0
const PROJECTILE_ROTATE_TO_VELOCITY: bool = true
const PROJECTILE_SNAPSHOT_INTERPOLATION: float = 0.6
const PROJECTILE_REMOTE_COLLISION_MASK: int = 0
const PROJECTILE_IMPACT_SHAKE_STRENGTH: float = 2.0
const PROJECTILE_IMPACT_SHAKE_TIME: float = 0.05

const MAP_BORDER_WARN_DISTANCE: float = 50.0
const MAP_BORDER_LINE_LENGTH: float = 60.0
const MAP_BORDER_LINE_THICKNESS: float = 5.0
const MAP_BORDER_LINE_COLOR: Color = Color(1.0, 0.0, 0.0, 0.85)
const MAP_BORDER_THICKNESS: float = 24.0
const MAP_BORDER_KNOCKBACK_SPEED: float = 1250.0
const MAP_BORDER_KNOCKBACK_LIFT: float = 380.0
const MAP_BORDER_BOTTOM_KNOCKBACK_SPEED: float = 1500.0
const MAP_BORDER_DAMAGE: int = 50
const MAP_BORDER_HIT_COOLDOWN: float = 0.25
const MAP_BORDER_INITIAL_HIT_TIME: float = -1000.0
const MAP_BORDER_COLLISION_MASK: int = 2
const MAP_BORDER_LINE_Z_INDEX: int = 100
const MAP_BORDER_SIDE_LEFT: StringName = &"left"
const MAP_BORDER_SIDE_RIGHT: StringName = &"right"
const MAP_BORDER_SIDE_TOP: StringName = &"top"
const MAP_BORDER_SIDE_BOTTOM: StringName = &"bottom"

const HEALTH_BAR_WIDTH: float = 28.0
const HEALTH_BAR_HEIGHT: float = 4.0
const HEALTH_BAR_OFFSET_Y: float = -26.0
const HEALTH_BAR_LOW_RATIO: float = 0.34
const HEALTH_BAR_BACKGROUND_COLOR: Color = Color8(40, 40, 40, 180)
const HEALTH_BAR_HEALTHY_COLOR: Color = Color8(70, 200, 70, 230)
const HEALTH_BAR_LOW_COLOR: Color = Color8(220, 50, 50, 230)
const HEALTH_BAR_BORDER_COLOR: Color = Color8(0, 0, 0, 120)
const HEALTH_BAR_BORDER_WIDTH: float = 1.0
const HEALTH_BAR_DAMAGE_TRAIL_COLOR: Color = Color8(255, 190, 70, 135)
const HEALTH_BAR_FLASH_COLOR: Color = Color8(255, 245, 180, 210)
const HEALTH_BAR_DAMAGE_FLASH_TIME: float = 0.18
const HEALTH_BAR_DAMAGE_SHAKE_TIME: float = 0.14
const HEALTH_BAR_DAMAGE_SHAKE: float = 1.7
const HEALTH_BAR_LAG_SPEED: float = 1.85
const HEALTH_BAR_LOW_PULSE_SPEED: float = 7.5

const PLAYER_COLOR_RED: StringName = &"red"
const PLAYER_COLOR_BLUE: StringName = &"blue"
const PLAYER_COLOR_GREEN: StringName = &"green"
const PLAYER_COLOR_YELLOW: StringName = &"yellow"
const PLAYER_COLOR_ORANGE: StringName = &"orange"
const PLAYER_COLOR_PURPLE: StringName = &"purple"
const PLAYER_COLOR_CYAN: StringName = &"cyan"
const PLAYER_COLOR_PINK: StringName = &"pink"
const PLAYER_COLOR_WHITE: StringName = &"white"
const PLAYER_COLOR_CHARCOAL: StringName = &"charcoal"


static func game_config() -> Dictionary:
	return {
		"spawn_left": PLAYER_ONE_SPAWN,
		"spawn_right": PLAYER_TWO_SPAWN,
		"wins_needed": MATCH_WINS_NEEDED,
		"camera_follow_speed": CAMERA_FOLLOW_SPEED,
		"camera_y": CAMERA_Y,
		"snapshot_rate": DEFAULT_WORLD_SNAPSHOT_RATE,
	}


static func default_score() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: 0,
		PLAYER_TWO_SLOT: 0,
	}


static func default_block_state() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: false,
		PLAYER_TWO_SLOT: false,
	}


static func default_ready_state() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: false,
		PLAYER_TWO_SLOT: false,
	}


static func default_player_colors() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: ONLINE_DEFAULT_LOCAL_COLOR,
		PLAYER_TWO_SLOT: ONLINE_DEFAULT_REMOTE_COLOR,
	}


static func player_color_ids() -> Array[StringName]:
	return [
		PLAYER_COLOR_RED,
		PLAYER_COLOR_BLUE,
		PLAYER_COLOR_GREEN,
		PLAYER_COLOR_YELLOW,
		PLAYER_COLOR_ORANGE,
		PLAYER_COLOR_PURPLE,
		PLAYER_COLOR_CYAN,
		PLAYER_COLOR_PINK,
		PLAYER_COLOR_WHITE,
		PLAYER_COLOR_CHARCOAL,
	]


static func is_valid_player_color(color_id: StringName) -> bool:
	return player_color_ids().has(color_id)


static func player_color_value(color_id: StringName) -> Color:
	match color_id:
		PLAYER_COLOR_RED:
			return Color8(235, 80, 80, 255)
		PLAYER_COLOR_BLUE:
			return Color8(80, 170, 255, 255)
		PLAYER_COLOR_GREEN:
			return Color8(80, 210, 125, 255)
		PLAYER_COLOR_YELLOW:
			return Color8(245, 220, 80, 255)
		PLAYER_COLOR_ORANGE:
			return Color8(245, 145, 55, 255)
		PLAYER_COLOR_PURPLE:
			return Color8(170, 100, 245, 255)
		PLAYER_COLOR_CYAN:
			return Color8(70, 220, 220, 255)
		PLAYER_COLOR_PINK:
			return Color8(245, 115, 190, 255)
		PLAYER_COLOR_WHITE:
			return Color8(235, 235, 235, 255)
		PLAYER_COLOR_CHARCOAL:
			return Color8(55, 62, 72, 255)
		_:
			return player_color_value(ONLINE_DEFAULT_LOCAL_COLOR)


static func player_color_display_name(color_id: StringName) -> String:
	match color_id:
		PLAYER_COLOR_RED:
			return "Red"
		PLAYER_COLOR_BLUE:
			return "Blue"
		PLAYER_COLOR_GREEN:
			return "Green"
		PLAYER_COLOR_YELLOW:
			return "Yellow"
		PLAYER_COLOR_ORANGE:
			return "Orange"
		PLAYER_COLOR_PURPLE:
			return "Purple"
		PLAYER_COLOR_CYAN:
			return "Cyan"
		PLAYER_COLOR_PINK:
			return "Pink"
		PLAYER_COLOR_WHITE:
			return "White"
		PLAYER_COLOR_CHARCOAL:
			return "Charcoal"
		_:
			return "Blue"


static func player_slots() -> Array[int]:
	return [PLAYER_ONE_SLOT, PLAYER_TWO_SLOT]


static func border_sides() -> Array[StringName]:
	return [
		MAP_BORDER_SIDE_LEFT,
		MAP_BORDER_SIDE_RIGHT,
		MAP_BORDER_SIDE_TOP,
		MAP_BORDER_SIDE_BOTTOM,
	]
