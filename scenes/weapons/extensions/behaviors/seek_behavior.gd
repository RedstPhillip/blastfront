class_name SeekBehavior
extends ExtensionBehavior

## Rounds that turn toward the nearest enemy in reach (Homing, and Ground Hover MK III along the floor). Once
## a round has a target it is locked on: Homing MK II stops its drop (no_drop) and MK III gives it a one-off
## burst of speed (lock_boost). It runs on every peer like the hover; the host's snapshots keep the copies
## together and only the host's round decides the hit. A round keeps its speed and turns at most turn_rate
## degrees a second; "horizontal" rounds only turn back along the floor toward an enemy they flew past.

const DEFAULT_TURN_RATE: float = 140.0
const DEFAULT_RANGE: float = 420.0


func update(projectile: Projectile, delta: float, effect_data: Dictionary = {}) -> void:
	if projectile == null or delta <= 0.0 or not projectile.is_inside_tree():
		return
	if effect_data.get("after_bounce", false) == true and not projectile.has_bounced():
		return
	var target: Player = _nearest_enemy(projectile, float(effect_data.get("range", DEFAULT_RANGE)))
	if target == null:
		return
	if not projectile.has_meta(&"seek_locked"):
		projectile.set_meta(&"seek_locked", true)
		var boost: float = float(effect_data.get("lock_boost", 0.0))
		if boost > 0.0:
			projectile.velocity *= 1.0 + boost
	if float(effect_data.get("no_drop", 0.0)) > 0.0:
		# Cancels the gravity the round gets right after its behaviours this step.
		projectile.velocity.y -= projectile.gravity * WorldConditions.projectile_gravity_scale * delta
	var turn: float = deg_to_rad(float(effect_data.get("turn_rate", DEFAULT_TURN_RATE))) * delta
	var to_target: Vector2 = target.global_position - projectile.global_position
	if effect_data.get("horizontal", false) == true:
		# Along the floor: ease the run round toward the enemy's side, leave the height to the hover.
		if absf(to_target.x) < 24.0:
			return
		var run: float = maxf(absf(projectile.velocity.x), projectile.muzzle_speed * 0.6)
		projectile.velocity.x = move_toward(projectile.velocity.x, signf(to_target.x) * run, run * turn * 2.0)
		return
	var speed: float = projectile.velocity.length()
	if speed <= 1.0:
		return
	var current_angle: float = projectile.velocity.angle()
	var wanted: float = to_target.angle()
	var step: float = clampf(wrapf(wanted - current_angle, -PI, PI), -turn, turn)
	projectile.velocity = Vector2.from_angle(current_angle + step) * speed


static func _nearest_enemy(projectile: Projectile, reach: float) -> Player:
	var best: Player = null
	var best_distance: float = reach * reach
	for node in projectile.get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player.player_slot == projectile.owner_slot or player.is_eliminated():
			continue
		var distance: float = player.global_position.distance_squared_to(projectile.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best
