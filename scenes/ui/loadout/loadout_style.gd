class_name LoadoutStyle
extends RefCounted

## Shared look of the loadout and the other between-rounds pages, on the game's neutral charcoal palette
## (UiStyle): flat surfaces instead of boxed panels, off-white type in three strengths, the accent only for
## "equipped / selected / drop here", the quality grade only as a thin bar on items and the team colour only
## on the operator. Slots are named in the player's words (barrel / optic / ammo).

const BG_TOP: Color = Color(0.075, 0.075, 0.07, 1.0)
const BG_BOTTOM: Color = Color(0.035, 0.035, 0.033, 1.0)
## The between-rounds pages share one frame: the world stays faintly visible under an ink wash (SCRIM),
## every surface is a recessed ink well (WELL, no border), every section opens with an eyebrow label and a
## hairline, and the page's one action sits at the foot of its right-hand dock.
const SCRIM_TOP: Color = Color(0.025, 0.026, 0.024, 0.68)
const SCRIM_BOTTOM: Color = Color(0.012, 0.013, 0.012, 0.84)
const WELL: Color = Color(0.0, 0.0, 0.0, 0.3)
const WELL_RADIUS: int = 3
const DOCK: Color = WELL
const DOCK_WIDTH: float = 392.0
const DOCK_PAD: float = 24.0
const EYEBROW_SIZE: int = 11
const CARD: Color = Color(0.11, 0.11, 0.104, 1.0)
const CARD_HOVER: Color = Color(0.16, 0.16, 0.15, 1.0)
const CARD_EMPTY: Color = Color(1.0, 1.0, 1.0, 0.025)
const SLOT: Color = Color(1.0, 1.0, 1.0, 0.045)
const HAIRLINE: Color = UiStyle.LINE
const TEXT: Color = UiStyle.TEXT
const TEXT_SECONDARY: Color = Color(0.93, 0.92, 0.88, 0.66)
const TEXT_MUTED: Color = Color(0.93, 0.92, 0.88, 0.38)
const ACCENT: Color = UiStyle.ACCENT
const POSITIVE: Color = UiStyle.SUCCESS
const NEGATIVE: Color = UiStyle.DANGER
const COIN: Color = Color(0.95, 0.78, 0.34, 1.0)
const TARGET: Color = ACCENT
const DANGER: Color = NEGATIVE

## Older names still used by the drag ghost, the merge dialog and the research page.
const TILE: Color = CARD
const TILE_HOVER: Color = CARD_HOVER
const TILE_EMPTY: Color = CARD_EMPTY
const EDGE: Color = HAIRLINE
const EDGE_SOFT: Color = Color(1.0, 1.0, 1.0, 0.05)
const SURFACE: Color = Color(1.0, 1.0, 1.0, 0.03)
const SURFACE_RAISED: Color = SLOT
const SURFACE_DEEP: Color = BG_BOTTOM
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


static func flat(fill: Color, radius: int = 2) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(mini(radius, 3))
	style.anti_aliasing = true
	return style


static func panel_style(fill: Color = SURFACE, border: Color = Color(0, 0, 0, 0), radius: int = 2) -> StyleBoxFlat:
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


static func well(radius: int = WELL_RADIUS) -> StyleBoxFlat:
	return flat(WELL, radius)


## The page wash over the dimmed world.
static func draw_scrim(canvas: CanvasItem, rect: Rect2) -> void:
	draw_gradient_rect(canvas, rect, SCRIM_TOP, SCRIM_BOTTOM)


## A section label with a hairline running on to the right edge, and optional quiet text at the end of the
## line ("0 / 8", "RESETS TO 5 NEXT SET"). `y` is the line's height; the label sits on it.
static func draw_eyebrow(canvas: CanvasItem, x: float, y: float, width: float, text: String, meta: String = "", meta_color: Color = TEXT_MUTED) -> void:
	var font: Font = UiStyle.FONT_BOLD
	canvas.draw_string(font, Vector2(x, y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, EYEBROW_SIZE, TEXT_SECONDARY)
	var start: float = x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, EYEBROW_SIZE).x + 10.0
	var end: float = x + width
	if meta != "":
		var meta_width: float = font.get_string_size(meta, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		canvas.draw_string(font, Vector2(end - meta_width, y + 4.0), meta, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, meta_color)
		end -= meta_width + 10.0
	if end > start:
		canvas.draw_line(Vector2(start, y), Vector2(end, y), HAIRLINE, 1.0)


## The eyebrow as a control for container layouts; its end text comes from the "eyebrow_meta" meta (set it,
## then queue_redraw).
static func eyebrow(text: String, height: float = 26.0) -> Control:
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0.0, height)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("eyebrow_meta", "")
	row.draw.connect(func() -> void: draw_eyebrow(row, 0.0, row.size.y * 0.5, row.size.x, text, str(row.get_meta("eyebrow_meta", ""))))
	return row


