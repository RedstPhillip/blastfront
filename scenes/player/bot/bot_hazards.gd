class_name BotHazards
extends RefCounted

## Places bots keep out of: burning ground (Fire Rounds), primed grenades, anything a weapon part or a world
## may add later. A node becomes a hazard for every bot by joining GROUP and answering these calls:
##
##   get_bot_hazard_area() -> Rect2        where it hurts, in world space (a box around it is fine when
##                                         bot_hazard_covers() narrows it down)
##   bot_hazard_covers(body: Vector2) -> bool   whether a fighter's body there gets hurt (optional; the
##                                         area alone is used without it)
##   get_bot_hazard_danger() -> float      how bad standing in it is; 1 = a fire patch's burn
##   get_bot_hazard_owner() -> int         the slot it belongs to (its own fighter is never hurt by it), 0 for
##                                         the world's own hazards
##   get_bot_hazard_time_left() -> float   seconds until it is gone (INF while it lasts)
##
## Bots read a snapshot of them once a frame (collect) and query it through BotSenses, so a new hazard needs
## no bot code at all.

const GROUP: StringName = &"bot_hazards"


## Every hazard that can hurt the fighter in `for_slot`, as {"node", "area", "danger", "time_left"}.
static func collect(tree: SceneTree, for_slot: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if tree == null:
		return result
	for node in tree.get_nodes_in_group(GROUP):
		if node == null or node.is_queued_for_deletion() or not node.has_method(&"get_bot_hazard_area"):
			continue
		var owner_slot: int = int(node.call(&"get_bot_hazard_owner")) if node.has_method(&"get_bot_hazard_owner") else 0
		if owner_slot != 0 and owner_slot == for_slot:
			continue
		result.append({
			"node": node,
			"area": node.call(&"get_bot_hazard_area"),
			"danger": float(node.call(&"get_bot_hazard_danger")) if node.has_method(&"get_bot_hazard_danger") else 1.0,
			"time_left": float(node.call(&"get_bot_hazard_time_left")) if node.has_method(&"get_bot_hazard_time_left") else INF,
		})
	return result


## How bad it is to have a body at `body`: the worst hazard covering it, 0 when none does.
static func danger_at(hazards: Array[Dictionary], body: Vector2) -> float:
	var worst: float = 0.0
	for hazard in hazards:
		if _covers(hazard, body):
			worst = maxf(worst, float(hazard["danger"]))
	return worst


## Seconds until every hazard covering `body` is gone (0 when none covers it).
static func time_left_at(hazards: Array[Dictionary], body: Vector2) -> float:
	var longest: float = 0.0
	for hazard in hazards:
		if _covers(hazard, body):
			longest = maxf(longest, float(hazard["time_left"]))
	return longest


## The worst danger a body meets moving in a straight line from `from` to `to` (sampled every 16 px).
static func danger_along(hazards: Array[Dictionary], from: Vector2, to: Vector2) -> float:
	if hazards.is_empty():
		return 0.0
	var steps: int = maxi(1, int(ceil(from.distance_to(to) / 16.0)))
	var worst: float = 0.0
	for step in range(steps + 1):
		worst = maxf(worst, danger_at(hazards, from.lerp(to, float(step) / float(steps))))
	return worst


static func _covers(hazard: Dictionary, body: Vector2) -> bool:
	var area: Rect2 = hazard["area"]
	if not area.has_point(body):
		return false
	var node: Object = hazard["node"]
	if node != null and is_instance_valid(node) and node.has_method(&"bot_hazard_covers"):
		return bool(node.call(&"bot_hazard_covers", body))
	return true
