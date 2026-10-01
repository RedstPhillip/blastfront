extends Node

## Event based sound playback.
## Every event is a set of layers; each layer picks a random variation with its own volume and pitch range.
## Voices are pooled, per-event polyphony is capped and rapid retriggers are filtered to avoid phasing.

const SFX_DIR: String = "res://assets/audio/sfx/"
const UI_DIR: String = "res://assets/audio/ui/"
const STINGER_DIR: String = "res://assets/audio/stingers/"
const LEGACY_DIR: String = "res://assets/audio/"
const MUSIC_DIR: String = "res://assets/audio/music/"

const POOL_SIZE_2D: int = 40
const POOL_SIZE_GLOBAL: int = 16
const MUSIC_FADE_DEFAULT: float = 1.6
const MUFFLE_CUTOFF_OPEN: float = 20500.0
const MUFFLE_CUTOFF_CLOSED: float = 850.0

# event_id: {bus, layers: [{files, volume, pitch: Vector2}], voices, cooldown}
const EVENTS: Dictionary = {
	&"shoot": {"bus": &"SFX", "voices": 6, "cooldown": 0.02, "layers": [
		{"files": ["legacy:gun_shot.mp3"], "volume": -3.0, "pitch": Vector2(0.94, 1.06)},
		{"files": ["impact_light_0", "impact_light_1", "impact_light_2"], "volume": -15.0, "pitch": Vector2(0.55, 0.7)},
	]},
	&"dry_fire": {"bus": &"SFX", "voices": 2, "cooldown": 0.12, "layers": [
		{"files": ["ui:dry_fire"], "volume": -6.0, "pitch": Vector2(0.8, 0.9)},
	]},
	&"reload_start": {"bus": &"SFX", "voices": 2, "layers": [
		{"files": ["reload_start"], "volume": -9.0, "pitch": Vector2(0.95, 1.08)},
	]},
	&"reload_end": {"bus": &"SFX", "voices": 2, "layers": [
		{"files": ["reload_end"], "volume": -6.0, "pitch": Vector2(1.0, 1.1)},
		{"files": ["reload_mid"], "volume": -14.0, "pitch": Vector2(1.1, 1.25)},
	]},
	&"casing": {"bus": &"SFX", "voices": 5, "cooldown": 0.03, "layers": [
		{"files": ["casing_0", "casing_1", "casing_2", "casing_3", "casing_4"], "volume": -21.0, "pitch": Vector2(1.25, 1.6)},
	]},
	&"hit": {"bus": &"SFX", "voices": 4, "cooldown": 0.03, "layers": [
		{"files": ["legacy:hit.wav"], "volume": 0.0, "pitch": Vector2(0.92, 1.08)},
		{"files": ["hit_punch_0", "hit_punch_1", "hit_punch_2", "hit_punch_3", "hit_punch_4"], "volume": -3.0, "pitch": Vector2(0.9, 1.1)},
	]},
	&"hit_heavy": {"bus": &"SFX", "voices": 3, "cooldown": 0.04, "layers": [
		{"files": ["hit_heavy_0", "hit_heavy_1", "hit_heavy_2", "hit_heavy_3", "hit_heavy_4"], "volume": 0.0, "pitch": Vector2(0.85, 1.0)},
		{"files": ["legacy:hit.wav"], "volume": -2.0, "pitch": Vector2(0.8, 0.9)},
	]},
	&"impact": {"bus": &"SFX", "voices": 6, "cooldown": 0.025, "layers": [
		{"files": ["legacy:impact.wav"], "volume": -7.0, "pitch": Vector2(0.9, 1.15)},
		{"files": ["impact_soft_0", "impact_soft_1", "impact_soft_2", "impact_soft_3", "impact_soft_4"], "volume": -6.0, "pitch": Vector2(0.9, 1.2)},
		{"files": ["impact_light_0", "impact_light_1", "impact_light_2", "impact_light_3", "impact_light_4"], "volume": -12.0, "pitch": Vector2(0.9, 1.2)},
	]},
	&"block": {"bus": &"SFX", "voices": 3, "cooldown": 0.05, "layers": [
		{"files": ["shield_0", "shield_1", "shield_2", "shield_3", "shield_4"], "volume": -5.0, "pitch": Vector2(1.15, 1.35)},
		{"files": ["legacy:block.wav"], "volume": -3.0, "pitch": Vector2(0.95, 1.08)},
		{"files": ["metal_heavy_0", "metal_heavy_1", "metal_heavy_2"], "volume": -16.0, "pitch": Vector2(1.3, 1.5)},
	]},
	&"block_raise": {"bus": &"SFX", "voices": 2, "cooldown": 0.08, "layers": [
		{"files": ["shield_0", "shield_2", "shield_4"], "volume": -15.0, "pitch": Vector2(1.6, 1.8)},
	]},
	&"reflect": {"bus": &"SFX", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["metal_heavy_0", "metal_heavy_1", "metal_heavy_2", "metal_heavy_3", "metal_heavy_4"], "volume": -6.0, "pitch": Vector2(1.2, 1.4)},
		{"files": ["shield_1", "shield_3"], "volume": -8.0, "pitch": Vector2(1.4, 1.6)},
	]},
	&"jump": {"bus": &"SFX", "voices": 3, "cooldown": 0.04, "layers": [
		{"files": ["legacy:jump.wav"], "volume": -2.0, "pitch": Vector2(0.94, 1.1)},
		{"files": ["step_grass_0", "step_grass_2", "step_grass_4"], "volume": -12.0, "pitch": Vector2(1.0, 1.2)},
	]},
	&"land": {"bus": &"SFX", "voices": 3, "cooldown": 0.06, "layers": [
		{"files": ["legacy:land.wav"], "volume": -5.0, "pitch": Vector2(0.9, 1.08)},
		{"files": ["land_thud_0", "land_thud_1", "land_thud_2", "land_thud_3", "land_thud_4"], "volume": -10.0, "pitch": Vector2(0.95, 1.1)},
		{"files": ["step_grass_1", "step_grass_3"], "volume": -12.0, "pitch": Vector2(0.9, 1.0)},
	]},
	&"land_heavy": {"bus": &"SFX", "voices": 2, "cooldown": 0.08, "layers": [
		{"files": ["land_thud_0", "land_thud_1", "land_thud_2", "land_thud_3", "land_thud_4"], "volume": -3.0, "pitch": Vector2(0.8, 0.95)},
		{"files": ["legacy:land.wav"], "volume": -3.0, "pitch": Vector2(0.8, 0.9)},
	]},
	&"step": {"bus": &"SFX", "voices": 3, "cooldown": 0.06, "layers": [
		{"files": ["step_grass_0", "step_grass_1", "step_grass_2", "step_grass_3", "step_grass_4"], "volume": -15.0, "pitch": Vector2(0.95, 1.15)},
	]},
	&"wall_slide": {"bus": &"SFX", "voices": 1, "cooldown": 0.12, "layers": [
		{"files": ["step_grass_0", "step_grass_1", "step_grass_2", "step_grass_3", "step_grass_4"], "volume": -19.0, "pitch": Vector2(1.3, 1.6)},
	]},
	&"spawn": {"bus": &"SFX", "voices": 3, "cooldown": 0.05, "layers": [
		{"files": ["legacy:spawn.wav"], "volume": -4.0, "pitch": Vector2(0.96, 1.04)},
		{"files": ["teleport_0", "teleport_1"], "volume": -13.0, "pitch": Vector2(0.9, 1.05)},
	]},
	&"death": {"bus": &"SFX", "voices": 2, "cooldown": 0.1, "layers": [
		{"files": ["legacy:death.wav"], "volume": 0.0, "pitch": Vector2(0.92, 1.05)},
		{"files": ["explosion_0", "explosion_1", "explosion_3"], "volume": -5.0, "pitch": Vector2(0.95, 1.1)},
		{"files": ["boom_low_0", "boom_low_1"], "volume": -2.0, "pitch": Vector2(0.9, 1.05)},
		{"files": ["hit_heavy_0", "hit_heavy_2"], "volume": -4.0, "pitch": Vector2(0.75, 0.85)},
	]},
	&"explosion": {"bus": &"SFX", "voices": 3, "cooldown": 0.05, "layers": [
		{"files": ["explosion_0", "explosion_1", "explosion_2", "explosion_3", "explosion_4"], "volume": -2.0, "pitch": Vector2(0.9, 1.1)},
		{"files": ["boom_low_0", "boom_low_1"], "volume": -1.0, "pitch": Vector2(0.95, 1.15)},
	]},
	&"grenade_arm": {"bus": &"SFX", "voices": 3, "cooldown": 0.05, "layers": [
		{"files": ["ui:tick"], "volume": -6.0, "pitch": Vector2(1.4, 1.5)},
	]},
	&"freeze": {"bus": &"SFX", "voices": 2, "cooldown": 0.1, "layers": [
		{"files": ["ice_0", "ice_1", "ice_2", "ice_3", "ice_4"], "volume": -8.0, "pitch": Vector2(1.0, 1.3)},
	]},
	&"shock": {"bus": &"SFX", "voices": 2, "cooldown": 0.1, "layers": [
		{"files": ["zap_0", "zap_1"], "volume": -10.0, "pitch": Vector2(0.9, 1.2)},
	]},
	&"poison": {"bus": &"SFX", "voices": 2, "cooldown": 0.2, "layers": [
		{"files": ["poison_0", "poison_1"], "volume": -10.0, "pitch": Vector2(0.9, 1.2)},
	]},
	&"border_hit": {"bus": &"SFX", "voices": 2, "cooldown": 0.1, "layers": [
		{"files": ["zap_0", "zap_1"], "volume": -4.0, "pitch": Vector2(0.6, 0.75)},
		{"files": ["shield_0", "shield_3"], "volume": -6.0, "pitch": Vector2(0.7, 0.8)},
		{"files": ["hit_heavy_1", "hit_heavy_3"], "volume": -4.0, "pitch": Vector2(0.8, 0.9)},
	]},
	&"airdrop_land": {"bus": &"SFX", "voices": 1, "layers": [
		{"files": ["metal_heavy_0", "metal_heavy_2", "metal_heavy_4"], "volume": -1.0, "pitch": Vector2(0.7, 0.8)},
		{"files": ["land_thud_0", "land_thud_2"], "volume": 0.0, "pitch": Vector2(0.7, 0.8)},
	]},
	&"capture": {"bus": &"SFX", "voices": 1, "layers": [
		{"files": ["powerup_0", "powerup_1"], "volume": -3.0, "pitch": Vector2(1.0, 1.05)},
		{"files": ["coins_0", "coins_1"], "volume": -6.0, "pitch": Vector2(1.0, 1.1)},
	]},
	&"phoenix": {"bus": &"SFX", "voices": 1, "layers": [
		{"files": ["powerup_1"], "volume": -2.0, "pitch": Vector2(0.9, 0.95)},
		{"files": ["teleport_0"], "volume": -4.0, "pitch": Vector2(0.8, 0.85)},
	]},
	&"reward": {"bus": &"UI", "voices": 2, "cooldown": 0.1, "layers": [
		{"files": ["powerup_0", "powerup_1"], "volume": -7.0, "pitch": Vector2(1.08, 1.16)},
		{"files": ["coins_0", "coins_1"], "volume": -10.0, "pitch": Vector2(1.1, 1.2)},
	]},
	&"shop_purchase": {"bus": &"UI", "voices": 2, "cooldown": 0.08, "layers": [
		{"files": ["coins_0", "coins_1"], "volume": -5.0, "pitch": Vector2(1.0, 1.1)},
		{"files": ["powerup_0"], "volume": -12.0, "pitch": Vector2(1.25, 1.35)},
		{"files": ["ui:confirm"], "volume": -10.0, "pitch": Vector2(1.0, 1.05)},
	]},
	&"shop_denied": {"bus": &"UI", "voices": 1, "cooldown": 0.15, "layers": [
		{"files": ["ui:error"], "volume": -7.0, "pitch": Vector2(0.9, 0.95)},
		{"files": ["impact_soft_0", "impact_soft_2"], "volume": -14.0, "pitch": Vector2(0.7, 0.8)},
	]},
	&"equip": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["metal_heavy_1", "metal_heavy_3"], "volume": -15.0, "pitch": Vector2(1.6, 1.8)},
		{"files": ["reload_end"], "volume": -10.0, "pitch": Vector2(1.05, 1.15)},
	]},
	&"unequip": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["reload_start"], "volume": -12.0, "pitch": Vector2(1.1, 1.2)},
	]},
	&"merge": {"bus": &"UI", "voices": 1, "cooldown": 0.2, "layers": [
		{"files": ["powerup_1"], "volume": -6.0, "pitch": Vector2(1.0, 1.05)},
		{"files": ["teleport_0", "teleport_1"], "volume": -10.0, "pitch": Vector2(1.1, 1.2)},
		{"files": ["metal_heavy_0"], "volume": -12.0, "pitch": Vector2(1.3, 1.4)},
	]},
	&"recycle": {"bus": &"UI", "voices": 1, "cooldown": 0.15, "layers": [
		{"files": ["zap_0", "zap_1"], "volume": -12.0, "pitch": Vector2(0.8, 0.9)},
		{"files": ["coins_0", "coins_1"], "volume": -8.0, "pitch": Vector2(0.9, 1.0)},
	]},
	&"research_unlock": {"bus": &"UI", "voices": 1, "cooldown": 0.15, "layers": [
		{"files": ["powerup_0", "powerup_1"], "volume": -6.0, "pitch": Vector2(1.12, 1.2)},
		{"files": ["shield_1", "shield_2"], "volume": -13.0, "pitch": Vector2(1.4, 1.5)},
	]},
	&"item_move": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["impact_light_0", "impact_light_2", "impact_light_4"], "volume": -14.0, "pitch": Vector2(1.5, 1.7)},
	]},
	&"heartbeat": {"bus": &"SFX", "voices": 1, "cooldown": 0.5, "layers": [
		{"files": ["heartbeat"], "volume": -7.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"coins": {"bus": &"UI", "voices": 2, "cooldown": 0.06, "layers": [
		{"files": ["coins_0", "coins_1"], "volume": -6.0, "pitch": Vector2(0.95, 1.1)},
	]},
	&"ui_hover": {"bus": &"UI", "voices": 3, "cooldown": 0.035, "layers": [
		{"files": ["ui:hover"], "volume": -12.0, "pitch": Vector2(0.96, 1.06)},
	]},
	&"ui_click": {"bus": &"UI", "voices": 3, "cooldown": 0.03, "layers": [
		{"files": ["ui:click"], "volume": -6.0, "pitch": Vector2(0.97, 1.04)},
	]},
	&"ui_confirm": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["ui:confirm"], "volume": -7.0, "pitch": Vector2(0.98, 1.02)},
	]},
	&"ui_back": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["ui:back"], "volume": -7.0, "pitch": Vector2(0.98, 1.02)},
	]},
	&"ui_open": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["ui:open"], "volume": -8.0, "pitch": Vector2(0.98, 1.02)},
	]},
	&"ui_close": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["ui:close"], "volume": -8.0, "pitch": Vector2(0.98, 1.02)},
	]},
	&"ui_error": {"bus": &"UI", "voices": 1, "cooldown": 0.1, "layers": [
		{"files": ["ui:error"], "volume": -8.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"ui_toggle": {"bus": &"UI", "voices": 2, "cooldown": 0.04, "layers": [
		{"files": ["ui:toggle"], "volume": -8.0, "pitch": Vector2(0.97, 1.05)},
	]},
	&"ui_slider": {"bus": &"UI", "voices": 1, "cooldown": 0.06, "layers": [
		{"files": ["ui:tick"], "volume": -14.0, "pitch": Vector2(0.95, 1.1)},
	]},
	&"ui_whoosh": {"bus": &"UI", "voices": 2, "cooldown": 0.05, "layers": [
		{"files": ["ui:switch"], "volume": -10.0, "pitch": Vector2(0.8, 0.9)},
	]},
	&"ui_glitch": {"bus": &"UI", "voices": 1, "cooldown": 0.2, "layers": [
		{"files": ["ui:glitch"], "volume": -10.0, "pitch": Vector2(0.95, 1.05)},
	]},
	&"count_tick": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:count_tick"], "volume": -5.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"count_go": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:count_go"], "volume": -4.0, "pitch": Vector2(1.0, 1.0)},
		{"files": ["stinger:fight"], "volume": -3.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"round_win": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:round_win"], "volume": -4.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"round_win_big": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:round_win_big"], "volume": -3.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"match_victory": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:match_victory"], "volume": -2.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"match_defeat": {"bus": &"UI", "voices": 1, "layers": [
		{"files": ["stinger:match_defeat"], "volume": -3.0, "pitch": Vector2(1.0, 1.0)},
	]},
	&"bullet_whiz": {"bus": &"SFX", "voices": 2, "cooldown": 0.08, "layers": [
		{"files": ["shield_1", "shield_3"], "volume": -18.0, "pitch": Vector2(2.4, 2.9)},
	]},
}

