class_name TimeFlow
extends RefCounted

## How fast time runs for each player (Time Control research). 1 is normal. A slowed player's movement,
## gun, block, bot thinking and every round they fired run on their own clock, while everybody else keeps
## full speed. Kept per player slot instead of Engine.time_scale, so an online host can hand each peer its
## own value. Effects spawned near a slowed player read scale_at() so their particles crawl as well.

## The look of slowed time: grade, aura, projectile tint and HUD chips.
const COLOR: Color = Color(0.64, 0.52, 1.0, 1.0)
## Around a slowed player, effects slow down inside this radius and recover towards its edge.
const FIELD_RADIUS: float = 170.0

static var _scales: Dictionary = {}
static var _positions: Dictionary = {}
## True while any player runs slow; every reader takes the fast path otherwise.
static var active: bool = false


static func scale_for(slot: int) -> float:
	if not active:
		return 1.0
	return float(_scales.get(slot, 1.0))


## Called every frame by a slowed player with its current scale and position; 1 removes the slot.
static func set_scale(slot: int, value: float, world_position: Vector2) -> void:
	if value >= 0.999:
		_scales.erase(slot)
		_positions.erase(slot)
	else:
		_scales[slot] = value
		_positions[slot] = world_position
	active = not _scales.is_empty()


static func reset() -> void:
	_scales.clear()
	_positions.clear()
	active = false


## Time scale an effect at this point should run with: the slowed player's own scale near them, easing
## back to 1 towards the edge of the field.
static func scale_at(world_position: Vector2) -> float:
	if not active:
		return 1.0
	var result: float = 1.0
	for slot in _scales.keys():
		var distance: float = world_position.distance_to(_positions[slot])
		if distance >= FIELD_RADIUS:
			continue
		var reach: float = 1.0 - smoothstep(FIELD_RADIUS * 0.6, FIELD_RADIUS, distance)
		result = minf(result, lerpf(1.0, float(_scales[slot]), reach))
	return result


## The most slowed player right now as {slot, scale, position}, or {} when time runs normally. Drives the
## screen grade, which only has room for one centre.
static func strongest() -> Dictionary:
	if not active:
		return {}
	var best_slot: int = 0
	var best_scale: float = 1.0
	for slot in _scales.keys():
		if float(_scales[slot]) < best_scale:
			best_scale = float(_scales[slot])
			best_slot = int(slot)
	if best_slot == 0:
		return {}
	return {"slot": best_slot, "scale": best_scale, "position": _positions[best_slot]}


## 0 for normal time, 1 for the full Mk I slow and beyond: how strongly cues (grade, tint, aura) show.
static func strength_of(scale: float) -> float:
	return clampf((1.0 - scale) / 0.6, 0.0, 1.0)
