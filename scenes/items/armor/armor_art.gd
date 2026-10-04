class_name ArmorArt
extends RefCounted

## Procedural vector art for every shield, vest and pair of boots, drawn into any CanvasItem. It speaks the
## same language as WeaponArt: steel and polymer bodies with a dark outline, light from above, gold diamonds
## for the mark, and one effect colour per family (ice for Frosty, green for Healing, ...) on a core, stripe
## or glow so a piece reads at a glance. Starter pieces carry the owner's team colour instead, like the
## stock carbine. MK II and MK III add visible parts (trim, plates, shards, fins) on top of the pips.
## Pieces are authored at two units per world pixel: shields and vests sit centred on the grip / body
## centre, boots on the ankle with the toe pointing to +x. A piece is a list of layers; each layer draws an
## outline pass and then its fills, so shapes inside one layer merge into a single outlined silhouette and
## a later layer (an emblem, a pouch) gets an outline of its own.

## World pixels per art unit (ArmorArtView applies it; icons fit the art to their rect instead).
const WORLD_SCALE: float = 0.5
const OUTLINE_WIDTH: float = 1.7
const ICON_OUTLINE_PX: float = 2.2

const OUTLINE: Color = WeaponArt.OUTLINE
const STEEL_DARK: Color = WeaponArt.STEEL_DARK
const STEEL: Color = WeaponArt.STEEL
const STEEL_MID: Color = WeaponArt.STEEL_MID
const STEEL_LIGHT: Color = WeaponArt.STEEL_LIGHT
const STEEL_EDGE: Color = WeaponArt.STEEL_EDGE
const POLYMER: Color = WeaponArt.POLYMER
const POLYMER_LIGHT: Color = WeaponArt.POLYMER_LIGHT
const GLASS: Color = WeaponArt.GLASS
const GOLD: Color = WeaponArt.GOLD
const JACKET: Color = Color(0.3, 0.34, 0.39)
const FUR: Color = Color(0.86, 0.88, 0.9)
const FUR_SHADE: Color = Color(0.62, 0.66, 0.71)
const DEFAULT_TEAM: Color = Color(0.32, 0.67, 1.0)

## The effect colour of each family. Starter pieces have none and use the team colour.
const ACCENTS: Dictionary = {
	&"frosty_shield": Color(0.5, 0.86, 1.0),
	&"healing_shield": Color(0.42, 1.0, 0.58),
	&"pull_shield": Color(0.78, 0.5, 1.0),
	&"tactical_reload_shield": Color(1.0, 0.74, 0.3),
	&"light_kevlar_vest": Color(0.88, 0.84, 0.6),
	&"arctic_jacket": Color(1.0, 0.56, 0.22),
	&"delayed_armor": Color(1.0, 0.45, 0.76),
	&"reflective_armor": Color(0.72, 0.95, 1.0),
	&"stationary_armor": Color(1.0, 0.82, 0.25),
	&"jump_boots": Color(0.74, 1.0, 0.34),
	&"adrenaline_boots": Color(1.0, 0.32, 0.34),
	&"chasing_boots": Color(1.0, 0.54, 0.18),
	&"escape_boots": Color(0.46, 0.8, 1.0),
}
const STOCK_PIECES: Dictionary = {
	ArmorItemData.CATEGORY_SHIELD: &"training_shield",
	ArmorItemData.CATEGORY_VEST: &"scout_vest",
	ArmorItemData.CATEGORY_BOOTS: &"light_boots",
}
const KNOWN_PIECES: Array[StringName] = [
	&"training_shield", &"frosty_shield", &"healing_shield", &"pull_shield", &"tactical_reload_shield",
	&"scout_vest", &"light_kevlar_vest", &"arctic_jacket", &"delayed_armor", &"reflective_armor", &"stationary_armor",
	&"light_boots", &"jump_boots", &"adrenaline_boots", &"chasing_boots", &"escape_boots",
]
## Where the effect glows (piece space, radius) for animated views.
const GLOW_POINTS: Dictionary = {
	&"frosty_shield": [Vector2(0, -1), 10.0],
	&"healing_shield": [Vector2(0, -2), 10.0],
	&"pull_shield": [Vector2(0, 0), 10.0],
	&"tactical_reload_shield": [Vector2(0, 2), 9.0],
	&"arctic_jacket": [Vector2(0, 14), 8.0],
	&"delayed_armor": [Vector2(0, 16), 10.0],
	&"reflective_armor": [Vector2(0, 14), 8.0],
	&"stationary_armor": [Vector2(0, 13), 7.0],
	&"jump_boots": [Vector2(-5.2, -5.2), 3.5],
	&"adrenaline_boots": [Vector2(-8, -5.5), 3.5],
	&"chasing_boots": [Vector2(-1, 0), 4.0],
	&"escape_boots": [Vector2(-10, -5), 4.5],
}

static var _piece_cache: Dictionary = {}
static var _tint: Color = Color.WHITE
static var _flash: float = 0.0
static var _desaturate: float = 0.0
static var _accent: Color = DEFAULT_TEAM
static var _team: Color = DEFAULT_TEAM
static var _outline_width: float = OUTLINE_WIDTH


## The design an item is drawn with; unknown items fall back to their category's starter piece.
static func art_id_for(item: ArmorItemData) -> StringName:
	if item == null:
		return &""
	var art_id: StringName = item.get_art_id()
	if KNOWN_PIECES.has(art_id):
		return art_id
	return STOCK_PIECES.get(item.category, &"scout_vest")


static func accent_color(art_id: StringName, team: Color = DEFAULT_TEAM) -> Color:
	return ACCENTS.get(art_id, team)


# --- Drawing ---------------------------------------------------------------------------------------------

## Draws one piece. style keys (all optional): team: Color, alpha, flash, desaturate: float, outline: float
## (in art units; small renders want a heavier one), pips: bool (default true).
static func draw_piece(canvas: CanvasItem, xform: Transform2D, art_id: StringName, mark: int, style: Dictionary = {}) -> void:
	_outline_width = float(style.get("outline", OUTLINE_WIDTH))
	_team = style.get("team", DEFAULT_TEAM)
	_accent = accent_color(art_id, _team)
	_begin(float(style.get("alpha", 1.0)), float(style.get("flash", 0.0)), float(style.get("desaturate", 0.0)))
	canvas.draw_set_transform_matrix(xform)
	_draw_layers(canvas, _piece(art_id, mark))
	if style.get("pips", true):
		_draw_mark_pips(canvas, art_id, mark)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_begin(1.0, 0.0, 0.0)
	_outline_width = OUTLINE_WIDTH


## Draws a piece centred and fitted into rect (inventory tiles, socket chips, the inspector). The outline
## keeps the same on-screen weight whatever the piece's size.
static func draw_icon(canvas: CanvasItem, rect: Rect2, art_id: StringName, mark: int, style: Dictionary = {}) -> void:
	if art_id == &"" or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var bounds: Rect2 = piece_bounds(art_id, mark)
	var fit: float = minf(rect.size.x / maxf(bounds.size.x, 1.0), rect.size.y / maxf(bounds.size.y, 1.0))
	fit = minf(fit, float(style.get("max_scale", 4.0)))
	var icon_style: Dictionary = style.duplicate()
	var outline_px: float = float(style.get("outline_px", ICON_OUTLINE_PX))
	icon_style["outline"] = clampf(snappedf(outline_px / fit, 0.1), 0.6, 4.0)
	var xform: Transform2D = Transform2D(0.0, Vector2.ONE * fit, 0.0, rect.get_center()) * Transform2D(0.0, -bounds.get_center())
	draw_piece(canvas, xform, art_id, mark, icon_style)