const MUSIC_TRACKS: Dictionary = {
	&"menu": "menu_theme.ogg",
	&"battle": "battle_theme.ogg",
	&"locker": "locker_theme.ogg",
	&"ambience_wind": "ambience_wind.ogg",
}

var _streams: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool_global: Array[AudioStreamPlayer] = []
var _pool_cursor_2d: int = 0
var _pool_cursor_global: int = 0
var _last_play_msec: Dictionary = {}
var _active_voices: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _music_players: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _music_track: StringName = &""
var _music_tween: Tween = null
var _ambience_player: AudioStreamPlayer = null
var _ambience_track: StringName = &""
var _ambience_tween: Tween = null
var _muffle_amount: float = 0.0
var _muffle_tween: Tween = null
var _duck_tween: Tween = null
var _music_duck_db: float = 0.0
var _music_base_db: float = -6.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_load_event_streams()
	_build_pools()
	_build_music_players()


func has_event(event_id: StringName) -> bool:
	return EVENTS.has(event_id)


func play(event_id: StringName, volume_offset_db: float = 0.0, pitch_multiplier: float = 1.0) -> void:
	if not _accept_trigger(event_id):
		return
	var definition: Dictionary = EVENTS[event_id]
	for layer in definition["layers"]:
		var stream: AudioStream = _pick_stream(layer)
		if stream == null:
			continue
		var player: AudioStreamPlayer = _take_global_player()
		player.bus = definition.get("bus", &"SFX")
		_start_voice(player, stream, layer, volume_offset_db, pitch_multiplier, event_id)


