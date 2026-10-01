class_name ImpactDecals
extends RefCounted

## Places bullet holes, scorch marks and paint splats onto level geometry.
## Each decal quad is clipped against the platform polygon once, on the CPU, and becomes a plain
## textured Polygon2D child of the platform, so decals cost no extra render passes.

const TEX_HOLE: Texture2D = preload("res://assets/fx/decal_hole.png")
const TEX_SCORCH: Texture2D = preload("res://assets/fx/decal_scorch.png")
const TEX_SPLATS: Array[Texture2D] = [
	preload("res://assets/fx/decal_splat_0.png"),
	preload("res://assets/fx/decal_splat_1.png"),
	preload("res://assets/fx/decal_splat_2.png"),
]
const WORLD_MASK: int = 1
const MAX_DECALS_PER_HOST: int = 28
const MAX_DECALS_TOTAL: int = 140
const META_DECALS: StringName = &"impact_decals"

static var _all_decals: Array[Node2D] = []


static func add_hole(world_position: Vector2, normal: Vector2) -> void:
	var inward: Vector2 = -normal.normalized() if normal.length_squared() > 0.0001 else Vector2.DOWN
	var host: Polygon2D = _find_host_at(world_position + inward * 3.0)
	if host == null:
		return
	_attach(host, TEX_HOLE, Color(1, 1, 1, 0.85), randf_range(10.0, 14.0), world_position + inward * 1.5, 16.0)


static func add_scorch(world_position: Vector2, radius: float) -> void:
	for host in _find_hosts_in_radius(world_position, radius):
		_attach(host, TEX_SCORCH, Color(1, 1, 1, 0.8), radius * 2.0, world_position, 26.0)


static func add_splat(world_position: Vector2, color: Color, size: float) -> void:
	for host in _find_hosts_in_radius(world_position, size * 0.55):
		var texture: Texture2D = TEX_SPLATS[randi() % TEX_SPLATS.size()]
		_attach(host, texture, Color(color.r, color.g, color.b, 0.88), size, world_position, 32.0)


## Paint a few splats around a point by probing for nearby surfaces (death bursts).
static func splatter_around(world_position: Vector2, color: Color, count: int, reach: float) -> void:
	var space: PhysicsDirectSpaceState2D = _space()
	if space == null:
		return
	for index in range(count):
		var angle: float = TAU * float(index) / float(count) + randf_range(-0.4, 0.4)
		var target: Vector2 = world_position + Vector2(cos(angle), sin(angle) * 0.8 + 0.35).normalized() * reach * randf_range(0.6, 1.0)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, target, WORLD_MASK)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		add_splat(hit["position"], color, randf_range(34.0, 64.0))


static func clear_all() -> void:
	for decal in _all_decals:
		if decal != null and is_instance_valid(decal):
			decal.queue_free()
	_all_decals.clear()


static func _attach(host: Polygon2D, texture: Texture2D, color: Color, size: float, world_position: Vector2, lifetime: float) -> void:
	var decal: Node2D = _build_clipped_decal(host, texture, size, world_position)
	if decal == null:
		return
	decal.modulate = color
	host.add_child(decal)
	var host_decals: Array = host.get_meta(META_DECALS, [])
	host_decals.append(decal)
	host.set_meta(META_DECALS, host_decals)
	_all_decals.append(decal)
	if host_decals.size() > MAX_DECALS_PER_HOST:
		_fade_out(host_decals.pop_front(), 0.4)
	if _all_decals.size() > MAX_DECALS_TOTAL:
		_fade_out(_all_decals.pop_front(), 0.4)
	var appear: Tween = decal.create_tween()
	var target_alpha: float = decal.modulate.a
	decal.modulate.a = 0.0
	appear.tween_property(decal, "modulate:a", target_alpha, 0.08)
	appear.tween_interval(lifetime)
	appear.tween_property(decal, "modulate:a", 0.0, 2.5)
	appear.tween_callback(_remove.bind(decal))


static func _fade_out(decal_variant: Variant, duration: float) -> void:
	var decal: Node2D = decal_variant as Node2D
	if decal == null or not is_instance_valid(decal):
		return
	var tween: Tween = decal.create_tween()
	tween.tween_property(decal, "modulate:a", 0.0, duration)
	tween.tween_callback(_remove.bind(decal))


static func _remove(decal: Node2D) -> void:
	if decal == null or not is_instance_valid(decal):
		return
	_all_decals.erase(decal)
	var host: Polygon2D = decal.get_parent() as Polygon2D
	if host != null:
		var host_decals: Array = host.get_meta(META_DECALS, [])
		host_decals.erase(decal)
	decal.queue_free()


## Intersects the rotated decal square with the host polygon and maps the texture onto the pieces.
static func _build_clipped_decal(host: Polygon2D, texture: Texture2D, size: float, world_position: Vector2) -> Node2D:
	var host_polygon: PackedVector2Array = host.polygon
	if host_polygon.size() < 3 or size <= 0.5:
		return null
	if host.offset != Vector2.ZERO:
		host_polygon = Transform2D(0.0, host.offset) * host_polygon
	var placement: Transform2D = Transform2D(randf_range(0.0, TAU), world_position)
	var half: float = size * 0.5
	var decal_to_host: Transform2D = host.global_transform.affine_inverse() * placement
	var quad: PackedVector2Array = decal_to_host * PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(quad, host_polygon)
	if pieces.is_empty():
		return null
	var host_to_decal: Transform2D = decal_to_host.affine_inverse()
	var texture_size: Vector2 = texture.get_size()
	var container: Node2D = Node2D.new()
	container.light_mask = host.light_mask
	for piece in pieces:
		if piece.size() < 3:
			continue
		var uvs: PackedVector2Array = PackedVector2Array()
		uvs.resize(piece.size())
		for index in range(piece.size()):
			uvs[index] = ((host_to_decal * piece[index]) / size + Vector2(0.5, 0.5)) * texture_size
		var shape: Polygon2D = Polygon2D.new()
		shape.polygon = piece
		shape.uv = uvs
		shape.texture = texture
		shape.light_mask = host.light_mask
		container.add_child(shape)
	if container.get_child_count() == 0:
		container.free()
		return null
	return container


static func _find_host_at(world_position: Vector2) -> Polygon2D:
	var space: PhysicsDirectSpaceState2D = _space()
	if space == null:
		return null
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = WORLD_MASK
	query.collide_with_bodies = true
	for result in space.intersect_point(query, 4):
		var host: Polygon2D = _host_for(result.get("collider"))
		if host != null:
			return host
	return null


static func _find_hosts_in_radius(world_position: Vector2, radius: float) -> Array[Polygon2D]:
	var hosts: Array[Polygon2D] = []
	var space: PhysicsDirectSpaceState2D = _space()
	if space == null:
		return hosts
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = maxf(radius, 4.0)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, world_position)
	query.collision_mask = WORLD_MASK
	query.collide_with_bodies = true
	for result in space.intersect_shape(query, 8):
		var host: Polygon2D = _host_for(result.get("collider"))
		if host != null and not hosts.has(host):
			hosts.append(host)
	return hosts


static func _host_for(collider_variant: Variant) -> Polygon2D:
	var body: StaticBody2D = collider_variant as StaticBody2D
	if body == null:
		return null
	for child in body.get_children():
		if child is Polygon2D and child.visible:
			return child
	return null


static func _space() -> PhysicsDirectSpaceState2D:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var world: Node2D = tree.get_first_node_in_group(GameSettings.GAME_WORLD_GROUP) as Node2D
	if world == null or not world.is_inside_tree():
		return null
	return world.get_world_2d().direct_space_state
