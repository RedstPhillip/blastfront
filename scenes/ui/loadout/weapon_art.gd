class_name WeaponArt
extends RefCounted

## Procedural vector art for the carbine and every weapon extension, drawn into any CanvasItem.
## One source of truth for the loadout workbench, the item icons and the operator preview: barrels mount on
## the front socket, optics on the top rail, ammo swaps the magazine (and leaves a coloured window, accent
## lines and a muzzle glow on the gun) so every build is visible at a glance.
## Parts are lists of convex shapes; each part draws an outline pass first, then fills, then details, so
## pieces of one part merge into a single silhouette with a clean dark outline.

const SLOT_FRONT: StringName = &"front"
const SLOT_TOP: StringName = &"middle"
const SLOT_AMMO: StringName = &"ammo"

const OUTLINE: Color = Color(0.03, 0.035, 0.04, 1.0)
const OUTLINE_WIDTH: float = 1.7
const STEEL_DARK: Color = Color(0.12, 0.13, 0.145)
const STEEL: Color = Color(0.22, 0.24, 0.26)
const STEEL_MID: Color = Color(0.3, 0.32, 0.35)
const STEEL_LIGHT: Color = Color(0.43, 0.46, 0.49)
const STEEL_EDGE: Color = Color(0.62, 0.66, 0.68)
const POLYMER: Color = Color(0.19, 0.2, 0.21)
const POLYMER_LIGHT: Color = Color(0.28, 0.29, 0.3)
const BRASS: Color = Color(0.93, 0.72, 0.32)
const GOLD: Color = Color(1.0, 0.78, 0.3)
const GLASS: Color = Color(0.45, 0.85, 1.0)

## Socket origins on the base carbine (gun faces +x, origin at the top of the grip).
const SOCKET_POSITIONS: Dictionary = {
	SLOT_FRONT: Vector2(74.0, -5.0),
	SLOT_TOP: Vector2(4.0, -16.0),
	SLOT_AMMO: Vector2(18.0, 8.0),
}
## Where each slot sits visually for callouts and highlights (part centre in gun space).
const SLOT_FOCUS: Dictionary = {
	SLOT_FRONT: Vector2(96.0, -5.0),
	SLOT_TOP: Vector2(4.0, -25.0),
	SLOT_AMMO: Vector2(21.0, 22.0),
}
const AMMO_COLORS: Dictionary = {
	&"": Color(0.95, 0.75, 0.36),
	&"poison_rounds_mk1": Color(0.38, 1.0, 0.36),
	&"freeze_rounds_mk1": Color(0.5, 0.86, 1.0),
	&"shocking_rounds_mk1": Color(1.0, 0.92, 0.32),
	&"explosive_bullet_mk1": Color(1.0, 0.48, 0.16),
	&"grenades_mk1": Color(0.62, 0.86, 0.26),
	&"drill_bullets_mk1": Color(0.78, 0.82, 0.88),
	&"bouncy_bullets_mk1": Color(0.78, 1.0, 0.42),
	&"big_bullets_mk1": Color(1.0, 0.58, 0.2),
}

static var _part_cache: Dictionary = {}
static var _tint: Color = Color.WHITE
static var _flash: float = 0.0
static var _desaturate: float = 0.0
static var _accent: Color = Color(0.32, 0.67, 1.0)
static var _ammo_color: Color = Color(0.95, 0.75, 0.36)
## Outline thickness in gun units; small renders (the in-game gun) ask for a heavier outline.
static var _outline_width: float = OUTLINE_WIDTH


## Config: {slot: {"id": StringName, "mark": int}} for the three sockets; missing slots draw stock parts.
static func config_from_equipped(equipped: Dictionary) -> Dictionary:
	var config: Dictionary = {}
	for slot in [SLOT_FRONT, SLOT_TOP, SLOT_AMMO]:
		var item: WeaponExtensionItem = equipped.get(slot, null) as WeaponExtensionItem
		if item != null and item.definition != null:
			config[slot] = {"id": item.get_definition_id(), "mark": item.mark}
	return config


static func part_id(config: Dictionary, slot: StringName) -> StringName:
	var entry: Variant = config.get(slot, null)
	if entry is Dictionary:
		return StringName(str((entry as Dictionary).get("id", "")))
	return &""


static func part_mark(config: Dictionary, slot: StringName) -> int:
	var entry: Variant = config.get(slot, null)
	if entry is Dictionary:
		return int((entry as Dictionary).get("mark", 1))
	return 0


static func ammo_color(definition_id: StringName) -> Color:
	return AMMO_COLORS.get(definition_id, AMMO_COLORS[&""])


static func muzzle_position(config: Dictionary) -> Vector2:
	return SOCKET_POSITIONS[SLOT_FRONT] + _muzzle_offset(part_id(config, SLOT_FRONT))


static func slot_of(definition_id: StringName) -> StringName:
	var definition: WeaponExtensionDefinition = ExtensionInventory.get_definition(definition_id)
	return definition.get_slot() if definition != null else &""


## Rough bounds of the whole gun for a config, in gun space.
static func weapon_bounds(config: Dictionary) -> Rect2:
	var rect: Rect2 = Rect2(Vector2(-105.0, -22.0), Vector2(180.0, 52.0))
	rect = rect.expand(muzzle_position(config) + Vector2(4.0, 0.0))
	var top: StringName = part_id(config, SLOT_TOP)
	if top != &"":
		var top_rect: Rect2 = _part_bounds(SLOT_TOP, top)
		rect = rect.merge(Rect2(top_rect.position + SOCKET_POSITIONS[SLOT_TOP], top_rect.size))
	var ammo: StringName = part_id(config, SLOT_AMMO)
	var ammo_rect: Rect2 = _part_bounds(SLOT_AMMO, ammo)
	rect = rect.merge(Rect2(ammo_rect.position + SOCKET_POSITIONS[SLOT_AMMO], ammo_rect.size))
	if ammo == &"grenades_mk1":
		var launcher: Rect2 = _part_bounds(SLOT_AMMO, &"grenade_launcher")
		rect = rect.merge(Rect2(launcher.position + SOCKET_POSITIONS[SLOT_AMMO] + _relative_launcher_origin(), launcher.size))
	return rect


# --- Drawing ---------------------------------------------------------------------------------------------

