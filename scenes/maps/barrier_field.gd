class_name BarrierField
extends Node2D

## Visual energy walls around the map bounds. Purely cosmetic; MapBorder resolves contact.

const BARRIER_SHADER: Shader = preload("res://scenes/maps/barrier.gdshader")
const OUTSIDE: float = 80.0
const INSIDE: float = 40.0
const OVERHANG: float = 120.0

var _materials: Dictionary = {}
var _hit_ages: Dictionary = {}
var _color: Color = GameSettings.MAP_BORDER_COLOR
var _hit_color: Color = GameSettings.MAP_BORDER_HIT_COLOR


func build(bounds: Rect2, color: Color, hit_color: Color) -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	_color = color
	_hit_color = hit_color
	z_index = 3
	var thickness: float = OUTSIDE + INSIDE
	var edge: float = INSIDE / thickness
	_add_wall(GameSettings.MAP_BORDER_SIDE_TOP, Rect2(bounds.position.x - OVERHANG, bounds.position.y - OUTSIDE, bounds.size.x + OVERHANG * 2.0, thickness), 0, true, edge)
	_add_wall(GameSettings.MAP_BORDER_SIDE_BOTTOM, Rect2(bounds.position.x - OVERHANG, bounds.end.y - INSIDE, bounds.size.x + OVERHANG * 2.0, thickness), 0, false, edge)
	_add_wall(GameSettings.MAP_BORDER_SIDE_LEFT, Rect2(bounds.position.x - OUTSIDE, bounds.position.y - OVERHANG, thickness, bounds.size.y + OVERHANG * 2.0), 1, true, edge)
	_add_wall(GameSettings.MAP_BORDER_SIDE_RIGHT, Rect2(bounds.end.x - INSIDE, bounds.position.y - OVERHANG, thickness, bounds.size.y + OVERHANG * 2.0), 1, false, edge)


func notify_hit(side: StringName, world_position: Vector2) -> void:
	var material: ShaderMaterial = _materials.get(side) as ShaderMaterial
	if material == null:
		return
	_hit_ages[side] = 0.0
	material.set_shader_parameter(&"hit", Vector4(world_position.x, world_position.y, 0.0, 1.6))


func _process(delta: float) -> void:
	var pushers: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(GameSettings.PLAYERS_GROUP):
		var player: Player = node as Player
		if player != null and not player.is_eliminated():
			pushers.append(player.global_position)
		if pushers.size() >= 4:
			break
	while pushers.size() < 4:
		pushers.append(Vector2(-100000.0, -100000.0))
	for side in _materials.keys():
		var material: ShaderMaterial = _materials[side]
		material.set_shader_parameter(&"pushers", pushers)
		if _hit_ages.has(side):
			var age: float = float(_hit_ages[side]) + delta
			_hit_ages[side] = age
			var current: Vector4 = material.get_shader_parameter(&"hit")
			material.set_shader_parameter(&"hit", Vector4(current.x, current.y, age, current.w))
			if age > 1.0:
				_hit_ages.erase(side)


func _add_wall(side: StringName, rect: Rect2, axis: int, flip: bool, edge: float) -> void:
	var wall: ColorRect = ColorRect.new()
	wall.name = "Wall_%s" % str(side)
	wall.position = rect.position
	wall.size = rect.size
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BARRIER_SHADER
	material.set_shader_parameter(&"axis", axis)
	material.set_shader_parameter(&"flip", flip)
	material.set_shader_parameter(&"edge", edge)
	material.set_shader_parameter(&"color", _color)
	material.set_shader_parameter(&"hit_color", _hit_color)
	material.set_shader_parameter(&"hit", Vector4(0.0, 0.0, 10.0, 0.0))
	wall.material = material
	add_child(wall)
	_materials[side] = material