## Text shortened with an ellipsis to fit a width, for strings drawn straight onto a canvas.
static func fit_text(text: String, font: Font, font_size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var trimmed: String = text
	while trimmed.length() > 1 and font.get_string_size(trimmed.strip_edges() + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		trimmed = trimmed.left(-1)
	return trimmed.strip_edges() + "…"


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


## Durability colour: quiet while a part is in good shape, amber once worn, red when nearly broken.
static func wear_color(condition_ratio: float) -> Color:
	if condition_ratio < 0.35:
		return NEGATIVE
	if condition_ratio < 0.6:
		return ACCENT
	return Color(1.0, 1.0, 1.0, 0.32)


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


## Soft radial light (triangle fan, centre colour fading out). Use for lighting a scene (the operator's
## spotlight), never as a halo around UI.
static func draw_glow(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color, segments: int = 32) -> void:
	var edge: Color = Color(color.r, color.g, color.b, 0.0)
	for index in range(segments):
		var a: float = TAU * float(index) / float(segments)
		var b: float = TAU * float(index + 1) / float(segments)
		canvas.draw_polygon(
			PackedVector2Array([center, center + Vector2(cos(a) * radius.x, sin(a) * radius.y), center + Vector2(cos(b) * radius.x, sin(b) * radius.y)]),
			PackedColorArray([color, edge, edge])
		)


## Mark pips as small squares (filled up to the mark).
static func draw_pips(canvas: CanvasItem, origin: Vector2, mark: int, max_mark: int, size: float = 2.0, gap: float = 2.0) -> void:
	for index in range(max_mark):
		var rect: Rect2 = Rect2(origin + Vector2(float(index) * (size * 2.0 + gap), 0.0), Vector2(size * 2.0, size * 2.0))
		canvas.draw_rect(rect, Color(1, 1, 1, 0.85) if index < mark else Color(1, 1, 1, 0.16))


static func draw_check(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, mark: Color) -> void:
	canvas.draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), fill)
	var s: float = radius * 0.5
	canvas.draw_polyline(PackedVector2Array([center + Vector2(-s, 0.0), center + Vector2(-s * 0.25, s * 0.7), center + Vector2(s, -s * 0.6)]), mark, maxf(radius * 0.3, 1.4), true)


## Small coin glyph (a filled disc with a darker inner ring) used next to prices and balances.
static func draw_coin(canvas: CanvasItem, center: Vector2, radius: float, color: Color = COIN) -> void:
	canvas.draw_circle(center, radius, color, true, -1.0, true)
	canvas.draw_arc(center, radius * 0.58, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.32 * color.a), maxf(radius * 0.22, 1.0), true)


## Drop targets speak one language on tiles, sockets and stages: while a drag is on, every place the item
## can go pulses amber; the one under the cursor (armed: releasing does it) holds a steady amber.
static func drop_color(armed: bool, time: float) -> Color:
	if armed:
		return ACCENT
	return with_alpha(ACCENT, 0.5 + 0.4 * sin(time * 7.0))


## The merge mark: an amber disc with a plus (merge-ready tiles, merge drop targets).
static func draw_merge_badge(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(center, radius, color, true, -1.0, true)
	var arm: float = radius * 0.5
	canvas.draw_line(center + Vector2(-arm, 0.0), center + Vector2(arm, 0.0), with_alpha(BG_BOTTOM, color.a), 1.5)
	canvas.draw_line(center + Vector2(0.0, -arm), center + Vector2(0.0, arm), with_alpha(BG_BOTTOM, color.a), 1.5)


## Where a dragged part lands on a stage (end of the socket's callout line): a pulsing point that settles
## into a ring when armed, or the merge badge when dropping there merges with the installed twin.
static func draw_drop_point(canvas: CanvasItem, at: Vector2, armed: bool, merge: bool, time: float) -> void:
	var color: Color = drop_color(armed, time)
	if merge:
		draw_merge_badge(canvas, at, 7.0 if armed else 6.0, color)
		return
	if armed:
		canvas.draw_arc(at, 9.0, 0.0, TAU, 28, color, 1.5, true)
		canvas.draw_circle(at, 4.0, color, true, -1.0, true)
		return
	var radius: float = 4.0 + 1.5 * sin(time * 7.0)
	canvas.draw_arc(at, radius + 5.0, 0.0, TAU, 24, with_alpha(color, color.a * 0.4), 1.2, true)
	canvas.draw_circle(at, radius, color, true, -1.0, true)


static func draw_dashed_rect(canvas: CanvasItem, rect: Rect2, color: Color, dash: float = 3.0) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4):
		canvas.draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.0, dash, true)


## Corner brackets around a rect: a targeting mark.
static func draw_brackets(canvas: CanvasItem, rect: Rect2, color: Color, length: float = 7.0, width: float = 1.5) -> void:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	for corner in [[p, Vector2(1, 0), Vector2(0, 1)], [Vector2(e.x, p.y), Vector2(-1, 0), Vector2(0, 1)], [e, Vector2(-1, 0), Vector2(0, -1)], [Vector2(p.x, e.y), Vector2(1, 0), Vector2(0, -1)]]:
		var origin: Vector2 = corner[0]
		canvas.draw_polyline(PackedVector2Array([origin + (corner[1] as Vector2) * length, origin, origin + (corner[2] as Vector2) * length]), color, width, true)


## A keyboard / pad prompt chip: a small filled key cap with the key name. Returns the chip width so callers
## can lay out the action text after it.
static func draw_key_chip(canvas: CanvasItem, origin: Vector2, key: String, height: float = 18.0, color: Color = TEXT_SECONDARY) -> float:
	var font: Font = UiStyle.FONT_BOLD
	var text_width: float = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var width: float = maxf(text_width + 10.0, height)
	var rect: Rect2 = Rect2(origin, Vector2(width, height))
	canvas.draw_style_box(flat(Color(1, 1, 1, 0.12), 2), rect)
	canvas.draw_string(font, Vector2(rect.position.x, rect.position.y + height * 0.5 + 3.5), key, HORIZONTAL_ALIGNMENT_CENTER, width, 10, color)
	return width