## Draws the full carbine. style keys (all optional):
##   accent: Color, offsets: {slot: Vector2}, alphas: {slot: float}, flashes: {slot: float},
##   ghost: {slot: StringName} (hologram preview of a part), highlight: StringName slot, desaturate: float
static func draw_weapon(canvas: CanvasItem, xform: Transform2D, config: Dictionary, style: Dictionary = {}) -> void:
	_accent = style.get("accent", Color(0.32, 0.67, 1.0))
	_outline_width = float(style.get("outline", OUTLINE_WIDTH))
	var ghosts: Dictionary = style.get("ghost", {})
	var offsets: Dictionary = style.get("offsets", {})
	var alphas: Dictionary = style.get("alphas", {})
	var flashes: Dictionary = style.get("flashes", {})
	var base_desat: float = float(style.get("desaturate", 0.0))
	var base_alpha: float = float(style.get("alpha", 1.0))
	var ammo_id: StringName = part_id(config, SLOT_AMMO)
	_ammo_color = ammo_color(ammo_id)

	_begin(base_alpha, 0.0, base_desat)
	_draw_part_at(canvas, xform, Vector2.ZERO, _stock_part())
	if ammo_id == &"grenades_mk1":
		_draw_slot_part(canvas, xform, SLOT_AMMO, &"grenade_launcher", config, offsets, alphas, flashes, base_alpha, base_desat, true)
	_draw_slot_part(canvas, xform, SLOT_FRONT, part_id(config, SLOT_FRONT), config, offsets, alphas, flashes, base_alpha, base_desat)
	_begin(base_alpha, 0.0, base_desat)
	_draw_part_at(canvas, xform, Vector2.ZERO, _receiver_part(part_id(config, SLOT_TOP) == &""))
	_draw_ammo_accents(canvas, xform, ammo_id, float(alphas.get(SLOT_AMMO, 1.0)) * base_alpha)
	_draw_slot_part(canvas, xform, SLOT_AMMO, ammo_id, config, offsets, alphas, flashes, base_alpha, base_desat)
	_begin(base_alpha, 0.0, base_desat)
	_draw_part_at(canvas, xform, Vector2.ZERO, _grip_part())
	if part_id(config, SLOT_TOP) != &"":
		_draw_slot_part(canvas, xform, SLOT_TOP, part_id(config, SLOT_TOP), config, offsets, alphas, flashes, base_alpha, base_desat)
	for slot in ghosts.keys():
		_draw_ghost(canvas, xform, StringName(str(slot)), StringName(str(ghosts[slot])))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_begin(1.0, 0.0, 0.0)
	_outline_width = OUTLINE_WIDTH


## One socket's part on its own (used for parts flying off the gun while another snaps in).
static func draw_socket_part(canvas: CanvasItem, xform: Transform2D, slot: StringName, definition_id: StringName, mark: int, offset: Vector2, alpha: float, flash: float = 0.0, accent: Color = Color(0.32, 0.67, 1.0)) -> void:
	if alpha <= 0.01 or not SOCKET_POSITIONS.has(slot):
		return
	_accent = accent
	_ammo_color = ammo_color(definition_id) if slot == SLOT_AMMO else _ammo_color
	_begin(alpha, flash, 0.0)
	if slot == SLOT_AMMO and definition_id == &"grenades_mk1":
		_draw_part_at(canvas, xform, SOCKET_POSITIONS[SLOT_AMMO] + _relative_launcher_origin() + offset, _part(SLOT_AMMO, &"grenade_launcher"))
	_draw_part_at(canvas, xform, SOCKET_POSITIONS[slot] + offset, _part(slot, definition_id))
	if definition_id != &"":
		_draw_mark_pips_local(canvas, slot, definition_id, mark)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_begin(1.0, 0.0, 0.0)


## Draws a single part centred and fitted into rect (inventory icons, chips, drag previews).
static func draw_part_icon(canvas: CanvasItem, rect: Rect2, definition_id: StringName, style: Dictionary = {}) -> void:
	var slot: StringName = slot_of(definition_id)
	if slot == &"":
		return
	var bounds: Rect2 = _part_bounds(slot, definition_id)
	if definition_id == &"grenades_mk1":
		var launcher: Rect2 = _part_bounds(SLOT_AMMO, &"grenade_launcher")
		bounds = bounds.merge(Rect2(launcher.position + _relative_launcher_origin(), launcher.size))
	# Long barrels lie diagonally so they fill a square tile instead of a thin strip.
	var angle: float = float(style.get("rotation", -0.62 if slot == SLOT_FRONT else 0.0))
	var turned: Vector2 = Vector2(
		absf(bounds.size.x * cos(angle)) + absf(bounds.size.y * sin(angle)),
		absf(bounds.size.x * sin(angle)) + absf(bounds.size.y * cos(angle)))
	var fit: float = minf(rect.size.x / maxf(turned.x, 1.0), rect.size.y / maxf(turned.y, 1.0))
	fit = minf(fit, float(style.get("max_scale", 2.4)))
	var xform: Transform2D = Transform2D(angle, Vector2.ONE * fit, 0.0, rect.get_center())
	xform = (style.get("base", Transform2D.IDENTITY) as Transform2D) * xform * Transform2D(0.0, -bounds.get_center())
	_accent = style.get("accent", Color(0.32, 0.67, 1.0))
	_ammo_color = ammo_color(definition_id) if slot == SLOT_AMMO else ammo_color(&"")
	_begin(float(style.get("alpha", 1.0)), float(style.get("flash", 0.0)), float(style.get("desaturate", 0.0)))
	if definition_id == &"grenades_mk1":
		_draw_part_at(canvas, xform, _relative_launcher_origin(), _part(SLOT_AMMO, &"grenade_launcher"))
	_draw_part_at(canvas, xform, Vector2.ZERO, _part(slot, definition_id))
	_draw_mark_pips(canvas, xform, slot, definition_id, int(style.get("mark", 0)))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_begin(1.0, 0.0, 0.0)


