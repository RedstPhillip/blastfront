class_name LoadoutStyle
extends RefCounted

## Shared look of the loadout. Deliberately quiet: graphite surfaces without borders, white type in three
## strengths, one accent (the game's amber) for "active / drop here", and colour on items only through
## their quality grade. Slots are named in the player's words (barrel / optic / ammo).

const BG_TOP: Color = Color(0.082, 0.088, 0.1, 1.0)
const BG_BOTTOM: Color = Color(0.035, 0.038, 0.045, 1.0)
const TRAY: Color = Color(0.0, 0.0, 0.0, 0.32)
const CARD: Color = Color(0.118, 0.126, 0.142, 1.0)
const CARD_HOVER: Color = Color(0.165, 0.175, 0.196, 1.0)
const CARD_EMPTY: Color = Color(1.0, 1.0, 1.0, 0.025)
const SLOT: Color = Color(1.0, 1.0, 1.0, 0.045)
const HAIRLINE: Color = Color(1.0, 1.0, 1.0, 0.08)
const TEXT: Color = Color(0.95, 0.96, 0.97, 1.0)
const TEXT_SECONDARY: Color = Color(0.95, 0.96, 0.97, 0.58)
const TEXT_MUTED: Color = Color(0.95, 0.96, 0.97, 0.34)
const ACCENT: Color = Color(1.0, 0.72, 0.3, 1.0)
const POSITIVE: Color = Color(0.45, 0.88, 0.5, 1.0)
const NEGATIVE: Color = Color(1.0, 0.4, 0.38, 1.0)
const TARGET: Color = ACCENT
const DANGER: Color = NEGATIVE

## Kept for the drag ghost and shop pieces that still refer to the older names.
const TILE: Color = CARD
const TILE_HOVER: Color = CARD_HOVER
const TILE_EMPTY: Color = CARD_EMPTY
const EDGE: Color = HAIRLINE
const EDGE_SOFT: Color = Color(1.0, 1.0, 1.0, 0.05)
const SURFACE: Color = Color(1.0, 1.0, 1.0, 0.03)
const SURFACE_RAISED: Color = SLOT
const SURFACE_DEEP: Color = Color(0.03, 0.033, 0.04, 1.0)
const INSTALLED: Color = TEXT

const SLOT_LABELS: Dictionary = {
	&"front": "BARREL",
	&"middle": "OPTIC",
	&"ammo": "AMMO",
	&"boots": "BOOTS",
	&"vest": "VEST",
	&"shield": "SHIELD",
}


static func slot_label(slot: StringName) -> String:
	return str(SLOT_LABELS.get(slot, str(slot).to_upper()))


static func roman(mark: int) -> String:
	match mark:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
	return ""


static func local_accent() -> Color:
	return OnlineMatch.get_player_color(ExtensionInventory.get_local_player_slot())


static func local_color_id() -> StringName:
	return OnlineMatch.get_player_color_id(ExtensionInventory.get_local_player_slot())


static func flat(fill: Color, radius: int = 4) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


static func panel_style(fill: Color = SURFACE, border: Color = Color(0, 0, 0, 0), radius: int = 4) -> StyleBoxFlat:
	var style: StyleBoxFlat = flat(fill, radius)
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(1)
	return style


static func label(text: String, font: Font, size: int, color: Color) -> Label:
	var result: Label = Label.new()
	UiStyle.style_label(result, font, size, color)
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func caption(text: String, color: Color = TEXT_MUTED, size: int = 11) -> Label:
	return label(text, UiStyle.FONT_BOLD, size, color)


## Vertical gradient quad.
static func draw_gradient_rect(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	canvas.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)


## Soft radial light (triangle fan, centre colour fading out).
static func draw_glow(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color, segments: int = 32) -> void:
	var edge: Color = Color(color.r, color.g, color.b, 0.0)
	for index in range(segments):
		var a: float = TAU * float(index) / float(segments)
		var b: float = TAU * float(index + 1) / float(segments)
		canvas.draw_polygon(
			PackedVector2Array([center, center + Vector2(cos(a) * radius.x, sin(a) * radius.y), center + Vector2(cos(b) * radius.x, sin(b) * radius.y)]),
			PackedColorArray([color, edge, edge])
		)


## Mark pips: small squares, filled for each tier.
static func draw_pips(canvas: CanvasItem, origin: Vector2, mark: int, max_mark: int, size: float = 2.0, gap: float = 2.0) -> void:
	for index in range(max_mark):
		var rect: Rect2 = Rect2(origin + Vector2(float(index) * (size * 2.0 + gap), 0.0), Vector2(size * 2.0, size * 2.0))
		canvas.draw_rect(rect, Color(1, 1, 1, 0.85) if index < mark else Color(1, 1, 1, 0.16))


static func draw_check(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, mark: Color) -> void:
	canvas.draw_circle(center, radius, fill, true, -1.0, true)
	var s: float = radius * 0.5
	canvas.draw_polyline(PackedVector2Array([center + Vector2(-s, 0.0), center + Vector2(-s * 0.25, s * 0.7), center + Vector2(s, -s * 0.6)]), mark, maxf(radius * 0.28, 1.4), true)


static func draw_dashed_rect(canvas: CanvasItem, rect: Rect2, color: Color, dash: float = 3.0) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		canvas.draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.0, dash, true)
