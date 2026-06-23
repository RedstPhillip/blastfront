extends Node

signal research_changed
signal research_points_changed(points: int)

const DEFAULT_RESEARCH_POINTS: int = 5

const BRANCH_ECONOMY: StringName = &"economy"
const BRANCH_MOVEMENT: StringName = &"movement"
const BRANCH_MISC: StringName = &"miscellaneous"

const RECYCLING: StringName = &"recycling"
const BLUEPRINT_STORAGE: StringName = &"blueprint_storage"
const COIN_INTEREST: StringName = &"coin_interest"
const CONDITION_WEAR: StringName = &"condition_wear"
const UPGRADE_DISCOUNT: StringName = &"upgrade_discount"
const BONUS_MARK: StringName = &"bonus_mark"
const LUCK: StringName = &"luck"
const RESEARCH_YIELD: StringName = &"research_yield"

const DASHING: StringName = &"dashing"
const SLIDING: StringName = &"sliding"

const LIFE_STEAL: StringName = &"life_steal"
const RAGE: StringName = &"rage"
const PASSIVE_HEALING: StringName = &"passive_healing"
const PHOENIX: StringName = &"phoenix"
const TIME_CONTROL: StringName = &"time_control"
const FASTER_CAPTURE: StringName = &"faster_capture"
const CAPTURE_BONUS: StringName = &"capture_bonus"
const CAPTURE_RADIUS: StringName = &"capture_radius"

var research_points: int = DEFAULT_RESEARCH_POINTS
var _local_marks: Dictionary = {}
var _remote_marks_by_player: Dictionary = {}
var _definitions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_definitions = _build_definitions()
	call_deferred("_publish_local_profile")


func get_all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition_variant in _definitions.values():
		if definition_variant is Dictionary:
			var definition: Dictionary = definition_variant
			result.append(definition.duplicate(true))
	result.sort_custom(_sort_definitions)
	return result


func get_definition(research_id: StringName) -> Dictionary:
	var definition_variant: Variant = _definitions.get(str(research_id), {})
	if definition_variant is Dictionary:
		var definition: Dictionary = definition_variant
		return definition.duplicate(true)
	return {}


func get_mark(research_id: StringName, player_slot: int = 0) -> int:
	var marks: Dictionary = _marks_for_player(player_slot)
	return int(marks.get(str(research_id), 0))


func is_unlocked(research_id: StringName, player_slot: int = 0) -> bool:
	return get_mark(research_id, player_slot) > 0


func is_research_available(research_id: StringName) -> bool:
	var definition: Dictionary = get_definition(research_id)
	return not definition.is_empty() and definition["available"] == true


func get_next_cost(research_id: StringName) -> int:
	var definition: Dictionary = get_definition(research_id)
	if definition.is_empty():
		return 0
	var next_mark: int = get_mark(research_id) + 1
	var costs_variant: Variant = definition["costs"]
	if not (costs_variant is Array):
		return 0
	var costs: Array = costs_variant
	if next_mark <= 0 or next_mark > costs.size():
		return 0
	return int(costs[next_mark - 1])


func can_purchase(research_id: StringName) -> bool:
	var definition: Dictionary = get_definition(research_id)
	if definition.is_empty() or definition["available"] != true:
		return false
	var current_mark: int = get_mark(research_id)
	var max_mark: int = int(definition["max_mark"])
	if current_mark >= max_mark:
		return false
	if current_mark == 0 and not _requirements_met(definition):
		return false
	var cost: int = get_next_cost(research_id)
	return cost > 0 and research_points >= cost


func purchase(research_id: StringName) -> bool:
	if not can_purchase(research_id):
		return false
	var cost: int = get_next_cost(research_id)
	research_points -= cost
	_local_marks[str(research_id)] = get_mark(research_id) + 1
	research_points_changed.emit(research_points)
	research_changed.emit()
	_publish_local_profile()
	return true


func add_research_points(base_amount: int) -> int:
	if base_amount <= 0:
		return 0
	var awarded: int = maxi(1, int(roundf(float(base_amount) * get_research_point_multiplier())))
	return add_research_points_exact(awarded)


func add_research_points_exact(amount: int) -> int:
	if amount <= 0:
		return 0
	var awarded: int = amount
	research_points += awarded
	research_points_changed.emit(research_points)
	research_changed.emit()
	_publish_local_profile()
	return awarded