## Animated flourishes (laser beam, coils, ammo vapour, sparks). Cheap; meant for a canvas that redraws
## every frame on top of the static gun.
static func draw_fx(canvas: CanvasItem, xform: Transform2D, config: Dictionary, time: float, intensity: float = 1.0) -> void:
	var ammo_id: StringName = part_id(config, SLOT_AMMO)
	var top_id: StringName = part_id(config, SLOT_TOP)
	var front_id: StringName = part_id(config, SLOT_FRONT)
	var muzzle: Vector2 = muzzle_position(config)
	canvas.draw_set_transform_matrix(xform)
	var color: Color = ammo_color(ammo_id)
	if ammo_id != &"":
		var pulse: float = 0.55 + 0.45 * sin(time * 3.1)
		canvas.draw_circle(muzzle, 3.4 + pulse * 1.6, Color(color.r, color.g, color.b, 0.22 * intensity), true, -1.0, true)
		canvas.draw_circle(muzzle, 1.6, Color(1.0, 1.0, 1.0, 0.5 * intensity * pulse), true, -1.0, true)
	if top_id == &"laser_scope_mk1":
		var emitter: Vector2 = SOCKET_POSITIONS[SLOT_TOP] + Vector2(20.5, -4.5)
		var beam_end: Vector2 = emitter + Vector2(150.0, 0.0)
		var flicker: float = 0.75 + 0.25 * sin(time * 23.0) * sin(time * 7.0)
		canvas.draw_line(emitter, beam_end, Color(1.0, 0.12, 0.08, 0.18 * intensity), 3.2, true)
		canvas.draw_line(emitter, beam_end, Color(1.0, 0.35, 0.25, 0.65 * intensity * flicker), 0.9, true)
		canvas.draw_circle(beam_end, 2.2, Color(1.0, 0.3, 0.2, 0.55 * intensity * flicker), true, -1.0, true)
	if top_id == &"ground_hover_mk1":
		for ring in range(3):
			var phase: float = fmod(time * 0.9 + float(ring) / 3.0, 1.0)
			var center: Vector2 = Vector2(56.0, 8.0 + phase * 14.0)
			canvas.draw_arc(center, 5.0 + phase * 9.0, PI * 0.12, PI * 0.88, 14, Color(0.4, 1.0, 0.85, (1.0 - phase) * 0.5 * intensity), 1.2, true)
	if front_id == &"kinetic_amplifier_mk1":
		var socket: Vector2 = SOCKET_POSITIONS[SLOT_FRONT]
		for coil in range(3):
			var glow: float = 0.5 + 0.5 * sin(time * 6.0 - float(coil) * 1.1)
			var x: float = socket.x + 10.0 + float(coil) * 10.0
			canvas.draw_rect(Rect2(Vector2(x - 2.0, socket.y - 6.5), Vector2(4.0, 13.0)), Color(0.85, 0.45, 1.0, 0.35 * glow * intensity))
	match ammo_id:
		&"poison_rounds_mk1":
			for bubble in range(5):
				var phase: float = fmod(time * 0.45 + float(bubble) * 0.21, 1.0)
				var origin: Vector2 = SOCKET_POSITIONS[SLOT_AMMO] + Vector2(1.0 + sin(float(bubble) * 2.3) * 3.0, 14.0)
				var pos: Vector2 = origin + Vector2(sin(phase * 9.0 + float(bubble)) * 2.0, -phase * 30.0)
				canvas.draw_circle(pos, 1.0 + phase * 1.4, Color(0.45, 1.0, 0.4, (1.0 - phase) * 0.55 * intensity), false, 0.8, true)
		&"freeze_rounds_mk1":
			for flake in range(6):
				var phase: float = fmod(time * 0.3 + float(flake) * 0.17, 1.0)
				var pos: Vector2 = SOCKET_POSITIONS[SLOT_AMMO] + Vector2(-8.0 + float(flake) * 4.0 + sin(phase * 6.0 + float(flake)) * 3.0, 18.0 + phase * 22.0)
				canvas.draw_circle(pos, 0.9, Color(0.8, 0.95, 1.0, (1.0 - phase) * 0.7 * intensity), true, -1.0, true)
		&"shocking_rounds_mk1":
			var seed_step: int = int(time * 14.0)
			if seed_step % 3 != 0:
				var rng: RandomNumberGenerator = RandomNumberGenerator.new()
				rng.seed = seed_step
				var start: Vector2 = Vector2(48.0 + rng.randf_range(0.0, 20.0), -11.0)
				var points: PackedVector2Array = PackedVector2Array([start])
				for step in range(5):
					points.append(start + Vector2(float(step + 1) * rng.randf_range(2.5, 5.0), rng.randf_range(-4.0, 3.0)))
				canvas.draw_polyline(points, Color(1.0, 0.95, 0.45, 0.85 * intensity), 0.9, true)
		&"explosive_bullet_mk1":
			for ember in range(4):
				var phase: float = fmod(time * 0.6 + float(ember) * 0.27, 1.0)
				var pos: Vector2 = muzzle + Vector2(phase * 6.0 + float(ember), -phase * 12.0 + sin(phase * 8.0 + float(ember)) * 2.0)
				canvas.draw_circle(pos, 0.9 * (1.0 - phase) + 0.3, Color(1.0, 0.6, 0.2, (1.0 - phase) * 0.8 * intensity), true, -1.0, true)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Internals -------------------------------------------------------------------------------------------

static func _begin(alpha: float, flash: float, desat: float) -> void:
	_tint = Color(1.0, 1.0, 1.0, alpha)
	_flash = flash
	_desaturate = desat


static func _c(color: Color) -> Color:
	var result: Color = color
	if _desaturate > 0.0:
		var luma: float = color.r * 0.3 + color.g * 0.55 + color.b * 0.15
		result = Color(luma, luma, luma, color.a).lerp(result, 1.0 - _desaturate)
	if _flash > 0.0:
		result = result.lerp(Color(1.0, 0.97, 0.88, result.a), _flash)
	return Color(result.r * _tint.r, result.g * _tint.g, result.b * _tint.b, result.a * _tint.a)


static func _draw_slot_part(canvas: CanvasItem, xform: Transform2D, slot: StringName, definition_id: StringName, config: Dictionary, offsets: Dictionary, alphas: Dictionary, flashes: Dictionary, base_alpha: float, base_desat: float, is_launcher: bool = false) -> void:
	var alpha: float = float(alphas.get(slot, 1.0)) * base_alpha
	if alpha <= 0.01:
		return
	_begin(alpha, float(flashes.get(slot, 0.0)), base_desat)
	var offset: Vector2 = offsets.get(slot, Vector2.ZERO)
	if is_launcher:
		_draw_part_at(canvas, xform, SOCKET_POSITIONS[SLOT_AMMO] + _relative_launcher_origin() + offset, _part(SLOT_AMMO, &"grenade_launcher"))
		return
	_draw_part_at(canvas, xform, SOCKET_POSITIONS[slot] + offset, _part(slot, definition_id))
	if definition_id != &"":
		canvas.draw_set_transform_matrix(xform * Transform2D(0.0, SOCKET_POSITIONS[slot] + offset))
		_draw_mark_pips_local(canvas, slot, definition_id, part_mark(config, slot))


