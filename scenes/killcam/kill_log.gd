class_name KillLog
extends RefCounted

## Where the kill cam (see KillCam) hears about the fight: what hurt whom, who shoved whom, and one-shot
## world events worth showing again in a replay (blasts, fire patches, shockwaves, shark breaches).
## Gameplay code calls these static functions; with no kill cam listening each is one null check. Kept
## tiny and free of class references so autoloads can call it without compiling the kill cam.

## The running KillCam, or null (sandbox, menus, tests without a game).
static var listener: Object = null


## A damage source landed on target. Only the host (or an offline game) decides a kill's label from these.
## cause: &"round", &"fire", &"shark", &"border", &"status"; data carries what the label needs.
static func note_damage(target: Node, cause: StringName, data: Dictionary = {}) -> void:
	if listener != null:
		listener.call(&"_on_damage_noted", target, cause, data)


## target was thrown by source_slot: kind &"slam", &"dash" or &"impact" (a hit's shove, a blast's push).
static func note_shove(target: Node, source_slot: int, kind: StringName) -> void:
	if listener != null:
		listener.call(&"_on_shove_noted", target, source_slot, kind)


## A one-shot event in the world, recorded with the round so the replay can show it again:
## &"blast" (data.radius), &"fire", &"shockwave" (data.slam, data.tint), &"breach".
static func note_event(kind: StringName, world_position: Vector2, data: Dictionary = {}) -> void:
	if listener != null:
		listener.call(&"_on_event_noted", kind, world_position, data)
