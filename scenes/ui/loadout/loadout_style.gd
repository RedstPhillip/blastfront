class_name LoadoutStyle
extends RefCounted

## Shared look of the loadout, built on the game's ink-and-amber palette (UiStyle): ink washes instead of
## boxed panels, white type in three strengths, amber for "equipped / selected / drop here", the quality
## grade only as a thin condition bar on items and the team colour only on the operator.
## Slots are named in the player's words (barrel / optic / ammo).

const BACKDROP: Color = Color(0.018, 0.032, 0.035, 0.95)
const DOCK: Color = Color(0.0, 0.008, 0.01, 0.5)
const CARD: Color = Color(0.072, 0.1, 0.104, 1.0)
const CARD_HOVER: Color = Color(0.105, 0.145, 0.15, 1.0)
const CARD_EMPTY: Color = Color(0.62, 0.86, 0.8, 0.028)
const SLOT: Color = Color(0.62, 0.86, 0.8, 0.05)
const HAIRLINE: Color = Color(0.62, 0.86, 0.8, 0.11)
const TEXT: Color = UiStyle.TEXT
const TEXT_SECONDARY: Color = Color(0.86, 0.93, 0.9, 0.64)
const TEXT_MUTED: Color = Color(0.78, 0.9, 0.86, 0.36)
const ACCENT: Color = UiStyle.ACCENT
const POSITIVE: Color = Color(0.49, 0.9, 0.56, 1.0)
const NEGATIVE: Color = Color(1.0, 0.42, 0.4, 1.0)
const COIN: Color = Color(1.0, 0.8, 0.36, 1.0)
const TARGET: Color = ACCENT
const DANGER: Color = NEGATIVE

## Older names still used by the drag ghost and the merge dialog.
const TILE: Color = CARD
const TILE_HOVER: Color = CARD_HOVER
const TILE_EMPTY: Color = CARD_EMPTY
const EDGE: Color = HAIRLINE
const EDGE_SOFT: Color = Color(0.62, 0.86, 0.8, 0.06)
const SURFACE: Color = Color(0.62, 0.86, 0.8, 0.03)
const SURFACE_RAISED: Color = SLOT
const SURFACE_DEEP: Color = Color(0.02, 0.032, 0.035, 1.0)
const BG_BOTTOM: Color = SURFACE_DEEP
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


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func flat(fill: Color, radius: int = 3) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


static func panel_style(fill: Color = SURFACE, border: Color = Color(0, 0, 0, 0), radius: int = 3) -> StyleBoxFlat:
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


## Item name without its "MK n" suffix.
static func base_name(text: String) -> String:
	var index: int = text.rfind(" MK")
	return text.substr(0, index) if index > 0 else text


## Display name, mark, condition and colour of an extension or armor piece.
static func item_info(item: Variant) -> Dictionary:
	if item is WeaponExtensionItem:
		var extension: WeaponExtensionItem = item
		return {
			"name": base_name(extension.get_display_name()),
			"mark": extension.mark,
			"condition": extension.condition,
			"grade": extension.get_condition_tier_name(),
			"color": extension.get_condition_color(),
			"slot": extension.get_slot(),
		}
	if item is ArmorItemData:
		var armor: ArmorItemData = item
		return {
			"name": base_name(armor.get_hover_title()),
			"mark": armor.get_mark(),
			"condition": armor.condition,
			"grade": armor.get_condition_name(),
			"color": armor.get_condition_color(),
			"slot": armor.category,
		}
	return {}


## Vertical gradient quad.
static func draw_gradient_rect(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	canvas.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)


## Horizontal gradient quad.
static func draw_hgradient_rect(canvas: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	canvas.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([left, right, right, left])
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


static func draw_check(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, mark: Color) -> void:
	canvas.draw_circle(center, radius, fill, true, -1.0, true)
	var s: float = radius * 0.5
	canvas.draw_polyline(PackedVector2Array([center + Vector2(-s, 0.0), center + Vector2(-s * 0.25, s * 0.7), center + Vector2(s, -s * 0.6)]), mark, maxf(radius * 0.3, 1.4), true)


## Small coin glyph (a filled disc with a darker inner ring) used next to prices and balances.
static func draw_coin(canvas: CanvasItem, center: Vector2, radius: float, color: Color = COIN) -> void:
	canvas.draw_circle(center, radius, color, true, -1.0, true)
	canvas.draw_arc(center, radius * 0.58, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.32 * color.a), maxf(radius * 0.22, 1.0), true)


static func draw_dashed_rect(canvas: CanvasItem, rect: Rect2, color: Color, dash: float = 3.0) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		canvas.draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.0, dash, true)


## Corner brackets around a rect: the loadout's "selected / targeted" mark.
static func draw_brackets(canvas: CanvasItem, rect: Rect2, color: Color, length: float = 7.0, width: float = 1.5) -> void:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	for corner in [[p, Vector2(1, 0), Vector2(0, 1)], [Vector2(e.x, p.y), Vector2(-1, 0), Vector2(0, 1)], [e, Vector2(-1, 0), Vector2(0, -1)], [Vector2(p.x, e.y), Vector2(1, 0), Vector2(0, -1)]]:
		var origin: Vector2 = corner[0]
		canvas.draw_polyline(PackedVector2Array([origin + (corner[1] as Vector2) * length, origin, origin + (corner[2] as Vector2) * length]), color, width, true)


## A keyboard / pad prompt chip: rounded outline with the key name, followed by nothing (caller draws the label).
## Returns the chip width so callers can lay out the action text after it.
static func draw_key_chip(canvas: CanvasItem, origin: Vector2, key: String, height: float = 18.0, color: Color = TEXT_SECONDARY) -> float:
	var font: Font = UiStyle.FONT_BOLD
	var text_width: float = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var width: float = maxf(text_width + 10.0, height)
	var rect: Rect2 = Rect2(origin, Vector2(width, height))
	var style: StyleBoxFlat = flat(Color(1, 1, 1, 0.06), 3)
	style.border_color = with_alpha(color, 0.45)
	style.set_border_width_all(1)
	canvas.draw_style_box(style, rect)
	canvas.draw_string(font, Vector2(rect.position.x, rect.position.y + height * 0.5 + 3.5), key, HORIZONTAL_ALIGNMENT_CENTER, width, 10, color)
	return width