static func _draw_ghost(canvas: CanvasItem, xform: Transform2D, slot: StringName, definition_id: StringName) -> void:
	if not SOCKET_POSITIONS.has(slot):
		return
	_tint = Color(1.0, 0.86, 0.62, 0.66)
	_flash = 0.4
	_desaturate = 1.0
	if definition_id == &"grenades_mk1":
		_draw_part_at(canvas, xform, SOCKET_POSITIONS[SLOT_AMMO] + _relative_launcher_origin(), _part(SLOT_AMMO, &"grenade_launcher"))
	_draw_part_at(canvas, xform, SOCKET_POSITIONS[slot], _part(slot, definition_id))


static func _draw_part_at(canvas: CanvasItem, xform: Transform2D, origin: Vector2, part: Array) -> void:
	canvas.draw_set_transform_matrix(xform * Transform2D(0.0, origin))
	for op in part:
		if op.get("o", false):
			if op["t"] == "poly":
				for outline in op["outline"]:
					canvas.draw_colored_polygon(outline, _c(OUTLINE))
			elif op["t"] == "circle":
				canvas.draw_circle(op["p"], float(op["r"]) + float(op.get("ow", OUTLINE_WIDTH)), _c(OUTLINE), true, -1.0, true)
	for op in part:
		match op["t"]:
			"poly":
				canvas.draw_colored_polygon(op["pts"], _c(_role_color(op)))
			"circle":
				canvas.draw_circle(op["p"], op["r"], _c(_role_color(op)), true, -1.0, true)
			"ring":
				canvas.draw_arc(op["p"], op["r"], 0.0, TAU, 20, _c(_role_color(op)), op["w"], true)
			"line":
				canvas.draw_polyline(op["pts"], _c(_role_color(op)), op["w"], true)


static func _role_color(op: Dictionary) -> Color:
	match op.get("role", &""):
		&"accent":
			return _accent
		&"ammo":
			return _ammo_color
		&"ammo_dark":
			return _ammo_color.darkened(0.55)
		&"ammo_light":
			return _ammo_color.lightened(0.45)
	return op["c"]


static func _draw_mark_pips(canvas: CanvasItem, xform: Transform2D, slot: StringName, definition_id: StringName, mark: int) -> void:
	if mark <= 0:
		return
	canvas.draw_set_transform_matrix(xform)
	_draw_mark_pips_local(canvas, slot, definition_id, mark)


static func _draw_mark_pips_local(canvas: CanvasItem, slot: StringName, definition_id: StringName, mark: int) -> void:
	if mark <= 1:
		return
	var anchor: Vector2 = _pip_anchor(slot, definition_id)
	for index in range(mark):
		var center: Vector2 = anchor + Vector2(float(index) * 3.4, 0.0)
		var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -1.4), center + Vector2(1.4, 0), center + Vector2(0, 1.4), center + Vector2(-1.4, 0)])
		canvas.draw_colored_polygon(diamond, _c(GOLD))


static func _pip_anchor(slot: StringName, definition_id: StringName) -> Vector2:
	match slot:
		SLOT_FRONT:
			return Vector2(5.0, 0.0) if definition_id != &"heavy_barrel_mk1" else Vector2(6.0, 0.0)
		SLOT_TOP:
			return Vector2(-4.0, -7.5)
		SLOT_AMMO:
			return Vector2(-2.5, 21.0)
	return Vector2.ZERO


static func _relative_launcher_origin() -> Vector2:
	return Vector2(34.0, -4.5)


static func _muzzle_offset(front_id: StringName) -> Vector2:
	match front_id:
		&"extended_barrel_mk1":
			return Vector2(58.0, 0.0)
		&"heavy_barrel_mk1":
			return Vector2(50.0, 0.0)
		&"kinetic_amplifier_mk1":
			return Vector2(51.0, 0.0)
		&"lighter_barrel_mk1":
			return Vector2(39.0, 0.0)
		&"multi_barrel_mk1":
			return Vector2(34.0, 0.0)
		&"shotgun_mk1":
			return Vector2(38.0, -1.5)
		&"sniper_barrel_mk1":
			return Vector2(83.0, 0.0)
	return Vector2(26.0, 0.0)


static func _part_bounds(slot: StringName, definition_id: StringName) -> Rect2:
	var part: Array = _part(slot, definition_id)
	var has: bool = false
	var rect: Rect2 = Rect2()
	for op in part:
		var points: PackedVector2Array = PackedVector2Array()
		if op["t"] == "poly" or op["t"] == "line":
			points = op["pts"]
		elif op["t"] == "circle" or op["t"] == "ring":
			var r: float = float(op["r"])
			points = PackedVector2Array([op["p"] - Vector2(r, r), op["p"] + Vector2(r, r)])
		for point in points:
			if has:
				rect = rect.expand(point)
			else:
				rect = Rect2(point, Vector2.ZERO)
				has = true
	return rect.grow(OUTLINE_WIDTH)


static func _ammo_accent_line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(48.0, -1.2), Vector2(70.0, -1.2)])


## Ammo leaves a mark on the gun itself: glowing vents on the handguard and an accent stripe.
static func _draw_ammo_accents(canvas: CanvasItem, xform: Transform2D, ammo_id: StringName, alpha: float) -> void:
	if ammo_id == &"" or alpha <= 0.01:
		return
	canvas.draw_set_transform_matrix(xform)
	var color: Color = ammo_color(ammo_id)
	for index in range(3):
		var x: float = 51.0 + float(index) * 7.0
		canvas.draw_rect(Rect2(Vector2(x, -8.0), Vector2(4.5, 2.2)), _c(Color(color.r, color.g, color.b, 0.95 * alpha)))
	canvas.draw_line(Vector2(-34.0, -0.6), Vector2(44.0, -0.6), _c(Color(color.r, color.g, color.b, 0.75 * alpha)), 1.1, true)


# --- Part library ----------------------------------------------------------------------------------------

static func _part(slot: StringName, definition_id: StringName) -> Array:
	var key: String = "%s/%s/%.1f" % [slot, definition_id, _outline_width]
	if _part_cache.has(key):
		return _part_cache[key]
	var ops: Array = []
	match slot:
		SLOT_FRONT:
			ops = _front_part(definition_id)
		SLOT_TOP:
			ops = _top_part(definition_id)
		SLOT_AMMO:
			ops = _ammo_part(definition_id)
	_prepare(ops)
	_part_cache[key] = ops
	return ops


