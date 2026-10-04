class_name LoadoutOperatorPuppet
extends Node2D

## The player's character for the loadout stage, drawn like the in-game ball character but large:
## breathing idle, eyes on the cursor, the configured carbine in hand (same art as the workbench) and the
## equipped boots, vest and shield. Equipping something makes it materialise with a flash and the
## character reacts with a little hop.

const BODY_PATH: String = "res://assets/player/body/%s.png"
const BODY_SCALE: float = 0.25
const ARMOR_SCALE: float = 4.0
const GUN_SCALE: float = 0.78
## Armor outline in art units at this size, about as heavy as the limbs' outline.
const ARMOR_OUTLINE: float = 1.5
const BODY_SHADER: Shader = preload("res://scenes/player/player_body.gdshader")

var facing: float = 1.0

var _body: Sprite2D = null
var _face: PlayerFace = null
var _gun_holder: Node2D = null
var _back_limbs: Node2D = null
var _front_arm: Node2D = null
var _vest_anchor: Node2D = null
var _boot_anchors: Array[Node2D] = []
var _shield_anchor: Node2D = null
var _ghost_anchor: Node2D = null
var _limb_color: Color = Color.WHITE
var _accent: Color = Color.WHITE
var _time: float = 0.0
var _hop: float = 0.0
var _check: float = 0.0
var _materialize: Dictionary = {}
var _config: Dictionary = {}
var _hand: Vector2 = Vector2.ZERO
var _guard_hand: Vector2 = Vector2.ZERO
var _feet: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]


func _ready() -> void:
	var color_id: StringName = LoadoutStyle.local_color_id()
	_limb_color = GameSettings.player_color_value(color_id)
	_accent = _limb_color
	_back_limbs = Node2D.new()
	_back_limbs.draw.connect(_draw_back_limbs)
	add_child(_back_limbs)
	_gun_holder = Node2D.new()
	_gun_holder.draw.connect(_draw_gun)
	add_child(_gun_holder)
	_front_arm = Node2D.new()
	_front_arm.draw.connect(_draw_front_arm)
	add_child(_front_arm)
	_body = Sprite2D.new()
	_body.texture = load(BODY_PATH % str(color_id))
	_body.scale = Vector2.ONE * BODY_SCALE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BODY_SHADER
	_body.material = material
	add_child(_body)
	_face = PlayerFace.new()
	_face.body_sprite = _body
	add_child(_face)
	_vest_anchor = Node2D.new()
	_vest_anchor.scale = Vector2.ONE * ARMOR_SCALE
	add_child(_vest_anchor)
	for index in range(2):
		var boot: Node2D = Node2D.new()
		boot.scale = Vector2.ONE * ARMOR_SCALE
		boot.z_index = 1
		add_child(boot)
		_boot_anchors.append(boot)
	_shield_anchor = Node2D.new()
	_shield_anchor.scale = Vector2.ONE * ARMOR_SCALE
	_shield_anchor.z_index = 2
	add_child(_shield_anchor)
	_ghost_anchor = Node2D.new()
	_ghost_anchor.z_index = 3
	add_child(_ghost_anchor)
	_update_pose(0.0)


func set_weapon(config: Dictionary, animate: bool) -> void:
	if animate and config != _config:
		_check = 1.0
		_face.set_expression(PlayerFace.Mood.FOCUS, 0.9)
	_config = config
	_gun_holder.queue_redraw()


func set_armor(category: StringName, item: ArmorItemData, animate: bool) -> void:
	var anchors: Array[Node2D] = _anchors_for(category)
	for anchor in anchors:
		for child in anchor.get_children():
			child.queue_free()
		if item != null:
			anchor.add_child(ArmorArtView.create(item, _limb_color, ARMOR_OUTLINE, true))
	if animate:
		_hop = 1.0
		_materialize[category] = 1.0
		if item != null:
			_face.set_expression(PlayerFace.Mood.HAPPY, 1.1)