## Soft pulsing glow over the effect core, for views that redraw every frame (the operator preview).
static func draw_fx(canvas: CanvasItem, xform: Transform2D, art_id: StringName, mark: int, time: float, intensity: float = 1.0) -> void:
	if not GLOW_POINTS.has(art_id):
		return
	var glow: Array = GLOW_POINTS[art_id]
	var color: Color = accent_color(art_id)
	var pulse: float = 0.6 + 0.4 * sin(time * 2.6)
	var strength: float = (0.07 + 0.035 * float(mark)) * pulse * intensity
	canvas.draw_set_transform_matrix(xform)
	for ring in range(3):
		var radius: float = float(glow[1]) * (1.0 - float(ring) * 0.3)
		canvas.draw_circle(glow[0], radius, Color(color.r, color.g, color.b, strength), true, -1.0, true)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Bounds of a piece in art space, outline included.
static func piece_bounds(art_id: StringName, mark: int) -> Rect2:
	var has: bool = false
	var rect: Rect2 = Rect2()
	for layer in _piece(art_id, mark):
		for op in layer:
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
	return rect.grow(_outline_width)


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


static func _draw_layers(canvas: CanvasItem, layers: Array) -> void:
	for layer in layers:
		for op in layer:
			if op.get("o", false):
				if op["t"] == "poly":
					for outline in op["outline"]:
						canvas.draw_colored_polygon(outline, _c(OUTLINE))
				elif op["t"] == "circle":
					canvas.draw_circle(op["p"], float(op["r"]) + float(op["ow"]), _c(OUTLINE), true, -1.0, true)
		for op in layer:
			match op["t"]:
				"poly":
					canvas.draw_colored_polygon(op["pts"], _c(_role_color(op)))
				"circle":
					canvas.draw_circle(op["p"], op["r"], _c(_role_color(op)), true, -1.0, true)
				"ring":
					canvas.draw_arc(op["p"], op["r"], 0.0, TAU, 24, _c(_role_color(op)), op["w"], true)
				"line":
					canvas.draw_polyline(op["pts"], _c(_role_color(op)), op["w"], true)


static func _role_color(op: Dictionary) -> Color:
	match op.get("role", &""):
		&"accent":
			return _accent
		&"accent_dark":
			return _accent.darkened(0.5)
		&"accent_light":
			return _accent.lightened(0.5)
		&"team":
			return _team
	return op["c"]


static func _draw_mark_pips(canvas: CanvasItem, art_id: StringName, mark: int) -> void:
	if mark <= 1:
		return
	var anchor: Vector2 = _pip_anchor(art_id) - Vector2(float(mark - 1) * 1.7, 0.0)
	for index in range(mark):
		var center: Vector2 = anchor + Vector2(float(index) * 3.4, 0.0)
		var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -1.4), center + Vector2(1.4, 0), center + Vector2(0, 1.4), center + Vector2(-1.4, 0)])
		canvas.draw_colored_polygon(diamond, _c(GOLD))


static func _pip_anchor(art_id: StringName) -> Vector2:
	match art_id:
		&"frosty_shield":
			return Vector2(0, 17.5)
		&"healing_shield":
			return Vector2(0, 19.5)
		&"pull_shield":
			return Vector2(0, 14.5)
		&"tactical_reload_shield":
			return Vector2(0, 17.5)
		&"stationary_armor":
			return Vector2(0, 31.5)
		&"light_kevlar_vest", &"arctic_jacket", &"delayed_armor", &"reflective_armor":
			return Vector2(0, 28.5)
		&"jump_boots":
			return Vector2(1.5, 8.0)
	return Vector2(0.5, 6.5)


static func _piece(art_id: StringName, mark: int) -> Array:
	var key: String = "%s/%d/%.1f" % [art_id, mark, _outline_width]
	if _piece_cache.has(key):
		return _piece_cache[key]
	var layers: Array = []
	match art_id:
		&"training_shield":
			layers = _training_shield()
		&"frosty_shield":
			layers = _frosty_shield(mark)
		&"healing_shield":
			layers = _healing_shield(mark)
		&"pull_shield":
			layers = _pull_shield(mark)
		&"tactical_reload_shield":
			layers = _tactical_reload_shield(mark)
		&"scout_vest":
			layers = _scout_vest()
		&"light_kevlar_vest":
			layers = _light_kevlar_vest(mark)
		&"arctic_jacket":
			layers = _arctic_jacket(mark)
		&"delayed_armor":
			layers = _delayed_armor(mark)
		&"reflective_armor":
			layers = _reflective_armor(mark)
		&"stationary_armor":
			layers = _stationary_armor(mark)
		&"light_boots":
			layers = _light_boots()
		&"jump_boots":
			layers = _jump_boots(mark)
		&"adrenaline_boots":
			layers = _adrenaline_boots(mark)
		&"chasing_boots":
			layers = _chasing_boots(mark)
		&"escape_boots":
			layers = _escape_boots(mark)
	for layer in layers:
		_prepare(layer)
	_piece_cache[key] = layers
	return layers


static func _prepare(ops: Array) -> void:
	for op in ops:
		if op["t"] == "poly" and op.get("o", false):
			op["outline"] = Geometry2D.offset_polygon(op["pts"], _outline_width, Geometry2D.JOIN_ROUND)
		op["ow"] = _outline_width


static func _poly(points: Variant, color: Color, outlined: bool = true, role: StringName = &"") -> Dictionary:
	return {"t": "poly", "pts": PackedVector2Array(points), "c": color, "o": outlined, "role": role}


static func _circle(center: Vector2, radius: float, color: Color, outlined: bool = true, role: StringName = &"") -> Dictionary:
	return {"t": "circle", "p": center, "r": radius, "c": color, "o": outlined, "role": role}


static func _ring(center: Vector2, radius: float, color: Color, width: float, role: StringName = &"") -> Dictionary:
	return {"t": "ring", "p": center, "r": radius, "c": color, "w": width, "role": role}


static func _line(points: Variant, color: Color, width: float, role: StringName = &"") -> Dictionary:
	return {"t": "line", "pts": PackedVector2Array(points), "c": color, "w": width, "role": role}


## A symmetric outline from its right half, listed top to bottom; points on the centre line are not doubled.
static func _sym(half: Array) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array(half)
	for index in range(half.size() - 1, -1, -1):
		var point: Vector2 = half[index]
		if absf(point.x) > 0.001:
			points.append(Vector2(-point.x, point.y))
	return points


static func _mirror(points: Array) -> Array:
	var mirrored: Array = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		mirrored.append(Vector2(-point.x, point.y))
	return mirrored