func reset_for_new_game(persist_progress: bool = true) -> void:
	research_points = DEFAULT_RESEARCH_POINTS
	_local_marks.clear()
	_remote_marks_by_player.clear()
	research_points_changed.emit(research_points)
	research_changed.emit()
	_publish_local_profile()


func reset_points_for_big_round() -> void:
	research_points = DEFAULT_RESEARCH_POINTS
	research_points_changed.emit(research_points)
	research_changed.emit()
	_publish_local_profile()


func get_local_profile() -> Dictionary:
	return {
		"marks": _local_marks.duplicate(),
	}


func apply_online_profiles(profiles: Dictionary) -> void:
	_remote_marks_by_player.clear()
	for raw_slot in profiles.keys():
		var slot: int = int(raw_slot)
		var profile_variant: Variant = profiles[raw_slot]
		if not (profile_variant is Dictionary):
			continue
		var profile: Dictionary = profile_variant
		var marks_variant: Variant = profile.get("marks", {})
		if marks_variant is Dictionary:
			var marks: Dictionary = marks_variant
			_remote_marks_by_player[slot] = marks.duplicate()
	research_changed.emit()


func get_recycling_refund_ratio(player_slot: int = 0) -> float:
	match get_mark(RECYCLING, player_slot):
		1:
			return 0.5
		2:
			return 0.75
		3:
			return 1.0
	return 0.0


func get_blueprint_slot_count(player_slot: int = 0) -> int:
	match get_mark(BLUEPRINT_STORAGE, player_slot):
		1:
			return 1
		2:
			return 2
		3:
			return 4
	return 0


func get_coin_multiplier(player_slot: int = 0) -> float:
	return 1.0 + 0.05 * float(get_mark(COIN_INTEREST, player_slot))


func get_research_point_multiplier(player_slot: int = 0) -> float:
	match get_mark(RESEARCH_YIELD, player_slot):
		1:
			return 1.2
		2:
			return 1.4
		3:
			return 1.65
	return 1.0


func get_condition_wear_multiplier(player_slot: int = 0) -> float:
	match get_mark(CONDITION_WEAR, player_slot):
		1:
			return 0.7
		2:
			return 0.35
		3:
			return 0.0
	return 1.0


func get_upgrade_cost_multiplier(player_slot: int = 0) -> float:
	match get_mark(UPGRADE_DISCOUNT, player_slot):
		1:
			return 0.9
		2:
			return 0.78
		3:
			return 0.65
	return 1.0


func get_bonus_mark_chance(player_slot: int = 0) -> float:
	match get_mark(BONUS_MARK, player_slot):
		1:
			return 0.06
		2:
			return 0.14
		3:
			return 0.26
	return 0.0


func get_luck_level(player_slot: int = 0) -> int:
	return get_mark(LUCK, player_slot)


func get_capture_time_multiplier(player_slot: int = 0) -> float:
	match get_mark(FASTER_CAPTURE, player_slot):
		1:
			return 0.85
		2:
			return 0.7
		3:
			return 0.55
	return 1.0


func get_capture_radius(player_slot: int = 0) -> float:
	match get_mark(CAPTURE_RADIUS, player_slot):
		1:
			return GameSettings.AIRDROP_BASE_CAPTURE_RADIUS + 20.0
		2:
			return GameSettings.AIRDROP_BASE_CAPTURE_RADIUS + 42.0
		3:
			return GameSettings.AIRDROP_BASE_CAPTURE_RADIUS + 68.0
	return GameSettings.AIRDROP_BASE_CAPTURE_RADIUS


func get_capture_research_reward(player_slot: int = 0) -> int:
	return GameSettings.AIRDROP_BASE_RESEARCH_REWARD + get_mark(CAPTURE_BONUS, player_slot)


func get_life_steal_ratio(player_slot: int = 0) -> float:
	match get_mark(LIFE_STEAL, player_slot):
		1:
			return 0.05
		2:
			return 0.1
		3:
			return 0.16
	return 0.0


func get_rage_damage_multiplier(player_slot: int = 0) -> float:
	match get_mark(RAGE, player_slot):
		1:
			return 1.15
		2:
			return 1.3
		3:
			return 1.5
	return 1.0


func get_passive_healing_cap(player_slot: int = 0) -> float:
	match get_mark(PASSIVE_HEALING, player_slot):
		1:
			return 0.5
		2:
			return 0.75
		3:
			return 1.0
	return 0.0