func play_at(event_id: StringName, world_position: Vector2, volume_offset_db: float = 0.0, pitch_multiplier: float = 1.0) -> void:
	if not _accept_trigger(event_id):
		return
	var definition: Dictionary = EVENTS[event_id]
	if definition.get("bus", &"SFX") == &"UI":
		play(event_id, volume_offset_db, pitch_multiplier)
		return
	for layer in definition["layers"]:
		var stream: AudioStream = _pick_stream(layer)
		if stream == null:
			continue
		var player: AudioStreamPlayer2D = _take_2d_player()
		player.bus = definition.get("bus", &"SFX")
		player.global_position = world_position
		_start_voice(player, stream, layer, volume_offset_db, pitch_multiplier, event_id)


func play_music(track_id: StringName, fade_seconds: float = MUSIC_FADE_DEFAULT) -> void:
	if track_id == _music_track:
		return
	var stream: AudioStream = _load_music(track_id)
	_music_track = track_id
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var outgoing: AudioStreamPlayer = _music_players[_music_index]
	_music_index = 1 - _music_index
	var incoming: AudioStreamPlayer = _music_players[_music_index]
	if not outgoing.playing and stream == null:
		return
	_music_tween = create_tween().set_parallel(true)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", -60.0, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.tween_callback(outgoing.stop).set_delay(fade_seconds)
	if stream == null:
		return
	incoming.stream = stream
	incoming.volume_db = -50.0
	incoming.play()
	_music_tween.tween_property(incoming, "volume_db", _music_base_db, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func stop_music(fade_seconds: float = MUSIC_FADE_DEFAULT) -> void:
	_music_track = &""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_interval(fade_seconds)
	for player in _music_players:
		if player.playing:
			_music_tween.parallel().tween_property(player, "volume_db", -60.0, fade_seconds)
	_music_tween.tween_callback(func() -> void:
		for player in _music_players:
			player.stop()
	)


func play_ambience(track_id: StringName, fade_seconds: float = 2.5) -> void:
	if track_id == _ambience_track:
		return
	_ambience_track = track_id
	var stream: AudioStream = _load_music(track_id)
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if stream == null:
		_ambience_player.stop()
		return
	_ambience_player.stream = stream
	_ambience_player.volume_db = -50.0
	_ambience_player.play()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", -9.0, fade_seconds).set_trans(Tween.TRANS_SINE)


func stop_ambience(fade_seconds: float = 1.5) -> void:
	_ambience_track = &""
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", -60.0, fade_seconds)
	_ambience_tween.tween_callback(_ambience_player.stop)


## Smoothly low-passes gameplay audio, e.g. while a menu is open over the match.
func set_muffled(enabled: bool, duration: float = 0.35) -> void:
	if _muffle_tween != null and _muffle_tween.is_valid():
		_muffle_tween.kill()
	_muffle_tween = create_tween()
	_muffle_tween.tween_method(_apply_muffle, _muffle_amount, 1.0 if enabled else 0.0, duration).set_trans(Tween.TRANS_SINE)


## Temporarily lowers the music so a key moment cuts through.
func duck_music(amount_db: float = -9.0, hold_seconds: float = 0.6, release_seconds: float = 1.2) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_apply_music_duck, _music_duck_db, amount_db, 0.08)
	_duck_tween.tween_interval(hold_seconds)
	_duck_tween.tween_method(_apply_music_duck, amount_db, 0.0, release_seconds).set_trans(Tween.TRANS_SINE)