## Hologram of an armor piece being dragged over the stage.
func set_ghost(category: StringName, item: ArmorItemData) -> void:
	for child in _ghost_anchor.get_children():
		child.queue_free()
	if item == null:
		return
	var targets: Array[Node2D] = _anchors_for(category)
	for target in targets:
		var holder: Node2D = Node2D.new()
		holder.set_meta("follow", target)
		holder.scale = target.scale
		holder.modulate = Color(1.0, 0.86, 0.62, 0.6)
		holder.add_child(ArmorArtView.create(item, _limb_color, ARMOR_OUTLINE))
		_ghost_anchor.add_child(holder)
	_sync_ghosts()


func get_anchor_position(category: StringName) -> Vector2:
	match category:
		ArmorItemData.CATEGORY_VEST:
			return _vest_anchor.position + Vector2(0.0, 10.0)
		ArmorItemData.CATEGORY_SHIELD:
			return _guard_hand
		ArmorItemData.CATEGORY_BOOTS:
			return (_feet[0] + _feet[1]) * 0.5 + Vector2(0.0, -6.0)
	return Vector2.ZERO


func _anchors_for(category: StringName) -> Array[Node2D]:
	match category:
		ArmorItemData.CATEGORY_VEST:
			return [_vest_anchor]
		ArmorItemData.CATEGORY_SHIELD:
			return [_shield_anchor]
		ArmorItemData.CATEGORY_BOOTS:
			return _boot_anchors
	return []


func _process(delta: float) -> void:
	_time += delta
	_hop = maxf(_hop - delta * 2.6, 0.0)
	_check = maxf(_check - delta * 2.2, 0.0)
	for key in _materialize.keys():
		_materialize[key] = maxf(float(_materialize[key]) - delta * 2.4, 0.0)
	_update_pose(delta)
	_gun_holder.queue_redraw()
	_back_limbs.queue_redraw()
	_front_arm.queue_redraw()


func _update_pose(_delta: float) -> void:
	var breathe: float = sin(_time * 2.2) * 0.02
	var hop_height: float = sin(_hop * PI) * 26.0
	var squash: float = sin(clampf(_hop * 1.6 - 0.6, 0.0, 1.0) * PI) * 0.12
	_body.scale = Vector2.ONE * BODY_SCALE * Vector2(1.0 + breathe + squash, 1.0 - breathe - squash)
	_body.position = Vector2(0.0, -sin(_time * 2.2) * 2.0 - hop_height + squash * 26.0)
	var mouse: Vector2 = get_local_mouse_position() - _body.position
	_face.look_target = mouse.normalized() * clampf(mouse.length() / 260.0, 0.35, 1.0)
	var raise: float = sin(_check * PI)
	var aim: Vector2 = Vector2(facing, 0.16 - raise * 0.5 + sin(_time * 1.3) * 0.03).normalized()
	_hand = aim * 80.0 + Vector2(0.0, 22.0 + _body.position.y * 0.6)
	_guard_hand = Vector2(-facing * 70.0, 26.0 + _body.position.y * 0.8 + sin(_time * 1.7) * 1.5)
	_gun_holder.position = _hand
	_gun_holder.rotation = aim.angle() - raise * 0.25 * facing
	_gun_holder.scale = Vector2(1.0, 1.0 if facing > 0.0 else -1.0)
	var lift: float = hop_height * 0.35
	_feet[0] = Vector2(-34.0, 116.0 - lift)
	_feet[1] = Vector2(34.0, 116.0 - lift)
	_vest_anchor.position = _body.position + Vector2(0.0, -4.0)
	_vest_anchor.scale = Vector2.ONE * ARMOR_SCALE * Vector2(1.0 + breathe + squash, 1.0 - breathe - squash) * _materialize_scale(ArmorItemData.CATEGORY_VEST)
	for index in range(2):
		_boot_anchors[index].position = _feet[index] + Vector2(0.0, -6.0)
		_boot_anchors[index].scale = Vector2(facing, 1.0) * ARMOR_SCALE * _materialize_scale(ArmorItemData.CATEGORY_BOOTS)
	_shield_anchor.position = _guard_hand + Vector2(-facing * 8.0, -2.0)
	_shield_anchor.rotation = -0.18 * facing
	_shield_anchor.scale = Vector2(-facing, 1.0) * ARMOR_SCALE * _materialize_scale(ArmorItemData.CATEGORY_SHIELD)
	for category in [ArmorItemData.CATEGORY_VEST, ArmorItemData.CATEGORY_BOOTS, ArmorItemData.CATEGORY_SHIELD]:
		var glow: float = float(_materialize.get(category, 0.0))
		for anchor in _anchors_for(category):
			anchor.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(2.2, 2.2, 2.0, 1.0), glow)
	_sync_ghosts()


