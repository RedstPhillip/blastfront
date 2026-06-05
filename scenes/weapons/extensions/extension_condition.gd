class_name ExtensionCondition
extends RefCounted

const TIER_FACTORY_NEW: StringName = &"factory_new"
const TIER_BARELY_USED: StringName = &"barely_used"
const TIER_FIELD_TESTED: StringName = &"field_tested"
const TIER_WELL_WORN: StringName = &"well_worn"
const TIER_BATTLE_SCARRED: StringName = &"battle_scarred"


static func clamp_value(value: float) -> float:
	return clampf(value, 0.0, 100.0)


static func get_condition_multiplier(value: float, minimum_factor: float = 0.0) -> float:
	var normalized_condition: float = clamp_value(value) / 100.0
	var safe_minimum: float = clampf(minimum_factor, 0.0, 1.0)
	return lerpf(safe_minimum, 1.0, normalized_condition)


static func get_tier_id(value: float) -> StringName:
	var condition: float = clamp_value(value)
	if condition >= 90.0:
		return TIER_FACTORY_NEW
	if condition >= 75.0:
		return TIER_BARELY_USED
	if condition >= 55.0:
		return TIER_FIELD_TESTED
	if condition >= 35.0:
		return TIER_WELL_WORN
	return TIER_BATTLE_SCARRED


static func get_tier_name(value: float) -> String:
	match get_tier_id(value):
		TIER_FACTORY_NEW:
			return "Factory New"
		TIER_BARELY_USED:
			return "Barely Used"
		TIER_FIELD_TESTED:
			return "Field-Tested"
		TIER_WELL_WORN:
			return "Well-Worn"
		TIER_BATTLE_SCARRED:
			return "Battle Scarred"
	return "Unknown"


static func get_tier_color(value: float) -> Color:
	match get_tier_id(value):
		TIER_FACTORY_NEW:
			return Color(1.0, 0.76, 0.22, 1.0)
		TIER_BARELY_USED:
			return Color(0.64, 0.36, 1.0, 1.0)
		TIER_FIELD_TESTED:
			return Color(0.28, 0.58, 1.0, 1.0)
		TIER_WELL_WORN:
			return Color(0.32, 0.84, 0.44, 1.0)
		TIER_BATTLE_SCARRED:
			return Color(0.62, 0.66, 0.70, 1.0)
	return Color.WHITE


static func roll_condition(rng: RandomNumberGenerator = null) -> float:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	var roll: float = generator.randf()
	if roll < 0.03:
		return generator.randf_range(90.0, 100.0)
	if roll < 0.15:
		return generator.randf_range(75.0, 90.0)
	if roll < 0.40:
		return generator.randf_range(55.0, 75.0)
	if roll < 0.70:
		return generator.randf_range(35.0, 55.0)
	return generator.randf_range(10.0, 30.0)