func _apply_music_duck(value_db: float) -> void:
	_music_duck_db = value_db
	var bus_index: int = AudioServer.get_bus_index(&"Music")
	if bus_index == -1:
		return
	var base_linear: float = UserSettings.get_float(UserSettings.MUSIC_VOLUME)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(base_linear, 0.0001)) + value_db)


func _apply_muffle(amount: float) -> void:
	_muffle_amount = amount
	var cutoff: float = lerpf(MUFFLE_CUTOFF_OPEN, MUFFLE_CUTOFF_CLOSED, amount * amount)
	for bus_name in [&"SFX", &"Music", &"Ambience"]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index == -1:
			continue
		for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, effect_index)
			if effect is AudioEffectLowPassFilter:
				(effect as AudioEffectLowPassFilter).cutoff_hz = cutoff
				AudioServer.set_bus_effect_enabled(bus_index, effect_index, amount > 0.001)


func _accept_trigger(event_id: StringName) -> bool:
	if not EVENTS.has(event_id):
		return false
	var definition: Dictionary = EVENTS[event_id]
	var now: int = Time.get_ticks_msec()
	var cooldown_msec: int = int(float(definition.get("cooldown", 0.0)) * 1000.0)
	if cooldown_msec > 0 and now - int(_last_play_msec.get(event_id, -100000)) < cooldown_msec:
		return false
	var max_voices: int = int(definition.get("voices", 4))
	if _count_active_voices(event_id) >= max_voices:
		return false
	_last_play_msec[event_id] = now
	return true