func get_passive_healing_rate(player_slot: int = 0) -> float:
	match get_mark(PASSIVE_HEALING, player_slot):
		1:
			return 2.0
		2:
			return 3.0
		3:
			return 4.0
	return 0.0


func has_phoenix(player_slot: int = 0) -> bool:
	return is_unlocked(PHOENIX, player_slot)


func apply_local_life_steal(source_slot: int, applied_damage: int) -> int:
	if applied_damage <= 0:
		return 0
	var ratio: float = get_life_steal_ratio(source_slot)
	if ratio <= 0.0:
		return 0
	var world: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null:
		return 0
	var source_player: Player = world.get_player_by_slot(source_slot)
	if source_player == null or source_player.health_component == null or source_player.is_eliminated():
		return 0
	var old_health: int = source_player.health_component.health
	source_player.health_component.heal(maxi(1, int(roundf(float(applied_damage) * ratio))))
	return source_player.health_component.health - old_health


func apply_rage_to_damage(source_slot: int, base_damage: int) -> int:
	if base_damage <= 0:
		return 0
	var world: Variant = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world == null:
		return base_damage
	var source_player: Player = world.get_player_by_slot(source_slot)
	if source_player == null or source_player.health_component == null:
		return base_damage
	var health_ratio: float = float(source_player.health_component.health) / maxf(float(source_player.health_component.max_health), 1.0)
	if health_ratio > 0.2:
		return base_damage
	return maxi(1, int(roundf(float(base_damage) * get_rage_damage_multiplier(source_slot))))


func _marks_for_player(player_slot: int) -> Dictionary:
	var effective_slot: int = player_slot
	if effective_slot <= 0:
		effective_slot = NetworkSession.local_player_slot
	if effective_slot == NetworkSession.local_player_slot:
		return _local_marks
	var marks_variant: Variant = _remote_marks_by_player.get(effective_slot, {})
	if marks_variant is Dictionary:
		var marks: Dictionary = marks_variant
		return marks
	return {}


func _requirements_met(definition: Dictionary) -> bool:
	var requirements_variant: Variant = definition["requires"]
	if not (requirements_variant is Array):
		return true
	var requirements: Array = requirements_variant
	for requirement_variant in requirements:
		if not (requirement_variant is Dictionary):
			continue
		var requirement: Dictionary = requirement_variant
		var required_id: StringName = StringName(str(requirement["id"]))
		var required_mark: int = int(requirement["mark"])
		if get_mark(required_id) < required_mark:
			return false
	return true



func _publish_local_profile() -> void:
	OnlineMatch.set_local_research_profile(get_local_profile())


func _definition(
	research_id: StringName,
	display_name: String,
	branch: StringName,
	icon_path: String,
	description: String,
	costs: Array,
	position: Vector2,
	requirements: Array = [],
	available: bool = true,
	order: int = 0
) -> Dictionary:
	return {
		"id": str(research_id),
		"name": display_name,
		"branch": str(branch),
		"icon_path": icon_path,
		"description": description,
		"costs": costs,
		"max_mark": costs.size(),
		"position": position,
		"requires": requirements,
		"available": available,
		"order": order,
	}


func _require(research_id: StringName, mark: int = 1) -> Dictionary:
	return {"id": str(research_id), "mark": mark}


func _sort_definitions(first: Dictionary, second: Dictionary) -> bool:
	return int(first["order"]) < int(second["order"])


