class_name WorldConditions
extends RefCounted

## Physical conditions of the map currently loaded. Maps set them through their MapProfile (and weather);
## players, projectiles, the laser sight and the bot read them every physics step. Defaults describe the
## normal world, so online matches and anything without a profile behave exactly as before.

## Projectile acceleration (px/s²) per px/s of wind for a reference round (1000 px/s, scale 1).
const PROJECTILE_WIND_ACCEL: float = 2.4
## How far upwind terrain is checked for shelter, and how much wind still reaches a sheltered spot.
const SHELTER_DISTANCE: float = 170.0
const SHELTERED_EXPOSURE: float = 0.18
const WORLD_MASK: int = 1

static var gravity_scale: float = 1.0
static var projectile_gravity_scale: float = 1.0
static var projectile_range_scale: float = 1.0
## Wind as air speed in px/s (only x is used for now). Its sign is the direction the storm blows to.
static var wind: Vector2 = Vector2.ZERO
## 0 = calm, 1 = full storm. Drives cues (HUD, audio, haze) rather than physics.
static var storm: float = 0.0
## 1 = clear air, towards 0 = whiteout. Scales how far players (and the bot) can see.
static var visibility: float = 1.0


static func reset() -> void:
	gravity_scale = 1.0
	projectile_gravity_scale = 1.0
	projectile_range_scale = 1.0
	wind = Vector2.ZERO
	storm = 0.0
	visibility = 1.0


static func has_wind() -> bool:
	return absf(wind.x) > 0.5


## How strongly the wind pushes a projectile: fast rounds cut through, slow light pellets drift, big and
## heavy payloads resist. The laser sight and the bot use the same number, so the drift is predictable.
static func projectile_wind_response(muzzle_speed: float, projectile_scale: float, tags: Array, source_extensions: Array) -> float:
	var response: float = clampf(1000.0 / maxf(muzzle_speed, 200.0), 0.28, 1.7)
	response /= clampf(sqrt(maxf(projectile_scale, 0.1)), 0.7, 1.8)
	if tags.has("bouncy"):
		response *= 1.3
	if tags.has("grenade"):
		response *= 0.75
	if tags.has("explosive"):
		response *= 0.85
	if tags.has("drill") or tags.has("hover"):
		response *= 0.7
	if source_extensions.has("shotgun_mk1"):
		response *= 1.35
	return response


static func projectile_wind_acceleration(response: float) -> Vector2:
	return Vector2(wind.x * PROJECTILE_WIND_ACCEL * response, 0.0)


## Fraction of the wind that reaches a point: terrain upwind within SHELTER_DISTANCE (a mesa step, the
## crater rim, the spire) puts the point in its wind shadow.
static func wind_exposure_at(space: PhysicsDirectSpaceState2D, point: Vector2, exclude: Array[RID] = []) -> float:
	if space == null or not has_wind():
		return 1.0
	var upwind: Vector2 = Vector2(-signf(wind.x), 0.0)
	var best: float = 1.0
	for height in [0.0, -18.0]:
		var from: Vector2 = point + Vector2(0.0, height)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, from + upwind * SHELTER_DISTANCE, WORLD_MASK)
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return 1.0
		var distance: float = from.distance_to(hit["position"])
		best = minf(best, lerpf(SHELTERED_EXPOSURE, 0.6, clampf(distance / SHELTER_DISTANCE, 0.0, 1.0)))
	return best