func _count_active_voices(event_id: StringName) -> int:
	var voices: Array = _active_voices.get(event_id, [])
	var alive: Array = []
	for voice in voices:
		if voice != null and is_instance_valid(voice) and voice.playing and voice.get_meta(&"event_id", &"") == event_id:
			alive.append(voice)
	_active_voices[event_id] = alive
	var definition: Dictionary = EVENTS[event_id]
	return int(ceil(float(alive.size()) / float(maxi(1, (definition["layers"] as Array).size()))))


func _start_voice(player: Node, stream: AudioStream, layer: Dictionary, volume_offset_db: float, pitch_multiplier: float, event_id: StringName) -> void:
	var pitch_range: Vector2 = layer.get("pitch", Vector2.ONE)
	player.stream = stream
	player.volume_db = float(layer.get("volume", 0.0)) + volume_offset_db
	player.pitch_scale = maxf(0.05, _rng.randf_range(pitch_range.x, pitch_range.y) * pitch_multiplier)
	player.set_meta(&"event_id", event_id)
	player.play()
	var voices: Array = _active_voices.get(event_id, [])
	voices.append(player)
	_active_voices[event_id] = voices


func _pick_stream(layer: Dictionary) -> AudioStream:
	var files: Array = layer.get("files", [])
	if files.is_empty():
		return null
	var key: String = str(files[_rng.randi_range(0, files.size() - 1)])
	return _streams.get(key, null) as AudioStream