static func _stock_part() -> Array:
	return _cached("base/stock", func() -> Array:
		return [
			_poly([Vector2(-62, -11), Vector2(-38, -11), Vector2(-38, -4), Vector2(-62, -4)], STEEL_DARK),
			_poly([Vector2(-100, -10), Vector2(-96, -14), Vector2(-64, -12.5), Vector2(-60, -9), Vector2(-60, 3), Vector2(-74, 8), Vector2(-96, 10), Vector2(-100, 6)], POLYMER),
			_poly([Vector2(-105, -13), Vector2(-100, -13), Vector2(-100, 11), Vector2(-105, 11)], STEEL_DARK),
			_poly([Vector2(-95, -11.5), Vector2(-66, -10.2), Vector2(-64, -8), Vector2(-95, -8.6)], POLYMER_LIGHT, false),
			_poly([Vector2(-92, -3.0), Vector2(-74, -2.5), Vector2(-74, 1.5), Vector2(-92, 2.5)], STEEL_DARK, false),
			_line([Vector2(-104, -9), Vector2(-104, 8)], STEEL_MID, 1.2),
		])


static func _receiver_part(with_iron_sights: bool) -> Array:
	return _cached("base/receiver/%s" % with_iron_sights, func() -> Array:
		var ops: Array = [
			_poly([Vector2(46, -11), Vector2(70, -11), Vector2(74, -7.5), Vector2(74, 0), Vector2(70, 3), Vector2(46, 3)], POLYMER),
			_poly([Vector2(-30, 1), Vector2(30, 1), Vector2(27, 8), Vector2(-24, 8)], STEEL),
			_poly([Vector2(-38, -13), Vector2(40, -13), Vector2(46, -8), Vector2(46, 1), Vector2(-38, 1)], STEEL_MID),
			_poly([Vector2(-26, -16.5), Vector2(36, -16.5), Vector2(36, -13), Vector2(-26, -13)], STEEL_DARK),
			_poly([Vector2(-36, -11.6), Vector2(39.4, -11.6), Vector2(43, -8.6), Vector2(-36, -8.6)], STEEL_LIGHT, false),
			_poly([Vector2(-36, -3.2), Vector2(44.4, -3.2), Vector2(44.4, -0.3), Vector2(-36, -0.3)], STEEL, false),
			_poly([Vector2(7, -9), Vector2(22, -9), Vector2(22, -4.5), Vector2(7, -4.5)], STEEL_DARK, false),
			_poly([Vector2(23.5, -7.5), Vector2(28.5, -7.5), Vector2(28.5, -4), Vector2(23.5, -4)], STEEL_EDGE),
			_poly([Vector2(48, -9.6), Vector2(69.5, -9.6), Vector2(72.5, -6.8), Vector2(48, -6.8)], POLYMER_LIGHT, false),
			_poly([Vector2(-30, 2.2), Vector2(29, 2.2), Vector2(28.4, 3.6), Vector2(-29.4, 3.6)], STEEL_MID, false),
			_poly([Vector2(-34, -2.6), Vector2(-8, -2.6), Vector2(-8, -1.1), Vector2(-34, -1.1)], Color.WHITE, false, &"accent"),
			_poly([Vector2(-20, -8), Vector2(-15, -8), Vector2(-17.5, -5)], Color.WHITE, false, &"accent"),
		]
		for tooth in range(12):
			var x: float = -24.0 + float(tooth) * 5.0
			ops.append(_poly([Vector2(x, -16.5), Vector2(x + 2.4, -16.5), Vector2(x + 2.4, -15.0), Vector2(x, -15.0)], STEEL_MID, false))
		for vent in range(3):
			var vx: float = 51.0 + float(vent) * 7.0
			ops.append(_poly([Vector2(vx, -8.0), Vector2(vx + 4.5, -8.0), Vector2(vx + 4.5, -5.8), Vector2(vx, -5.8)], STEEL_DARK, false))
		if with_iron_sights:
			ops.append(_poly([Vector2(-22, -21), Vector2(-15, -21), Vector2(-14, -16.5), Vector2(-23, -16.5)], STEEL_DARK))
			ops.append(_poly([Vector2(64, -17.5), Vector2(67, -17.5), Vector2(68, -11), Vector2(63, -11)], STEEL_DARK))
		return ops)


static func _grip_part() -> Array:
	return _cached("base/grip", func() -> Array:
		return [
			_poly([Vector2(-13, 6), Vector2(-1, 6), Vector2(-6, 29), Vector2(-17, 30), Vector2(-19, 26)], POLYMER),
			_poly([Vector2(-11, 8), Vector2(-4, 8), Vector2(-7.5, 24), Vector2(-14, 25)], POLYMER_LIGHT, false),
			_line([Vector2(-1, 7), Vector2(0, 13.5), Vector2(10, 13.5), Vector2(12, 7.5)], OUTLINE, 2.2),
			_line([Vector2(3, 7.5), Vector2(4.5, 11.5)], STEEL_EDGE, 1.5),
		])


