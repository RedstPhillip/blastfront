class_name ExtensionEffectRegistry
extends Node

const POISON_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/poison_effect.gd")
const FREEZE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/freeze_effect.gd")
const SHOCK_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/shock_effect.gd")
const EXPLOSIVE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/explosive_effect.gd")
const GRENADE_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/grenade_effect.gd")

## Explosive Bullet MK III: the second blast goes off this long after the first, on the nearest enemy
## still within AFTERSHOCK_REACH times the blast's radius (the first blast's throw carries them away), with
## AFTERSHOCK_RADIUS times its radius; with nobody in reach it goes off where the first did.
const AFTERSHOCK_DELAY: float = 0.3
const AFTERSHOCK_REACH: float = 2.2
const AFTERSHOCK_RADIUS: float = 0.6

static var effects: Dictionary = {
	&"poison": POISON_EFFECT_SCRIPT.new(),
	&"freeze": FREEZE_EFFECT_SCRIPT.new(),
	&"shock": SHOCK_EFFECT_SCRIPT.new(),
	&"explosive": EXPLOSIVE_EFFECT_SCRIPT.new(),
	&"grenade": GRENADE_EFFECT_SCRIPT.new(),
}


## A short stun dressed as a single shock tick, so the stagger traits (and blast stuns) travel the same way
## as every other status effect, online too.
static func stagger_data(duration: float) -> Dictionary:
	return {
		"duration": duration + 0.05,
		"tick_count": 1,
		"tick_interval": 0.01,
		"stun_duration": duration,
		"tint_color": Color(1.0, 0.96, 0.82, 1.0),
	}


## A blast's throw on someone at target_position: away from the blast, mostly sideways and a little up.
static func blast_knockback(origin: Vector2, target_position: Vector2, strength: float) -> Vector2:
	if strength <= 0.0:
		return Vector2.ZERO
	var side: float = signf(target_position.x - origin.x)
	if side == 0.0:
		side = 1.0
	return Vector2(side * strength, -strength * 0.55)


## Offline counterpart of the host's blast throw and stun: moves the player straight away when this side
## runs it.
static func apply_blast_extras(target: Player, origin: Vector2, push: float, stun: float) -> void:
	if target == null or target.is_eliminated():
		return
	var knockback: Vector2 = blast_knockback(origin, target.global_position, push)
	if knockback != Vector2.ZERO:
		target.receive_hit_knockback(knockback)
	if stun > 0.0:
		target.apply_stun(stun)


## Where the MK III second blast goes off: on the nearest living enemy of owner_slot within reach of
## origin, else at origin. Every peer asks this at the same moment, so they agree closely enough.
static func aftershock_origin(origin: Vector2, owner_slot: int, blast_radius: float) -> Vector2:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return origin
	var best: Vector2 = origin
	var best_distance: float = pow(blast_radius * AFTERSHOCK_REACH, 2.0)
	for node in tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player == null or player.is_eliminated() or player.player_slot == owner_slot:
			continue
		var distance: float = player.global_position.distance_squared_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = player.global_position
	return best


## The MK III second blast's look, on every peer (damage stays with the authority).
static func show_aftershock(origin: Vector2, owner_slot: int, blast_radius: float) -> void:
	GameJuice.spawn_explosion(aftershock_origin(origin, owner_slot, blast_radius), blast_radius * AFTERSHOCK_RADIUS)


static func has_effect(effect_name: StringName) -> bool:
	return effects.has(effect_name)


static func apply_projectile_effects(target: Player, projectile: Projectile) -> void:
	var projectile_effects: Dictionary = projectile.extension_effects
	for raw_effect_name in projectile_effects.keys():
		var effect_name: StringName = StringName(str(raw_effect_name))
		var effect: ExtensionEffect = effects.get(effect_name, null) as ExtensionEffect
		if effect == null:
			continue

		var effect_data: Variant = projectile_effects[raw_effect_name]
		effect.apply(target, effect_data, projectile)
