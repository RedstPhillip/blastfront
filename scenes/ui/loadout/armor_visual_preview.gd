extends Control
class_name ArmorVisualPreview

var _visual_root: Node2D = null
var _visual_instance: Node = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_visual_root()


func set_armor_item(item: ArmorItemData) -> bool:
	_clear_visual()
	if item == null:
		return false

	_ensure_visual_root()
	_visual_instance = item.visual_scene.instantiate()
	_visual_root.add_child(_visual_instance)
	call_deferred("_fit_visual")
	return true


func clear() -> void:
	_clear_visual()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_visual()


func _ensure_visual_root() -> void:
	if _visual_root != null:
		return
	_visual_root = Node2D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)


func _clear_visual() -> void:
	if _visual_instance != null and is_instance_valid(_visual_instance):
		if _visual_instance.get_parent() != null:
			_visual_instance.get_parent().remove_child(_visual_instance)
		_visual_instance.queue_free()
	_visual_instance = null
	if _visual_root != null:
		_visual_root.position = size * 0.5
		_visual_root.scale = Vector2.ONE


func _fit_visual() -> void:
	if _visual_root == null or _visual_instance == null or not is_instance_valid(_visual_instance):
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var bounds: Rect2 = _get_node_bounds(_visual_instance, Transform2D.IDENTITY)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_visual_root.position = size * 0.5
		_visual_root.scale = Vector2.ONE
		return

	var fit_size: Vector2 = size * 0.76
	var visual_scale: float = minf(fit_size.x / bounds.size.x, fit_size.y / bounds.size.y)
	_visual_root.scale = Vector2.ONE * visual_scale
	_visual_root.position = size * 0.5 - bounds.get_center() * visual_scale


func _get_node_bounds(node: Node, parent_transform: Transform2D) -> Rect2:
	var node_transform: Transform2D = parent_transform
	var node_2d: Node2D = node as Node2D
	if node_2d != null:
		node_transform *= node_2d.transform

	var has_bounds: bool = false
	var bounds: Rect2 = Rect2()

	var polygon_2d: Polygon2D = node as Polygon2D
	if polygon_2d != null:
		for point in polygon_2d.polygon:
			var transformed_point: Vector2 = node_transform * point
			if has_bounds:
				bounds = bounds.expand(transformed_point)
			else:
				bounds = Rect2(transformed_point, Vector2.ZERO)
				has_bounds = true

	var line_2d: Line2D = node as Line2D
	if line_2d != null:
		var half_width: Vector2 = Vector2.ONE * line_2d.width * 0.5
		for point in line_2d.points:
			var transformed_point: Vector2 = node_transform * point
			var point_rect: Rect2 = Rect2(transformed_point - half_width, half_width * 2.0)
			if has_bounds:
				bounds = bounds.merge(point_rect)
			else:
				bounds = point_rect
				has_bounds = true

	var sprite_2d: Sprite2D = node as Sprite2D
	if sprite_2d != null and sprite_2d.texture != null:
		var sprite_size: Vector2 = sprite_2d.texture.get_size()
		var offset: Vector2 = -sprite_size * 0.5 if sprite_2d.centered else Vector2.ZERO
		var points: Array[Vector2] = [
			offset,
			offset + Vector2(sprite_size.x, 0.0),
			offset + sprite_size,
			offset + Vector2(0.0, sprite_size.y),
		]
		for point in points:
			var transformed_point: Vector2 = node_transform * point
			if has_bounds:
				bounds = bounds.expand(transformed_point)
			else:
				bounds = Rect2(transformed_point, Vector2.ZERO)
				has_bounds = true

	for child in node.get_children():
		var child_bounds: Rect2 = _get_node_bounds(child, node_transform)
		if child_bounds.size.x <= 0.0 and child_bounds.size.y <= 0.0:
			continue
		if has_bounds:
			bounds = bounds.merge(child_bounds)
		else:
			bounds = child_bounds
			has_bounds = true

	return bounds if has_bounds else Rect2()
