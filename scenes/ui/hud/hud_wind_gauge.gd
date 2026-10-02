class_name HudWindGauge
extends Control

## Compact wind readout for maps with weather: chevrons pointing where the wind blows (how many are lit is
## the strength), a short state word, a countdown while a storm rolls in and a SHELTER tag when the local
## player stands in the lee of rock. Fed every frame by the weather director.

const CHEVRONS: int = 5
const CHEVRON_SIZE: Vector2 = Vector2(9.0, 12.0)
const CHEVRON_GAP: float = 5.0
const WIDTH: float = 230.0
const HEIGHT: float = 40.0

var wind: float = 0.0
var full_wind: float = 250.0
var state_text: String = "WIND"
var state_color: Color = UiStyle.TEXT_DIM
var countdown: float = -1.0
var sheltered: float = 0.0
var alert: float = 0.0

var _scroll: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 40.0
	offset_bottom = 40.0 + HEIGHT


func _process(delta: float) -> void:
	_time += delta
	visible = _should_show()
	if not visible:
		return
	var strength: float = clampf(absf(wind) / full_wind, 0.0, 1.0)
	_scroll = fposmod(_scroll + delta * (0.6 + 3.2 * strength), 1.0)
	queue_redraw()


func _draw() -> void:
	var strength: float = clampf(absf(wind) / full_wind, 0.0, 1.0)
	var side: float = signf(wind) if absf(wind) > 2.0 else 1.0
	var lit: int = int(ceil(strength * float(CHEVRONS) - 0.15))
	var center: Vector2 = Vector2(WIDTH * 0.5, 13.0)
	var pulse: float = 0.5 + 0.5 * sin(_time * 9.0)
	var row_width: float = float(CHEVRONS) * CHEVRON_SIZE.x + float(CHEVRONS - 1) * CHEVRON_GAP
	# Soft backing so the readout stays legible over a bright sky.
	draw_rect(Rect2(center.x - row_width * 0.5 - 14.0, 1.0, row_width + 28.0, 24.0), Color(0.0, 0.0, 0.0, 0.22 + 0.18 * alert))
	for index in range(CHEVRONS):
		# Order the chevrons so the lit run starts on the upwind side and travels downwind.
		var slot: int = index if side > 0.0 else CHEVRONS - 1 - index
		var x: float = center.x - row_width * 0.5 + float(slot) * (CHEVRON_SIZE.x + CHEVRON_GAP) + CHEVRON_SIZE.x * 0.5
		var on: bool = index < lit
		var travel: float = fposmod(_scroll - float(index) / float(CHEVRONS), 1.0)
		var shimmer: float = 0.75 + 0.25 * (1.0 - travel) if on else 1.0
		var color: Color = state_color if on else Color(1.0, 1.0, 1.0, 0.16)
		if on and alert > 0.0:
			color = color.lerp(Color(1.0, 1.0, 1.0), 0.35 * pulse * alert)
		color.a *= shimmer
		_draw_chevron(Vector2(x, center.y), side, color)
	var font: Font = UiStyle.FONT_BOLD
	var label: String = state_text
	if countdown >= 0.0:
		label = "%s  %d" % [state_text, int(ceil(countdown))]
	var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(center.x - label_size.x * 0.5, 39.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(state_color.r, state_color.g, state_color.b, 0.95))
	if sheltered > 0.01:
		var tag_pos: Vector2 = Vector2(center.x + row_width * 0.5 + 22.0, 17.0)
		draw_string(font, tag_pos, "SHELTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.95, 0.82, 0.9 * sheltered))
		draw_rect(Rect2(tag_pos + Vector2(-8.0, -7.0), Vector2(4.0, 4.0)), Color(0.78, 0.95, 0.82, 0.9 * sheltered))


func _draw_chevron(at: Vector2, side: float, color: Color) -> void:
	var half: Vector2 = CHEVRON_SIZE * 0.5
	var tip: Vector2 = at + Vector2(half.x * side, 0.0)
	var top: Vector2 = at + Vector2(-half.x * side, -half.y)
	var bottom: Vector2 = at + Vector2(-half.x * side, half.y)
	var thickness: float = 3.0
	var inner_top: Vector2 = top + Vector2(thickness * side, 0.0)
	var inner_bottom: Vector2 = bottom + Vector2(thickness * side, 0.0)
	var inner_tip: Vector2 = tip + Vector2(-thickness * side, 0.0)
	var colors: PackedColorArray = PackedColorArray([color, color, color, color])
	draw_primitive(PackedVector2Array([top, tip, inner_tip, inner_top]), colors, PackedVector2Array())
	draw_primitive(PackedVector2Array([inner_tip, tip, bottom, inner_bottom]), colors, PackedVector2Array())


## Only during play: hidden under the pause menu, the loadout and the end-of-match screens.
func _should_show() -> bool:
	if get_tree().paused:
		return false
	for modal in get_tree().get_nodes_in_group(&"modal_ui"):
		if modal is CanvasItem and (modal as CanvasItem).is_visible_in_tree():
			return false
	var world: Node = get_tree().get_first_node_in_group(GameSettings.GAME_WORLD_GROUP)
	if world != null and world.has_method(&"is_match_over") and world.is_match_over():
		return false
	return true