static func _front_part(id: StringName) -> Array:
	match id:
		&"extended_barrel_mk1":
			return [
				_poly([Vector2(0, -2.2), Vector2(48, -2.2), Vector2(48, 2.2), Vector2(0, 2.2)], STEEL),
				_poly([Vector2(0, -2.2), Vector2(48, -2.2), Vector2(48, -0.8), Vector2(0, -0.8)], STEEL_LIGHT, false),
				_poly([Vector2(20, -3.8), Vector2(25, -3.8), Vector2(25, 3.8), Vector2(20, 3.8)], STEEL_DARK),
				_poly([Vector2(47, -4), Vector2(58, -4), Vector2(58, 4), Vector2(47, 4)], STEEL_DARK),
				_poly([Vector2(50, -2.8), Vector2(52, -2.8), Vector2(52, 2.8), Vector2(50, 2.8)], OUTLINE, false),
				_poly([Vector2(54, -2.8), Vector2(56, -2.8), Vector2(56, 2.8), Vector2(54, 2.8)], OUTLINE, false),
			]
		&"heavy_barrel_mk1":
			var heavy: Array = [
				_poly([Vector2(0, -5.5), Vector2(34, -5.5), Vector2(36, -3.5), Vector2(36, 3.5), Vector2(34, 5.5), Vector2(0, 5.5)], STEEL_DARK),
				_poly([Vector2(1, -4.4), Vector2(33, -4.4), Vector2(34.5, -3), Vector2(1, -3)], STEEL, false),
				_poly([Vector2(35, -3), Vector2(41, -3), Vector2(41, 3), Vector2(35, 3)], STEEL),
				_poly([Vector2(40, -6), Vector2(51, -6), Vector2(51, 6), Vector2(40, 6)], STEEL_DARK),
				_poly([Vector2(43, -4.5), Vector2(45, -4.5), Vector2(45, 4.5), Vector2(43, 4.5)], OUTLINE, false),
				_poly([Vector2(47, -4.5), Vector2(49, -4.5), Vector2(49, 4.5), Vector2(47, 4.5)], OUTLINE, false),
			]
			for slot_index in range(4):
				var x: float = 8.0 + float(slot_index) * 6.5
				heavy.append(_poly([Vector2(x, -1.6), Vector2(x + 4.0, -1.6), Vector2(x + 4.0, 1.6), Vector2(x, 1.6)], Color(0.9, 0.42, 0.18), false))
			return heavy
		&"kinetic_amplifier_mk1":
			var kinetic: Array = [
				_poly([Vector2(0, -2.6), Vector2(44, -2.6), Vector2(44, 2.6), Vector2(0, 2.6)], STEEL),
				_poly([Vector2(0, -0.6), Vector2(44, -0.6), Vector2(44, 0.6), Vector2(0, 0.6)], Color(0.85, 0.5, 1.0), false),
				_poly([Vector2(43, -4.2), Vector2(49, -4.2), Vector2(51, -1.5), Vector2(51, 1.5), Vector2(49, 4.2), Vector2(43, 4.2)], STEEL_DARK),
			]
			for coil in range(3):
				var cx: float = 8.0 + float(coil) * 10.0
				kinetic.append(_poly([Vector2(cx, -6.5), Vector2(cx + 4.0, -6.5), Vector2(cx + 4.0, 6.5), Vector2(cx, 6.5)], Color(0.42, 0.22, 0.52)))
				kinetic.append(_poly([Vector2(cx + 0.8, -5.5), Vector2(cx + 3.2, -5.5), Vector2(cx + 3.2, 5.5), Vector2(cx + 0.8, 5.5)], Color(0.86, 0.52, 1.0), false))
			return kinetic
		&"lighter_barrel_mk1":
			return [
				_poly([Vector2(0, -4.2), Vector2(31, -4.2), Vector2(33, -2.2), Vector2(33, 2.2), Vector2(31, 4.2), Vector2(0, 4.2)], STEEL_MID),
				_circle(Vector2(8, 0), 2.2, STEEL_DARK, false),
				_circle(Vector2(16, 0), 2.2, STEEL_DARK, false),
				_circle(Vector2(24, 0), 2.2, STEEL_DARK, false),
				_poly([Vector2(1, -3.4), Vector2(30, -3.4), Vector2(31, -2.4), Vector2(1, -2.4)], STEEL_EDGE, false),
				_poly([Vector2(33, -1.8), Vector2(39, -1.8), Vector2(39, 1.8), Vector2(33, 1.8)], STEEL),
			]
		&"multi_barrel_mk1":
			return [
				_poly([Vector2(0, -5.6), Vector2(32, -5.6), Vector2(32, -1.4), Vector2(0, -1.4)], STEEL),
				_poly([Vector2(0, 1.4), Vector2(32, 1.4), Vector2(32, 5.6), Vector2(0, 5.6)], STEEL),
				_poly([Vector2(0, -5.6), Vector2(32, -5.6), Vector2(32, -4.2), Vector2(0, -4.2)], STEEL_LIGHT, false),
				_poly([Vector2(5, -7), Vector2(10, -7), Vector2(10, 7), Vector2(5, 7)], STEEL_DARK),
				_poly([Vector2(22, -7), Vector2(27, -7), Vector2(27, 7), Vector2(22, 7)], STEEL_DARK),
				_poly([Vector2(31, -6.2), Vector2(35, -6.2), Vector2(35, -0.8), Vector2(31, -0.8)], STEEL_DARK),
				_poly([Vector2(31, 0.8), Vector2(35, 0.8), Vector2(35, 6.2), Vector2(31, 6.2)], STEEL_DARK),
			]
		&"shotgun_mk1":
			var shotgun: Array = [
				_poly([Vector2(0, -5.5), Vector2(38, -5.5), Vector2(38, 2.0), Vector2(0, 2.0)], STEEL),
				_poly([Vector2(0, -5.5), Vector2(38, -5.5), Vector2(38, -3.8), Vector2(0, -3.8)], STEEL_LIGHT, false),
				_poly([Vector2(0, 2.5), Vector2(33, 2.5), Vector2(33, 7), Vector2(0, 7)], STEEL_DARK),
				_poly([Vector2(6, 1.5), Vector2(23, 1.5), Vector2(24, 9), Vector2(5, 9)], Color(0.36, 0.22, 0.13)),
				_circle(Vector2(35, -6.6), 1.3, Color(0.85, 0.85, 0.8), false),
			]
			for ridge in range(4):
				var rx: float = 8.0 + float(ridge) * 4.0
				shotgun.append(_line([Vector2(rx, 2.8), Vector2(rx, 8.0)], Color(0.2, 0.12, 0.07), 1.0))
			return shotgun
		&"sniper_barrel_mk1":
			return [
				_poly([Vector2(0, -2.6), Vector2(14, -2.2), Vector2(72, -1.8), Vector2(72, 1.8), Vector2(14, 2.2), Vector2(0, 2.6)], STEEL),
				_poly([Vector2(0, -2.6), Vector2(14, -2.2), Vector2(72, -1.8), Vector2(72, -0.6), Vector2(0, -1.2)], STEEL_LIGHT, false),
				_poly([Vector2(71, -4), Vector2(81, -4), Vector2(83, -2), Vector2(83, 2), Vector2(81, 4), Vector2(71, 4)], STEEL_DARK),
				_poly([Vector2(74, -2.8), Vector2(76, -2.8), Vector2(76, 2.8), Vector2(74, 2.8)], OUTLINE, false),
				_poly([Vector2(77.5, -2.8), Vector2(79.5, -2.8), Vector2(79.5, 2.8), Vector2(77.5, 2.8)], OUTLINE, false),
				_line([Vector2(6, 3), Vector2(36, 6.5)], STEEL_DARK, 1.8),
				_line([Vector2(6, 4.4), Vector2(34, 8.5)], STEEL_DARK, 1.8),
				_poly([Vector2(4, 1.5), Vector2(9, 1.5), Vector2(9, 5), Vector2(4, 5)], STEEL_DARK),
			]
	return [
		_poly([Vector2(0, -2.2), Vector2(18, -2.2), Vector2(18, 2.2), Vector2(0, 2.2)], STEEL),
		_poly([Vector2(0, -2.2), Vector2(18, -2.2), Vector2(18, -0.9), Vector2(0, -0.9)], STEEL_LIGHT, false),
		_poly([Vector2(17, -3.6), Vector2(26, -3.6), Vector2(26, 3.6), Vector2(17, 3.6)], STEEL_DARK),
		_poly([Vector2(19.5, -2.4), Vector2(23.5, -2.4), Vector2(23.5, -0.8), Vector2(19.5, -0.8)], OUTLINE, false),
		_poly([Vector2(19.5, 0.8), Vector2(23.5, 0.8), Vector2(23.5, 2.4), Vector2(19.5, 2.4)], OUTLINE, false),
	]