func _take_2d_player() -> AudioStreamPlayer2D:
	for offset in range(_pool_2d.size()):
		var index: int = (_pool_cursor_2d + offset) % _pool_2d.size()
		if not _pool_2d[index].playing:
			_pool_cursor_2d = (index + 1) % _pool_2d.size()
			return _pool_2d[index]
	var stolen: AudioStreamPlayer2D = _pool_2d[_pool_cursor_2d]
	_pool_cursor_2d = (_pool_cursor_2d + 1) % _pool_2d.size()
	stolen.stop()
	return stolen


func _take_global_player() -> AudioStreamPlayer:
	for offset in range(_pool_global.size()):
		var index: int = (_pool_cursor_global + offset) % _pool_global.size()
		if not _pool_global[index].playing:
			_pool_cursor_global = (index + 1) % _pool_global.size()
			return _pool_global[index]
	var stolen: AudioStreamPlayer = _pool_global[_pool_cursor_global]
	_pool_cursor_global = (_pool_cursor_global + 1) % _pool_global.size()
	stolen.stop()
	return stolen


func _build_pools() -> void:
	for index in range(POOL_SIZE_2D):
		var player_2d: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player_2d.name = "Voice2D_%d" % index
		player_2d.max_distance = 2200.0
		player_2d.attenuation = 0.6
		player_2d.panning_strength = 0.75
		player_2d.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(player_2d)
		_pool_2d.append(player_2d)
	for index in range(POOL_SIZE_GLOBAL):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Voice_%d" % index
		add_child(player)
		_pool_global.append(player)