func _build_definitions() -> Dictionary:
	var definitions: Dictionary = {}
	var entries: Array = [
		_definition(RECYCLING, "Recycling", BRANCH_ECONOMY, "res://assets/ui/research/recycling.svg", "Recycle shop blueprints for 50%, 75% or 100% of their coin price.", [1, 3, 7], Vector2(150, 40), [], true, 10),
		_definition(BLUEPRINT_STORAGE, "Blueprint Storage", BRANCH_ECONOMY, "res://assets/ui/research/blueprint_storage.svg", "Unlock 1, 2 or 4 shared storage slots for armor and weapon blueprints.", [2, 4, 8], Vector2(330, 40), [_require(RECYCLING)], true, 20),
		_definition(COIN_INTEREST, "Compound Interest", BRANCH_ECONOMY, "res://assets/ui/research/coin_interest.svg", "Earn 5%, 10% or 15% more coins from every completed set.", [2, 5, 9], Vector2(510, 40), [_require(BLUEPRINT_STORAGE)], true, 30),
		_definition(CONDITION_WEAR, "Maintenance", BRANCH_ECONOMY, "res://assets/ui/research/condition_wear.svg", "Reduces condition wear to 70%, 35% or finally 0%.", [3, 6, 12], Vector2(690, 40), [_require(COIN_INTEREST)], true, 40),
		_definition(UPGRADE_DISCOUNT, "Efficient Upgrades", BRANCH_ECONOMY, "res://assets/ui/research/upgrade_discount.svg", "Extension upgrades cost 10%, 22% or 35% fewer coins.", [3, 7, 12], Vector2(870, 40), [_require(CONDITION_WEAR)], true, 50),
		_definition(RESEARCH_YIELD, "Applied Research", BRANCH_ECONOMY, "res://assets/ui/research/research_yield.svg", "Future quests award 20%, 40% or 65% more Research Points.", [5, 10, 16], Vector2(1050, 40), [_require(UPGRADE_DISCOUNT)], true, 60),
		_definition(BONUS_MARK, "Prototype Assembly", BRANCH_ECONOMY, "res://assets/ui/research/bonus_mark.svg", "Bought weapon blueprints have a 6%, 14% or 26% chance to arrive as MK2.", [3, 6, 10], Vector2(690, 130), [_require(COIN_INTEREST)], true, 70),
		_definition(LUCK, "Quality Control", BRANCH_ECONOMY, "res://assets/ui/research/luck.svg", "Increases the probability of receiving blueprints in a better condition.", [2, 5, 9], Vector2(870, 130), [_require(CONDITION_WEAR)], true, 80),

		_definition(DASHING, "Dashing", BRANCH_MOVEMENT, "res://assets/ui/research/dashing.svg", "Unlock dash, then reduce its cooldown and add a protective shockwave.", [4, 8, 14], Vector2(330, 260), [], false, 110),
		_definition(SLIDING, "Sliding", BRANCH_MOVEMENT, "res://assets/ui/research/sliding.svg", "Unlock a ground slide and improve speed and control.", [4, 8, 13], Vector2(570, 260), [_require(DASHING)], false, 120),

		_definition(LIFE_STEAL, "Life Steal", BRANCH_MISC, "res://assets/ui/research/life_steal.svg", "Heal for 5%, 10% or 16% of damage dealt.", [3, 7, 12], Vector2(270, 395), [], true, 210),
		_definition(RAGE, "Last Stand", BRANCH_MISC, "res://assets/ui/research/rage.svg", "Below 20% health, deal 15%, 30% or 50% more damage.", [3, 7, 13], Vector2(470, 395), [_require(LIFE_STEAL)], true, 220),
		_definition(PASSIVE_HEALING, "Field Regeneration", BRANCH_MISC, "res://assets/ui/research/passive_healing.svg", "While standing still, heal up to 50%, 75% or 100% health.", [4, 8, 14], Vector2(670, 395), [_require(RAGE)], true, 230),
		_definition(PHOENIX, "Phoenix", BRANCH_MISC, "res://assets/ui/research/phoenix.svg", "Once per set, survive lethal damage and return with 40% health.", [20], Vector2(870, 395), [_require(PASSIVE_HEALING, 3)], true, 240),
		_definition(TIME_CONTROL, "Time Control", BRANCH_MISC, "res://assets/ui/research/time_control.svg", "Future research: slow the world, extend the effect, then briefly freeze time.", [60, 120, 240], Vector2(1030, 395), [], false, 999),
		_definition(FASTER_CAPTURE, "Faster Capture", BRANCH_MISC, "res://assets/ui/research/faster_capture.svg", "Capture airdrops 15%, 30% or 45% faster.", [3, 7, 12], Vector2(670, 500), [_require(RAGE)], true, 260),
		_definition(CAPTURE_BONUS, "Capture Bonus", BRANCH_MISC, "res://assets/ui/research/capture_bonus.svg", "Captured airdrops award 6, 7 or 8 Research Points instead of 5.", [4, 8, 14], Vector2(870, 500), [_require(FASTER_CAPTURE)], true, 270),
		_definition(CAPTURE_RADIUS, "Capture Radius", BRANCH_MISC, "res://assets/ui/research/capture_radius.svg", "Increase airdrop capture radius by 20, 42 or 68 units.", [4, 9, 15], Vector2(1070, 500), [_require(CAPTURE_BONUS)], true, 280),
	]
	for entry in entries:
		definitions[str(entry["id"])] = entry
	return definitions
