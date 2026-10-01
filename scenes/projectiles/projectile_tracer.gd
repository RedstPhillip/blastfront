class_name ProjectileTracer
extends Line2D

## Additive, tapered light trail that follows a projectile in world space and fades out on its own
## once the projectile is gone.

const MAX_POINTS: int = 24

var max_length: float = 90.0
var _target: Node2D = null
var _detached: bool = false

static var _width_curve: Curve = null


func setup(target: Node2D, color: Color, width_px: float, length: float) -> void:
	_target = target
	max_length = length
	width = width_px
	top_level = true
	z_index = 1
	material = FxLib.additive_material()
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_NONE
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	width_curve = _get_width_curve()
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.0), Color(color.r, color.g, color.b, 0.45), Color(1.0, 0.98, 0.9, 0.95)])
	gradient = ramp


func _physics_process(delta: float) -> void:
	if _detached:
		width = maxf(width - delta * 40.0, 0.0)
		modulate.a = maxf(modulate.a - delta * 7.0, 0.0)
		if modulate.a <= 0.0 or width <= 0.0:
			queue_free()
		return
	if _target == null or not is_instance_valid(_target):
		detach()
		return
	add_point(_target.global_position)
	while get_point_count() > MAX_POINTS:
		remove_point(0)
	_trim_to_length()


## Leaves the trail behind in the world so it can fade naturally when the projectile despawns.
func detach() -> void:
	if _detached:
		return
	_detached = true
	_target = null
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var world: Node = tree.get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world != null and get_parent() != world:
		var keep_points: PackedVector2Array = points
		get_parent().remove_child(self)
		world.add_child(self)
		points = keep_points


func _trim_to_length() -> void:
	var total: float = 0.0
	var index: int = get_point_count() - 1
	while index > 0:
		total += get_point_position(index).distance_to(get_point_position(index - 1))
		if total > max_length:
			for _remove in range(index - 1):
				remove_point(0)
			return
		index -= 1


static func _get_width_curve() -> Curve:
	if _width_curve == null:
		_width_curve = Curve.new()
		_width_curve.add_point(Vector2(0.0, 0.0))
		_width_curve.add_point(Vector2(0.75, 0.7))
		_width_curve.add_point(Vector2(1.0, 1.0))
	return _width_curve
