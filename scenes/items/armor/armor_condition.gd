extends RefCounted
class_name ArmorCondition

const GRADE_FACTORY_NEW: StringName = &"factory_new"
const GRADE_BARELY_USED: StringName = &"barely_used"
const GRADE_FIELD_TESTED: StringName = &"field_tested"
const GRADE_WELL_WORN: StringName = &"well_worn"
const GRADE_BATTLE_SCARRED: StringName = &"battle_scarred"


static func clamp_condition(condition: float) -> float:
	return clampf(condition, 0.0, 100.0)


static func get_grade(condition: float) -> StringName:
	var value: float = clamp_condition(condition)
	if value >= 90.0:
		return GRADE_FACTORY_NEW
	if value >= 75.0:
		return GRADE_BARELY_USED
	if value >= 55.0:
		return GRADE_FIELD_TESTED
	if value >= 35.0:
		return GRADE_WELL_WORN
	return GRADE_BATTLE_SCARRED


static func get_grade_name(condition: float) -> String:
	match get_grade(condition):
		GRADE_FACTORY_NEW:
			return "Factory New"
		GRADE_BARELY_USED:
			return "Barely Used"
		GRADE_FIELD_TESTED:
			return "Field-Tested"
		GRADE_WELL_WORN:
			return "Well-Worn"
		_:
			return "Battle Scarred"


static func get_grade_probability(condition: float) -> float:
	match get_grade(condition):
		GRADE_FACTORY_NEW:
			return 0.03
		GRADE_BARELY_USED:
			return 0.12
		GRADE_FIELD_TESTED:
			return 0.25
		GRADE_WELL_WORN:
			return 0.30
		_:
			return 0.30


static func get_grade_color(condition: float) -> Color:
	match get_grade(condition):
		GRADE_FACTORY_NEW:
			return Color8(242, 198, 74, 255)
		GRADE_BARELY_USED:
			return Color8(156, 92, 230, 255)
		GRADE_FIELD_TESTED:
			return Color8(80, 153, 235, 255)
		GRADE_WELL_WORN:
			return Color8(72, 190, 111, 255)
		_:
			return Color8(139, 145, 154, 255)


static func get_scale(condition: float, minimum_scale: float) -> float:
	var clamped_minimum: float = clampf(minimum_scale, 0.0, 1.0)
	var condition_ratio: float = clamp_condition(condition) / 100.0
	return lerpf(clamped_minimum, 1.0, condition_ratio)