func _materialize_scale(category: StringName) -> float:
	var t: float = float(_materialize.get(category, 0.0))
	return 1.0 + sin(t * PI) * 0.22


func _sync_ghosts() -> void:
	if _ghost_anchor == null:
		return
	var pulse: float = 0.45 + 0.2 * sin(_time * 6.0)
	for holder in _ghost_anchor.get_children():
		var follow: Node2D = holder.get_meta("follow", null) as Node2D
		if follow == null:
			continue
		var node: Node2D = holder as Node2D
		node.position = follow.position
		node.rotation = follow.rotation
		node.scale = follow.scale
		node.modulate = Color(1.0, 0.86, 0.62, pulse)


func _draw_gun() -> void:
	var xform: Transform2D = Transform2D(0.0, Vector2.ONE * GUN_SCALE, 0.0, Vector2.ZERO)
	WeaponArt.draw_weapon(_gun_holder, xform, _config, {"accent": _accent, "flashes": {&"front": _check * 0.4, &"middle": _check * 0.4, &"ammo": _check * 0.4}})
	WeaponArt.draw_fx(_gun_holder, xform, _config, _time, 0.85)


func _limb_points() -> Dictionary:
	var body_y: float = _body.position.y
	var hip_l: Vector2 = Vector2(-26.0, 52.0 + body_y)
	var hip_r: Vector2 = Vector2(26.0, 52.0 + body_y)
	var shoulder: Vector2 = Vector2(facing * 34.0, 8.0 + body_y)
	var hand: Vector2 = _hand + Vector2(-facing * 2.0, 3.0)
	var guard_shoulder: Vector2 = Vector2(-facing * 34.0, 8.0 + body_y)
	return {
		"legs": [
			[hip_l, (hip_l + _feet[0]) * 0.5 + Vector2(-facing * 12.0, 0.0), _feet[0]],
			[hip_r, (hip_r + _feet[1]) * 0.5 + Vector2(-facing * 12.0, 0.0), _feet[1]],
		],
		"guard": [guard_shoulder, (guard_shoulder + _guard_hand) * 0.5 + Vector2(0.0, 22.0), _guard_hand],
		"front": [shoulder, (shoulder + hand) * 0.5 + Vector2(0.0, 24.0), hand],
	}


func _draw_back_limbs() -> void:
	var points: Dictionary = _limb_points()
	var limbs: Array = (points["legs"] as Array).duplicate()
	limbs.append(points["guard"])
	_draw_limbs(_back_limbs, limbs)


func _draw_front_arm() -> void:
	_draw_limbs(_front_arm, [_limb_points()["front"]])


func _draw_limbs(canvas: Node2D, limbs: Array) -> void:
	var outline: Color = _limb_color.darkened(0.62)
	for limb in limbs:
		canvas.draw_polyline(_bezier(limb[0], limb[1], limb[2]), outline, 15.0, true)
		canvas.draw_circle(limb[2], 13.0, outline, true, -1.0, true)
	for limb in limbs:
		canvas.draw_polyline(_bezier(limb[0], limb[1], limb[2]), _limb_color, 9.0, true)
		canvas.draw_circle(limb[2], 9.0, _limb_color.lightened(0.08), true, -1.0, true)


func _bezier(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(13):
		var t: float = float(index) / 12.0
		var mt: float = 1.0 - t
		points.append(mt * mt * a + 2.0 * mt * t * b + t * t * c)
	return points
