class_name FirePatch
extends Node2D

## Burning ground left by Fire Rounds: a strip of flames on the floor under the impact. Every peer shows it
## (it is spawned with the impact feedback); only the side that judges hits (offline, or the host online)
## burns whoever steps into it the moment they do, then every `tick` seconds while they stay; from MK II it
## sets them burning (the "burn" status) the moment they step out or the fire dies under them, and stepping
## back in puts that burn out, so the two never burn at once. Each fighter burns at most once per `tick`, so
## dancing on the edge burns no faster than standing in it. A new patch next to one of the same owner
## refreshes it instead of stacking, so a shotgun volley makes one fire, not seven.

const MAX_PER_OWNER: int = 4
const FADE_IN: float = 0.15
const FADE_OUT: float = 0.45
const COLOR_CORE: Color = Color(1.0, 0.86, 0.42, 1.0)
const COLOR_FLAME: Color = Color(1.0, 0.45, 0.12, 1.0)
const COLOR_EMBER: Color = Color(0.85, 0.16, 0.05, 1.0)

var owner_slot: int = 0
var width: float = 80.0
var duration: float = 2.5
var damage: int = 3
var tick: float = 0.4
var afterburn: float = 0.0

var _age: float = 0.0
## Fighters standing in the fire (they get the afterburn when they leave it).
var _inside: Array[Player] = []
## Player -> seconds since this fire last burned them.
var _since_burn: Dictionary = {}
var _seed: float = 0.0


## Lights the floor under `impact` (within 600 px below), or refreshes this owner's patch already burning
## there. Returns the patch, or null when there is no floor (or only water) below.
static func ignite(world: Node, impact: Vector2, source_slot: int, data: Dictionary) -> FirePatch:
	if world == null or not world.is_inside_tree():
		return null
	var space: PhysicsDirectSpaceState2D = (world as Node2D).get_world_2d().direct_space_state if world is Node2D else null
	if space == null:
		return null
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(impact + Vector2(0.0, -6.0), impact + Vector2(0.0, 600.0), 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector2).y > -0.5:
		return null
	var floor_point: Vector2 = hit["position"]
	if floor_point.y > WorldConditions.water_level:
		return null
	var patch_width: float = float(data.get("width", 80.0))
	var mine: Array[FirePatch] = []
	for node in world.get_tree().get_nodes_in_group(&"fire_patches"):
		var other: FirePatch = node as FirePatch
		if other == null or other.owner_slot != source_slot or other.is_queued_for_deletion():
			continue
		if absf(other.global_position.x - floor_point.x) < patch_width * 0.5 and absf(other.global_position.y - floor_point.y) < 12.0:
			other._age = minf(other._age, FADE_IN)
			return other
		mine.append(other)
	if mine.size() >= MAX_PER_OWNER:
		mine[0].extinguish()
	var patch: FirePatch = FirePatch.new()
	patch.owner_slot = source_slot
	patch.width = patch_width
	patch.duration = float(data.get("duration", 2.5))
	patch.damage = maxi(1, int(roundf(float(data.get("damage", 3)))))
	patch.tick = maxf(float(data.get("tick", 0.4)), 0.1)
	patch.afterburn = float(data.get("afterburn", 0.0))
	world.add_child(patch)
	patch.global_position = floor_point
	AudioDirector.play_at(&"explosion", floor_point, -16.0, 1.7)
	return patch


func _ready() -> void:
	add_to_group(&"fire_patches")
	z_index = 4
	_seed = randf() * 100.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		extinguish()
		return
	queue_redraw()


## Goes out: whoever still stands in it starts burning (MK II+), then it is gone.
func extinguish() -> void:
	if is_queued_for_deletion():
		return
	if _judges_hits():
		for player in _inside:
			if is_instance_valid(player) and not player.is_eliminated():
				_afterburn(player)
	_inside.clear()
	queue_free()


func _physics_process(delta: float) -> void:
	if not _judges_hits():
		return
	for key in _since_burn.keys():
		_since_burn[key] = float(_since_burn[key]) + delta
	var now_inside: Array[Player] = []
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player.player_slot == owner_slot or player.is_eliminated():
			continue
		if not _covers(player.global_position):
			continue
		now_inside.append(player)
		if not _inside.has(player):
			_put_out_afterburn(player)
		# The first burn the moment they step in, then one per tick while they stay.
		if float(_since_burn.get(player, INF)) >= tick:
			_since_burn[player] = 0.0
			_burn(player)
	for player in _inside:
		if is_instance_valid(player) and not now_inside.has(player) and not player.is_eliminated():
			_afterburn(player)
	_inside = now_inside


