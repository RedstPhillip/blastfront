class_name BotStance
extends RefCounted

## How a bot's own condition changes the way it fights. Each condition the bot is in (see conditions())
## brings a row of RULES; the rows are combined (scales multiply, the rest take the strongest) into the
## numbers the brain reads. A new status effect that should change bot play only needs a condition and a row.
##
##   distance   multiplies the preferred fighting distance
##   cover      0..1, how much a firing spot out of the target's line of fire is worth over one in it
##   block      multiplies the chance to block an incoming round (0: never; a broken guard cannot block)
##   block_floor  lowest block chance (caught in slowed time it leans on the block)
##   dodge      multiplies the chance to hop or air jump over a round
##   dash_dodge multiplies the chance to dash out of a round's way
##   retreat_within  backs away from a target closer than this (px; INF: always)

const RULES: Dictionary = {
	# Sniper Barrel MK III: the next sniper hit deals more. Keep further off, prefer cover, dodge harder.
	&"marked": {"distance": 1.3, "cover": 1.0, "dodge": 1.5, "dash_dodge": 1.4},
	# Shocking Rounds MK II: no shield. Back off from close range and dodge instead of blocking.
	&"guard_broken": {"distance": 1.2, "block": 0.0, "dodge": 1.8, "dash_dodge": 1.6, "retreat_within": 220.0},
	# Time Control: it cannot win a trade while slowed; it backs away and leans on its block.
	&"slowed": {"block_floor": 0.85, "retreat_within": INF},
}
const SCALE_KEYS: Array[StringName] = [&"distance", &"block", &"dodge", &"dash_dodge"]

var distance: float = 1.0
var cover: float = 0.0
var block: float = 1.0
var block_floor: float = 0.0
var dodge: float = 1.0
var dash_dodge: float = 1.0
var retreat_within: float = 0.0
## The conditions behind the numbers, and whether they changed with the last update.
var active: Array[StringName] = []
var changed: bool = false


## What the bot is going through right now that RULES know about.
static func conditions(player: Player, target: Player) -> Array[StringName]:
	var result: Array[StringName] = []
	var effects: StatusEffectManager = player.status_effect_manager
	if effects != null and target != null and effects.has_mark_from(target.player_slot):
		result.append(&"marked")
	if player.is_guard_broken():
		result.append(&"guard_broken")
	if player.is_time_slowed():
		result.append(&"slowed")
	return result


func update(player: Player, target: Player) -> void:
	var now: Array[StringName] = conditions(player, target)
	changed = now != active
	active = now
	distance = 1.0
	cover = 0.0
	block = 1.0
	block_floor = 0.0
	dodge = 1.0
	dash_dodge = 1.0
	retreat_within = 0.0
	for condition in active:
		var rule: Dictionary = RULES.get(condition, {})
		for key in rule.keys():
			var value: float = float(rule[key])
			if SCALE_KEYS.has(key):
				set(key, float(get(key)) * value)
			else:
				set(key, maxf(float(get(key)), value))


func has(condition: StringName) -> bool:
	return active.has(condition)
