class_name FxLib
extends RefCounted

## Shared building blocks for one-shot visual effects: particle emitters with fade ramps and
## scale curves, additive glow flashes, expanding rings and short-lived light flashes.

const TEX_SOFT: Texture2D = preload("res://assets/fx/soft_circle.png")
const TEX_GLOW: Texture2D = preload("res://assets/fx/glow.png")
const TEX_DOT: Texture2D = preload("res://assets/fx/dot.png")
const TEX_SPARK: Texture2D = preload("res://assets/fx/spark.png")
const TEX_RING: Texture2D = preload("res://assets/fx/ring.png")
const TEX_SMOKE: Texture2D = preload("res://assets/fx/smoke.png")
const TEX_DEBRIS: Texture2D = preload("res://assets/fx/debris.png")
const TEX_SQUARE: Texture2D = preload("res://assets/particles/square_particle.png")

## Light layers: 2 = characters, 4 = level geometry. Flashes light both but leave the sky alone.
const FLASH_LIGHT_MASK: int = 2 | 4

## Most effects are world-space one-shots, so their emitters are pooled: creating a CPUParticles2D
## allocates its mesh and multimesh buffers, which showed up as frame spikes when a volley hit.
const POOL_LIMIT: int = 160

static var _additive: CanvasItemMaterial = null
static var _gradients: Dictionary = {}
static var _curves: Dictionary = {}
static var _pool_host: Node2D = null
## Idle emitters keyed by the params they were configured with: an exact match only needs a new
## transform and a restart, which is what keeps volleys of identical effects cheap.
static var _idle_by_key: Dictionary = {}
static var _idle_count: int = 0
static var _pooled_count: int = 0


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _additive


## Spawns a one-shot CPUParticles2D. Keys: texture, amount, lifetime, direction, spread, speed (Vector2),
## gravity, damping (Vector2), size (Vector2 min/max), curve (&"shrink"/&"grow"/&"pop"/&"flat"),
## color, fade (&"out"/&"late"/&"flash"), additive, align, spin (Vector2), explosiveness, radius,
## z, randomness, local, offset (Vector2, in the parent's space).
static func emit(parent: Node, params: Dictionary) -> CPUParticles2D:
	var multiplier: float = GameJuice.particles_multiplier
	if multiplier <= 0.0:
		return null
	var parent_2d: Node2D = parent as Node2D
	var pooled: bool = not bool(params.get("local", false)) and parent_2d != null and _pool_available(parent_2d)
	var key: int = 0
	var particles: CPUParticles2D = null
	if pooled:
		# Direction and offset only change the emitter's placement, so they stay out of the key.
		var keyed: Dictionary = params.duplicate()
		keyed.erase("direction")
		keyed.erase("offset")
		key = keyed.hash() ^ hash(multiplier)
		particles = _take_configured(parent_2d, key)
		if particles != null:
			_place_pooled(particles, parent_2d, params)
			return particles
		particles = _take_emitter(parent_2d)
		particles.set_meta(&"fx_key", key)
	else:
		particles = CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	var texture: Texture2D = params.get("texture", TEX_SOFT)
	if particles.texture != texture:
		particles.texture = texture
	var amount: int = maxi(1, int(round(float(params.get("amount", 8)) * multiplier)))
	if particles.amount != amount:
		particles.amount = amount
	particles.lifetime = float(params.get("lifetime", 0.4))
	particles.explosiveness = float(params.get("explosiveness", 0.95))
	particles.randomness = float(params.get("randomness", 0.4))
	particles.lifetime_randomness = float(params.get("lifetime_randomness", 0.35))
	particles.local_coords = bool(params.get("local", false))
	var direction: Vector2 = params.get("direction", Vector2.UP)
	if pooled:
		particles.direction = Vector2.RIGHT
	else:
		particles.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.UP
	particles.spread = float(params.get("spread", 45.0))
	var speed: Vector2 = params.get("speed", Vector2(60.0, 160.0))
	particles.initial_velocity_min = speed.x
	particles.initial_velocity_max = speed.y
	particles.gravity = params.get("gravity", Vector2(0.0, 400.0))
	var damping: Vector2 = params.get("damping", Vector2(20.0, 80.0))
	particles.damping_min = damping.x
	particles.damping_max = damping.y
	var size: Vector2 = params.get("size", Vector2(0.5, 1.0))
	particles.scale_amount_min = size.x
	particles.scale_amount_max = size.y
	particles.scale_amount_curve = curve(params.get("curve", &"shrink"))
	particles.color = params.get("color", Color.WHITE)
	particles.color_ramp = fade_ramp(params.get("fade", &"out"))
	var spin: Vector2 = params.get("spin", Vector2.ZERO)
	particles.angular_velocity_min = spin.x
	particles.angular_velocity_max = spin.y
	if spin != Vector2.ZERO:
		particles.angle_min = -180.0
		particles.angle_max = 180.0
	else:
		particles.angle_min = 0.0
		particles.angle_max = 0.0
	particles.particle_flag_align_y = bool(params.get("align", false))
	var radius: float = float(params.get("radius", 0.0))
	if radius > 0.0:
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = radius
	elif particles.emission_shape != CPUParticles2D.EMISSION_SHAPE_POINT:
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	particles.material = additive_material() if bool(params.get("additive", false)) else null
	if pooled:
		_place_pooled(particles, parent_2d, params)
	else:
		particles.z_index = int(params.get("z", 0))
		particles.position = params.get("offset", Vector2.ZERO)
		parent.add_child(particles)
		particles.emitting = true
	return particles


