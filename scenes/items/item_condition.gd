extends RefCounted
class_name ItemCondition

const FACTORY_NEW: StringName = &"factory_new"
const BARELY_USED: StringName = &"barely_used"
const FIELD_TESTED: StringName = &"field_tested"
const WELL_WORN: StringName = &"well_worn"
const BATTLE_SCARRED: StringName = &"battle_scarred"
const CONDITION_POWER_CURVE: float = 1.35


static func clamp_value(value: float) -> float:
	return clampf(value, 0.0, 100.0)


static func get_grade(value: float) -> StringName:
	var v: float = clamp_value(value)
	if v >= 90.0:
		return FACTORY_NEW
	if v >= 75.0:
		return BARELY_USED
	if v >= 55.0:
		return FIELD_TESTED
	if v >= 35.0:
		return WELL_WORN
	return BATTLE_SCARRED


static func get_grade_name(value: float) -> String:
	match get_grade(value):
		FACTORY_NEW:
			return "Factory New"
		BARELY_USED:
			return "Barely Used"
		FIELD_TESTED:
			return "Field-Tested"
		WELL_WORN:
			return "Well-Worn"
		_:
			return "Battle Scarred"


static func get_grade_color(value: float) -> Color:
	match get_grade(value):
		FACTORY_NEW:
			return Color8(242, 198, 74, 255)
		BARELY_USED:
			return Color8(156, 92, 230, 255)
		FIELD_TESTED:
			return Color8(80, 153, 235, 255)
		WELL_WORN:
			return Color8(72, 190, 111, 255)
		_:
			return Color8(139, 145, 154, 255)


static func get_grade_probability(value: float) -> float:
	match get_grade(value):
		FACTORY_NEW:
			return 0.03
		BARELY_USED:
			return 0.12
		FIELD_TESTED:
			return 0.25
		WELL_WORN:
			return 0.30
		_:
			return 0.30


static func get_scale(value: float, minimum: float = 0.0) -> float:
	var normalized: float = pow(clamp_value(value) / 100.0, CONDITION_POWER_CURVE)
	var safe_min: float = clampf(minimum, 0.0, 1.0)
	return lerpf(safe_min, 1.0, normalized)


static func roll(rng: RandomNumberGenerator = null) -> float:
	var gen: RandomNumberGenerator = rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()

	var roll_value: float = gen.randf()
	if roll_value < 0.03:
		return gen.randf_range(90.0, 100.0)
	if roll_value < 0.15:
		return gen.randf_range(75.0, 90.0)
	if roll_value < 0.40:
		return gen.randf_range(55.0, 75.0)
	if roll_value < 0.70:
		return gen.randf_range(35.0, 55.0)
	return gen.randf_range(10.0, 30.0)


static func roll_with_luck(rng: RandomNumberGenerator, luck_level: int) -> float:
	var best_roll: float = roll(rng)
	for extra_roll_index in range(clampi(luck_level, 0, 3)):
		best_roll = maxf(best_roll, roll(rng))
	return best_roll