static func _arc(center: Vector2, radius: Vector2, from_degrees: float, to_degrees: float, steps: int) -> Array:
	var points: Array = []
	for index in range(steps + 1):
		var angle: float = deg_to_rad(lerpf(from_degrees, to_degrees, float(index) / float(steps)))
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


static func _ellipse(radius: Vector2, steps: int = 32, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var points: Array = _arc(center, radius, 0.0, 360.0, steps)
	points.pop_back()
	return PackedVector2Array(points)


## The lower part of the round body below top_y: what a vest wraps around. sag curves the top edge down in
## the middle so it reads as wrapping the ball; bumps adds puffy scallops.
static func _band(top_y: float, radius: float, sag: float = 0.0, steps: int = 28, bumps: int = 0, bump: float = 0.0) -> PackedVector2Array:
	var start: float = asin(clampf(top_y / radius, -1.0, 1.0))
	var finish: float = PI - start
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var angle: float = lerpf(start, finish, t)
		var r: float = radius
		if bumps > 0:
			r += bump * absf(sin(t * PI * float(bumps)))
		points.append(Vector2(cos(angle), sin(angle)) * r)
	if sag > 0.0:
		var half: float = cos(start) * radius
		for index in range(1, 8):
			var x: float = lerpf(-half, half, float(index) / 8.0)
			points.append(Vector2(x, top_y + sag * (1.0 - pow(x / half, 2.0))))
	return points


## Darkens the bottom of a vest so it reads round, like the light on the gun comes from above.
static func _shade(mask: PackedVector2Array) -> Array:
	var ops: Array = []
	for piece in Geometry2D.clip_polygons(mask, _ellipse(Vector2(BODY_RADIUS - 1.0, BODY_RADIUS - 1.0), 32, Vector2(0, -6))):
		ops.append(_poly(piece, Color(0.0, 0.0, 0.0, 0.26), false))
	return ops


static func _rect(from: Vector2, to: Vector2) -> PackedVector2Array:
	return PackedVector2Array([from, Vector2(to.x, from.y), to, Vector2(from.x, to.y)])


## Fills of shape cut to mask (stripes and panels that follow a vest's curve).
static func _clipped(shape: PackedVector2Array, mask: PackedVector2Array, color: Color, role: StringName = &"") -> Array:
	var ops: Array = []
	for piece in Geometry2D.intersect_polygons(shape, mask):
		ops.append(_poly(piece, color, false, role))
	return ops


## Half-width of the body band at height y, inset from the edge.
static func _band_half_width(y: float, radius: float, inset: float) -> float:
	return sqrt(maxf(radius * radius - y * y, 0.0)) - inset


# --- Shields (centred on the grip, about 29 x 54) -----------------------------------------------------------

static func _training_shield() -> Array:
	var frame: PackedVector2Array = _sym([Vector2(0, -26), Vector2(12, -26), Vector2(14.5, -23.5), Vector2(14.5, -4), Vector2(11.5, 9), Vector2(6, 19), Vector2(0, 25.5)])
	var face: PackedVector2Array = _sym([Vector2(0, -23), Vector2(11, -23), Vector2(12, -21.5), Vector2(12, -4.5), Vector2(9.3, 7.5), Vector2(4.5, 16), Vector2(0, 21.5)])
	var body: Array = [
		_poly(frame, STEEL_DARK),
		_poly(face, POLYMER, false),
		_poly(_sym([Vector2(0, -23), Vector2(11, -23), Vector2(12, -21.5), Vector2(12, -19.5), Vector2(0, -19.5)]), POLYMER_LIGHT, false),
		_poly([Vector2(-1.6, -19.5), Vector2(1.6, -19.5), Vector2(1.6, 13), Vector2(0, 16.5), Vector2(-1.6, 13)], Color.WHITE, false, &"team"),
	]
	for rivet in [Vector2(8.5, -15), Vector2(-8.5, -15), Vector2(8.5, 0), Vector2(-8.5, 0), Vector2(5, 11), Vector2(-5, 11)]:
		body.append(_circle(rivet, 1.2, STEEL_EDGE, false))
	var boss: Array = [
		_circle(Vector2(0, -4), 3.4, STEEL_MID),
		_circle(Vector2(-0.6, -4.6), 1.6, STEEL_EDGE, false),
	]
	return [body, boss]


static func _frosty_shield(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var shards: Array = [
			_poly([Vector2(12.5, -11), Vector2(19.5, -17), Vector2(17, -3), Vector2(13, 1)], Color.WHITE, true, &"accent"),
			_poly(_mirror([Vector2(12.5, -11), Vector2(19.5, -17), Vector2(17, -3), Vector2(13, 1)]), Color.WHITE, true, &"accent_light"),
		]
		if mark >= 3:
			shards.append(_poly([Vector2(-3.5, -23), Vector2(0, -35), Vector2(3.5, -23)], Color.WHITE, true, &"accent_light"))
			shards.append(_poly([Vector2(4, -22), Vector2(10.5, -30), Vector2(9, -18)], Color.WHITE, true, &"accent"))
			shards.append(_poly(_mirror([Vector2(4, -22), Vector2(10.5, -30), Vector2(9, -18)]), Color.WHITE, true, &"accent_light"))
			shards.append(_poly([Vector2(8, 15), Vector2(15, 20), Vector2(5, 21)], Color.WHITE, true, &"accent"))
			shards.append(_poly(_mirror([Vector2(8, 15), Vector2(15, 20), Vector2(5, 21)]), Color.WHITE, true, &"accent_light"))
		layers.append(shards)
	var frame: PackedVector2Array = _sym([Vector2(0, -27), Vector2(9.5, -21), Vector2(14, -8), Vector2(14, 6), Vector2(9, 18.5), Vector2(0, 27)])
	var right_facet: Array = [Vector2(0, -23.5), Vector2(7.5, -18.5), Vector2(11.2, -7.5), Vector2(11.2, 5), Vector2(7, 15.5), Vector2(0, 22.5)]
	var body: Array = [
		_poly(frame, STEEL_DARK),
		_poly(right_facet, STEEL, false),
		_poly(_mirror(right_facet), STEEL_MID, false),
		_line([Vector2(-11.2, -7.5), Vector2(-7.5, -18.5), Vector2(0, -23.5), Vector2(7.5, -18.5)], STEEL_LIGHT, 1.2),
		_line([Vector2(-7, 15.5), Vector2(0, 22.5), Vector2(7, 15.5)], Color.WHITE, 1.1, &"accent_dark"),
		_line([Vector2(-8.5, 6), Vector2(-5.5, 9)], Color.WHITE, 1.0, &"accent_dark"),
		_line([Vector2(8.5, 6), Vector2(5.5, 9)], Color.WHITE, 1.0, &"accent_dark"),
	]
	if mark >= 2:
		body.append(_line([Vector2(-12.6, -8.2), Vector2(-8.6, -19.8), Vector2(0, -25.4), Vector2(8.6, -19.8), Vector2(12.6, -8.2)], STEEL_EDGE, 0.9))
	layers.append(body)
	var size: float = 1.0 + 0.1 * float(mark - 1)
	layers.append([
		_poly([Vector2(0, -15) * size, Vector2(6, -3) * size, Vector2(0, 13) * size, Vector2(-6, -3) * size], Color.WHITE, true, &"accent_dark"),
		_poly([Vector2(0, -13) * size, Vector2(-4.6, -3) * size, Vector2(0, 10.5) * size], Color.WHITE, false, &"accent_light"),
		_poly([Vector2(0, -13) * size, Vector2(4.6, -3) * size, Vector2(0, 10.5) * size], Color.WHITE, false, &"accent"),
		_poly([Vector2(-0.2, -9), Vector2(1.2, -4), Vector2(-0.2, 1), Vector2(-1.6, -4)], Color(0.95, 1.0, 1.0), false),
	])
	return layers


static func _healing_shield(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var canisters: Array = [
			_poly(_rect(Vector2(12.5, -7), Vector2(17.5, 9)), STEEL_MID),
			_poly(_rect(Vector2(-17.5, -7), Vector2(-12.5, 9)), STEEL_MID),
			_poly(_rect(Vector2(14, -4.5), Vector2(16, 6.5)), Color.WHITE, false, &"accent"),
			_poly(_rect(Vector2(-16, -4.5), Vector2(-14, 6.5)), Color.WHITE, false, &"accent"),
			_poly(_rect(Vector2(14, -4.5), Vector2(14.8, 6.5)), Color.WHITE, false, &"accent_light"),
			_poly(_rect(Vector2(-16, -4.5), Vector2(-15.2, 6.5)), Color.WHITE, false, &"accent_light"),
		]
		if mark >= 3:
			canisters.append(_circle(Vector2(0, -26.5), 4.8, STEEL_DARK))
			canisters.append(_circle(Vector2(0, -27), 2.6, Color.WHITE, false, &"accent_light"))
		layers.append(canisters)
	var frame_half: Array = _arc(Vector2(0, -12), Vector2(14.5, 14.5), -90.0, 0.0, 8)
	frame_half.append_array([Vector2(14.5, 10), Vector2(9.5, 20), Vector2(0, 26)])
	var face_half: Array = _arc(Vector2(0, -12), Vector2(12, 12), -90.0, 0.0, 8)
	face_half.append_array([Vector2(12, 9.5), Vector2(7.8, 18), Vector2(0, 23)])
	var body: Array = [
		_poly(_sym(frame_half), STEEL_DARK),
		_poly(_sym(face_half), STEEL, false),
		_line(_arc(Vector2(0, -12), Vector2(10.6, 10.6), -165.0, -60.0, 8), STEEL_LIGHT, 1.4),
		_line([Vector2(-10.2, 12), Vector2(-6.4, 18.6), Vector2(0, 21.4)], STEEL_MID, 1.0),
	]
	if mark >= 2:
		body.append(_line(_arc(Vector2(0, -12), Vector2(13.4, 13.4), -175.0, -5.0, 10), STEEL_EDGE, 0.9))
	layers.append(body)
	layers.append([
		_poly(_rect(Vector2(-2.8, -11), Vector2(2.8, 7)), Color.WHITE, true, &"accent"),
		_poly(_rect(Vector2(-8.5, -4.8), Vector2(8.5, 0.8)), Color.WHITE, true, &"accent"),
		_poly(_rect(Vector2(-2.8, -11), Vector2(-1.0, 7)), Color.WHITE, false, &"accent_light"),
		_poly(_rect(Vector2(-8.5, -4.8), Vector2(8.5, -3.2)), Color.WHITE, false, &"accent_light"),
		_circle(Vector2(0, 13.5), 2.1, Color.WHITE, true, &"accent"),
	])
	return layers


static func _pull_shield(mark: int) -> Array:
	var layers: Array = []
	if mark >= 3:
		var horns: Array = []
		for side in [-1.0, 1.0]:
			horns.append(_poly(_rect(Vector2(6.5 * side, -12), Vector2(11.5 * side, -29)), STEEL_DARK))
			horns.append(_poly(_rect(Vector2(6.5 * side, -29), Vector2(11.5 * side, -33.5)), Color.WHITE, true, &"accent"))
		layers.append(horns)
	var body: Array = [
		_poly(_ellipse(Vector2(14.5, 22)), STEEL_DARK),
		_poly(_ellipse(Vector2(12, 19.5)), STEEL, false),
		_line(_arc(Vector2.ZERO, Vector2(10.4, 18), -160.0, -70.0, 10), STEEL_LIGHT, 1.3),
		_line(_arc(Vector2.ZERO, Vector2(10.4, 18), 30.0, 70.0, 6), STEEL_MID, 1.0),
	]
	if mark >= 2:
		for index in range(10):
			var angle: float = TAU * float(index) / 10.0 + 0.31
			body.append(_circle(Vector2(cos(angle) * 13.3, sin(angle) * 20.8), 1.1, STEEL_EDGE, false))
	layers.append(body)
	var core: Array = [
		_circle(Vector2.ZERO, 8.5, Color.WHITE, true, &"accent_dark"),
		_ring(Vector2.ZERO, 6.4, Color.WHITE, 2.0, &"accent"),
		_circle(Vector2.ZERO, 3.0, Color.WHITE, false, &"accent_light"),
		_circle(Vector2(-0.8, -0.8), 1.2, Color(1.0, 0.96, 1.0), false),
	]
	for index in range(4):
		var direction: Vector2 = Vector2.from_angle(TAU * float(index) / 4.0 + PI * 0.25)
		core.append(_line([direction * 10.0, direction * 13.5], Color.WHITE, 1.2, &"accent"))
	for clamp_point in [Vector2(0, -8.5), Vector2(8.5, 0), Vector2(0, 8.5), Vector2(-8.5, 0)]:
		var tangent: Vector2 = clamp_point.normalized().orthogonal() * 1.6
		var normal: Vector2 = clamp_point.normalized() * 1.4
		core.append(_poly([clamp_point - tangent - normal, clamp_point + tangent - normal, clamp_point + tangent + normal, clamp_point - tangent + normal], STEEL_MID, false))
	layers.append(core)
	return layers


static func _tactical_reload_shield(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var guards: Array = [
			_poly([Vector2(13, -18), Vector2(16.5, -15.5), Vector2(16.5, 15.5), Vector2(13, 18)], STEEL_MID),
			_poly(_mirror([Vector2(13, -18), Vector2(16.5, -15.5), Vector2(16.5, 15.5), Vector2(13, 18)]), STEEL_MID),
		]
		if mark >= 3:
			guards.append(_poly(_rect(Vector2(-3.5, -29.5), Vector2(3.5, -25)), Color.WHITE, true, &"accent"))
			guards.append(_poly(_rect(Vector2(-3.5, -29.5), Vector2(3.5, -28.2)), Color.WHITE, false, &"accent_light"))
		layers.append(guards)
	var body: Array = [
		_poly(_sym([Vector2(0, -26), Vector2(11, -26), Vector2(14, -23), Vector2(14, 22), Vector2(11, 26), Vector2(0, 26)]), STEEL_DARK),
		_poly(_sym([Vector2(0, -23.5), Vector2(10, -23.5), Vector2(11.8, -21.7), Vector2(11.8, 21), Vector2(10, 23.5), Vector2(0, 23.5)]), STEEL, false),
		_poly(_sym([Vector2(0, -23.5), Vector2(10, -23.5), Vector2(11.8, -21.7), Vector2(11.8, -20.4), Vector2(0, -20.4)]), STEEL_LIGHT, false),
		_poly(_rect(Vector2(-7.5, -17.5), Vector2(7.5, -12.5)), OUTLINE, false),
		_poly(_rect(Vector2(-6.5, -16.6), Vector2(6.5, -13.4)), GLASS.darkened(0.25), false),
		_line([Vector2(-5.2, -16.2), Vector2(-3.2, -13.8)], Color(0.92, 1.0, 1.0, 0.9), 0.9),
		_line([Vector2(-10, 16), Vector2(10, 16)], STEEL_DARK, 1.2),
		_line([Vector2(-10, 19.2), Vector2(10, 19.2)], STEEL_DARK, 1.2),
	]
	layers.append(body)
	var count: int = 5 if mark >= 3 else 3
	var spacing: float = 4.2 if mark >= 3 else 5.0
	var half_width: float = spacing * float(count - 1) * 0.5 + 3.5
	var rack: Array = [_poly(_rect(Vector2(-half_width, -6), Vector2(half_width, 10)), POLYMER)]
	for index in range(count):
		var x: float = -spacing * float(count - 1) * 0.5 + spacing * float(index)
		rack.append(_poly([Vector2(x - 1.6, -1), Vector2(x + 1.6, -1), Vector2(x + 1.6, 8), Vector2(x - 1.6, 8)], Color.WHITE, false, &"accent"))
		rack.append(_poly([Vector2(x - 1.6, -1), Vector2(x + 1.6, -1), Vector2(x + 1.0, -3.6), Vector2(x, -4.8), Vector2(x - 1.0, -3.6)], Color.WHITE, false, &"accent_light"))
		rack.append(_line([Vector2(x - 0.9, -0.5), Vector2(x - 0.9, 7.5)], Color.WHITE, 0.7, &"accent_light"))
	rack.append(_poly(_rect(Vector2(-half_width, 4.5), Vector2(half_width, 7)), POLYMER_LIGHT, false))
	layers.append(rack)
	return layers


# --- Vests (centred on the body, which is a 64-unit ball) ---------------------------------------------------

const BODY_RADIUS: float = 32.5
const NECK_SAG: float = 3.0


## Shoulder straps running up the sides of the ball; they make a vest read as worn rather than as a bowl.
static func _straps(color: Color, width: float = 6.0) -> Array:
	var right: Array = _arc(Vector2.ZERO, Vector2.ONE * (BODY_RADIUS + 0.5), 14.0, -30.0, 8)
	right.append_array(_arc(Vector2.ZERO, Vector2.ONE * (BODY_RADIUS + 0.5 - width), -26.0, 14.0, 8))
	return [_poly(right, color), _poly(_mirror(right), color)]


static func _scout_vest() -> Array:
	var straps: Array = _straps(POLYMER, 5.0)
	var base: PackedVector2Array = _band(5, BODY_RADIUS, NECK_SAG)
	var body: Array = [_poly(base, POLYMER)]
	body.append_array(_clipped(_rect(Vector2(-40, 0), Vector2(40, 10)), _band(5, BODY_RADIUS - 2.0, NECK_SAG), POLYMER_LIGHT))
	body.append_array(_clipped(_rect(Vector2(-40, 0), Vector2(40, 7.4)), _band(5, BODY_RADIUS - 2.0, NECK_SAG), POLYMER))
	body.append_array(_clipped(_rect(Vector2(-40, 12), Vector2(40, 14)), base, Color.WHITE, &"team"))
	body.append_array(_shade(base))
	var pouches: Array = []
	for side in [-1.0, 1.0]:
		pouches.append(_poly(_rect(Vector2(7 * side, 16), Vector2(17 * side, 25)), POLYMER_LIGHT))
	for side in [-1.0, 1.0]:
		pouches.append(_poly(_rect(Vector2(7 * side, 16), Vector2(17 * side, 18.5)), POLYMER, false))
	pouches.append(_poly(_rect(Vector2(-2.6, 15.5), Vector2(2.6, 20.5)), STEEL_EDGE))
	pouches.append(_poly(_rect(Vector2(-1.2, 17), Vector2(1.2, 19)), STEEL_DARK, false))
	return [straps, body, pouches]


static func _light_kevlar_vest(mark: int) -> Array:
	var straps: Array = _straps(POLYMER_LIGHT)
	if mark >= 2:
		for side in [-1.0, 1.0]:
			straps.append(_poly(_rect(Vector2(27 * side, -7.5), Vector2(32 * side, -4.5)), STEEL_EDGE, false))
	var base: PackedVector2Array = _band(1, BODY_RADIUS)
	base.append_array(PackedVector2Array([Vector2(-9, 1), Vector2(0, 8), Vector2(9, 1)]))
	var body: Array = [_poly(base, POLYMER)]
	for side in [-1.0, 1.0]:
		var panel: PackedVector2Array = PackedVector2Array([Vector2(3.5 * side, 10), Vector2(10 * side, 4), Vector2(40 * side, 4), Vector2(40 * side, 40), Vector2(3.5 * side, 40)])
		body.append_array(_clipped(panel, _band(4, BODY_RADIUS - 2.5), STEEL_MID if side > 0.0 else STEEL_LIGHT))
	var rows: Array = [12.0, 18.0, 24.0] if mark >= 2 else [13.0, 20.0]
	for y in rows:
		var half: float = _band_half_width(y, BODY_RADIUS, 4.5)
		body.append(_line([Vector2(-half, y), Vector2(-4.5, y)], STEEL_DARK, 1.6))
		body.append(_line([Vector2(4.5, y), Vector2(half, y)], STEEL_DARK, 1.6))
		body.append(_line([Vector2(-half, y + 1.3), Vector2(-4.5, y + 1.3)], Color.WHITE, 0.8, &"accent"))
		body.append(_line([Vector2(4.5, y + 1.3), Vector2(half, y + 1.3)], Color.WHITE, 0.8, &"accent"))
	body.append(_line([Vector2(-27, 6.2), Vector2(-10.5, 6.2), Vector2(-3.8, 11.2)], STEEL_LIGHT, 1.1))
	body.append(_line([Vector2(27, 6.2), Vector2(10.5, 6.2), Vector2(3.8, 11.2)], STEEL_MID, 1.1))
	body.append_array(_shade(base))
	body.append(_poly(_rect(Vector2(-14, 24.5), Vector2(-9, 27.5)), Color.WHITE, false, &"accent"))
	var layers: Array = [straps, body]
	if mark >= 3:
		layers.append([
			_poly([Vector2(-6.5, 12), Vector2(6.5, 12), Vector2(7.5, 23), Vector2(0, 27.5), Vector2(-7.5, 23)], STEEL_MID),
			_line([Vector2(-6.5, 12.8), Vector2(6.5, 12.8)], Color.WHITE, 1.2, &"accent"),
			_line([Vector2(-5.6, 14.5), Vector2(-6.4, 22.6)], STEEL_LIGHT, 1.0),
		])
	return layers


static func _arctic_jacket(mark: int) -> Array:
	var base: PackedVector2Array = _band(-1, BODY_RADIUS - 1.5, NECK_SAG, 54, 6, 2.2)
	var body: Array = [_poly(base, JACKET)]
	for y in [11.0, 20.0, 27.5]:
		var half: float = _band_half_width(y, BODY_RADIUS, 3.5)
		var seam: Array = []
		for index in range(9):
			var x: float = lerpf(-half, half, float(index) / 8.0)
			seam.append(Vector2(x, y + 2.2 * (1.0 - pow(x / maxf(half, 1.0), 2.0))))
		body.append(_line(seam, Color.WHITE, 1.1, &"accent") if mark >= 3 else _line(seam, STEEL_DARK, 1.3))
		var shine: Array = []
		for point in seam.slice(0, 5):
			shine.append(point + Vector2(0, -2.6))
		body.append(_line(shine, JACKET.lightened(0.22), 0.9))
	body.append_array(_shade(base))
	body.append(_line([Vector2(0, 4), Vector2(0, 31.5)], STEEL_DARK, 2.2))
	body.append(_line([Vector2(0, 4), Vector2(0, 31.5)], Color.WHITE, 1.0, &"accent"))
	body.append(_poly(_rect(Vector2(-1.4, 7), Vector2(1.4, 11)), Color.WHITE, false, &"accent_light"))
	var layers: Array = [body]
	if mark >= 2:
		var pads: Array = []
		for side in [-1.0, 1.0]:
			pads.append(_poly(_rect(Vector2(9 * side, 9), Vector2(19 * side, 17)), Color.WHITE, true, &"accent_dark"))
		for side in [-1.0, 1.0]:
			pads.append(_poly(_rect(Vector2(10.6 * side, 10.6), Vector2(17.4 * side, 15.4)), Color.WHITE, false, &"accent"))
			pads.append(_line([Vector2(11.5 * side, 12), Vector2(16.5 * side, 12)], Color.WHITE, 0.8, &"accent_light"))
		layers.append(pads)
	var collar_half: float = _band_half_width(-1.0, BODY_RADIUS, 1.5)
	var fur: Array = []
	var puffs: int = 11
	for index in range(puffs):
		var x: float = lerpf(-collar_half, collar_half, float(index) / float(puffs - 1))
		var drop: float = NECK_SAG * (1.0 - pow(x / collar_half, 2.0))
		var radius: float = 3.9 if index % 2 == 0 else 3.2
		fur.append(_circle(Vector2(x, 0.2 + drop + (0.0 if index % 2 == 0 else 0.8)), radius, FUR_SHADE))
	for index in range(puffs):
		var x: float = lerpf(-collar_half, collar_half, float(index) / float(puffs - 1))
		var drop: float = NECK_SAG * (1.0 - pow(x / collar_half, 2.0))
		var radius: float = 2.9 if index % 2 == 0 else 2.2
		fur.append(_circle(Vector2(x - 0.7, -0.8 + drop + (0.0 if index % 2 == 0 else 0.8)), radius, FUR, false))
	if mark >= 3:
		for side in [-1.0, 1.0]:
			fur.append(_line([Vector2(4.5 * side, 5), Vector2(4.5 * side, 11)], STEEL_EDGE, 0.9))
			fur.append(_circle(Vector2(4.5 * side, 11.7), 1.2, Color.WHITE, false, &"accent"))
	layers.append(fur)
	return layers


static func _delayed_armor(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var pauldrons: Array = []
		for side in [-1.0, 1.0]:
			pauldrons.append(_poly([Vector2(21 * side, -9), Vector2(30.5 * side, -7), Vector2(32 * side, 3), Vector2(21 * side, 3)], STEEL_MID))
		layers.append(pauldrons)
	var base: PackedVector2Array = _band(-2, BODY_RADIUS, NECK_SAG)
	var plates: PackedVector2Array = _band(1, BODY_RADIUS - 2.4, NECK_SAG)
	var body: Array = [_poly(base, STEEL_DARK)]
	body.append_array(_clipped(_rect(Vector2(-40, 0), Vector2(-11, 40)), plates, STEEL_MID))
	body.append_array(_clipped(_rect(Vector2(11, 0), Vector2(40, 40)), plates, STEEL))
	body.append_array(_clipped(_rect(Vector2(-9, 0), Vector2(9, 40)), plates, STEEL))
	body.append_array(_clipped(_rect(Vector2(-40, 0), Vector2(-11, 6.4)), plates, STEEL_LIGHT))
	body.append_array(_clipped(_rect(Vector2(-9, 0), Vector2(9, 6.4)), plates, STEEL_LIGHT))
	body.append_array(_clipped(_rect(Vector2(11, 0), Vector2(40, 6.4)), plates, STEEL_MID))
	if mark >= 2:
		for rivet in [Vector2(-20, 9), Vector2(20, 9), Vector2(-24, 18), Vector2(24, 18), Vector2(-18, 26), Vector2(18, 26)]:
			body.append(_circle(rivet, 1.2, STEEL_EDGE, false))
	body.append_array(_shade(base))
	layers.append(body)
	var center: Vector2 = Vector2(0, 16)
	var dial: Array = [
		_circle(center, 10.0, STEEL_DARK),
		_ring(center, 8.2, Color.WHITE, 1.4, &"accent_dark"),
		_poly([center + Vector2(-4.6, -6), center + Vector2(4.6, -6), center + Vector2(0.6, -0.6), center + Vector2(-0.6, -0.6)], Color.WHITE, false, &"accent_light"),
		_poly([center + Vector2(-4.6, 6), center + Vector2(4.6, 6), center + Vector2(0.6, 0.6), center + Vector2(-0.6, 0.6)], Color.WHITE, false, &"accent"),
		_poly([center + Vector2(-2.4, 6), center + Vector2(2.4, 6), center + Vector2(0, 3.2)], Color.WHITE, false, &"accent_light"),
		_line([center + Vector2(-5.6, -6), center + Vector2(5.6, -6)], STEEL_EDGE, 1.2),
		_line([center + Vector2(-5.6, 6), center + Vector2(5.6, 6)], STEEL_EDGE, 1.2),
	]
	if mark >= 3:
		for index in range(8):
			var direction: Vector2 = Vector2.from_angle(TAU * float(index) / 8.0 + PI / 8.0)
			dial.append(_line([center + direction * 11.6, center + direction * 13.4], Color.WHITE, 1.2, &"accent"))
	layers.append(dial)
	return layers


static func _reflective_armor(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var fins: Array = []
		for side in [-1.0, 1.0]:
			fins.append(_poly([Vector2(26 * side, 2), Vector2(36 * side, 5), Vector2(33.5 * side, 16), Vector2(28 * side, 12)], STEEL_LIGHT))
		if mark >= 3:
			for side in [-1.0, 1.0]:
				fins.append(_poly([Vector2(19 * side, -13), Vector2(28.5 * side, -11), Vector2(31 * side, -1), Vector2(21 * side, -1)], STEEL_EDGE))
		layers.append(fins)
	var base: PackedVector2Array = _band(0, BODY_RADIUS, NECK_SAG, 6)
	var plates: PackedVector2Array = _band(3, BODY_RADIUS - 2.5, NECK_SAG, 6)
	var body: Array = [_poly(base, STEEL_DARK)]
	body.append_array(_clipped(_rect(Vector2(-40, 0), Vector2(-1.4, 40)), plates, STEEL_EDGE))
	body.append_array(_clipped(_rect(Vector2(1.4, 0), Vector2(40, 40)), plates, STEEL_LIGHT))
	var glints: Array = [
		[Vector2(-21, 3), Vector2(-15.5, 3), Vector2(-24.5, 30), Vector2(-30, 30)],
		[Vector2(-12.5, 3), Vector2(-10.5, 3), Vector2(-19.5, 30), Vector2(-21.5, 30)],
		[Vector2(18, 3), Vector2(21.5, 3), Vector2(12.5, 30), Vector2(9, 30)],
	]
	for glint in glints:
		body.append_array(_clipped(PackedVector2Array(glint), plates, Color.WHITE, &"accent_light"))
	body.append_array(_clipped(_rect(Vector2(-40, 24), Vector2(40, 40)), plates, STEEL_MID))
	layers.append(body)
	var prism_size: float = 1.0 + 0.15 * float(mark - 1)
	var top: Vector2 = Vector2(0, 6)
	layers.append([
		_poly([top, Vector2(4.5 * prism_size, 14), Vector2(0, 22), Vector2(-4.5 * prism_size, 14)], Color.WHITE, true, &"accent"),
		_poly([top, Vector2(0, 22), Vector2(-4.5 * prism_size, 14)], Color.WHITE, false, &"accent_light"),
		_line([Vector2(0, 8), Vector2(0, 20)], Color(1.0, 1.0, 1.0, 0.85), 0.7),
	])
	return layers


static func _stationary_armor(mark: int) -> Array:
	var tassets: Array = [
		_poly([Vector2(-8, 26), Vector2(8, 26), Vector2(7, 38), Vector2(-7, 38)], STEEL_MID),
		_poly([Vector2(10, 24), Vector2(22, 18), Vector2(26.5, 29), Vector2(14, 35.5)], STEEL),
		_poly(_mirror([Vector2(10, 24), Vector2(22, 18), Vector2(26.5, 29), Vector2(14, 35.5)]), STEEL_MID),
	]
	if mark >= 3:
		for claw in [[Vector2(-5.5, 37), Vector2(-2, 37), Vector2(-3.8, 42)], [Vector2(2, 37), Vector2(5.5, 37), Vector2(3.8, 42)], [Vector2(14.5, 34), Vector2(18, 32.5), Vector2(18.2, 38)], [Vector2(-14.5, 34), Vector2(-18, 32.5), Vector2(-18.2, 38)]]:
			tassets.append(_poly(claw, STEEL_EDGE))
	if mark >= 2:
		for side in [-1.0, 1.0]:
			tassets.append(_poly([Vector2(21 * side, -11), Vector2(29.5 * side, -8), Vector2(32 * side, 2), Vector2(22 * side, 2)], STEEL_MID))
	var base: PackedVector2Array = _band(-2, BODY_RADIUS + 0.5, NECK_SAG)
	var plate: PackedVector2Array = _band(1, BODY_RADIUS - 2.0, NECK_SAG)
	var body: Array = [_poly(base, STEEL_DARK)]
	body.append_array(_clipped(_rect(Vector2(-40, -10), Vector2(40, 40)), plate, STEEL_MID))
	body.append_array(_clipped(_rect(Vector2(-40, -10), Vector2(40, 5.5)), plate, STEEL_LIGHT))
	var hazard: PackedVector2Array = Geometry2D.intersect_polygons(_rect(Vector2(-40, 20), Vector2(40, 26)), plate)[0]
	body.append(_poly(hazard, Color.WHITE, false, &"accent"))
	var x: float = -32.0
	while x < 32.0:
		body.append_array(_clipped(PackedVector2Array([Vector2(x, 20), Vector2(x + 3, 20), Vector2(x + 6, 26), Vector2(x + 3, 26)]), hazard, OUTLINE))
		x += 6.0
	for bolt in [Vector2(-15, 9), Vector2(15, 9), Vector2(-25, 11), Vector2(25, 11), Vector2(-11, 16.5), Vector2(11, 16.5)]:
		body.append(_circle(bolt, 1.5, STEEL_EDGE, false))
	body.append_array(_shade(base))
	var emblem: Array = [
		_poly([Vector2(-6, 6), Vector2(6, 6), Vector2(6, 16), Vector2(0, 19.5), Vector2(-6, 16)], STEEL),
		_line([Vector2(-3, 9), Vector2(0, 12), Vector2(3, 9)], Color.WHITE, 1.4, &"accent"),
		_line([Vector2(-3, 12.6), Vector2(0, 15.6), Vector2(3, 12.6)], Color.WHITE, 1.4, &"accent"),
	]
	return [tassets, body, emblem]


# --- Boots (ankle at the origin, toe towards +x, sole bottom near y = 8) --------------------------------------

static func _sole(length: float = 10.0) -> Dictionary:
	return _poly([Vector2(-7, 5), Vector2(length, 5), Vector2(length + 1.5, 6.5), Vector2(length + 0.5, 8.5), Vector2(-7, 8.5), Vector2(-8, 7)], STEEL_DARK)


static func _light_boots() -> Array:
	return [[
		_sole(),
		_poly([Vector2(-6, -5), Vector2(1, -5), Vector2(2, -1), Vector2(9, 1.5), Vector2(10.5, 5), Vector2(-7, 5), Vector2(-7, -1)], POLYMER),
		_poly([Vector2(5, 0.6), Vector2(9, 1.5), Vector2(10.5, 5), Vector2(5, 5)], STEEL_MID, false),
		_poly([Vector2(-6, -5), Vector2(1, -5), Vector2(1.3, -3.4), Vector2(-6.3, -3.4)], POLYMER_LIGHT, false),
		_line([Vector2(-5.5, 2.4), Vector2(3.5, 3.4)], Color.WHITE, 1.4, &"team"),
		_line([Vector2(1.5, -2), Vector2(4, -0.6)], STEEL_EDGE, 0.8),
		_line([Vector2(2.5, -0.4), Vector2(5, 0.8)], STEEL_EDGE, 0.8),
	]]


## Jump boots stand on coil springs: the boot sits higher and the base plate takes the floor.
static func _jump_boots(mark: int) -> Array:
	var springs: Array = []
	var spring_xs: Array = [-2.5, 5.5] if mark >= 2 else [1.5]
	var coil_radius: Vector2 = Vector2(2.6, 0.9) if mark >= 2 else Vector2(4.0, 1.0)
	for spring_x in spring_xs:
		for turn in range(3):
			var ring: Array = _arc(Vector2(float(spring_x), 1.7 + float(turn) * 1.9), coil_radius, 0.0, 360.0, 16)
			springs.append(_line(ring, OUTLINE, 3.0))
			springs.append(_line(ring, STEEL_EDGE, 1.2))
	springs.append(_poly([Vector2(-7.5, 6.8), Vector2(10.5, 6.8), Vector2(11.5, 8), Vector2(10.5, 9), Vector2(-7.5, 9)], STEEL_DARK))
	springs.append(_poly(_rect(Vector2(-6.8, 6.8), Vector2(10, 7.6)), STEEL_MID, false))
	var layers: Array = [springs]
	if mark >= 3:
		layers.append([
			_poly([Vector2(-6.5, -11), Vector2(-12, -8.5), Vector2(-11, -5.5), Vector2(-6.5, -6)], STEEL_MID),
			_poly([Vector2(-11.2, -8.2), Vector2(-13.6, -7.2), Vector2(-12.8, -5.6), Vector2(-10.6, -5.8)], Color.WHITE, true, &"accent"),
		])
	layers.append([
		_poly([Vector2(-7, -3), Vector2(10, -3), Vector2(11.5, -1), Vector2(10.5, 0), Vector2(-7, 0), Vector2(-8, -1)], STEEL_DARK),
		_poly([Vector2(-6, -13), Vector2(1.5, -13), Vector2(2.5, -7), Vector2(9, -5), Vector2(10.5, -3), Vector2(-7, -3), Vector2(-7, -8)], STEEL),
		_poly([Vector2(5, -6), Vector2(9, -5), Vector2(10.5, -3), Vector2(5, -3)], STEEL_MID, false),
		_poly([Vector2(-6, -13), Vector2(1.5, -13), Vector2(1.7, -11), Vector2(-6.2, -11)], STEEL_LIGHT, false),
		_line([Vector2(-3.5, -8.5), Vector2(0.5, -8.5)], Color.WHITE, 1.1, &"accent"),
		_circle(Vector2(-5.2, -5.2), 1.4, Color.WHITE, false, &"accent"),
	])
	return layers


static func _adrenaline_boots(mark: int) -> Array:
	var body: Array = [
		_sole(),
		_poly([Vector2(-6, -11), Vector2(2, -11), Vector2(2.5, -2), Vector2(9, 0.5), Vector2(10.5, 5), Vector2(-7, 5), Vector2(-7, -6)], POLYMER),
		_poly(_rect(Vector2(-6.6, -12.4), Vector2(2.6, -9.6)), STEEL_MID),
		_poly([Vector2(5, -0.2), Vector2(9, 0.5), Vector2(10.5, 5), Vector2(5, 5)], STEEL_MID, false),
		_line([Vector2(-6.2, -4), Vector2(-3.8, -4), Vector2(-2.8, -6.6), Vector2(-1.4, -1.4), Vector2(-0.2, -4), Vector2(1.8, -4)], Color.WHITE, 1.1, &"accent"),
	]
	if mark >= 2:
		body.append(_poly(_rect(Vector2(-6.8, -8.2), Vector2(2.4, -7)), STEEL_LIGHT, false))
		body.append(_poly(_rect(Vector2(-6.8, 1.2), Vector2(4, 2.4)), STEEL_LIGHT, false))
	if mark >= 3:
		body.append(_line([Vector2(-6.5, 6.8), Vector2(10, 6.8)], Color.WHITE, 1.1, &"accent"))
	var vial_top: float = -11.0 if mark >= 3 else -9.0
	var vial: Array = [
		_poly(_rect(Vector2(-10, vial_top), Vector2(-6.4, -1.6)), STEEL_DARK),
		_poly(_rect(Vector2(-9.2, vial_top + 2.6), Vector2(-7.2, -2.4)), Color.WHITE, false, &"accent"),
		_poly(_rect(Vector2(-9.2, vial_top + 2.6), Vector2(-8.5, -2.4)), Color.WHITE, false, &"accent_light"),
		_poly(_rect(Vector2(-10.3, vial_top - 1), Vector2(-6.1, vial_top + 0.4)), STEEL_EDGE, false),
	]
	if mark >= 2:
		vial.append(_line([Vector2(-6.4, -3), Vector2(-4.4, -3)], STEEL_EDGE, 0.8))
	return [body, vial]


static func _chasing_boots(mark: int) -> Array:
	var layers: Array = []
	if mark >= 2:
		var fins: Array = [_poly([Vector2(-6.5, -3.5), Vector2(-11.5, -6.5), Vector2(-8.5, 0.5)], STEEL_MID)]
		if mark >= 3:
			fins.append(_poly([Vector2(11, 2.5), Vector2(16.5, 4.8), Vector2(12, 5.2)], STEEL_EDGE))
		layers.append(fins)
	var body: Array = [
		_sole(12.0),
		_poly([Vector2(-6, -6), Vector2(0, -6), Vector2(3, -2.5), Vector2(11, 1.5), Vector2(13.5, 5), Vector2(-7, 5), Vector2(-7, -2)], STEEL),
		_poly([Vector2(7.5, -0.4), Vector2(11, 1.5), Vector2(13.5, 5), Vector2(7.5, 5)], STEEL_MID, false),
		_line([Vector2(-5.6, -5.4), Vector2(0, -5.4), Vector2(3, -1.9), Vector2(11, 2.1)], STEEL_LIGHT, 0.9),
	]
	var chevrons: Array = [-4.0, 0.0, 4.0] if mark >= 3 else [-3.0, 1.0]
	for x in chevrons:
		body.append(_line([Vector2(float(x), -1.5), Vector2(float(x) + 2.2, 0.6), Vector2(float(x), 2.7)], Color.WHITE, 1.3, &"accent"))
	layers.append(body)
	return layers


static func _escape_boots(mark: int) -> Array:
	var spread: float = 1.0 + 0.2 * float(mark - 1)
	var root: Vector2 = Vector2(-6, -3)
	var feathers: Array = [
		[Vector2(-1, -3.5), Vector2(-9, -8.5), Vector2(-7, -5.5), Vector2(0, 0), &"accent_light"],
		[Vector2(-1, -1.5), Vector2(-9, -4.5), Vector2(-7, -2), Vector2(0, 1.5), &"accent"],
		[Vector2(-1, 0.5), Vector2(-7, -0.5), Vector2(-5, 1.5), Vector2(0, 3), &"accent_dark"],
	]
	if mark >= 3:
		feathers.push_front([Vector2(-1, -5.5), Vector2(-8, -12), Vector2(-6.5, -8.5), Vector2(0, -2), &"accent_light"])
	var wing: Array = []
	for feather in feathers:
		var points: Array = []
		for index in range(4):
			var offset: Vector2 = feather[index]
			points.append(root + Vector2(offset.x * spread, offset.y * spread))
		wing.append(_poly(points, Color.WHITE, true, feather[4]))
	var body: Array = [
		_sole(),
		_poly([Vector2(-6, -8), Vector2(1.5, -8), Vector2(2.5, -2), Vector2(9, 0.5), Vector2(10.5, 5), Vector2(-7, 5), Vector2(-7, -3)], POLYMER),
		_poly(_rect(Vector2(-6.4, -9), Vector2(1.9, -6.6)), STEEL_MID),
		_poly([Vector2(5, -0.2), Vector2(9, 0.5), Vector2(10.5, 5), Vector2(5, 5)], STEEL_MID, false),
		_line([Vector2(-6, 2.2), Vector2(8, 3.2)], Color.WHITE, 1.0, &"accent"),
	]
	if mark >= 3:
		body.append(_line([Vector2(-6.5, 6.8), Vector2(10, 6.8)], Color.WHITE, 1.0, &"accent"))
	return [wing, body]