## Pooled emitters live outside the effect node: copy its placement and resolve its draw depth.
static func _place_pooled(particles: CPUParticles2D, parent_2d: Node2D, params: Dictionary) -> void:
	var direction: Vector2 = params.get("direction", Vector2.UP)
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP
	# Pooled emitters always fire along +x; the requested direction becomes the emitter's rotation.
	particles.global_transform = parent_2d.global_transform.translated_local(params.get("offset", Vector2.ZERO)) * Transform2D(direction.angle(), Vector2.ZERO)
	particles.z_as_relative = false
	particles.z_index = clampi(_absolute_z(parent_2d) + int(params.get("z", 0)), RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
	particles.restart()


## The pool lives directly under the viewport that shows the effects, so it survives scene changes.
## Effects in any other viewport (previews) fall back to plain emitters.
static func _pool_available(near: Node2D) -> bool:
	if not near.is_inside_tree():
		return false
	var viewport: Viewport = near.get_viewport()
	if is_instance_valid(_pool_host):
		# A host that is not in the tree yet is still waiting for its deferred add.
		return _pool_host.is_inside_tree() and _pool_host.get_viewport() == viewport
	_pool_host = Node2D.new()
	_pool_host.name = "FxEmitterPool"
	_pool_host.process_mode = Node.PROCESS_MODE_PAUSABLE
	_idle_by_key.clear()
	_idle_count = 0
	_pooled_count = 0
	viewport.add_child.call_deferred(_pool_host)
	return false


static func _take_configured(_near: Node2D, key: int) -> CPUParticles2D:
	var idle: Array = _idle_by_key.get(key, [])
	while not idle.is_empty():
		var particles: CPUParticles2D = idle.pop_back()
		_idle_count -= 1
		if is_instance_valid(particles):
			return particles
	return null


static func _take_emitter(_near: Node2D) -> CPUParticles2D:
	if _idle_count > 0:
		# No exact match: repurpose an idle emitter of another effect before allocating a new one.
		for other_key in _idle_by_key.keys():
			var idle: Array = _idle_by_key[other_key]
			while not idle.is_empty():
				var candidate: CPUParticles2D = idle.pop_back()
				_idle_count -= 1
				if is_instance_valid(candidate):
					return candidate
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.local_coords = false
	_pool_host.add_child(particles)
	if _pooled_count < POOL_LIMIT:
		_pooled_count += 1
		particles.finished.connect(FxLib._return_emitter.bind(particles))
	else:
		particles.finished.connect(particles.queue_free)
	return particles


static func _return_emitter(particles: CPUParticles2D) -> void:
	if not is_instance_valid(particles) or particles.is_queued_for_deletion():
		return
	var key: int = int(particles.get_meta(&"fx_key", 0))
	if not _idle_by_key.has(key):
		_idle_by_key[key] = []
	(_idle_by_key[key] as Array).append(particles)
	_idle_count += 1


static func _absolute_z(node: Node) -> int:
	var z: int = 0
	var current: Node = node
	while current is CanvasItem:
		var item: CanvasItem = current as CanvasItem
		z += item.z_index
		if not item.z_as_relative:
			break
		current = current.get_parent()
	return z


## Quick additive glow sprite that pops and fades.
static func glow_flash(parent: Node, color: Color, size: float, duration: float, z: int = 2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = TEX_GLOW
	sprite.material = additive_material()
	sprite.modulate = color
	sprite.z_index = z
	var base_scale: float = size / float(TEX_GLOW.get_width())
	sprite.scale = Vector2.ONE * base_scale * 0.6
	parent.add_child(sprite)
	var tween: Tween = sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * base_scale, duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(sprite.queue_free)
	return sprite


## Anti-aliased expanding shock ring.
static func ring(parent: Node, color: Color, start_size: float, end_size: float, duration: float, additive: bool = true, z: int = 3) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = TEX_RING
	if additive:
		sprite.material = additive_material()
	sprite.modulate = color
	sprite.z_index = z
	var texture_size: float = float(TEX_RING.get_width())
	sprite.scale = Vector2.ONE * (start_size / texture_size)
	parent.add_child(sprite)
	var tween: Tween = sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * (end_size / texture_size), duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sprite.queue_free)
	return sprite


## Short-lived dynamic light that illuminates nearby characters and level geometry.
static func light_flash(parent: Node, color: Color, energy: float, radius: float, duration: float) -> PointLight2D:
	if GameJuice.particles_multiplier <= 0.0:
		return null
	var light: PointLight2D = PointLight2D.new()
	light.texture = TEX_GLOW
	light.texture_scale = radius / (float(TEX_GLOW.get_width()) * 0.5)
	light.color = color
	light.energy = energy
	light.range_item_cull_mask = FLASH_LIGHT_MASK
	light.shadow_enabled = false
	parent.add_child(light)
	var tween: Tween = light.create_tween()
	tween.tween_property(light, "energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)
	return light


static func curve(kind: StringName) -> Curve:
	if _curves.has(kind):
		return _curves[kind]
	var result: Curve = Curve.new()
	match kind:
		&"grow":
			result.add_point(Vector2(0.0, 0.35))
			result.add_point(Vector2(0.35, 0.85))
			result.add_point(Vector2(1.0, 1.0))
		&"pop":
			result.add_point(Vector2(0.0, 0.2))
			result.add_point(Vector2(0.12, 1.0))
			result.add_point(Vector2(1.0, 0.0))
		&"flat":
			result.add_point(Vector2(0.0, 1.0))
			result.add_point(Vector2(1.0, 1.0))
		&"puff":
			result.add_point(Vector2(0.0, 0.25))
			result.add_point(Vector2(0.25, 0.9))
			result.add_point(Vector2(1.0, 1.25))
		_:
			result.add_point(Vector2(0.0, 1.0))
			result.add_point(Vector2(0.7, 0.6))
			result.add_point(Vector2(1.0, 0.0))
	result.max_value = 1.5
	_curves[kind] = result
	return result


static func fade_ramp(kind: StringName) -> Gradient:
	if _gradients.has(kind):
		return _gradients[kind]
	var gradient: Gradient = Gradient.new()
	match kind:
		&"late":
			gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
			gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		&"flash":
			gradient.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
			gradient.colors = PackedColorArray([Color(1.6, 1.6, 1.6, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
		&"fire":
			gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 1.0])
			gradient.colors = PackedColorArray([Color(1.0, 0.97, 0.8, 1), Color(1.0, 0.72, 0.25, 0.95), Color(0.85, 0.28, 0.08, 0.6), Color(0.2, 0.12, 0.1, 0)])
		&"smoke":
			gradient.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
			gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		_:
			gradient.offsets = PackedFloat32Array([0.0, 1.0])
			gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_gradients[kind] = gradient
	return gradient
