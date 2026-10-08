class_name UiStyle
extends RefCounted

## Shared visual language for HUD and menus: palette, fonts and stylebox factories.
##
## The look follows tactical shooters (Modern Warfare, Tarkov) rather than generic "gamer" UI:
## - Neutral, slightly warm charcoal surfaces. No teal or cyan tint, no glass, no glow.
## - Off-white text in three strengths; size and weight carry hierarchy, not colour.
## - One signal colour (ACCENT) for what is selected or what you should press next. Everything else stays
##   quiet; colour elsewhere means something (team, danger, rarity, intel/coins).
## - Square shapes: 2 px corners, no skew, no outlines on panels or buttons. A hairline only to separate.
## - Few words: no captions explaining what a control does when the control says it.

const INK: Color = Color(0.043, 0.043, 0.04, 1.0)
const PANEL: Color = Color(0.067, 0.067, 0.063, 0.94)
const PANEL_SOLID: Color = Color(0.082, 0.082, 0.077, 1.0)
const PANEL_RAISED: Color = Color(0.125, 0.125, 0.117, 0.97)
const LINE: Color = Color(1.0, 1.0, 1.0, 0.08)
const LINE_STRONG: Color = Color(1.0, 1.0, 1.0, 0.2)
const TEXT: Color = Color(0.93, 0.92, 0.88, 1.0)
const TEXT_DIM: Color = Color(0.66, 0.65, 0.61, 1.0)
const TEXT_MUTED: Color = Color(0.43, 0.42, 0.39, 1.0)
const ACCENT: Color = Color(0.96, 0.74, 0.26, 1.0)
const ACCENT_HOT: Color = Color(1.0, 0.85, 0.5, 1.0)
const ACCENT_DEEP: Color = Color(0.7, 0.5, 0.12, 1.0)
## Research points ("intel"): a muted sage so it never competes with coins (gold) or the accent.
const INTEL: Color = Color(0.67, 0.78, 0.58, 1.0)
const DANGER: Color = Color(0.9, 0.32, 0.27, 1.0)
const SUCCESS: Color = Color(0.58, 0.77, 0.42, 1.0)
const SHIELD: Color = Color(0.855, 0.838, 0.797, 1.0)
## Hover and selection fills for flat controls.
const FILL_HOVER: Color = Color(1.0, 1.0, 1.0, 0.1)
const FILL_IDLE: Color = Color(1.0, 1.0, 1.0, 0.045)

const FONT_DISPLAY: Font = preload("res://assets/fonts/blastfront_combat_font.tres")
const FONT_BOLD: Font = preload("res://assets/fonts/blastfront_hud_font.tres")
const FONT_UI: Font = preload("res://assets/fonts/blastfront_ui_font.tres")
const FONT_BODY: Font = preload("res://assets/fonts/blastfront_body_font.tres")


## Flat panel. Borders default to none; pass a border colour and width only where a line separates things.
static func panel(bg: Color = PANEL, border: Color = LINE, radius: int = 2, border_width: int = 0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(mini(radius, 3))
	style.anti_aliasing = true
	return style


static func with_margins(style: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


static func with_shadow(style: StyleBoxFlat, size: int = 12, offset: Vector2 = Vector2(0, 6), color: Color = Color(0, 0, 0, 0.45)) -> StyleBoxFlat:
	style.shadow_size = size
	style.shadow_offset = offset
	style.shadow_color = color
	return style


static func style_label(label: Label, font: Font, size: int, color: Color = TEXT, outline: int = 0) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))


static func player_color(slot: int) -> Color:
	if NetworkSession.is_steam_match_active():
		return OnlineMatch.get_player_color(slot)
	return GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR)


static func player_name(slot: int) -> String:
	if NetworkSession.is_steam_match_active():
		return OnlineMatch.get_player_color_name(slot).to_upper()
	if NetworkSession.is_bot_duel() and slot == GameSettings.PLAYER_TWO_SLOT:
		return "CPU"
	if NetworkSession.is_training() and slot != GameSettings.PLAYER_ONE_SLOT:
		return "TARGET"
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return "YOU"
	return "PLAYER %d" % slot


static func difficulty_name(value: int) -> String:
	match value:
		0:
			return "EASY"
		2:
			return "HARD"
		_:
			return "NORMAL"


## Flat, square buttons. Primary: solid accent with dark text (the one thing to press). Secondary: a faint
## fill that brightens on hover/focus; no outlines.
static func style_button(button: Button, primary: bool, font_size: int = 20) -> void:
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if primary:
		normal = with_margins(panel(ACCENT), 26, 10)
		hover = with_margins(panel(ACCENT_HOT), 26, 10)
		pressed = with_margins(panel(ACCENT_DEEP), 26, 10)
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_focus_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
	else:
		normal = with_margins(panel(FILL_IDLE), 26, 10)
		hover = with_margins(panel(FILL_HOVER), 26, 10)
		pressed = with_margins(panel(Color(1.0, 1.0, 1.0, 0.03)), 26, 10)
		button.add_theme_color_override("font_color", TEXT_DIM)
		button.add_theme_color_override("font_hover_color", TEXT)
		button.add_theme_color_override("font_focus_color", TEXT)
		button.add_theme_color_override("font_pressed_color", TEXT)
	var disabled: StyleBoxFlat = with_margins(panel(Color(1.0, 1.0, 1.0, 0.02)), 26, 10)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", font_size)


## A toggle option inside a row (difficulty, world, on/off): selected = solid light fill with dark text.
## Focus (pad / keyboard) is an accent frame drawn over whatever state the option is in, so the selected
## option still shows which one the cursor is on.
static func style_option(button: Button, font_size: int = 17) -> void:
	style_button(button, false, font_size)
	button.add_theme_stylebox_override("pressed", with_margins(panel(TEXT), 26, 10))
	button.add_theme_stylebox_override("focus", focus_frame())
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)


## Focus overlay for controls whose fill already means something (selected options): an accent frame only.
static func focus_frame() -> StyleBoxFlat:
	var style: StyleBoxFlat = panel(Color(0, 0, 0, 0), ACCENT, 2, 2)
	style.draw_center = false
	return style