static func _top_part(id: StringName) -> Array:
	match id:
		&"standard_scope_mk1":
			return [
				_poly([Vector2(-14, 0), Vector2(-9, 0), Vector2(-9, -6), Vector2(-14, -6)], STEEL_DARK),
				_poly([Vector2(9, 0), Vector2(14, 0), Vector2(14, -6), Vector2(9, -6)], STEEL_DARK),
				_poly([Vector2(-23, -12.5), Vector2(22, -12.5), Vector2(22, -5.5), Vector2(-23, -5.5)], STEEL),
				_poly([Vector2(21, -15), Vector2(31, -16), Vector2(31, -2), Vector2(21, -3)], STEEL_DARK),
				_poly([Vector2(-30, -13), Vector2(-22, -12.5), Vector2(-22, -5.5), Vector2(-30, -5)], STEEL_DARK),
				_poly([Vector2(-1, -16), Vector2(5, -16), Vector2(5, -12.5), Vector2(-1, -12.5)], STEEL_MID),
				_poly([Vector2(-22, -11.4), Vector2(21, -11.4), Vector2(21, -9.6), Vector2(-22, -9.6)], STEEL_LIGHT, false),
				_poly([Vector2(31, -15.2), Vector2(33, -14.6), Vector2(33, -3.4), Vector2(31, -2.8)], GLASS),
				_poly([Vector2(31.2, -13.5), Vector2(32.6, -13.2), Vector2(32.6, -10.5), Vector2(31.2, -10.6)], Color(0.95, 1.0, 1.0), false),
			]
		&"laser_scope_mk1":
			return [
				_poly([Vector2(-8, 0), Vector2(-4, 0), Vector2(-4, -3), Vector2(-8, -3)], STEEL_DARK),
				_poly([Vector2(6, 0), Vector2(10, 0), Vector2(10, -3), Vector2(6, -3)], STEEL_DARK),
				_poly([Vector2(-12, -9), Vector2(15, -9), Vector2(18, -6.5), Vector2(18, -2.5), Vector2(-12, -2.5)], STEEL_DARK),
				_poly([Vector2(-11, -8), Vector2(14.5, -8), Vector2(16, -6.8), Vector2(-11, -6.8)], STEEL_MID, false),
				_poly([Vector2(17.5, -6.5), Vector2(21, -6.5), Vector2(21, -2.5), Vector2(17.5, -2.5)], Color(0.9, 0.12, 0.08)),
				_circle(Vector2(-5, -5.8), 1.4, Color(1.0, 0.25, 0.18), false),
				_poly([Vector2(1, -12), Vector2(6, -12), Vector2(6, -9), Vector2(1, -9)], STEEL_MID),
			]
		&"reload_improver_mk1":
			var loader: Array = [
				_poly([Vector2(-13, 0), Vector2(13, 0), Vector2(11, -4), Vector2(-11, -4)], STEEL_DARK),
				_poly([Vector2(-18, -4), Vector2(14, -4), Vector2(18, -7), Vector2(18, -11), Vector2(14, -13), Vector2(-18, -13)], STEEL),
				_poly([Vector2(-17, -12), Vector2(14, -12), Vector2(16.5, -10.6), Vector2(-17, -10.6)], STEEL_LIGHT, false),
				_poly([Vector2(-14, -9.6), Vector2(8, -9.6), Vector2(8, -5.6), Vector2(-14, -5.6)], OUTLINE, false),
				_line([Vector2(-13, -7.6), Vector2(-11, -9.2), Vector2(-9, -6), Vector2(-7, -9.2), Vector2(-5, -6), Vector2(-3, -9.2), Vector2(-1, -6), Vector2(1, -9.2), Vector2(3, -6), Vector2(5, -9.2), Vector2(7, -7.6)], GOLD, 1.3),
				_poly([Vector2(10, -16), Vector2(14, -16), Vector2(14, -12.5), Vector2(10, -12.5)], GOLD),
				_poly([Vector2(-16, -16), Vector2(-12, -16), Vector2(-12, -12.5), Vector2(-16, -12.5)], STEEL_DARK),
			]
			return loader
		&"ground_hover_mk1":
			return [
				_poly([Vector2(-9, 0), Vector2(11, 0), Vector2(9, -4), Vector2(-7, -4)], STEEL_DARK),
				_line([Vector2(-10, -11), Vector2(-14, -21)], STEEL_DARK, 1.6),
				_circle(Vector2(-14.3, -21.6), 1.9, Color(0.4, 1.0, 0.85)),
				_poly([Vector2(-17, -4), Vector2(15, -4), Vector2(20, -6.5), Vector2(20, -10), Vector2(15, -13), Vector2(-14, -13), Vector2(-18, -9)], STEEL),
				_poly([Vector2(-15, -12), Vector2(14.5, -12), Vector2(17.5, -10.5), Vector2(-16.4, -10.5)], STEEL_LIGHT, false),
				_poly([Vector2(-14, -6.4), Vector2(14, -6.4), Vector2(14, -5), Vector2(-14, -5)], Color(0.38, 1.0, 0.84), false),
				_poly([Vector2(19, -10), Vector2(22.5, -9.4), Vector2(22.5, -7), Vector2(19, -6.4)], Color(0.38, 1.0, 0.84)),
				_circle(Vector2(-6, -8.6), 2.0, STEEL_DARK, false),
				_circle(Vector2(1, -8.6), 2.0, STEEL_DARK, false),
			]
	return []


