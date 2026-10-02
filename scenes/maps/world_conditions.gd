class_name WorldConditions
extends RefCounted

## Physical conditions of the map currently loaded. Maps set them through their MapProfile; players and
## projectiles read them every physics step. Defaults describe the normal world, so online matches and
## anything without a profile behave exactly as before.

static var gravity_scale: float = 1.0
static var projectile_gravity_scale: float = 1.0
static var wind: Vector2 = Vector2.ZERO


static func reset() -> void:
	gravity_scale = 1.0
	projectile_gravity_scale = 1.0
	wind = Vector2.ZERO