func _covers(body: Vector2) -> bool:
	return absf(body.x - global_position.x) < width * 0.5 + 10.0 and body.y > global_position.y - 60.0 and body.y < global_position.y + 10.0


func _judges_hits() -> bool:
	if not NetworkSession.is_steam_match_active():
		return true
	var game: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	var sync: Variant = game.get("_game_sync") if game != null else null
	return sync != null and sync.is_host()


func _burn(player: Player) -> void:
	var combat: Variant = _combat()
	if combat != null:
		combat.apply_hit(player.player_slot, owner_slot, 0, damage, true, global_position)
		return
	if not NetworkSession.is_steam_match_active():
		player.apply_incoming_damage(damage, owner_slot, global_position, false)


## Stepping back into the fire puts out the burn they took with them, so fire and burn never stack.
func _put_out_afterburn(player: Player) -> void:
	if afterburn <= 0.0:
		return
	var combat: Variant = _combat()
	if combat != null:
		combat.clear_status_effect(player.player_slot, owner_slot, &"burn")
	elif player.status_effect_manager != null:
		player.status_effect_manager.remove_effects(&"burn")


## Fire Rounds MK II / III: the burn a fighter takes with them out of the fire.
func _afterburn(player: Player) -> void:
	if afterburn <= 0.0:
		return
	var burn: Dictionary = {
		"duration": afterburn,
		"tick_interval": 0.5,
		"tick_count": maxi(1, int(ceil(afterburn / 0.5))),
		"damage_per_tick": damage,
		"source_slot": owner_slot,
		"tint_color": Color(1.0, 0.55, 0.25, 1.0),
	}
	var combat: Variant = _combat()
	if combat != null:
		combat.apply_status_effect(player.player_slot, owner_slot, &"burn", burn)
	elif not NetworkSession.is_steam_match_active() and player.status_effect_manager != null:
		player.status_effect_manager.apply_effect(&"burn", burn)


## The host's combat module online, null offline.
func _combat() -> Variant:
	if not NetworkSession.is_steam_match_active():
		return null
	var game: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	var sync: Variant = game.get("_game_sync") if game != null else null
	return sync.get_module(GameSettings.MODULE_COMBAT) if sync != null else null


func _draw() -> void:
	var fade: float = minf(_age / FADE_IN, 1.0) * clampf((duration - _age) / FADE_OUT, 0.0, 1.0)
	if fade <= 0.0:
		return
	var half: float = width * 0.5
	var t: float = _age + _seed
	# Charred floor and a low glow under the flames.
	draw_rect(Rect2(-half, -2.0, width, 4.0), Color(0.08, 0.03, 0.02, 0.7 * fade))
	draw_rect(Rect2(-half, -5.0, width, 3.0), Color(COLOR_EMBER.r, COLOR_EMBER.g, COLOR_EMBER.b, 0.55 * fade))
	var count: int = maxi(3, int(width / 11.0))
	for i in range(count):
		var u: float = (float(i) + 0.5) / float(count)
		var x: float = -half + u * width
		var flicker: float = 0.6 + 0.4 * sin(t * (9.0 + float(i % 3)) + float(i) * 1.7)
		var height: float = (10.0 + 9.0 * flicker) * (1.0 - absf(u - 0.5) * 0.9) * fade
		var sway: float = sin(t * 4.0 + float(i)) * 2.2
		var base_w: float = width / float(count) * 0.75 + 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - base_w, -3.0), Vector2(x + sway, -3.0 - height), Vector2(x + base_w, -3.0)]),
			Color(COLOR_FLAME.r, COLOR_FLAME.g, COLOR_FLAME.b, 0.85 * fade))
		draw_colored_polygon(PackedVector2Array([Vector2(x - base_w * 0.45, -3.0), Vector2(x + sway * 0.6, -3.0 - height * 0.55), Vector2(x + base_w * 0.45, -3.0)]),
			Color(COLOR_CORE.r, COLOR_CORE.g, COLOR_CORE.b, 0.9 * fade))
	# A few embers rising off it.
	for e in range(3):
		var phase: float = fmod(t * 0.8 + float(e) * 0.33, 1.0)
		var ex: float = -half + fmod(float(e) * 37.0 + _seed * 13.0, width)
		draw_circle(Vector2(ex + sin(phase * 7.0) * 3.0, -6.0 - phase * 26.0), 1.3 * (1.0 - phase) + 0.4, Color(1.0, 0.7, 0.3, (1.0 - phase) * 0.8 * fade))