static func _ammo_part(id: StringName) -> Array:
	if id == &"grenade_launcher":
		return [
			_poly([Vector2(-6, 0), Vector2(30, 0), Vector2(30, 8.5), Vector2(-6, 8.5)], Color(0.24, 0.27, 0.2)),
			_poly([Vector2(-6, 0.8), Vector2(30, 0.8), Vector2(30, 2.4), Vector2(-6, 2.4)], Color(0.36, 0.4, 0.3), false),
			_poly([Vector2(-12, 2), Vector2(-5, 2), Vector2(-6, 13), Vector2(-12, 13)], POLYMER),
			_poly([Vector2(30, -0.5), Vector2(34, -0.5), Vector2(34, 9), Vector2(30, 9)], STEEL_DARK),
			_circle(Vector2(34.5, 4.25), 3.4, Color(0.46, 0.62, 0.2), false),
			_circle(Vector2(35.5, 3.4), 1.2, Color(0.8, 0.95, 0.5), false),
		]
	if id == &"big_bullets_mk1":
		var drum: Array = [
			_poly([Vector2(-6, 0), Vector2(6, 0), Vector2(6, 5), Vector2(-6, 5)], STEEL_DARK),
			_circle(Vector2(1, 16), 13.0, STEEL),
			_circle(Vector2(1, 16), 9.5, STEEL_DARK, false),
			_circle(Vector2(1, 16), 3.2, STEEL_MID, false),
		]
		for round_index in range(8):
			var angle: float = TAU * float(round_index) / 8.0 + 0.2
			drum.append(_circle(Vector2(1, 16) + Vector2.from_angle(angle) * 6.4, 2.1, Color.WHITE, false, &"ammo"))
		drum.append(_ring(Vector2(1, 16), 11.4, Color.WHITE, 1.0, &"ammo_light"))
		return drum
	var body_color: Color = STEEL
	match id:
		&"freeze_rounds_mk1":
			body_color = Color(0.3, 0.38, 0.44)
		&"bouncy_bullets_mk1":
			body_color = Color(0.26, 0.31, 0.22)
		&"drill_bullets_mk1":
			body_color = STEEL_MID
	var mag: Array = [
		_poly([Vector2(-7, 0), Vector2(7, 0), Vector2(10, 22), Vector2(-2, 24)], body_color),
		_poly([Vector2(-3.5, 22.5), Vector2(10.5, 20.5), Vector2(11.5, 25), Vector2(-2.5, 27)], STEEL_DARK),
		_poly([Vector2(-6, 1.2), Vector2(-3.4, 1.2), Vector2(-0.4, 22), Vector2(-2.6, 22.4)], body_color.lightened(0.18), false),
	]
	if id == &"":
		mag.append(_poly([Vector2(0.5, 4), Vector2(4.5, 4), Vector2(6, 15), Vector2(2, 15.5)], STEEL_DARK, false))
		for round_index in range(3):
			var y: float = 5.2 + float(round_index) * 3.4
			mag.append(_circle(Vector2(2.6 + y * 0.12, y), 1.15, BRASS, false))
		return mag
	mag.append(_poly([Vector2(0.2, 3.5), Vector2(5, 3.5), Vector2(6.6, 17), Vector2(1.8, 17.6)], Color.WHITE, false, &"ammo_dark"))
	mag.append(_poly([Vector2(0.6, 9), Vector2(5.6, 9), Vector2(6.5, 16.6), Vector2(2, 17.2)], Color.WHITE, false, &"ammo"))
	mag.append(_poly([Vector2(1.0, 9.4), Vector2(2.4, 9.4), Vector2(3.0, 16.4), Vector2(2.2, 16.6)], Color.WHITE, false, &"ammo_light"))
	match id:
		&"poison_rounds_mk1":
			mag.append(_circle(Vector2(-1.5, 19.0), 2.6, Color(0.06, 0.08, 0.05), false))
			mag.append(_circle(Vector2(-1.5, 19.0), 1.6, Color(0.5, 1.0, 0.4), false))
			mag.append(_circle(Vector2(3.5, 6.5), 0.9, Color(0.8, 1.0, 0.7), false))
		&"freeze_rounds_mk1":
			mag.append(_line([Vector2(-7, 0.5), Vector2(-5, 4), Vector2(-7.5, 7), Vector2(-5.2, 10)], Color(0.85, 0.97, 1.0), 1.1))
			mag.append(_line([Vector2(7.5, 1), Vector2(9.5, 5), Vector2(8, 8)], Color(0.85, 0.97, 1.0), 1.1))
			mag.append(_line([Vector2(-1.5, 16.5), Vector2(-1.5, 21.5)], Color(0.85, 0.97, 1.0), 1.0))
			mag.append(_line([Vector2(-3.7, 19), Vector2(0.7, 19)], Color(0.85, 0.97, 1.0), 1.0))
		&"shocking_rounds_mk1":
			mag.append(_line([Vector2(-1, 15), Vector2(-3, 19), Vector2(-0.6, 19), Vector2(-2.6, 23)], Color(1.0, 0.92, 0.3), 1.2))
		&"explosive_bullet_mk1":
			for stripe in range(3):
				var sy: float = 18.5 + float(stripe) * 0.0
				var sx: float = -4.0 + float(stripe) * 4.0
				mag.append(_poly([Vector2(sx, sy), Vector2(sx + 2.0, sy), Vector2(sx + 0.8, sy + 3.5), Vector2(sx - 1.2, sy + 3.5)], Color(1.0, 0.8, 0.15), false))
		&"grenades_mk1":
			mag.append(_circle(Vector2(-1.5, 19.0), 2.2, Color(0.46, 0.62, 0.2), false))
		&"drill_bullets_mk1":
			mag.append(_poly([Vector2(-3.5, 16), Vector2(0.5, 18), Vector2(-3.5, 20)], STEEL_EDGE, false))
			mag.append(_line([Vector2(-3, 16.8), Vector2(-1.5, 19.2)], STEEL_DARK, 0.7))
		&"bouncy_bullets_mk1":
			mag.append(_ring(Vector2(-1.5, 19.0), 2.3, Color(0.8, 1.0, 0.45), 1.1))
	return mag


# --- Shape helpers ---------------------------------------------------------------------------------------

static func _cached(base_key: String, builder: Callable) -> Array:
	var key: String = "%s/%.1f" % [base_key, _outline_width]
	if _part_cache.has(key):
		return _part_cache[key]
	var ops: Array = builder.call()
	_prepare(ops)
	_part_cache[key] = ops
	return ops


static func _prepare(ops: Array) -> void:
	for op in ops:
		if op["t"] == "poly" and op.get("o", false):
			op["outline"] = Geometry2D.offset_polygon(op["pts"], _outline_width, Geometry2D.JOIN_ROUND)
		op["ow"] = _outline_width


static func _poly(points: Array, color: Color, outlined: bool = true, role: StringName = &"") -> Dictionary:
	return {"t": "poly", "pts": PackedVector2Array(points), "c": color, "o": outlined, "role": role}


static func _circle(center: Vector2, radius: float, color: Color, outlined: bool = true, role: StringName = &"") -> Dictionary:
	return {"t": "circle", "p": center, "r": radius, "c": color, "o": outlined, "role": role}


static func _ring(center: Vector2, radius: float, color: Color, width: float, role: StringName = &"") -> Dictionary:
	return {"t": "ring", "p": center, "r": radius, "c": color, "w": width, "role": role}


static func _line(points: Array, color: Color, width: float) -> Dictionary:
	return {"t": "line", "pts": PackedVector2Array(points), "c": color, "w": width}