func _build_music_players() -> void:
	for index in range(2):
		var music_player: AudioStreamPlayer = AudioStreamPlayer.new()
		music_player.name = "Music_%d" % index
		music_player.bus = &"Music"
		music_player.volume_db = -60.0
		add_child(music_player)
		_music_players.append(music_player)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "Ambience"
	_ambience_player.bus = &"Ambience"
	_ambience_player.volume_db = -60.0
	add_child(_ambience_player)


func _load_event_streams() -> void:
	for event_id in EVENTS.keys():
		for layer in EVENTS[event_id]["layers"]:
			for key in layer["files"]:
				var file_key: String = str(key)
				if _streams.has(file_key):
					continue
				var stream: AudioStream = load(_resolve_path(file_key)) as AudioStream
				if stream != null:
					_streams[file_key] = stream


func _resolve_path(key: String) -> String:
	if key.begins_with("legacy:"):
		return LEGACY_DIR + key.substr(7)
	if key.begins_with("ui:"):
		return UI_DIR + key.substr(3) + ".ogg"
	if key.begins_with("stinger:"):
		return STINGER_DIR + key.substr(8) + ".ogg"
	return SFX_DIR + key + ".ogg"


func _load_music(track_id: StringName) -> AudioStream:
	if not MUSIC_TRACKS.has(track_id):
		return null
	var path: String = MUSIC_DIR + str(MUSIC_TRACKS[track_id])
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream
